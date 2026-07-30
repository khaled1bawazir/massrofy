/// **The construction sites for every reports screen — KHA-37.**
///
/// Same shape and same reason as `ledger_routes.dart` and
/// `categorization_routes.dart`. `docs/lessons.md`, twice:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code — it
/// > expires the moment someone adds a route, silently."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// So a future reachability question about S-28..S-32 is answered by grepping for
/// the `open*` functions below and the [ReportsHubHost] the shell builds, and
/// nothing else.
///
/// ## Hosts, not screens
///
/// Every screen in `reports_screen.dart` is a plain widget over values. The
/// `Consumer` hosts here watch the providers, render design.md §3.4's
/// loading/error/empty states, and hand the screen values plus callbacks. That is
/// what keeps the widget tests pure render tests and what keeps ADR-005's
/// guarantee checkable — a screen cannot read something the app lock has not
/// unlocked, because it cannot read anything at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/category_breakdown.dart';
import '../../features/ledger/instrument_breakdown.dart';
import '../../features/ledger/month_comparison.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/ledger_providers.dart';
import '../providers/report_providers.dart';
import '../widgets/category_widgets.dart';
import '../widgets/ledger_widgets.dart';
import 'ledger_routes.dart';
import 'reports_screen.dart';

// =========================================================================
// The navigation graph.
// =========================================================================

/// **S-29 — Category Breakdown** (US-E2).
Future<void> openCategoryBreakdown(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const CategoryBreakdownHost()));

/// **S-30 — Card and Account Breakdown** (US-E3).
Future<void> openInstrumentBreakdown(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const InstrumentBreakdownHost()),
    );

/// **S-31 — Month over Month** (US-E4).
Future<void> openMonthComparison(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const MonthComparisonHost()));

/// **S-32 — Spent vs Kept** (AC-B10.3).
Future<void> openSpentVsKept(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const SpentVsKeptHost()));

// =========================================================================
// Hosts
// =========================================================================

/// **S-28 — the Reports hub.** The fourth `BottomNav` tab's page.
class ReportsHubHost extends ConsumerWidget {
  const ReportsHubHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);

    final AsyncValue<CategoryBreakdown> categories = ref.watch(
      categoryBreakdownProvider,
    );
    final AsyncValue<InstrumentBreakdown> instruments = ref.watch(
      instrumentBreakdownProvider,
    );
    final AsyncValue<MonthComparison> comparison = ref.watch(
      monthComparisonProvider,
    );
    final AsyncValue<PeriodReport> report = ref.watch(periodReportProvider);

    final bool anyError =
        categories.hasError ||
        instruments.hasError ||
        comparison.hasError ||
        report.hasError;
    final bool anyLoading =
        categories.value == null ||
        instruments.value == null ||
        comparison.value == null ||
        report.value == null;

    return ReportsHubScreen(
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
      isLoading: !anyError && anyLoading,
      hasError: anyError,
      // The hub is empty when the period's spend total has nothing in it AND no
      // instrument recorded anything. Both, because a period can hold income only
      // (US-B10) — a spend total of "nothing" with a salary in it is not an empty
      // month, and the Spent-vs-Kept card has something real to say about it.
      isEmpty:
          !anyError &&
          !anyLoading &&
          (report.value?.spend.isEmpty ?? true) &&
          (report.value?.income.isEmpty ?? true) &&
          (instruments.value?.isEmpty ?? true),
      topCategoryLine: _topCategoryLine(context, l10n, categories.value),
      topInstrumentLine: _topInstrumentLine(context, l10n, instruments.value),
      monthOverMonthLine: _monthOverMonthLine(context, l10n, comparison.value),
      spentVsKeptLine: _spentVsKeptLine(l10n, report.value),
      onOpenCategoryBreakdown: () => openCategoryBreakdown(context),
      onOpenInstrumentBreakdown: () => openInstrumentBreakdown(context),
      onOpenMonthComparison: () => openMonthComparison(context),
      onOpenSpentVsKept: () => openSpentVsKept(context),
    );
  }

  /// The largest **spending** slice. Null when nothing qualifies, so the card
  /// renders without a subtitle rather than with an invented zero.
  String? _topCategoryLine(
    BuildContext context,
    AppLocalizations l10n,
    CategoryBreakdown? breakdown,
  ) {
    if (breakdown == null) {
      return null;
    }
    CategoryTotal? top;
    for (final CategoryTotal slice in breakdown.categories) {
      final Money? value = slice.totals.base;
      if (value == null || value.isNegative || value.amount.sign == 0) {
        // Skip a slice with no figure, and skip a *net credit* slice: "top
        // category: Groceries −40.00" (a month of refunds) would be a confusing
        // headline for a screen about where money went.
        continue;
      }
      if (top == null || value > top.totals.base!) {
        top = slice;
      }
    }
    if (top == null) {
      return null;
    }
    return l10n.reportsByCategorySummary(
      categoryName(context, top.category),
      '${formatAmountDigits(top.totals.base!)} ${top.totals.baseCurrencyCode}',
    );
  }

  String? _topInstrumentLine(
    BuildContext context,
    AppLocalizations l10n,
    InstrumentBreakdown? breakdown,
  ) {
    if (breakdown == null) {
      return null;
    }
    InstrumentSlice? top;
    for (final InstrumentSlice slice in breakdown.instruments) {
      final Money? value = slice.summary.totals.base;
      if (value == null || value.isNegative || value.amount.sign == 0) {
        continue;
      }
      if (top == null || value > top.summary.totals.base!) {
        top = slice;
      }
    }
    if (top == null) {
      return null;
    }
    return l10n.reportsByCardSummary(
      top.label,
      '${formatAmountDigits(top.summary.totals.base!)} '
      '${top.summary.totals.baseCurrencyCode}',
    );
  }

  /// AC-E4.1's delta as one line, or AC-E4.2's honest sentence when there is not
  /// enough history for one.
  String? _monthOverMonthLine(
    BuildContext context,
    AppLocalizations l10n,
    MonthComparison? comparison,
  ) {
    if (comparison == null) {
      return null;
    }
    if (!comparison.hasEnoughHistory) {
      return l10n.monthComparisonInsufficientTitle;
    }
    final Money? difference = comparison.difference;
    if (difference == null) {
      return l10n.monthComparisonIncomplete;
    }
    final String priorLabel = formatPeriodMonthLabel(
      context,
      comparison.priorPeriod.startUtc,
    );
    final String figure =
        '${formatAmountDigits(difference.abs)} ${difference.currencyCode}';
    if (difference.amount.sign == 0) {
      return l10n.monthComparisonSame(priorLabel);
    }
    return difference.isNegative
        ? l10n.monthComparisonDown(figure, priorLabel)
        : l10n.monthComparisonUp(figure, priorLabel);
  }

  String? _spentVsKeptLine(AppLocalizations l10n, PeriodReport? report) {
    final Money? kept = report?.netKept;
    if (kept == null) {
      return null;
    }
    return formatSignedAmount(kept.abs, isCredit: !kept.isNegative);
  }
}

