/// **S-28..S-32 — the Reports screens.** Mockup: `docs/mockups/reports.html`.
/// **KHA-37, US-E2/E3/E4, AC-E2.1-3, AC-E3.1-2, AC-E4.1-2, AC-C1.3, NFR-A6.**
///
/// ---
///
/// ## Pure widgets, and the reason it matters more here than anywhere else
///
/// Every screen in this file is a `StatelessWidget` over plain values with no
/// provider, no database and **no arithmetic on money** — the codebase's standing
/// rule (see `categorization_routes.dart`), and `reports_routes.dart` holds the
/// `Consumer` hosts that do the joining.
///
/// On these screens the rule is doing real work rather than being tidy. This is
/// the part of the app whose entire purpose is that the numbers reconcile, and
/// the figures arrive here as `CategoryBreakdown` / `InstrumentBreakdown` /
/// `MonthComparison` — domain types that computed them once, from one analysis,
/// with the same `LedgerTotals.spend` every other screen uses. A widget that
/// could add up a column itself would be a second implementation of the period
/// total, on the screen that exists to prove there is only one.
///
/// ## The two invariants, rendered rather than assumed
///
/// AC-C1.3 (category slices sum to the period total) and AC-E3.2 (instrument
/// slices sum to the period total) are guaranteed by construction in the domain
/// types. Both screens below **still render the footer and still render an error
/// line when `reconciles` is false.** That is not belt-and-braces for its own
/// sake: `docs/build-plan.md` calls these *"a reconciliation guarantee, not a
/// display detail"*, and a break the user cannot see is the actual failure mode
/// NFR-A6 exists to prevent. If the guarantee ever stops holding, the app must say
/// so on the screen rather than print a plausible wrong number.
///
/// ## AC-E2.3 — "Uncategorized" is its own line, always
///
/// > *"'Uncategorized' with a non-zero total is shown as its OWN LINE, never
/// > hidden and never folded into 'Other'."*
///
/// There is no "Other" bucket anywhere in this file, and no `take(n)` on the
/// category list. The reason the AC exists is that hiding the row *"would let the
/// user believe their data is more complete than it is"* — so [CategoryBreakdownScreen]
/// renders whatever `CategoryBreakdown` gives it, in the design's order, and
/// `chart-uncategorized` is pinned to grey (brand.md §2.5) so the row reads as
/// *unassigned* rather than as one more kind of spending.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/categories.dart';
import '../../features/categorization/category_breakdown.dart';
import '../../features/ledger/instrument_breakdown.dart';
import '../../features/ledger/month_comparison.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';
import '../widgets/period_widgets.dart';
import '../widgets/report_widgets.dart';
import '../widgets/spent_vs_kept_card.dart';

/// **S-28 — the Reports hub.**
///
/// Four cards, each pre-showing its own top line so the hub is informative before
/// the user taps anything (design.md §7's *"each pre-showing its top line so the
/// hub itself is informative"*).
class ReportsHubScreen extends StatelessWidget {
  /// The period every card describes. The selector lives here rather than on the
  /// four detail screens, so "which month am I looking at" is answered once —
  /// and it is the **same** `ledgerPeriodProvider` Home and S-10 read, so paging
  /// to June on Home and opening Reports shows June.
  final PeriodRange period;
  final bool isCurrentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  /// The pre-shown top lines. Null when the ledger has nothing to summarise, in
  /// which case the card renders without a subtitle rather than with an invented
  /// zero.
  final String? topCategoryLine;
  final String? topInstrumentLine;

  /// Null while the comparison is not entitled to exist (AC-E4.2), which the card
  /// reports as the insufficient-history sentence rather than a delta.
  final String? monthOverMonthLine;
  final String? spentVsKeptLine;

  /// True when the ledger holds nothing at all in this period — the hub's own
  /// empty state, which is one honest sentence instead of four cards each reading
  /// "no data".
  final bool isEmpty;

  final bool isLoading;
  final bool hasError;

  final VoidCallback onOpenCategoryBreakdown;
  final VoidCallback onOpenInstrumentBreakdown;
  final VoidCallback onOpenMonthComparison;
  final VoidCallback onOpenSpentVsKept;

