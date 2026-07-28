/// The boundary between "the Android SMS content provider" and everything
/// else — `docs/architecture.md` §5.4 Contract C:
///
/// ```dart
/// abstract interface class SmsSource {          // data/sms → features/ingestion
///   Future<List<RawSmsRecord>> readSince(IngestWatermark w);
/// }
/// ```
///
/// ## Why the pipeline never touches a platform channel directly
///
/// The entire ingestion pipeline — classification, parsing, dedup, the
/// watermark, the review queue — can then be tested with an in-memory fake
/// inbox, on a laptop, in milliseconds, with no emulator. That is not a
/// nicety: the alternative is that the only way to test "does an interrupted
/// import resume without duplicating?" is to install an APK and kill it by
/// hand, which means in practice it never gets tested.
///
/// The **one** thing that genuinely cannot be tested this way is whether
/// Android actually delivers the broadcast on a given OEM's build. That is
/// the P0 spike (KHA-7) and a real-device check — see this phase's PR
/// description, which states plainly what was and was not verified.
library;

/// One row of `content://sms/inbox`, reduced to the four columns this app
/// reads.
///
/// **Nothing here is stored as-is.** The body goes through `SmsSanitizer`
/// (ADR-013) before it can reach the database, and for a non-financial sender
/// it is never persisted at all (NFR-P4). This type exists only in memory, on
/// the ingestion isolate, for the duration of one message's processing.
final class RawSmsRecord {
  /// The provider's `_id`. Monotonic within one SMS database, and the
  /// `UNIQUE` key on `raw_message.sms_provider_id` that makes a re-scan
  /// idempotent (AC-A3.3).
  final int providerId;

  /// The originating address — a short code (`BAJ`, `D360`) or a phone
  /// number. **Bank resolution keys on this**, which is what makes AC-A2.3
  /// ("a message from a person is never a transaction") absolute rather than
  /// heuristic.
  final String address;

  /// The message text, exactly as the provider holds it: multi-part messages
  /// already reassembled by the platform, no normalisation, no redaction.
  final String body;

  /// The provider's `date`, in UTC.
  ///
  /// This is when the *message arrived*, not when the *transaction happened*.
  /// They differ, sometimes by days for a delayed posting alert, which is why
  /// `Transaction.occurredAt` is parsed from the body and this value is only
  /// the `received_at_fallback`.
  final DateTime receivedAt;

  const RawSmsRecord({
    required this.providerId,
    required this.address,
    required this.body,
    required this.receivedAt,
  });

  /// Ids and a timestamp only — **never the body or the sender** (NFR-S4,
  /// ADR-015). An accidental `'$record'` in a log line is one of the easiest
  /// ways to leak an entire bank SMS into a diagnostic file.
  @override
  String toString() =>
      'RawSmsRecord(#$providerId, ${receivedAt.toIso8601String()})';
}

/// A position in the inbox: everything with a provider id greater than this
/// has not been processed yet.
final class IngestCursor {
  final int lastProcessedProviderId;
  final DateTime? lastProcessedDate;

  const IngestCursor({
    required this.lastProcessedProviderId,
    this.lastProcessedDate,
  });

  /// The starting position for a device that has never ingested anything.
  static const IngestCursor beginning = IngestCursor(
    lastProcessedProviderId: 0,
  );
}

/// Reads the device's SMS inbox.
abstract interface class SmsSource {
  /// Messages newer than [cursor], oldest first.
  ///
  /// Oldest-first ordering is required, not incidental: the pipeline advances
  /// the watermark as it goes, so processing out of order would let a
  /// high-id message advance the watermark past lower-id messages that were
  /// never processed — losing them silently, which NFR-A7 forbids.
  ///
  /// [limit] bounds one batch. ADR-006 gives the broadcast-triggered worker
  /// roughly a 10-second budget, so a first run against a large inbox must
  /// not try to do everything at once.
  Future<List<RawSmsRecord>> readSince(IngestCursor cursor, {int limit});

  /// Messages received at or after [from], **oldest first**, for the
  /// historical import (AC-A3.1: from the start of the current calendar
  /// month).
  ///
  /// [afterProviderId] is the resume point (AC-A3.3). Note this walks
  /// *forwards* from the oldest in-range message, which is what makes the
  /// cursor meaningful across a restart: a backwards walk's cursor would have
  /// to be reinterpreted whenever new messages arrived at the top.
  Future<List<RawSmsRecord>> readRange({
    required DateTime from,
    required int afterProviderId,
    required int limit,
  });

  /// How many messages the historical import will consider, for the progress
  /// bar on S-05 (AC-A3.2). A count, never content.
  Future<int> countRange({required DateTime from});
}
