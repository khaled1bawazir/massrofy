import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'ledger_widgets.dart';

/// **S-32 — Spent vs Kept.** AC-B10.3, US-B10, US-B11.
///
/// ## What this card is for
///
/// *"A 'spent vs kept' summary nets spend against income for the period
/// rather than showing spend alone"* (AC-B10.3). The product's stated goal is
/// total spent vs total kept, not card spend — capability C15 — and a screen
/// that shows only outgoings answers a narrower question than the user asked.
///
/// ## Why every component is on its own row
///
/// The netting has to be **checkable**. NFR-A6 forbids a derived figure the
/// user cannot trace to its constituents, and "kept = received − spent" is a
/// derivation like any other: showing only the answer would make it exactly
/// the kind of number this app exists to replace. So received, spent and the
/// net are three rows, and the two figures that are deliberately *not* in the
/// arithmetic — cash withdrawn (AC-B10.2) and internal transfers excluded
/// (AC-B11.1) — are shown underneath rather than left as an unexplained gap
/// between the ledger and the total.
///
/// ## Scope note
///
/// design.md places S-32 in the P5 reporting screens. This card is the
/// **domain figure made reachable now**, on the post-unlock screen, because a
/// computation with no production call site is library code rather than
/// shipped behaviour (the P1 review's finding). P5 owns the full screen —
/// period selector, chart, drill-down — and will render the same
/// [PeriodReport].
class SpentVsKeptCard extends StatelessWidget {
  final PeriodReport report;

  const SpentVsKeptCard({required this.report, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final Money? kept = report.netKept;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.spentVsKeptTitle,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _Row(
            label: l10n.spentVsKeptIncome,
            totals: report.income,
            sign: TotalsSign.credit,
          ),
          _Row(label: l10n.spentVsKeptSpent, totals: report.spend),
          const Divider(height: 20),
          // The net. Null when neither side has a base-currency figure —
          // netting a known number against an unknown one produces something
          // that looks authoritative and is not, so the card shows the
          // empty-state words instead (see `PeriodReport.netKept`).
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.spentVsKeptNet,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (kept == null)
                Text(
                  l10n.totalsNoneForPeriod,
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                )
              else
                // A negative "kept" means the period spent more than it
                // received, which is a real and important state — it is shown
                // with the same sign vocabulary as everything else rather
                // than being clamped or coloured into an alarm.
                SignedAmountText(
                  amount: kept.abs,
                  isCredit: !kept.isNegative,
                  style: text.titleMedium,
                ),
            ],
          ),
          // Both of these are money that moved without being spent or
          // received, so neither carries a sign (design.md §3.3). Putting a
          // "−" on cash withdrawn would make it read as spending, which is
          // exactly the reading AC-B10.2 exists to prevent.
          if (!report.cashWithdrawals.isEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _Row(
              label: l10n.spentVsKeptCashOut,
              totals: report.cashWithdrawals,
              sign: TotalsSign.none,
            ),
          ],
          if (!report.internalTransfers.isEmpty)
            _Row(
              label: l10n.spentVsKeptInternalExcluded,
              totals: report.internalTransfers,
              sign: TotalsSign.none,
            ),
          if (report.isIncomplete) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.spentVsKeptIncomplete,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
          if (report.needsReviewCount > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              l10n.spentVsKeptNeedsReview(report.needsReviewCount),
              style: text.bodySmall?.copyWith(color: AppColors.warningText),
            ),
          ],
        ],
      ),
    );
  }
}

/// One `label / figure` line. Uses [PeriodTotalsText] so the "not converted"
/// disclosure travels with every figure automatically rather than only on the
/// ones somebody remembered to annotate.
class _Row extends StatelessWidget {
  final String label;
  final PeriodTotals totals;
  final TotalsSign sign;

  const _Row({
    required this.label,
    required this.totals,
    this.sign = TotalsSign.spend,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ),
          const SizedBox(width: 12),
          PeriodTotalsText(totals: totals, style: text.bodyMedium, sign: sign),
        ],
      ),
    );
  }
}
