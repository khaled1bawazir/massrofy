/// The reporting component library — **KHA-37**, design.md §5 + §7's S-28..S-32.
///
/// | design.md / mockup element | here |
/// |---|---|
/// | S-28's four summary cards (`.summary-card`) | [ReportSummaryCard] |
/// | S-29/S-30's breakdown row (`.cat-row`) | [BreakdownRow] |
/// | S-30's footer (`.total-line`) | [BreakdownTotalLine] |
/// | S-31's bar chart (`.bar-chart`) | [MonthTrailChart] |
/// | S-31's two figures + delta (`.mom-cards`, `.delta-line`) | [MonthComparisonHeader] |
///
/// Everything here is a `StatelessWidget` over plain values: **no provider, no
/// database, no async, and no arithmetic on money**. That is the codebase's
/// standing rule for screens and their parts (see `categorization_routes.dart`),
/// and it is load-bearing twice over here:
///
///  - the figures arrive as `PeriodTotals`/`Money` already computed by
///    `LedgerTotals`, which ADR-002 makes the only place a total is produced —
///    so no widget in this file can invent a number;
///  - the *shares* are the one derived quantity these widgets do render, and
///    [percentShareOf] is the single function that produces them, so a
///    percentage cannot be rounded two ways on two screens.
///
/// ## NFR-U4 — no chart in this app means anything by colour alone
///
/// `docs/brand.md` §5.3: *"never a bare, unlabelled colour-only chart"*, and §2.5
/// keeps the chart palette strictly separate from the semantic colours. So every
/// row and every bar below carries its **name**, its **figure** and, where it
/// applies, its **share as text**. The colour swatch is a scanning aid. Convert
/// this screen to greyscale and nothing is lost but convenience — which is what
/// `test/widget/p5b_greyscale_test.dart` asserts.
///
/// ## ADR-002's CI guard covers this file, and that shaped two things in it
///
/// `.github/scripts/check_money_type_ban.sh` fails the build on Dart's
/// floating-point tokens (and the conversions to them) in **any** file under
/// `lib/` whose name matches `*money*`, `*amount*`, `*budget*` or `*report*`. This
/// file matches, and that is correct rather than inconvenient: it renders money,
/// and a float sneaking into a percentage or a bar scale is exactly the class of
/// defect ADR-002 exists to prevent.
///
/// The guard greps the **whole file, comments included**, which is why the prose
/// here talks around the banned identifiers rather than quoting them. That is not
/// the guard being clumsy — a blunt grep is the point of it, and a version clever
/// enough to skip comments would be a version that could be talked into skipping
/// code.
///
/// Two consequences, both visible below and neither a workaround:
///
///  1. **[percentShareOf] does its arithmetic on `Decimal`/`Rational`** and rounds
///     to a `BigInt`. There is no floating-point step anywhere between the ledger
///     and the string on screen.
///  2. **[MonthTrailChart] sizes its bars with integer `flex` weights**, not pixel
///     heights derived from a ratio. Two `Expanded`s in a fixed-height box are
///     proportional by construction, so the chart needs no float at all — and it
///     happens to be the better widget, since the proportion is then exact rather
///     than rounded to a device pixel.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/time/clock.dart';
import '../../features/ledger/month_comparison.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'ledger_widgets.dart';

/// [part] as a whole-number percentage of [whole], or **null** when the question
/// has no answer.
///
/// ## Why null and not zero, and why a whole number
///
/// Null in three genuinely different situations that a `0` would flatten
/// together, and each of them would be a lie:
///
///  - **[whole] is null** — nothing in the period could be expressed in the base
///    currency (ADR-009 case 4). There is no denominator, so there is no share.
///  - **[whole] is zero** — a period whose credits exactly cancelled its debits.
///    Dividing by it is undefined; reporting "0%" would say this category is a
///    vanishing part of a real total.
///  - **[part] is null** — this slice has no base figure of its own.
///
/// The result is a whole number because a share printed to two decimals invites
/// the user to reconcile a rounding artefact instead of the money. AC-E2.1 asks
/// for the share *and* the total; the total is the exact figure, and it is right
/// there beside it.
///
/// The arithmetic runs on `Decimal`/`Rational` throughout and rounds to a
/// `BigInt`: no floating-point step exists between the ledger and the string on
/// screen (ADR-002, and the CI guard named in the library comment).
int? percentShareOf(Money? part, Money? whole) {
  if (part == null || whole == null) {
    return null;
  }
  // Magnitudes. A refund-heavy category can hold a negative net, and a negative
  // percentage of a positive total would be arithmetically right and unreadable —
  // the row's own signed figure already carries the direction.
  final Money numerator = part.abs;
  final Money denominator = whole.abs;
  if (denominator.amount.sign == 0) {
    return null;
  }
  // Multiply *before* dividing, so the ratio never has to be represented at a
  // finite scale on the way to a percentage. `Decimal / Decimal` yields a
  // `Rational` — an exact fraction — and `Rational.round()` yields a `BigInt`.
  return ((numerator.amount * Decimal.fromInt(100)) / denominator.amount)
      .round()
      .toInt();
}

