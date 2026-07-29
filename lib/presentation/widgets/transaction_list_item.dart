/// **design.md §5's `TransactionListItem`** — the one row shape every list in
/// the app uses (KHA-36).
///
/// Rendered by S-10 (the transaction list), S-08 (Home's recent-activity
/// preview) and S-23/S-24 (instrument detail). One implementation on purpose:
/// three copies of "how a transaction looks in a list" is three chances for one
/// of them to forget a badge, and the badges here are acceptance criteria
/// rather than decoration.
///
/// ---
///
/// ## NFR-U4 — nothing on this row means anything by colour alone
///
/// This is the requirement KHA-36's done-check turns into a greyscale test, so
/// it is worth stating exactly which signal carries which fact:
///
/// | Fact | Non-colour carrier | Colour's role |
/// |---|---|---|
/// | credit vs debit (AC-B7.3) | the `+` / `−` prefix in the amount **text**, plus a `Semantics` label reading "Credit"/"Debit" | green on a credit, ink on a debit — reinforcement only |
/// | needs review (AC-C4.1) | a flag **icon** and the words "Needs review" | a warning tint behind the pill |
/// | entered by hand (AC-B4.3) | a pencil **icon** and the word "Manual" | a neutral tint |
/// | internal transfer (AC-B11.1) | a swap **icon**, the words "Internal transfer", and **no sign at all** | none |
///
/// Delete every colour from this file and each distinction above survives in
/// text and iconography. That is what `test/widget/p5a_greyscale_test.dart`
/// asserts, by collecting the strings and icons two rows render and proving
/// they differ.
///
/// The leading accent bar on a flagged row (design.md §5's
/// *"flagged-review (leading accent bar)"*) is the one purely-colour signal,
/// and it is deliberately **redundant** — the same row always carries the
/// worded badge, so the bar is a scanning aid, never the only clue.
///
/// ## Flutter notes for a newcomer
///
/// - `EdgeInsetsDirectional` / `BorderDirectional` rather than
///   `EdgeInsets.only(left:)`: the `start`/`end` forms flip automatically under
///   Arabic RTL, which is this app's primary direction (design.md §3.1). The
///   accent bar therefore sits on the right in Arabic and the left in English
///   with no branching.
/// - `Wrap` rather than `Row` for the badges: at the largest OS font size
///   (NFR-U3) three pills do not fit on one line, and a `Row` would overflow
///   with the yellow-and-black stripes instead of wrapping.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/learned_rules.dart';
import '../../features/ledger/internal_transfer.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';
import '../widgets/ledger_widgets.dart';

class TransactionListItem extends StatelessWidget {
  final LedgerTransaction transaction;

  /// `internal` | `candidate` | `external`, resolved by the caller from the
  /// **whole** ledger.
  ///
  /// Passed in rather than derived, for the reason `bank_tree.dart` and
  /// `transaction_detail_screen.dart` both give: an internal transfer is a
  /// property of a *pair*, and a row only ever holds one leg. A widget that
  /// worked it out for itself would always answer "not internal", which is
  /// exactly the bug US-B11 exists to prevent. Null falls back to the row's own
  /// persisted state, so a caller that has not wired the detector under-reports
  /// rather than mislabels.
  final String? internalTransferState;

  /// This transaction's category and how sure the app was (AC-C4.1). Null
  /// renders no chip — an invented *Uncategorized* pill would be a claim about
  /// the data rather than a statement about this widget's inputs.
  final CategoryAssignment? categoryAssignment;

  /// Opens S-11. Null renders a non-tappable row (used by the greyscale test
  /// and by any future read-only context).
  final VoidCallback? onTap;

  /// Opens the S-12 correction sheet straight from the chip — design.md §6.1's
  /// first entry point, and the reason the product's highest-frequency
  /// interaction is two taps from anywhere.
  final VoidCallback? onTapCategory;

  const TransactionListItem({
    required this.transaction,
    this.internalTransferState,
    this.categoryAssignment,
    this.onTap,
    this.onTapCategory,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final LedgerTransaction txn = transaction;
    final String? transferState =
        internalTransferState ?? txn.internalTransferState;
    final bool isInternal = transferState == InternalTransferState.internal;
    final bool isCandidate = transferState == InternalTransferState.candidate;

    // The headline is the merchant, or the counterparty on a transfer (a
    // transfer has no merchant but does have a payee), or the transaction type
    // when the message stated neither. Never blank, and never an invented
    // placeholder that could be mistaken for a real merchant name.
    final String headline =
        txn.merchantRawText ??
        txn.counterpartyName ??
        transactionTypeLabel(l10n, txn.transactionType);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 11, 8, 11),
        decoration: BoxDecoration(
          // design.md §5's flagged-review accent bar. Redundant with the
          // worded badge below by design — see the NFR-U4 table in this file's
          // doc comment.
          border: BorderDirectional(
            start: BorderSide(
              color: txn.needsReview
                  ? AppColors.warningFill
                  : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: AppColors.ink100),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    headline,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // AC-B1.3 — an absent date is stated, never rendered as a
                    // blank the user has to interpret.
                    txn.occurredAt == null
                        ? l10n.fieldNotStatedInMessage
                        : formatLocalizedDateTime(context, txn.occurredAt!),
                    style: text.bodySmall?.copyWith(color: AppColors.ink500),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      if (categoryAssignment != null)
                        CategoryChip(
                          category: categoryAssignment!.category,
                          band: categoryAssignment!.band,
                          compact: true,
                          onTap: onTapCategory,
                        ),
                      // AC-C4.1 — "the review indicator is visible in the
                      // transaction list", in words and an icon. The reason
                      // travels with it so the badge asks the question the app
                      // is actually asking, rather than reporting a status.
                      if (txn.needsReview)
                        NeedsReviewBadge(reviewReason: txn.reviewReason),
                      // AC-B4.3 — a hand-entered transaction is visually
                      // distinct from an SMS-derived one.
                      if (txn.isUserEntered) const _ManualBadge(),
                      if (isInternal || isCandidate)
                        InternalTransferBadge(isConfirmed: isInternal),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // A confirmed internal transfer carries **no +/− prefix at all**
            // (design.md §3.3): it is neither spend nor income, and a sign
            // would place it on a side of the ledger it does not belong to. A
            // *candidate* keeps its sign, because it is still being counted.
            if (isInternal)
              Text(
                '${formatAmountDigits(txn.amount)} ${txn.amount.currencyCode}',
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink700,
                ),
                textDirection: TextDirection.ltr,
              )
            else
              SignedAmountText(
                amount: txn.amount,
                isCredit: txn.isCredit,
                style: text.bodyLarge,
              ),
          ],
        ),
      ),
    );
  }
}

/// **AC-B4.3's badge.** An icon *and* the word, per NFR-U4.
///
/// Kept private to this file rather than added to `ledger_widgets.dart`: the
/// transaction detail screen has its own copy of this pill because it renders
/// it at a different size in a different container, and unifying two
/// three-line widgets would cost more in indirection than it saves.
class _ManualBadge extends StatelessWidget {
  const _ManualBadge();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.edit_outlined, size: 14, color: AppColors.ink700),
          const SizedBox(width: 4),
          Text(
            l10n.txnBadgeManual,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.ink700),
          ),
        ],
      ),
    );
  }
}
