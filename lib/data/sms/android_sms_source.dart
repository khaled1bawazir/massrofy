/// The Android implementation of the [SmsSource] port — a thin adapter over
/// the `massrofy/sms_channel` platform channel implemented in
/// `android/app/src/main/kotlin/.../SmsChannel.kt`.
///
/// ## Thin on purpose
///
/// There is no logic here beyond marshalling. Every decision — what counts as
/// financial, what to keep, what to discard, when to advance the watermark —
/// lives in `features/ingestion` and `features/parsing`, where it can be
/// tested on a laptop against an in-memory fake. If this class started
/// filtering or interpreting, that logic would become reachable only through
/// an emulator, and in practice would stop being tested.
///
/// The one thing this file *does* own is the platform's error surface:
/// `PlatformException` and `MissingPluginException` are converted into an
/// empty result rather than being allowed to escape. On a background isolate
/// an uncaught exception ends the run; returning empty means the run is a
/// no-op, the watermark does not move, and the messages are picked up next
/// time (NFR-A7 — nothing is lost, only delayed).
library;

import 'package:flutter/services.dart';

import '../../features/ingestion/sms_source.dart';

/// Shared channel name. Must match `SmsChannel.CHANNEL` in Kotlin — a
/// mismatch produces a `MissingPluginException` at runtime, which is exactly
/// the kind of thing that only shows up on a device, so it is defined once
/// here and referenced by both the source and the permission service.
const String smsMethodChannelName = 'massrofy/sms_channel';

final class AndroidSmsSource implements SmsSource {
  final MethodChannel _channel;

  AndroidSmsSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(smsMethodChannelName);

  @override
  Future<List<RawSmsRecord>> readSince(
    IngestCursor cursor, {
    int limit = 100,
  }) async {
    return _query('readSince', <String, Object?>{
      'afterId': cursor.lastProcessedProviderId,
      'limit': limit,
    });
  }

  @override
  Future<List<RawSmsRecord>> readRange({
    required DateTime from,
    required int afterProviderId,
    required int limit,
  }) async {
    return _query('readRange', <String, Object?>{
      'fromEpochMs': from.toUtc().millisecondsSinceEpoch,
      'afterId': afterProviderId,
      'limit': limit,
    });
  }

  @override
  Future<int> countRange({required DateTime from}) async {
    try {
      final int? count = await _channel.invokeMethod<int>(
        'countRange',
        <String, Object?>{'fromEpochMs': from.toUtc().millisecondsSinceEpoch},
      );
      return count ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<List<RawSmsRecord>> _query(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final List<Object?>? rows = await _invokeOrEmpty(method, arguments);
    if (rows == null) {
      return const <RawSmsRecord>[];
    }

    return <RawSmsRecord>[
      for (final Object? row in rows)
        if (row is Map)
          RawSmsRecord(
            providerId: (row['id'] as num).toInt(),
            address: (row['address'] as String?) ?? '',
            body: (row['body'] as String?) ?? '',
            // The provider stores `date` as epoch milliseconds. Converted to
            // UTC immediately: a local `DateTime` here would silently change
            // meaning when the device's timezone changed, and every stored
            // instant in this schema is UTC (architecture §7.4).
            receivedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['date'] as num).toInt(),
              isUtc: true,
            ),
          ),
    ];
  }

  Future<List<Object?>?> _invokeOrEmpty(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMethod<List<Object?>>(method, arguments);
    } on PlatformException {
      // Includes the permission-revoked-mid-run case: Android 11+ can
      // auto-reset an unused app's permissions (ADR-006). The Kotlin side
      // already converts `SecurityException` into an empty list; this is the
      // belt to that braces.
      return null;
    } on MissingPluginException {
      // Reached in a unit test or on a non-Android host, where the channel
      // does not exist. Behaving as "empty inbox" keeps the whole pipeline
      // runnable in `flutter test` without a platform mock.
      return null;
    }
  }
}
