/// The **unparsed review queue** — US-A4, AC-A4.1–A4.4, NFR-A7, Linear
/// KHA-22.
///
/// ## This is a correctness feature wearing a UI costume
///
/// KHA-22 states the bar plainly:
///
/// > *"If a message is judged financial but is neither converted to a
/// > transaction nor placed in this queue, **that is a defect**. The user must
/// > be able to trust that nothing is missing — that trust is the entire
/// > product."*
///
/// A spending tracker that quietly drops the messages it does not understand
/// produces a total that is confidently, invisibly wrong. Every other feature
/// in Massrofy is downstream of the user believing the number. The review
/// queue is what makes that belief justified: when the parser fails, the
/// failure is **visible and actionable** rather than silent.
///
/// ## Where the data comes from, and why there is no separate table
///
/// The queue is a *view* over `raw_message`, not its own table:
///
/// ```sql
/// WHERE classification = 'financial_unparsed'
///   AND dismissed_as_not_transaction = 0
/// ```
///
/// A dedicated table would mean two rows per message and two places for them
/// to disagree — and the disagreement would take the form of a message
/// existing in one and not the other, which is the exact failure NFR-A7
/// forbids. One row, one classification, one truth.
///
/// ## Dismissal is an update, never a delete
///
/// US-A4's "not a transaction" action sets `dismissedAsNotTransaction`. It
/// must not delete the row, for two independent reasons:
///
/// 1. The row holds the content HMAC (ADR-017 D1). Delete it and the next
///    provider sweep re-ingests the same message and it reappears in the
///    queue — a bug that looks like the app ignoring the user.
/// 2. The user said "this is not a transaction", not "pretend you never
///    received this". Keeping the row is what lets the parser-health panel
///    report honestly on what the parser missed.
library;

import '../parsing/partial_extraction.dart';

/// One item in the "not understood" tab (design.md S-18).
///
/// A plain value type rather than a Drift row so the widget layer never
/// imports `data/` — architecture §3's dependency rule — and so widget tests
/// need no database at all.
final class ReviewQueueItem {
  /// `raw_message.id`. What "fill in details" (S-19) and "not a transaction"
  /// act on.
  final int rawMessageId;

  /// The **sanitised** body (ADR-013). AC-A4.1 requires the original text to
  /// be shown so the user can see what the parser saw — and this is exactly
  /// why it is redacted *at the ingestion boundary* rather than at display
  /// time: by the time it reaches a widget there is no PAN, CVV or PIN left
  /// in it to leak into a screenshot or an accessibility tree.
  final String sanitizedBody;

  final String sender;
  final DateTime receivedAt;

  /// The resolved bank, when the sender matched one. Always non-null in
  /// practice for this queue — a message only reaches it if the sender was
  /// recognised — but nullable so a future ingestion path cannot be blocked
  /// by this type.
  final String? bankId;

  /// An `UnparsedReason` constant. Drives the plain-language explanation:
  /// "did not match any known format" (the bank changed a template, risk R-4)
  /// reads very differently to the user than "some details were missing".
  final String? unparsedReason;

  /// The rule that matched but could not complete, when there was one. Not
  /// shown to the user; carried for the parser-health panel (ADR-015), where
  /// "rule X is failing 40 times a month" is the signal a maintainer needs.
  final String? unparsedRuleId;

  /// **KHA-146** — what the parser DID read, when a rule matched and extracted
  /// but then failed its `requiredFields` check.
  ///
  /// `null` in the other case, and the distinction is the whole point: a
  /// message no rule recognised has nothing to pre-fill, and S-19 correctly
  /// shows a blank form for it. A message that failed on one field arrives
  /// here with the other four, and S-19 pre-fills them.
  ///
  /// **Suggestions for a form, not a transaction.** Nothing on this type is
  /// summed or counted anywhere; the values become money only when the user
  /// presses "Save as transaction". See `partial_extraction.dart`.
  final PartialExtraction? partialExtraction;

  const ReviewQueueItem({
    required this.rawMessageId,
    required this.sanitizedBody,
    required this.sender,
    required this.receivedAt,
    this.bankId,
    this.unparsedReason,
    this.unparsedRuleId,
    this.partialExtraction,
  });

  /// Ids and a timestamp only. **Never the body** — this type exists to carry
  /// message text around the UI, which makes an accidental
  /// `'$item'` in a log line one of the more plausible leaks in the app
  /// (NFR-S4, ADR-015).
  @override
  String toString() =>
      'ReviewQueueItem(#$rawMessageId, ${receivedAt.toIso8601String()})';
}

