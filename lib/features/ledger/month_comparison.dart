/// **S-31 — month over month** (KHA-37, US-E4, AC-E4.1, AC-E4.2).
///
/// > AC-E4.1 — *"the current period total alongside the prior period total and
/// > the difference."*
/// > AC-E4.2 — *"with fewer than two months of data, state that there isn't
/// > enough history rather than showing a misleading comparison."*
///
/// ---
///
/// ## AC-E4.2 is the whole reason this is a domain type and not a widget
///
/// A comparison screen has a strong pull toward always rendering something. With
/// one month of data the arithmetic still *works*: this month 3,214.50, last
/// month nothing, difference +3,214.50, *"up 100%"*. Every number is correct and
/// the conclusion is nonsense — the user did not increase their spending
/// infinitely, they installed the app. The approved mockup has a dedicated frame
/// for this and labels it *"never a misleading comparison"*.
///
/// So *"is there enough history?"* is a fact this type computes and exposes
/// ([hasEnoughHistory]), rather than a condition a screen is trusted to remember.
/// [difference] returns null in that case, so a caller cannot render a delta it
/// was not entitled to even by ignoring the flag.
///
/// ## What "two months of data" counts
///
/// Distinct **Riyadh calendar months** that contain at least one live, dated
/// transaction — the same month boundary every other figure in the app uses
/// (OQ-12, `RiyadhCalendar.monthWindowUtc`). Three details, each deliberate:
///
///  - **Distinct months, not "the prior month is non-empty".** A user whose first
///    month was June and who then spent nothing in July is entitled to the
///    comparison: they have two months of history and one of them was quiet. That
///    is a real, useful finding, unlike a comparison against a month that
///    predates the data.
///  - **Deleted rows do not count.** A soft-deleted transaction is out of every
///    total (US-B8), so it cannot be the sole evidence that a month happened.
///  - **Undated rows do not count.** They are in no period (see
///    `PeriodRange.contains`), so they cannot establish that a period exists.
///
/// ## Why the difference is nullable beyond the history rule
///
/// The same reason `PeriodReport.netKept` is: a component with **no**
/// transactions genuinely contributes zero, but a component holding transactions
/// the app could not convert to the base currency (ADR-009 case 4) contributes
/// *unknown*. Treating unknown as zero would report *"you spent 3,000 less than
/// last month"* to someone whose last month was entirely in a currency no message
/// quoted a rate for. Null instead, and the screen says so.
library;

import '../../core/money/money.dart';
import '../../core/time/clock.dart';
import 'base_currency.dart';
import 'internal_transfer.dart';
import 'ledger_transaction.dart';
import 'period_totals.dart';

/// How many months the S-31 bar chart shows, including the current one.
///
/// Three, matching the approved mockup. Enough to see a direction; few enough
/// that each bar is still readable at the largest OS font size (NFR-U3).
const int kMonthComparisonTrailLength = 3;

/// One bar in the S-31 trail.
final class MonthBar {
  final PeriodRange period;
  final PeriodTotals totals;

  /// True for the period the user is currently viewing — the bar the mockup
  /// draws in the primary colour rather than grey.
  final bool isSelected;

  const MonthBar({
    required this.period,
    required this.totals,
    required this.isSelected,
  });

  /// True when this month has no figure at all, so the chart draws no bar rather
  /// than a zero-height one that reads as "spent nothing".
  bool get isEmpty => totals.base == null;

  @override
  String toString() => 'MonthBar(${period.startUtc.toIso8601String()})';
}

/// The current period against the one before it.
final class MonthComparison {
  final PeriodRange currentPeriod;
  final PeriodRange priorPeriod;

  final PeriodTotals current;
  final PeriodTotals prior;

  /// Distinct Riyadh calendar months with at least one live, dated transaction.
  /// See the library comment for exactly what is counted.
  final int monthsWithData;

  /// Up to [kMonthComparisonTrailLength] months ending at [currentPeriod],
  /// oldest first.
  final List<MonthBar> trail;

  final String baseCurrencyCode;

  const MonthComparison({
    required this.currentPeriod,
    required this.priorPeriod,
    required this.current,
    required this.prior,
    required this.monthsWithData,
    required this.trail,
    required this.baseCurrencyCode,
  });

  /// **AC-E4.2.** False means the screen must state that there is not enough
  /// history, and must not render a chart or a delta.
  bool get hasEnoughHistory => monthsWithData >= 2;