  const ReportsHubScreen({
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    required this.onOpenCategoryBreakdown,
    required this.onOpenInstrumentBreakdown,
    required this.onOpenMonthComparison,
    required this.onOpenSpentVsKept,
    this.topCategoryLine,
    this.topInstrumentLine,
    this.monthOverMonthLine,
    this.spentVsKeptLine,
    this.isEmpty = false,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.reportsHubTitle)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLoading) {
      return const Center(
        key: Key('reports.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (hasError) {
      // Ahead of the empty check, deliberately: "nothing to report yet" is this
      // screen's welcome state, and rendering it for a failed read tells a user
      // with a year of history that the app has forgotten all of it.
      return CategorySectionError(
        key: const Key('reports.error'),
        message: l10n.reportsUnavailable,
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      children: <Widget>[
        PeriodSelector(
          period: period,
          isCurrentMonth: isCurrentMonth,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onCurrentMonth: onCurrentMonth,
        ),
        const SizedBox(height: 4),
        if (isEmpty)
          CategoryEmptyState(
            key: const Key('reports.empty'),
            icon: Icons.insights_outlined,
            headline: l10n.reportsNothingYetTitle,
            body: l10n.reportsNothingYetBody,
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 12),
            child: Text(
              l10n.reportsHubSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ),
          ReportSummaryCard(
            key: const Key('reports.card.category'),
            title: l10n.reportsByCategory,
            icon: Icons.donut_small_outlined,
            summary: topCategoryLine,
            onTap: onOpenCategoryBreakdown,
          ),
          ReportSummaryCard(
            key: const Key('reports.card.instrument'),
            title: l10n.reportsByCard,
            icon: Icons.credit_card_outlined,
            summary: topInstrumentLine,
            onTap: onOpenInstrumentBreakdown,
          ),
          ReportSummaryCard(
            key: const Key('reports.card.monthOverMonth'),
            title: l10n.reportsMonthOverMonth,
            icon: Icons.trending_up,
            summary: monthOverMonthLine,
            onTap: onOpenMonthComparison,
          ),
          ReportSummaryCard(
            key: const Key('reports.card.spentVsKept'),
            title: l10n.reportsSpentVsKept,
            icon: Icons.account_balance_wallet_outlined,
            summary: spentVsKeptLine,
            onTap: onOpenSpentVsKept,
          ),
        ],
      ],
    );
  }
}

/// **S-29 — Category Breakdown.** AC-E2.1, AC-E2.2, AC-E2.3, AC-C1.3.
class CategoryBreakdownScreen extends StatelessWidget {
  final CategoryBreakdown breakdown;
  final PeriodRange period;
  final bool isCurrentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  /// **AC-E2.2** — *"selecting a category lists its underlying transactions."*
  /// Null renders non-tappable rows, which is right for a caller with no
  /// navigation to offer.
  final void Function(Category category)? onOpenCategory;

  final bool isLoading;
  final bool hasError;

