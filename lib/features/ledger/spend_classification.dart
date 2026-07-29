/// What a movement *means* for the totals — KHA-28, KHA-29, US-B7, US-B10,
/// US-B11, AC-B7.1, AC-B10.1/2/3, AC-B11.1.
///
/// ---
///
/// ## One classifier, so two screens cannot disagree
///
/// Before this file, "does this count as spend?" was answered by the boolean
/// `affectsSpend` column alone — a value supplied by the *rule pack*. That is
/// right for a bank-specific fact ("this template is a card repayment") and
/// wrong as the last word on a domain invariant: a pack, especially an
/// imported one (ADR-007's answer to risk R-11), could assert that an
/// internal transfer *is* spend, and every total in the app would obey.
///
/// So classification is derived from the **type** (a closed vocabulary this
/// build owns, see `transaction_types.dart`) and the **direction**, with
/// `affectsSpend` demoted to a one-way veto:
///
/// > A pack may say *"this is not spend"* and be believed.
/// > A pack may not say *"this internal transfer is spend"*.
///
/// That keeps banks-as-data (packs still control the per-template facts)
/// without letting data overrule an invariant the PRD states three times.
///
/// ## The five outcomes, and why a withdrawal is none of the obvious ones
///
/// | [MovementClass] | Counts toward spend? | Why |
/// |---|---|---|
/// | [MovementClass.spend] | **+** | A purchase, a bill, a fee, a third-party transfer out |
/// | [MovementClass.spendCredit] | **−** | A refund or reversal. Nets against spend (AC-B7.1), never adds |
/// | [MovementClass.income] | no (counted as income) | Salary, third-party transfer in (AC-B10.1) |
/// | [MovementClass.cashWithdrawal] | no | AC-B10.2 — the money is still the user's, it has merely stopped being traceable. It becomes spend only when they record what the cash bought |
/// | [MovementClass.excluded] | no | Internal transfers (AC-B11.1), card repayment (settles spend already counted), and anything unclassifiable |
///
/// The withdrawal row is the one that surprises people. Treating an ATM
/// withdrawal as spend double-counts every cash purchase the user later
/// enters by hand; treating it as income is nonsense. It is a *transfer of
/// custody*, and reporting it on its own line is the only presentation that
/// does not mislead — which is why [PeriodReport] carries it separately
/// instead of folding it anywhere.
library;

import '../../core/money/sign_convention.dart';
import 'internal_transfer.dart';
import 'ledger_transaction.dart';
import 'transaction_types.dart';

/// How one transaction participates in the period figures.
enum MovementClass {
  /// Increases spend.
  spend,

  /// Decreases spend — a refund, reversal or merchant credit (US-B7).
  spendCredit,

  /// Money the user received and kept (AC-B10.1).
  income,

  /// Cash taken out (AC-B10.2). Neither spend nor income.
  cashWithdrawal,

  /// Deliberately in no total: internal transfers (AC-B11.1), card repayment,
  /// and movements this build cannot classify.
  excluded;

  /// True for the two classes that make up net spend.
  bool get isSpendComponent =>
      this == MovementClass.spend || this == MovementClass.spendCredit;
}

/// Why a movement was excluded — carried so a screen can say *"3 internal
/// transfers excluded"* rather than leaving a hole in the arithmetic the user
/// cannot account for (NFR-A6).
enum ExclusionReason {
  /// AC-B11.1 — a transfer between the user's own instruments.
  internalTransfer,

  /// Settles spend that was already counted when the card was used.
  cardRepayment,

  /// The rule pack declared `affectsSpend: false` for a type this build would
  /// otherwise have counted. Honoured (see the one-way veto above).
  packDeclaredNonSpend,

  /// Unknown type, unknown direction, or a contradictory combination — e.g. a
  /// `refund` recorded as a debit. Excluded rather than guessed, and surfaced
  /// for review (NFR-A7: never silently dropped, never silently counted).
  unclassifiable,
}

/// The classification of one transaction, with its reason.
final class SpendClassification {
  final MovementClass movementClass;

  /// Non-null exactly when [movementClass] is [MovementClass.excluded].
  final ExclusionReason? exclusionReason;

  /// True when the app could not classify this confidently and the user
  /// should be shown it. Drives AC-B11.2's flag.
  final bool needsReview;

  /// **KHA-80** — set when [needsReview] was raised because a transfer could
  /// not be *paired at all*, rather than because it was paired but unproven.
  ///
  /// Carried so the review inbox can say which of the two happened. "We found
  /// a matching transfer in another currency" and "we could not tell which
  /// account this reached" call for different sentences and, for the user,
  /// different next actions.
  final TransferReviewReason? transferReviewReason;

  const SpendClassification._(
    this.movementClass, {
    this.exclusionReason,
    this.needsReview = false,
    this.transferReviewReason,
  });

