/// ADR-017 — duplicate detection, with a bias that is stated out loud because
/// getting it backwards is unrecoverable.
///
/// ## The tension, and why it cannot be resolved by being clever
///
/// Three acceptance criteria pull in opposite directions:
///
///  - **AC-A5.1** — the *same message*, delivered twice by the carrier, must
///    produce one transaction.
///  - **AC-A5.2** — an *authorisation* alert and a *posting* alert for the
///    same charge must be **flagged for confirmation**, not silently merged
///    and not silently double-counted.
///  - **AC-A5.3** — two *genuinely separate* purchases at the same merchant,
///    for the same amount, on the same day must **both be kept**.
///
/// AC-A5.2 and AC-A5.3 can produce byte-identical evidence. No heuristic can
/// separate them, and pretending otherwise is how a spending tracker deletes a
/// real transaction. So ADR-017 makes an explicit, asymmetric choice:
///
/// > **Suppress only exact duplicates. Flag, never auto-remove, everything
/// > else.**
///
/// The asymmetry is the point. An **inflated total is visible and
/// correctable** — the user sees two rows and merges them. A **silently
/// deleted real transaction is invisible and uncorrectable** — the user never
/// learns it existed. Banking default: prefer the auditable, recoverable
/// error. Linear KHA-21's done check asks for a test asserting no code path
/// deletes a transaction as a duplicate without explicit user confirmation;
/// this file is written so that test is easy to keep true.
///
/// ## Scope note: what is fully live in P2 and what waits for P3
///
/// - **D1 (exact)** is fully live. It is enforced by two `UNIQUE` constraints
///   in the schema, so it holds even against a bug in this file.
/// - **D2 (reference number)** detects the match and reports it. The
///   *enrichment merge* it prescribes needs the P3 domain model (merging two
///   partial transactions into one is a domain operation over fields that do
///   not all exist yet), so P2 flags the pair rather than merging. That is
///   the safe direction to be incomplete in: a flagged pair is visible,
///   a botched merge is not.
/// - **D3 (heuristic)** is fully live as a flag, which is all ADR-017 ever
///   permits it to be.
library;

import '../../core/money/money.dart';

/// The tier that fired, in ADR-017's own vocabulary.
enum DuplicateTier {
  /// D1 — same provider row, or same content HMAC. A carrier redelivery or a
  /// re-scan of a message we already have.
  exact,

  /// D2 — same reference number on the same instrument. The bank's own
  /// identifier says these are the same movement.
  referenceNumber,

  /// D3 — same instrument, amount, currency, and within the time window;
  /// merchants equal, or one message is an authorisation and the other a
  /// posting.
  heuristic,

  /// Not a duplicate of anything we hold.
  none,
}

/// What the pipeline should do, and — critically — what it must never do.
///
/// Note there is **no `delete` case**. That absence is the control: a code
/// path that wanted to remove an existing transaction as a duplicate would
/// have to add a case here, in this file, under this doc comment, where a
/// reviewer would see it.
enum DuplicateAction {
  /// Write the transaction normally.
  accept,

  /// Do not write anything. The message is byte-identical to one already
  /// stored; there is no new information in it at all. A diagnostic event is
  /// recorded so a "why is this missing?" question is answerable later
  /// (ADR-017 D1: "suppress silently, but write a diagnostic event").
  suppress,

  /// Write the transaction **and** mark it, and its counterpart, as a
  /// possible duplicate awaiting the user's decision. Both rows stay in the
  /// list and in every total until the user chooses (design.md S-46).
  acceptAndFlag,
}

/// The subset of an already-stored transaction that dedup compares against.
///
/// Deliberately not the full row: dedup must not start depending on fields
/// that P3 has not built yet, and a narrow input makes the decision function
/// pure and exhaustively testable.
final class DuplicateCandidate {
  final int transactionId;
  final String? instrumentMaskedRef;
  final Money? amount;
  final DateTime? occurredAt;
  final String? referenceNumber;
  final String? merchantRawText;
  final String transactionType;

  const DuplicateCandidate({
    required this.transactionId,
    required this.transactionType,
    this.instrumentMaskedRef,
    this.amount,
    this.occurredAt,
    this.referenceNumber,
    this.merchantRawText,
  });
}

/// The dedup verdict for one incoming transaction.
final class DuplicateDecision {
  final DuplicateTier tier;
  final DuplicateAction action;

  /// The existing transaction this one relates to, when there is one.
  final int? matchedTransactionId;

  /// A machine-readable reason for `Transaction.reviewReason`. Never free
  /// text: it is aggregated by the parser-health panel and rendered as
  /// localised copy in the UI, and neither works with a prose string.
  final String? reviewReason;

  const DuplicateDecision({
    required this.tier,
    required this.action,
    this.matchedTransactionId,
    this.reviewReason,
  });

