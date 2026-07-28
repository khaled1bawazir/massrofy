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
final class FakeSmsSource implements SmsSource {
  final List<RawSmsRecord> messages;

  int readCallCount = 0;

  FakeSmsSource(List<RawSmsRecord> messages)
    : messages = List<RawSmsRecord>.of(messages)
        ..sort(
          (RawSmsRecord a, RawSmsRecord b) =>
              a.providerId.compareTo(b.providerId),
        );

  @override
  Future<List<RawSmsRecord>> readSince(
    IngestCursor cursor, {
    int limit = 100,
  }) async {
    readCallCount++;
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