  const CategoryBreakdownScreen({
    required this.breakdown,
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    this.onOpenCategory,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.reportsByCategory)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLoading) {
      return const Center(
        key: Key('categoryBreakdown.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (hasError) {
      return CategorySectionError(message: l10n.reportsUnavailable);
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      children: <Widget>[
        PeriodSelector(
          period: period,
          isCurrentMonth: isCurrentMonth,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onCurrentMonth: onCurrentMonth,
        ),
        const SizedBox(height: 8),
        if (breakdown.categories.isEmpty)
          CategoryEmptyState(
            key: const Key('categoryBreakdown.empty'),
            icon: Icons.donut_small_outlined,
            headline: l10n.reportsNothingYetTitle,
            body: l10n.reportsNothingYetBody,
          )
        else ...<Widget>[
          // Every slice the domain produced, in the design's category order, with
          // no "Other" fold and no truncation — see the library comment on
          // AC-E2.3.
          for (final CategoryTotal slice in breakdown.categories)
            BreakdownRow(
              rowKey: Key('categoryBreakdown.row.${slice.category.id}'),
              color: AppColors.chartColorFor(slice.category.colorToken),
              label: categoryName(context, slice.category),
              // A money-movement category (income, transfers, withdrawals)
              // carries transactions but no *spend* figure (US-B10/B11). Saying
              // so stops a count-with-no-figure row reading as lost money.
              subtitle: _subtitleFor(slice, l10n),
              totals: slice.totals,
              sharePercent: percentShareOf(
                slice.totals.base,
                breakdown.total.base,
              ),
              onTap: onOpenCategory == null || slice.transactionCount == 0
                  ? null
                  : () => onOpenCategory!(slice.category),
            ),
          const SizedBox(height: 4),
          // AC-C1.3 made visible. See the library comment on why the mismatch
          // line exists even though the invariant holds by construction.
          BreakdownTotalLine(
            key: const Key('categoryBreakdown.total'),
            label: l10n.categoryBreakdownTotalLine,
            totals: breakdown.total,
            reconciles: breakdown.reconciles,
            mismatchMessage: l10n.categoryBreakdownReconciliationFailed,
          ),
        ],
      ],
    );
  }

  String? _subtitleFor(CategoryTotal slice, AppLocalizations l10n) {
    if (slice.transactionCount == 0) {
      return l10n.categoryBreakdownEmptyCategoryNote;
    }
    if (slice.totals.isEmpty) {
      return l10n.categoryBreakdownMovementOnlyNote(slice.transactionCount);
    }
    return null;
  }
}

/// **S-30 — Card and Account Breakdown.** AC-E3.1, AC-E3.2.
class InstrumentBreakdownScreen extends StatelessWidget {
  final InstrumentBreakdown breakdown;
  final PeriodRange period;
  final bool isCurrentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  /// Opens the instrument's own detail screen (S-23/S-24), which already lists
  /// only that instrument's transactions and shows the same total (AC-B2.3).
  /// Reusing it rather than adding a second filtered list is what keeps the two
  /// figures identical by construction.
  final void Function(InstrumentSlice slice)? onOpenInstrument;

  final bool isLoading;
  final bool hasError;

  const InstrumentBreakdownScreen({
    required this.breakdown,
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    this.onOpenInstrument,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.reportsByCard)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLoading) {
      return const Center(
        key: Key('instrumentBreakdown.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (hasError) {
      return CategorySectionError(message: l10n.reportsUnavailable);
    }
    if (breakdown.instruments.isEmpty && !breakdown.hasUnassigned) {
      return CategoryEmptyState(
        key: const Key('instrumentBreakdown.empty'),
        icon: Icons.credit_card_outlined,
        headline: l10n.reportsNothingYetTitle,
        body: l10n.reportsNothingYetBody,
      );
    }

    // brand.md §2.5's palette, assigned in order and reused in order past eight —
    // which brand.md permits. The one colour never handed out here is
    // `chartUncategorized`, which stays reserved for the category screen's
    // Uncategorized row.
    int colorIndex = 0;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      children: <Widget>[
        PeriodSelector(
          period: period,
          isCurrentMonth: isCurrentMonth,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onCurrentMonth: onCurrentMonth,
        ),
        const SizedBox(height: 8),
        for (final InstrumentSlice slice in breakdown.instruments)
          BreakdownRow(
            rowKey: Key(
              'instrumentBreakdown.row.${slice.summary.instrument.id}',
            ),
            color: AppColors
                .chartSeries[colorIndex++ % AppColors.chartSeries.length],
            label: slice.label,
            subtitle: slice.transactionCount == 0
                ? l10n.instrumentBreakdownNoActivity
                : l10n.instrumentBreakdownBankLabel(
                    _kindLabel(l10n, slice),
                    slice.bank.displayName(
                      Localizations.localeOf(context).languageCode,
                    ),
                  ),
            totals: slice.summary.totals,
            // No share on this screen: the mockup shows per-card figures without
            // percentages, because what S-30 is *for* is the footer identity
            // (AC-E3.2), not proportions.
            showShare: false,
            onTap: onOpenInstrument == null
                ? null
                : () => onOpenInstrument!(slice),
          ),
        // **The row that makes AC-E3.2 true.** Cash and anything the app could
        // not attach to an instrument. Without it the footer would be smaller
        // than the period total shown everywhere else — see
        // `instrument_breakdown.dart`.
        if (breakdown.hasUnassigned)
          BreakdownRow(
            rowKey: const Key('instrumentBreakdown.row.unassigned'),
            color: AppColors.ink500,
            label: l10n.instrumentBreakdownUnassigned,
            totals: breakdown.unassigned,
            showShare: false,
          ),
        const SizedBox(height: 4),
        BreakdownTotalLine(
          key: const Key('instrumentBreakdown.total'),
          label: l10n.instrumentBreakdownTotalLine,
          totals: breakdown.total,
          reconciles: breakdown.reconciles,
          mismatchMessage: l10n.instrumentBreakdownReconciliationFailed,
        ),
      ],
    );
  }