/// **S-29.**
class CategoryBreakdownHost extends ConsumerWidget {
  const CategoryBreakdownHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CategoryBreakdown> breakdown = ref.watch(
      categoryBreakdownProvider,
    );
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);

    return CategoryBreakdownScreen(
      breakdown: breakdown.value ?? CategoryBreakdown.empty,
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      isLoading: breakdown.value == null && !breakdown.hasError,
      hasError: breakdown.hasError,
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
      // **AC-E2.2 — "selecting a category lists its underlying transactions."**
      //
      // Implemented by setting the shared `TransactionFilter` and pushing the
      // *same* S-10 the user filters by hand, rather than by adding a second
      // filtered-list screen. That is what makes the drill-down's total AC-E5.2's
      // total, computed by the same code over the same rows — a second screen
      // would be a second implementation of the one number this whole phase is
      // about.
      onOpenCategory: (Category category) {
        ref
            .read(transactionFilterProvider.notifier)
            .showOnlyCategory(category.id);
        openTransactionList(context);
      },
    );
  }
}

/// **S-30.**
class InstrumentBreakdownHost extends ConsumerWidget {
  const InstrumentBreakdownHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<InstrumentBreakdown> breakdown = ref.watch(
      instrumentBreakdownProvider,
    );
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);

    return InstrumentBreakdownScreen(
      breakdown: breakdown.value ?? InstrumentBreakdown.empty,
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      isLoading: breakdown.value == null && !breakdown.hasError,
      hasError: breakdown.hasError,
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
      // Straight to S-23/S-24, which already lists only that instrument's
      // transactions and shows the same figure (AC-B2.3). Reusing it rather than
      // filtering S-10 keeps the two totals identical by construction.
      onOpenInstrument: (InstrumentSlice slice) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              InstrumentDetailHost(instrumentId: slice.summary.instrument.id),
        ),
      ),
    );
  }
}

/// **S-31.**
class MonthComparisonHost extends ConsumerWidget {
  const MonthComparisonHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MonthComparison> comparison = ref.watch(
      monthComparisonProvider,
    );
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);

    final MonthComparison? value = comparison.value;
    if (value == null) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.reportsMonthOverMonth)),
        body: comparison.hasError
            ? CategorySectionError(message: l10n.reportsUnavailable)
            : const Center(child: CircularProgressIndicator()),
      );
    }

    return MonthComparisonScreen(
      comparison: value,
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
    );
  }
}

/// **S-32.**
class SpentVsKeptHost extends ConsumerWidget {
  const SpentVsKeptHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PeriodReport> report = ref.watch(periodReportProvider);
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);

    return SpentVsKeptScreen(
      report: report.value,
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      isLoading: report.value == null && !report.hasError,
      hasError: report.hasError,
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
    );
  }
}