  /// **AC-E4.1's difference** — current minus prior, in the base currency.
  ///
  /// Positive means the user spent *more* this period. Null when the comparison
  /// is not entitled to exist ([hasEnoughHistory]) or when either side holds
  /// transactions that could not be converted — see the library comment.
  Money? get difference {
    if (!hasEnoughHistory) {
      return null;
    }
    final Money zero = Money.zero(baseCurrencyCode);
    final Money? now = _contributionOf(current, zero);
    final Money? then = _contributionOf(prior, zero);
    if (now == null || then == null) {
      return null;
    }
    return now - then;
  }

  /// True when either side omits an unconvertible transaction, so the screen can
  /// label the comparison as incomplete rather than only one of its two figures.
  bool get isIncomplete => current.isIncomplete || prior.isIncomplete;

  /// A component's contribution: its base figure, `zero` when it is genuinely
  /// empty, or **null** when it holds transactions the app could not convert.
  static Money? _contributionOf(PeriodTotals totals, Money zero) {
    if (totals.base != null) {
      return totals.base;
    }
    return totals.isEmpty ? zero : null;
  }

  /// Builds the comparison for [period] out of the whole ledger.
  ///
  /// [transactions] must be the **whole** live set, not a period slice: the prior
  /// month's figure obviously needs rows outside the current period, and the
  /// internal-transfer detector needs the whole set to see both legs of a pair at
  /// all (`period_totals.dart`'s note on slicing). One analysis is computed here
  /// and handed to every figure, so the current month, the prior month and every
  /// bar in the trail agree about what an internal transfer is.
  static MonthComparison of(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    final List<LedgerTransaction> live = <LedgerTransaction>[
      for (final LedgerTransaction txn in transactions)
        if (!txn.isDeleted) txn,
    ];
    final InternalTransferAnalysis transfers = InternalTransferDetector.analyze(
      live,
    );

    PeriodRange shifted(int monthOffset) {
      final (DateTime start, DateTime end) = RiyadhCalendar.monthWindowUtc(
        // Mid-window rather than the boundary instant, for the reason
        // `PeriodRangeNotifier.shiftMonths` states: `startUtc` is 21:00 on the
        // previous month's last day in UTC, so shifting from it directly would be
        // off by one month.
        period.startUtc.add(const Duration(days: 1)),
        monthOffset: monthOffset,
      );
      return PeriodRange(startUtc: start, endUtcExclusive: end);
    }

    PeriodTotals spendIn(PeriodRange range) => LedgerTotals.spend(
      live,
      period: range,
      baseCurrencyCode: baseCurrencyCode,
      transfers: transfers,
    );

    final PeriodRange priorPeriod = shifted(-1);

    return MonthComparison(
      currentPeriod: period,
      priorPeriod: priorPeriod,
      current: spendIn(period),
      prior: spendIn(priorPeriod),
      monthsWithData: distinctMonthsWithData(live),
      trail: <MonthBar>[
        for (
          int offset = -(kMonthComparisonTrailLength - 1);
          offset <= 0;
          offset++
        )
          if (shifted(offset) case final PeriodRange range)
            MonthBar(
              period: range,
              totals: spendIn(range),
              isSelected: offset == 0,
            ),
      ],
      baseCurrencyCode: baseCurrencyCode,
    );
  }

  /// How many distinct Riyadh calendar months hold at least one live, dated
  /// transaction.
  ///
  /// Exposed (rather than private) because AC-E4.2's threshold is the kind of
  /// product rule that deserves its own direct test over a hand-built list, with
  /// no comparison object in the way.
  static int distinctMonthsWithData(Iterable<LedgerTransaction> transactions) {
    final Set<String> months = <String>{};
    for (final LedgerTransaction txn in transactions) {
      if (txn.isDeleted) {
        continue;
      }
      final DateTime? at = txn.occurredAt;
      if (at == null) {
        continue;
      }
      // Keyed on the Riyadh wall-clock year+month, so a purchase at 01:00 on the
      // 1st in Riyadh counts toward the month the user would say it happened in
      // — not the previous one, which is what its raw UTC instant reads as.
      final DateTime wall = RiyadhCalendar.toRiyadhWallClock(at);
      months.add('${wall.year}-${wall.month}');
    }
    return months.length;
  }
}