  /// The masked identifier is already the row's label, so the subtitle names the
  /// *kind* and the bank — the two things that disambiguate two cards ending in
  /// the same four digits (AC-B13.1/2).
  String _kindLabel(AppLocalizations l10n, InstrumentSlice slice) =>
      slice.isCard ? l10n.instrumentKindCard : l10n.instrumentKindAccount;
}

/// **S-31 — Month over Month.** AC-E4.1, AC-E4.2.
class MonthComparisonScreen extends StatelessWidget {
  final MonthComparison comparison;
  final PeriodRange period;
  final bool isCurrentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  final bool isLoading;
  final bool hasError;

  const MonthComparisonScreen({
    required this.comparison,
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.reportsMonthOverMonth)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLoading) {
      return const Center(
        key: Key('monthComparison.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (hasError) {
      return CategorySectionError(message: l10n.reportsUnavailable);
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
      children: <Widget>[
        PeriodSelector(
          period: period,
          isCurrentMonth: isCurrentMonth,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onCurrentMonth: onCurrentMonth,
        ),
        const SizedBox(height: 12),
        // **AC-E4.2.** With fewer than two months of history the chart and the
        // delta are not rendered *at all* — not greyed, not zeroed. The
        // arithmetic would still work and every number in it would be correct
        // while the conclusion was nonsense ("up 100%" means "you installed the
        // app"), which is exactly what the AC forbids.
        if (!comparison.hasEnoughHistory)
          CategoryEmptyState(
            key: const Key('monthComparison.insufficientHistory'),
            icon: Icons.insights_outlined,
            headline: l10n.monthComparisonInsufficientTitle,
            body: l10n.monthComparisonInsufficientBody,
          )
        else ...<Widget>[
          MonthComparisonHeader(comparison: comparison),
          const SizedBox(height: 16),
          MonthTrailChart(bars: comparison.trail),
        ],
      ],
    );
  }
}

/// **S-32 — Spent vs Kept.** AC-B10.3.
///
/// The card itself shipped in P3b-1 and has lived on Home ever since, with a note
/// saying *"P5b moves it to S-28"* — because a computation with no production call
/// site is library code rather than shipped behaviour, and Home was the only
/// screen that existed. This is that move: design.md always filed S-32 under the
/// Reports hub, and Home is now back to the five elements §7 S-08 lists.
class SpentVsKeptScreen extends StatelessWidget {
  final PeriodReport? report;
  final PeriodRange period;
  final bool isCurrentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  final bool isLoading;
  final bool hasError;

  const SpentVsKeptScreen({
    required this.report,
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PeriodReport? current = report;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.reportsSpentVsKept)),
      body: isLoading
          ? const Center(
              key: Key('spentVsKept.loading'),
              child: CircularProgressIndicator(),
            )
          : hasError || current == null
          ? CategorySectionError(message: l10n.reportsUnavailable)
          : ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
              children: <Widget>[
                PeriodSelector(
                  period: period,
                  isCurrentMonth: isCurrentMonth,
                  onPreviousMonth: onPreviousMonth,
                  onNextMonth: onNextMonth,
                  onCurrentMonth: onCurrentMonth,
                ),
                const SizedBox(height: 8),
                SpentVsKeptCard(report: current),
              ],
            ),
    );
  }
}
