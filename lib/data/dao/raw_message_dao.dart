import 'package:drift/drift.dart';

import '../../core/text/sms_sanitizer.dart';
import '../db/app_database.dart';
import '../db/tables/raw_message_table.dart';

part 'raw_message_dao.g.dart';

/// ADR-013's ingestion-boundary enforcement, expressed as a DAO signature:
/// [insert] takes a [SanitizedSmsText], never a plain `String`. There is no
/// way to write an unsanitised SMS body into the `raw_message` table — the
/// call simply will not compile if you try to pass a `String` where a
/// [SanitizedSmsText] is required.
@DriftAccessor(tables: [RawMessages])
class RawMessageDao extends DatabaseAccessor<AppDatabase>
    with _$RawMessageDaoMixin {
  RawMessageDao(super.attachedDatabase);

  /// Stores a message that was (or might yet be) a transaction — i.e. it
  /// has body text to keep, already redacted by [SmsSanitizer].
  ///
  /// [contentHmac] is the D1-exact dedup key (ADR-017) — computed by the
  /// caller (the future P2 ingestion pipeline) over the *normalised* body,
  /// sender, and timestamp, never over the redacted display text, so
  /// dedup semantics don't shift if a redaction rule changes later.
  /// [unparsedReason] / [unparsedRuleId] are set only for
  /// `classification: 'financial_unparsed'` — they are what lets the review
  /// queue tell the user *why* a message was not understood, and let the
  /// parser-health panel tell "the bank changed a template" apart from "the
  /// amount was missing" (two very different maintenance signals — risk R-4).
  Future<int> insert({
    String? smsProviderId,
    required String sender,
    required DateTime receivedAt,
    required SanitizedSmsText sanitizedText,
    required String contentHmac,
    String? bankId,
    required String classification,
    String? unparsedReason,
    String? unparsedRuleId,
  }) {
    return into(rawMessages).insert(
      RawMessagesCompanion.insert(
        smsProviderId: Value<String?>(smsProviderId),
        sender: sender,
        receivedAt: receivedAt,
        sanitizedBody: Value<String?>(sanitizedText.value),
        contentHmac: contentHmac,
        bankId: Value<String?>(bankId),
        classification: classification,
        panRedacted: Value<bool>(sanitizedText.panRedacted),
        unparsedReason: Value<String?>(unparsedReason),
        unparsedRuleId: Value<String?>(unparsedRuleId),
      ),
    );
  }

  /// The **unparsed** half of the Needs Review inbox (design.md S-18, US-A4).
  ///
  /// A Drift stream rather than a one-shot read, so the badge count on Home
  /// and the list itself update the moment a background ingestion run adds
  /// something — no polling, no manual refresh (architecture §7.5).
  ///
  /// Dismissed messages are excluded but **not deleted**: US-A4's "not a
  /// transaction" action must not resurrect the same message the next time
  /// the provider is swept.
  Stream<List<RawMessageRow>> watchReviewQueue() {
    return (select(rawMessages)
          ..where(
            (RawMessages t) =>
                t.classification.equals('financial_unparsed') &
                t.dismissedAsNotTransaction.equals(false),
          )
          ..orderBy(<OrderClauseGenerator<RawMessages>>[
            (RawMessages t) => OrderingTerm.desc(t.receivedAt),
          ]))
        .watch();
  }

  /// US-A4's "not a transaction" dismissal.
  ///
  /// Note this is an update, never a delete. Deleting would (a) lose the
  /// content-HMAC dedup key, so the next sweep would re-add the message, and
  /// (b) violate the spirit of NFR-A7 — the user said "not a transaction",
  /// not "pretend you never received this".
  Future<void> dismissAsNotTransaction(int id) {
    return (update(
      rawMessages,
    )..where((RawMessages t) => t.id.equals(id))).write(
      const RawMessagesCompanion(dismissedAsNotTransaction: Value<bool>(true)),
    );
  }

  Future<RawMessageRow?> byId(int id) {
    return (select(
      rawMessages,
    )..where((RawMessages t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Stores a content-free row for a message classified `intent: ignore`
  /// (OTP/marketing/info) from a known financial sender — NFR-P4's precise
  /// rule: "financial sender + intent:ignore -> row with sanitizedBody =
  /// NULL. Bank, classification, and timestamp only." There is no
  /// [SanitizedSmsText] parameter here at all, because there is no content
  /// to sanitize-and-keep in the first place.
  Future<int> insertIgnoredNoContent({
    String? smsProviderId,
    required String sender,
    required DateTime receivedAt,
    required String contentHmac,
    String? bankId,
    required String classification,
  }) {
    return into(rawMessages).insert(
      RawMessagesCompanion.insert(
        smsProviderId: Value<String?>(smsProviderId),
        sender: sender,
        receivedAt: receivedAt,
        contentHmac: contentHmac,
        bankId: Value<String?>(bankId),
        classification: classification,
      ),
    );
  }

  /// Looks up a message by its dedup key — the D1-exact carrier-retry
  /// check (ADR-017): if a row already exists for this HMAC, the incoming
  /// SMS is a duplicate delivery and should be suppressed silently.
  Future<RawMessageRow?> findByContentHmac(String contentHmac) {
    return (select(rawMessages)
          ..where((RawMessages t) => t.contentHmac.equals(contentHmac)))
        .getSingleOrNull();
  }

  Future<List<RawMessageRow>> all() => select(rawMessages).get();
}