/// **S-28's summary card** — one report, with its own top line so the hub is
/// informative before the user taps anything.
class ReportSummaryCard extends StatelessWidget {
  final String title;

  /// The pre-shown top line. Null renders the card without one, which is what an
  /// empty ledger looks like — an invented "0.00" headline would claim a
  /// measurement.
  final String? summary;

  final IconData icon;
  final VoidCallback? onTap;

  const ReportSummaryCard({
    required this.title,
    required this.icon,
    this.summary,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: summary == null
            ? null
            : Text(
                summary!,
                style: text.bodySmall?.copyWith(color: AppColors.ink700),
              ),
        // `arrow_forward_ios` rather than `chevron_right`: only a handful of
        // Flutter's icons auto-mirror, and this is one of them, so under Arabic
        // RTL it points the way the reader's eye travels (design.md §3.1).
        trailing: onTap == null
            ? null
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

/// **S-29/S-30's breakdown row** — a colour swatch, a name, a share and a figure.
///
/// One widget for both the category and the instrument breakdown. They render the
/// same shape and differ only in what fills it, and two copies would be two
/// chances for one of them to drop the share or the count.
class BreakdownRow extends StatelessWidget {
  /// brand.md §2.5's swatch. Reinforcement only — see the library comment.
  final Color color;

  final String label;

  /// A second line under [label] — the bank for an instrument row, or the
  /// "not counted as spending" note for a money-movement category.
  final String? subtitle;

  /// The figure, already computed. `PeriodTotalsText` carries its own
  /// "N not converted" disclosure, so an incomplete slice can never look more
  /// certain than the total it came from.
  final PeriodTotals totals;

  /// AC-E2.1's share, from [percentShareOf]. Null renders the explicit
  /// "share not available" words rather than a bare "0%".
  final int? sharePercent;

  /// Whether to render the share at all. False on S-30, where the mockup shows
  /// per-card figures without percentages — the footer identity is what that
  /// screen is about (AC-E3.2), not proportions.
  final bool showShare;

  /// AC-E2.2's drill-down. Null renders a non-tappable row, which is correct for
  /// a slice with nothing behind it.
  final VoidCallback? onTap;

  final Key? rowKey;

  const BreakdownRow({
    required this.color,
    required this.label,
    required this.totals,
    this.subtitle,
    this.sharePercent,
    this.showShare = true,
    this.onTap,
    this.rowKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 4,
          vertical: 10,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.ink100)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The mockup's 12x12 rounded `.dot`. Excluded from the semantics
            // tree: it carries no information the label does not, and announcing
            // "a coloured square" before every row would be noise to a screen
            // reader (NFR-U2).
            ExcludeSemantics(
              child: Container(
                key: const Key('breakdownRow.swatch'),
                margin: const EdgeInsetsDirectional.only(top: 4, end: 10),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: text.bodySmall?.copyWith(color: AppColors.ink500),
                    ),
                  ],
                  if (showShare) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      // AC-E2.1's share, in words when it cannot be computed.
                      sharePercent == null
                          ? l10n.categoryBreakdownShareUnknown
                          : l10n.categoryBreakdownShareOfPeriod(sharePercent!),
                      style: text.bodySmall?.copyWith(color: AppColors.ink500),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Right-aligned within its own box so a column of figures lines up,
            // which is the only way a reader can compare them by eye.
            PeriodTotalsText(totals: totals, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// **S-30's `.total-line`** — the footer AC-E3.2 is about.
///
/// A heavier top rule and bold weight, matching the mockup, because this row is
/// making a claim about every row above it: *these add up to the period total you
/// saw on Home.*
class BreakdownTotalLine extends StatelessWidget {
  final String label;
  final PeriodTotals totals;

  /// False when the parts do **not** sum to the whole. Renders [mismatchMessage]
  /// as well as the figure.
  ///
  /// This should be unreachable — both breakdowns partition once and sum each
  /// part with the same function, so the identity holds by construction — but a
  /// reconciliation break the user cannot see is precisely the failure NFR-A6
  /// exists to prevent. Silence would be the bug, not the arithmetic.
  final bool reconciles;

  final String mismatchMessage;

  const BreakdownTotalLine({
    required this.label,
    required this.totals,
    required this.mismatchMessage,
    this.reconciles = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 10, 4, 4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.ink900, width: 2)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              PeriodTotalsText(
                totals: totals,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (!reconciles)
          Padding(
            key: const Key('breakdown.reconciliationFailed'),
            padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 4, 0),
            child: Text(
              mismatchMessage,
              style: text.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

/// **S-31's two figures and the delta between them** (AC-E4.1).
class MonthComparisonHeader extends StatelessWidget {
  final MonthComparison comparison;

  const MonthComparisonHeader({required this.comparison, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String priorLabel = formatPeriodMonthLabel(
      context,
      comparison.priorPeriod.startUtc,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _FigureCard(
                key: const Key('mom.current'),
                label: l10n.monthComparisonThisPeriod(
                  formatPeriodMonthLabel(
                    context,
                    comparison.currentPeriod.startUtc,
                  ),
                ),
                totals: comparison.current,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FigureCard(
                key: const Key('mom.prior'),
                label: l10n.monthComparisonPriorPeriod(priorLabel),
                totals: comparison.prior,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _delta(context, l10n, text, priorLabel),
      ],
    );
  }

  /// The `.delta-line`. AC-E4.1's *difference*, as a sentence.
  Widget _delta(
    BuildContext context,
    AppLocalizations l10n,
    TextTheme text,
    String priorLabel,
  ) {
    final Money? difference = comparison.difference;
    if (difference == null) {
      // Entitled to no delta: either not enough history (handled by the screen,
      // which does not build this widget at all) or a period the app could not
      // convert. Saying which beats an empty gap.
      return Text(
        key: const Key('mom.deltaUnavailable'),
        l10n.monthComparisonIncomplete,
        style: text.bodySmall?.copyWith(color: AppColors.ink500),
      );
    }

    final bool up = !difference.isNegative && difference.amount.sign != 0;
    final bool flat = difference.amount.sign == 0;
    final String figure =
        '${formatAmountDigits(difference.abs)} ${difference.currencyCode}';

    return Row(
      key: const Key('mom.delta'),
      children: <Widget>[
        // Direction is carried by the **icon and the words**, never by the
        // colour: NFR-U4, and brand.md §2.3's rule that the ordinary case of
        // spending is not an alarm. Spending more is `ink900`, not red.
        Icon(
          flat
              ? Icons.drag_handle
              : (up ? Icons.trending_up : Icons.trending_down),
          size: 18,
          color: flat
              ? AppColors.ink500
              : (up ? AppColors.ink900 : AppColors.success),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            flat
                ? l10n.monthComparisonSame(priorLabel)
                : (up
                      ? l10n.monthComparisonUp(figure, priorLabel)
                      : l10n.monthComparisonDown(figure, priorLabel)),
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: flat
                  ? AppColors.ink700
                  : (up ? AppColors.ink900 : AppColors.success),
            ),
          ),
        ),
      ],
    );
  }
}

class _FigureCard extends StatelessWidget {
  final String label;
  final PeriodTotals totals;

  const _FigureCard({required this.label, required this.totals, super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: text.bodySmall?.copyWith(color: AppColors.ink500)),
          const SizedBox(height: 6),
          PeriodTotalsText(
            totals: totals,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// **S-31's `.bar-chart`** — the last few months, with the selected one
/// highlighted.
///
/// ## Why the bars are labelled and captioned rather than only drawn
///
/// A bar chart is the one place in this app where a figure would otherwise exist
/// **only** as a pixel height, which fails NFR-U4 outright and is invisible to a
/// screen reader. So every column carries its month name underneath and its
/// figure as a `Semantics` label, and the tallest bar is scaled from the largest
/// figure in the set rather than from a fixed maximum — a chart whose scale the
/// user cannot infer is decoration.
///
/// A month with **no** figure draws no bar at all (not a zero-height one): "we
/// have nothing for this month" and "you spent nothing" are different facts, the
/// same distinction `PeriodTotals.base`'s nullability exists to keep.
class MonthTrailChart extends StatelessWidget {
  final List<MonthBar> bars;

  const MonthTrailChart({required this.bars, super.key});

  /// The flex denominator. A bar's weight is `0..kBarWeightScale`, so one unit is
  /// one percent of the chart area — fine enough that two similar months are
  /// visibly different and coarse enough to stay an integer.
  static const int kBarWeightScale = 100;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // The scale. Taken from the largest magnitude present, so the shape of the
    // chart is a comparison between these months and not against an arbitrary
    // ceiling.
    Money? tallest;
    for (final MonthBar bar in bars) {
      final Money? value = bar.totals.base;
      if (value == null) {
        continue;
      }
      if (tallest == null || value.abs > tallest.abs) {
        tallest = value.abs;
      }
    }

    return SizedBox(
      // An int literal, which Dart widens implicitly — so no banned identifier
      // appears in this file (see the library comment on the ADR-002 guard).
      // Matches the mockup's chart area.
      height: 150,
      child: Row(
        key: const Key('mom.chart'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final MonthBar bar in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 7),
                child: Column(
                  children: <Widget>[
                    Expanded(child: _bar(bar, tallest)),
                    const SizedBox(height: 6),
                    Text(
                      // Riyadh wall clock, for the reason
                      // `formatPeriodMonthLabel` documents: a month window's
                      // `startUtc` is 21:00 on the previous month's last day, so
                      // the raw instant reads as the wrong month.
                      MaterialLocalizations.of(context).formatMonthYear(
                        RiyadhCalendar.toRiyadhWallClock(bar.period.startUtc),
                      ),
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: AppColors.ink500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One column's bar, sized by integer flex rather than by a pixel height.
  ///
  /// The empty space above the bar and the bar itself are two `Expanded`s whose
  /// flexes sum to [kBarWeightScale], which is what makes the proportion exact
  /// without a float. `Expanded` asserts `flex > 0`, so both zero cases are
  /// handled by *omitting* the child rather than by passing `flex: 0`.
  Widget _bar(MonthBar bar, Money? tallest) {
    final int weight = _weightFor(bar, tallest);
    return Semantics(
      // The figure, spoken. Without this the bar is a rectangle a screen-reader
      // user cannot read at all (NFR-U2) — the requirement brand.md §5.3 states
      // as "never a bare, unlabelled colour-only chart".
      label: bar.totals.base == null
          ? null
          : '${formatAmountDigits(bar.totals.base!.abs)} '
                '${bar.totals.baseCurrencyCode}',
      child: Column(
        // `stretch` is what makes the bar fill its column's width. The obvious
        // alternative — an infinite explicit width — would name an identifier the
        // ADR-002 guard bans in this file, and this is the better widget anyway:
        // the bar's width follows its parent instead of asserting an unbounded
        // one.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (weight < kBarWeightScale)
            Expanded(
              flex: kBarWeightScale - weight,
              child: const SizedBox.shrink(),
            ),
          if (weight > 0)
            Expanded(
              flex: weight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bar.isSelected ? AppColors.primary : AppColors.ink300,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `0` for a month with **no figure at all**, so the chart draws nothing rather
  /// than a flat bar: *"we have nothing for this month"* and *"you spent
  /// nothing"* are different facts, the same distinction `PeriodTotals.base`'s
  /// nullability exists to keep.
  ///
  /// `1` (a visible sliver) for a month whose figure is genuinely zero, so it
  /// reads as present-and-empty rather than missing.
  int _weightFor(MonthBar bar, Money? tallest) {
    final Money? value = bar.totals.base;
    if (value == null) {
      return 0;
    }
    if (tallest == null || tallest.amount.sign == 0) {
      return 1;
    }
    final int scaled =
        ((value.abs.amount * Decimal.fromInt(kBarWeightScale)) / tallest.amount)
            .round()
            .toInt();
    // Written as comparisons rather than `clamp`, whose return type is one of the
    // identifiers the ADR-002 guard bans in this file.
    if (scaled < 1) {
      return 1;
    }
    return scaled > kBarWeightScale ? kBarWeightScale : scaled;
  }
}