/// **KHA-157 (E)** — how many still-pending unparsed items arrived *before*
/// the window AC-A3.1 authorised, and where that window starts.
///
/// ## Why the date travels with the count
///
/// The offer this drives is *"N items received before &lt;date&gt; — discard
/// them"*, and the date is not decoration: it is the claim the user can check
/// against the list in front of them before agreeing to a deletion. A bare
/// "discard 424 items" asks them to trust an unexplained number.
///
/// A plain value type in `features/`, like every other type on this screen, so
/// the widget layer never imports `data/` (architecture §3) and widget tests
/// need no database. `OutOfWindowDiscard` in `out_of_window_discard.dart`
/// produces it; the screen only ever reads it.
final class OutOfWindowReviewSummary {
  final int itemCount;

  /// `min(importFromDate, startOfCurrentMonthUtc(now))` — AC-A3.1's lower
  /// bound as this app actually computes it, in UTC. The screen shifts it into
  /// Riyadh wall-clock time before printing.
  final DateTime windowStartUtc;

  const OutOfWindowReviewSummary({
    required this.itemCount,
    required this.windowStartUtc,
  });

  /// Nothing to offer — the overwhelmingly common case. A healthy install has
  /// never had an out-of-window message, so the banner never appears at all.
  bool get hasItems => itemCount > 0;

  /// A count and a date. No sender, no body (NFR-S4).
  @override
  String toString() =>
      'OutOfWindowReviewSummary($itemCount before '
      '${windowStartUtc.toIso8601String()})';
}

/// One item in the "low confidence" tab: a transaction that *was* parsed but
/// is flagged for the user — including ADR-017's possible duplicates
/// (AC-A5.2).
///
/// Kept as a **separate type and a separate tab**, per design.md S-18's
/// "never conflated". The two problems have different fixes: an unparsed
/// message needs the user to supply missing facts, whereas a flagged
/// transaction needs them to make a judgement about something already
/// recorded. Merging the lists would make both harder.
final class FlaggedTransactionItem {
  final int transactionId;

  /// Exact decimal string plus currency, never a `double` (ADR-002). The
  /// presentation layer formats it; it is never arithmetic here.
  final String amount;
  final String currencyCode;

  final String? merchantRawText;
  final DateTime? occurredAt;

  /// A `ReviewReason` constant, e.g. `possible_duplicate`.
  final String? reviewReason;

  /// The transaction this one may duplicate. **Both remain in the list and in
  /// every total** until the user decides — ADR-017 never auto-removes.
  final int? possibleDuplicateOfId;

  const FlaggedTransactionItem({
    required this.transactionId,
    required this.amount,
    required this.currencyCode,
    this.merchantRawText,
    this.occurredAt,
    this.reviewReason,
    this.possibleDuplicateOfId,
  });

  /// No amount, no merchant (NFR-S4).
  @override
  String toString() => 'FlaggedTransactionItem(#$transactionId)';
}

/// **KHA-78 / KHA-80 — a transfer awaiting the user's judgement.**
///
/// A third item type, and a third tab, rather than more rows in the
/// low-confidence list. design.md S-18's rule is *"never conflated"*, and the
/// reason generalises: each tab asks the user one kind of question. Unparsed
/// messages ask for **facts** the app is missing. Duplicate flags ask *"are
/// these the same thing?"*. A transfer asks *"is this account yours?"* — a
/// question about the world outside the app, which no amount of parsing could
/// ever answer. Mixing it in with duplicates would put two unrelated decisions
/// under one heading and make both slower.
final class TransferReviewItem {
  final int transactionId;

  /// The other leg, when the detector found a pair (KHA-78's candidate case).
  /// **Null for KHA-80's unpairable case** — a cross-currency near-match or a
  /// leg whose instrument never resolved — where there is no second row to act
  /// on together with this one.
  final int? counterpartTransactionId;

  /// `InternalTransferLink.groupId` for a pair; null when unpairable.
  final String? groupId;

  /// Exact decimal string plus currency, never a `double` (ADR-002).
  final String amount;
  final String currencyCode;

  final String? counterpartyName;
  final DateTime? occurredAt;

  /// Null for a paired candidate (the app found a partner but cannot prove
  /// it); set for KHA-80's unpairable cases, so the card can explain which
  /// specific thing stopped the match.
  final String? unpairableReasonKey;

  const TransferReviewItem({
    required this.transactionId,
    required this.amount,
    required this.currencyCode,
    this.counterpartTransactionId,
    this.groupId,
    this.counterpartyName,
    this.occurredAt,
    this.unpairableReasonKey,
  });

  /// True when both legs are known, so confirming can exclude the pair.
  ///
  /// When false, only rejection is offered — see
  /// `InternalTransferDecisionService.dismissUnpairable` for why confirming a
  /// single leg would produce figures that reconcile with nothing.
  bool get isPair => counterpartTransactionId != null && groupId != null;

  /// No amount, no counterparty (NFR-S4).
  @override
  String toString() => 'TransferReviewItem(#$transactionId, pair: $isPair)';
}