  /// Classifies [transaction].
  ///
  /// [transfers] supplies the internal-transfer analysis (see
  /// `internal_transfer.dart`). Passing [InternalTransferAnalysis.empty] is
  /// legitimate — it means "no pair information available for this slice" —
  /// but note that a per-instrument slice cannot see the other leg of a
  /// transfer, so callers that care about AC-B11.1 must analyse the **whole**
  /// transaction set and pass the result down. `BankTreeBuilder` does exactly
  /// that.
  factory SpendClassification.of(
    LedgerTransaction transaction, {
    required InternalTransferAnalysis transfers,
  }) {
    // --- 1. The invariant, checked before anything else can override it ----
    //
    // AC-B11.1. This is deliberately the first branch in the function: no
    // rule-pack flag, no transaction type and no direction can get a
    // determined internal transfer back into a spend total.
    final String? transferState = transfers.stateFor(transaction);
    if (transferState == InternalTransferState.internal) {
      return const SpendClassification._(
        MovementClass.excluded,
        exclusionReason: ExclusionReason.internalTransfer,
      );
    }

    // A candidate keeps counting (architecture §4.2: candidates do not change
    // totals until confirmed) but is flagged, so the user is told the figure
    // in front of them may include a transfer to themselves — AC-B11.2, and
    // risk R-7's bootstrap problem made visible rather than guessed at.
    final bool candidateTransfer =
        transferState == InternalTransferState.candidate;

    // **KHA-80.** The other half of AC-B11.2's "flagged, not silently
    // classified": a transfer the detector could not pair at all — a
    // cross-currency near-match, or a leg whose instrument never resolved.
    // Before this, such a transfer was counted as ordinary spend carrying no
    // flag, which met the arithmetic half of the criterion (the figure is
    // over-stated, never under-stated) and failed the honesty half completely.
    final TransferReviewReason? unpairable = transfers.unpairableReasonFor(
      transaction,
    );
    final bool needsTransferReview = candidateTransfer || unpairable != null;

    // --- 2. Direction has to be one of the two we understand --------------
    if (!MovementDirection.isKnown(transaction.direction)) {
      return const SpendClassification._(
        MovementClass.excluded,
        exclusionReason: ExclusionReason.unclassifiable,
        needsReview: true,
      );
    }
    final bool isCredit = transaction.direction == MovementDirection.credit;

    // --- 3. Type-driven classification ------------------------------------
    switch (transaction.transactionType) {
      case TransactionType.refund:
        // A refund recorded as a debit is a contradiction — either the pack
        // is wrong or the message was misread. Neither is something to
        // silently add to spend.
        return isCredit
            ? const SpendClassification._(MovementClass.spendCredit)
            : const SpendClassification._(
                MovementClass.excluded,
                exclusionReason: ExclusionReason.unclassifiable,
                needsReview: true,
              );

      case TransactionType.salaryIncome:
      case TransactionType.transferIn:
        return SpendClassification._(
          MovementClass.income,
          needsReview: needsTransferReview,
          transferReviewReason: unpairable,
        );

      case TransactionType.withdrawal:
        return const SpendClassification._(MovementClass.cashWithdrawal);

      case TransactionType.cardRepayment:
        return const SpendClassification._(
          MovementClass.excluded,
          exclusionReason: ExclusionReason.cardRepayment,
        );

      case TransactionType.posPurchase:
      case TransactionType.onlinePurchase:
      case TransactionType.billPayment:
      case TransactionType.fee:
      case TransactionType.installment:
      case TransactionType.accountDebit:
      case TransactionType.transferOut:
      case TransactionType.adjustment:
        return _spendOrVeto(
          transaction,
          isCredit: isCredit,
          needsReview: needsTransferReview,
          transferReviewReason: unpairable,
        );

      default:
        // An unknown type from a newer imported pack (§5.2 forward
        // compatibility). It is recorded and listed — NFR-A7 — but it is not
        // counted, because counting a movement we cannot name is how a total
        // becomes unexplainable.
        return const SpendClassification._(
          MovementClass.excluded,
          exclusionReason: ExclusionReason.unclassifiable,
          needsReview: true,
        );
    }
  }

  /// The spend branch, with the rule pack's one-way veto applied.
  ///
  /// A credit on a spend-shaped type (a merchant reversal that the bank sent
  /// on its purchase template, say) still nets against spend rather than
  /// being dropped: the money genuinely came back.
  static SpendClassification _spendOrVeto(
    LedgerTransaction transaction, {
    required bool isCredit,
    required bool needsReview,
    TransferReviewReason? transferReviewReason,
  }) {
    if (!transaction.affectsSpend) {
      return const SpendClassification._(
        MovementClass.excluded,
        exclusionReason: ExclusionReason.packDeclaredNonSpend,
      );
    }
    return SpendClassification._(
      isCredit ? MovementClass.spendCredit : MovementClass.spend,
      needsReview: needsReview,
      transferReviewReason: transferReviewReason,
    );
  }

  @override
  String toString() =>
      'SpendClassification(${movementClass.name}'
      '${exclusionReason == null ? '' : ', ${exclusionReason!.name}'})';
}
