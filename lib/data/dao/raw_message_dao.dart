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
  ///
  /// [partialExtractionJson] is **KHA-146**: `PartialExtraction.encode()` for a
  /// message whose rule extracted successfully and then failed its
  /// `requiredFields` check, so the completion form can pre-fill what the
  /// parser already read. `null` for every other row — including every message
  /// that matched no rule at all, where a blank form is the correct outcome.
  /// It is unconfirmed form data, never a transaction; see
  /// `lib/features/parsing/partial_extraction.dart`.
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
    String? partialExtractionJson,
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
        partialExtraction: Value<String?>(partialExtractionJson),
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
          ..where(_isPendingReviewItem)
          ..orderBy(<OrderClauseGenerator<RawMessages>>[
            (RawMessages t) => OrderingTerm.desc(t.receivedAt),
          ]))
        .watch();
  }

  /// **"Still pending in the Needs Review inbox"**, as one expression rather
  /// than as a `WHERE` clause copied per query.
  ///
  /// KHA-157 (E) adds a *destructive* query keyed on exactly this predicate,
  /// and a second hand-written copy of it is the obvious way for "what the
  /// user is looking at" and "what the button deletes" to drift apart — which
  /// on a delete means removing a row the user was never shown. One
  /// definition, used by the queue stream, the count and the delete.
  Expression<bool> _isPendingReviewItem(RawMessages t) =>
      t.classification.equals('financial_unparsed') &
      t.dismissedAsNotTransaction.equals(false);

  /// **KHA-157 (E)** — still-pending review items that arrived *before*
  /// [cutoffUtc], the lower bound of the window AC-A3.1 authorised.
  ///
  /// A count, for the banner. Content never leaves this method.
  ///
  /// Strictly `<`, matching [deletePendingReviewReceivedBefore] exactly: a
  /// message received at the very instant the window opens is **inside** it
  /// and is not the flood's.
  Future<int> countPendingReviewReceivedBefore(DateTime cutoffUtc) async {
    final Expression<int> rows = rawMessages.id.count();
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        (selectOnly(rawMessages)..addColumns(<Expression<Object>>[rows]))
          ..where(
            _isPendingReviewItem(rawMessages) &
                rawMessages.receivedAt.isSmallerThanValue(cutoffUtc),
          );
    return await query.map((TypedResult r) => r.read(rows)).getSingle() ?? 0;
  }

  /// **KHA-157 (E)** — the user-triggered, date-bounded discard.
  ///
  /// Returns how many rows were removed.
  ///
  /// ## This one really does delete, and that is not a contradiction
  ///
  /// Every other exit from this queue is an update — see
  /// [dismissAsNotTransaction] for the two reasons deleting is normally wrong.
  /// Both of them are answered here, and only here:
  ///
  ///  1. *"Deleting loses the content HMAC, so the next sweep re-adds it."*
  ///     It cannot. These rows are, by the definition of [cutoffUtc], older
  ///     than every window the app will ever read again: the incremental
  ///     watermark is above them (that is how they got here), and KHA-133's
  ///     re-scan window is `min(importFromDate, startOfCurrentMonthUtc(now))`,
  ///     which is the very bound being passed in. Nothing reaches back past
  ///     it, so there is nothing for a dedup key to protect against.
  ///  2. *"The user said 'not a transaction', not 'forget this'."* Here they
  ///     said exactly the second thing. AC-A3.1 never authorised retaining
  ///     this text at all — it was read by the KHA-157 defect — so deleting it
  ///     **reduces** what the app holds to what the ACs already promised.
  ///
  /// The action is recorded in the ADR-010 audit trail by the caller, which is
  /// what keeps "424 rows vanished" answerable afterwards.
  Future<int> deletePendingReviewReceivedBefore(DateTime cutoffUtc) {
    return (delete(rawMessages)..where(
          (RawMessages t) =>
              _isPendingReviewItem(t) &
              t.receivedAt.isSmallerThanValue(cutoffUtc),
        ))
        .go();
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

  /// **AC-A4.2 / KHA-64** — the message has been turned into a real
  /// transaction by hand, so it leaves the review queue.
  ///
  /// Like [dismissAsNotTransaction] this is an update, never a delete, and
  /// for the same two reasons: the row holds the content HMAC that stops the
  /// next provider sweep re-ingesting the message, and AC-B1.2 needs the
  /// original text to stay readable from the transaction it produced.
  ///
  /// Reclassifying to `financial_parsed` is what removes it from the queue —
  /// the queue is a view over `classification`, so there is one fact to
  /// change and no second list to keep in step (see `review_queue.dart`).
  ///
  /// `unparsedReason` / `unparsedRuleId` are deliberately **left in place**.
  /// The parser genuinely did fail on this message, and the parser-health
  /// panel (ADR-015) should keep counting that failure — a human filling the
  /// gap in by hand does not mean the rule pack no longer needs fixing.
  ///
  /// So is `partialExtraction` (KHA-146), for the same reason and one more:
  /// it is the record of *what the app suggested* on the form the user just
  /// confirmed, which is the only way to answer "why was that figure already
  /// filled in?" later. It is read solely by the completion form, and this row
  /// has just left the queue that form is reached from, so leaving it costs
  /// nothing and removes a fact nobody can reconstruct.
  Future<void> markCompletedIntoTransaction(int id) {
    return (update(
      rawMessages,
    )..where((RawMessages t) => t.id.equals(id))).write(
      const RawMessagesCompanion(
        classification: Value<String>('financial_parsed'),
      ),
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

  /// Looks up a message by the **inbox row** it came from — D1's *other*
  /// UNIQUE key (ADR-017), and the one that makes a re-scan of already-swept
  /// ground safe (AC-A3.3).
  ///
  /// ## Why this exists at all, given [findByContentHmac] already deduped
  ///
  /// Because the two keys genuinely catch different things, and until KHA-133
  /// only one of them was ever *pre-checked*:
  ///
  ///  - `content_hmac` catches a **carrier redelivery** — the same text
  ///    arriving as a brand-new provider row (AC-A5.1);
  ///  - `sms_provider_id` catches **the same inbox row read twice**, which is
  ///    exactly what the historical import and the KHA-133 re-scan do.
  ///
  /// Those overlap in the happy case, so the missing pre-check was invisible.
  /// It stops being invisible the moment a rule pack changes a bank's
  /// `redact[]` array: `contentHmac` is computed over text sanitised with
  /// those patterns, so the recomputed hmac for an already-stored message no
  /// longer matches, [findByContentHmac] misses, and the insert slams into the
  /// `sms_provider_id` UNIQUE constraint instead. Drift throws, the pipeline's
  /// per-message `catch` counts `failedWithError`, the watermark stops
  /// advancing — and a completely benign duplicate is reported to the user as
  /// a stalled pipeline. Every `redact` array in the bundled pack is `[]`
  /// today, which is the only reason this is latent rather than live.
  ///
  /// Pre-checking both keys converts that unhandled constraint violation into
  /// the counted `suppressedAsExactDuplicate` outcome ADR-017 D1 already
  /// specifies. See `docs/architecture.md` ADR-006, KHA-133 subsection, Q1.
  ///
  /// A `NULL` `sms_provider_id` (a manually entered transaction has no inbox
  /// row) can never match: SQL `=` is never true against `NULL`.
  Future<RawMessageRow?> findBySmsProviderId(String smsProviderId) {
    return (select(rawMessages)
          ..where((RawMessages t) => t.smsProviderId.equals(smsProviderId)))
        .getSingleOrNull();
  }

  Future<List<RawMessageRow>> all() => select(rawMessages).get();
}
