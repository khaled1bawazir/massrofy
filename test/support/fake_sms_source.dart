import 'package:massrofy/features/ingestion/sms_source.dart';

/// An in-memory stand-in for the device SMS inbox.
///
/// This is the piece that makes the whole ingestion pipeline testable on a
/// laptop. Without it, the only way to check "does an interrupted historical
/// import resume without duplicating transactions?" (AC-A3.3) would be to
/// install an APK on a phone and kill it by hand at the right moment — which
/// means, in practice, that it never gets checked.
///
/// It deliberately mimics the real content provider's contract rather than
/// being convenient:
///
///  - **oldest first**, always. The pipeline advances the watermark as it
///    goes, so a source that returned newest-first would let a high provider
///    id move the watermark past unprocessed messages. A fake that silently
///    sorted "helpfully" would hide that class of bug.
///  - **`limit` is honoured.** Batching is not decoration; ADR-006 gives the
///    broadcast worker roughly a 10-second budget.
///  - **[readCallCount]** is exposed so a test can assert *how many* reads a
///    resumed import performed — the difference between "resumed" and
///    "restarted from scratch and was saved by dedup" is invisible in the
///    final state but obvious in the call count.
///  - **[isReadable]** models the one distinction KHA-157 (A) turns on: an
///    inbox the app has no permission to read is not the same as an empty one.
///    A fake that could not express that could not have caught the 424-item
///    flood, which is precisely how the flood shipped.
final class FakeSmsSource implements SmsSource {
  final List<RawSmsRecord> messages;

  int readCallCount = 0;

  /// KHA-157 (A). `false` models a missing `READ_SMS` / `SecurityException`:
  /// every read comes back empty and [highWaterMark] comes back **null**,
  /// which the pipeline must treat as "seed nothing" rather than "seed zero".
  ///
  /// Mutable so a test can flip it mid-run — granting permission after a
  /// denied first sweep is the exact sequence the defect reproduced on.
  bool isReadable;

  /// Supplies the timestamp [highWaterMark] reports for a readable but
  /// **empty** inbox, mirroring `AndroidSmsSource`'s injected clock. Defaults
  /// to a fixed instant so tests are not time-dependent.
  DateTime emptyInboxNowUtc;

  /// How many times [highWaterMark] has been called. The seed must happen
  /// **once**, and "once" is invisible in the final state — a second seed of
  /// the same inbox writes the same values.
  int highWaterMarkCallCount = 0;

  FakeSmsSource(
    List<RawSmsRecord> messages, {
    this.isReadable = true,
    DateTime? emptyInboxNowUtc,
  }) : messages = List<RawSmsRecord>.of(messages)
         ..sort(
           (RawSmsRecord a, RawSmsRecord b) =>
               a.providerId.compareTo(b.providerId),
         ),
       emptyInboxNowUtc = emptyInboxNowUtc ?? DateTime.utc(2026, 7, 30, 9);

  /// Adds a message that "arrives" after construction, so a test can assert
  /// the property the seed must not break: a message newer than the seed is
  /// still ingested.
  void deliver(RawSmsRecord record) {
    messages
      ..add(record)
      ..sort(
        (RawSmsRecord a, RawSmsRecord b) =>
            a.providerId.compareTo(b.providerId),
      );
  }

  @override
  Future<InboxHighWaterMark?> highWaterMark() async {
    highWaterMarkCallCount++;
    if (!isReadable) {
      return null;
    }
    if (messages.isEmpty) {
      return InboxHighWaterMark(providerId: 0, dateUtc: emptyInboxNowUtc);
    }
    final RawSmsRecord newest = messages.last;
    return InboxHighWaterMark(
      providerId: newest.providerId,
      dateUtc: newest.receivedAt,
    );
  }

  @override
  Future<List<RawSmsRecord>> readSince(
    IngestCursor cursor, {
    int limit = 100,
  }) async {
    readCallCount++;
    if (!isReadable) {
      // What the real stack does: `SmsChannel.query` converts a
      // `SecurityException` into an empty list, so the run is a no-op and the
      // watermark does not move.
      return const <RawSmsRecord>[];
    }
    return messages
        .where(
          (RawSmsRecord m) => m.providerId > cursor.lastProcessedProviderId,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<RawSmsRecord>> readRange({
    required DateTime from,
    required int afterProviderId,
    required int limit,
  }) async {
    readCallCount++;
    if (!isReadable) {
      return const <RawSmsRecord>[];
    }
    return messages
        .where(
          (RawSmsRecord m) =>
              !m.receivedAt.isBefore(from) && m.providerId > afterProviderId,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<int> countRange({required DateTime from}) async {
    return messages
        .where((RawSmsRecord m) => !m.receivedAt.isBefore(from))
        .length;
  }
}