  static const DuplicateDecision accept = DuplicateDecision(
    tier: DuplicateTier.none,
    action: DuplicateAction.accept,
  );
}

/// `Transaction.reviewReason` values produced by dedup.
abstract final class ReviewReason {
  static const String possibleDuplicate = 'possible_duplicate';
  static const String possibleAuthorisationPosting =
      'possible_authorisation_posting_pair';
}

abstract final class DuplicatePolicy {
  /// ADR-017 D3's time window. Deliberately generous: an authorisation and
  /// its posting can be minutes apart, and the cost of a false *flag* is one
  /// tap, while the cost of a missed pair is a permanently inflated total the
  /// user has to hunt for.
  static const Duration heuristicWindow = Duration(minutes: 15);

  /// Message types that represent a *hold* rather than a settled movement.
  ///
  /// Empty in P2, and that is a deliberate, recorded gap rather than an
  /// oversight: neither sampled bank's nine observed message types (PRD §3.4)
  /// includes a distinct authorisation template, so there is nothing to put
  /// here yet that would not be invented. The D3 rule below is written to
  /// consult this set so that adding one message type is the entire change —
  /// no logic edit. Until then, an auth/posting pair from these banks is
  /// caught by the merchant-equality half of D3 instead.
  static const Set<String> authorisationTypes = <String>{};

  /// Decides what to do with an incoming transaction, given what is already
  /// stored.
  ///
  /// **Pure**: no database, no clock, no I/O. Every ADR-017 tier is therefore
  /// testable as a table of inputs and expected verdicts, which is exactly
  /// what KHA-21's done check asks for.
  ///
  /// D1 is *not* evaluated here — it is enforced by `UNIQUE` constraints on
  /// `raw_message.sms_provider_id` and `raw_message.content_hmac`, i.e. at
  /// the database layer, where it holds against any writer. See
  /// `IngestionPipeline`.
  static DuplicateDecision decide({
    required String? incomingInstrumentRef,
    required Money? incomingAmount,
    required DateTime? incomingOccurredAt,
    required String? incomingReferenceNumber,
    required String? incomingMerchant,
    required String incomingType,
    required List<DuplicateCandidate> existing,
  }) {
    // --- D2: the bank's own identifier ------------------------------------
    //
    // PRD §3.4 confirms transfers carry a reference number. Where one exists
    // it is authoritative — far better than any heuristic — but note it is
    // still only a *flag* here, not a merge: see the scope note in the
    // library doc comment for why the merge waits for P3.
    if (incomingReferenceNumber != null &&
        incomingReferenceNumber.isNotEmpty &&
        incomingInstrumentRef != null) {
      for (final DuplicateCandidate candidate in existing) {
        if (candidate.referenceNumber == incomingReferenceNumber &&
            candidate.instrumentMaskedRef == incomingInstrumentRef) {
          return DuplicateDecision(
            tier: DuplicateTier.referenceNumber,
            action: DuplicateAction.acceptAndFlag,
            matchedTransactionId: candidate.transactionId,
            reviewReason: ReviewReason.possibleDuplicate,
          );
        }
      }
    }

    // --- D3: the heuristic ------------------------------------------------
    if (incomingAmount == null ||
        incomingOccurredAt == null ||
        incomingInstrumentRef == null) {
      // Not enough to compare on. Accept — never guess. A transaction we
      // cannot compare is not thereby a duplicate.
      return DuplicateDecision.accept;
    }

    for (final DuplicateCandidate candidate in existing) {
      if (candidate.instrumentMaskedRef != incomingInstrumentRef) continue;
      if (candidate.amount == null || candidate.occurredAt == null) continue;

      // `Money`'s `==` compares amount **and** currency, so 100 USD never
      // matches 100 SAR here. That is ADR-002 doing its job — a cross-currency
      // comparison that silently succeeded would be exactly the class of
      // error the whole money type exists to prevent.
      if (candidate.amount != incomingAmount) continue;

      final Duration gap = candidate.occurredAt!
          .difference(incomingOccurredAt)
          .abs();
      if (gap > heuristicWindow) continue;

      final bool sameMerchant =
          incomingMerchant != null &&
          candidate.merchantRawText != null &&
          candidate.merchantRawText == incomingMerchant;

      final bool authPostingPair =
          authorisationTypes.contains(incomingType) !=
          authorisationTypes.contains(candidate.transactionType);

      if (sameMerchant || authPostingPair) {
        return DuplicateDecision(
          tier: DuplicateTier.heuristic,
          action: DuplicateAction.acceptAndFlag,
          matchedTransactionId: candidate.transactionId,
          reviewReason: authPostingPair
              ? ReviewReason.possibleAuthorisationPosting
              : ReviewReason.possibleDuplicate,
        );
      }
    }

    return DuplicateDecision.accept;
  }
}
