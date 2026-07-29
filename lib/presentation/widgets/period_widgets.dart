/// The period selector and the Home headline figure — **KHA-35 / US-E1**.
///
/// | design.md §5 component | here |
/// |---|---|
/// | `MonthTotalCard` | [MonthTotalCard] |
/// | the period row on S-10 | [PeriodSelector] |
///
/// Both are pure widgets over plain values: no provider, no database, no async.
/// That is this codebase's standing rule for screens and their parts (see
/// `categorization_routes.dart`), and it is what makes the AC-E1.3 empty state
/// and the AC-E1.4 month rollover testable without a running app.
library;

import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'ledger_widgets.dart';

/// **AC-E1.4's selector** — `‹ July 2026 ›`, plus a "This month" escape hatch.
///
/// ## Why "next month" is disabled on the current month
///
/// There is nothing after now. A live arrow into an empty future month would
/// invite the user to conclude the app had lost their data when it showed them
/// zero. Disabling it (rather than hiding it) keeps the control's geometry
/// stable so the month label does not jump sideways when paging.
class PeriodSelector extends StatelessWidget {
  final PeriodRange period;

  /// True when [period] is the live current month — drives both the disabled
  /// forward arrow and whether the "This month" shortcut is offered at all.
  final bool isCurrentMonth;

  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  const PeriodSelector({
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        IconButton(
          key: const Key('period.previous'),
          // `chevron_left` inside a `Directionality` is NOT auto-mirrored by
          // Flutter — only a handful of built-in icons are. `Icons.arrow_back`
          // IS direction-aware, so "go to the older month" points the way the
          // reader's own back gesture does in both locales.
          icon: const Icon(Icons.arrow_back),
          // NFR-U2: a screen reader must announce what the arrow does, not
          // "button".
          tooltip: l10n.periodPreviousMonth,
          onPressed: onPreviousMonth,
        ),
        Expanded(
          child: Text(
            formatPeriodMonthLabel(context, period.startUtc),
            key: const Key('period.label'),
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const Key('period.next'),
          icon: const Icon(Icons.arrow_forward),
          tooltip: l10n.periodNextMonth,
          // Null disables the button, which is also what makes a screen reader
          // announce it as unavailable.
          onPressed: isCurrentMonth ? null : onNextMonth,
        ),
        if (!isCurrentMonth)
          TextButton(
            key: const Key('period.current'),
            onPressed: onCurrentMonth,
            child: Text(l10n.periodCurrentMonth),
          ),
      ],
    );
  }
}

/// **design.md §5's `MonthTotalCard`, and AC-E1.1/E1.3.**
///
/// ## The empty state renders `0.00`, and that is a deliberate exception
///
/// Everywhere else in this app, an absent figure renders as words rather than
/// a zero — `PeriodTotalsText` says *"no transactions in this period"*, and
/// `PeriodTotals.base` is nullable precisely so that *"we measured nothing"*
/// and *"you spent nothing"* stay different facts. That rule is right for a
/// figure sitting in a list of other figures.
///
/// AC-E1.3 and the approved mockup (`docs/mockups/home.html`, "Empty" frame)
/// ask for the opposite **here**: *"an explicit `0.00 SAR`, never blank"*. The
/// reason is that this is the *first* number the user sees on opening the app,
/// and the product's promise is answering "what did I spend this month" in
/// under ten seconds. Prose where a headline figure should be reads as a
/// failure to load.
///
/// The two positions are reconciled by showing **both**: the explicit `0.00`
/// *and* the caption "No transactions recorded yet this month". The figure
/// answers the question; the caption stops the user believing we have measured
/// something we have not. Neither alone would do.
///
/// **Loading is still not a zero.** A `0.00` shown while the read is in flight
/// is a number the user may read and believe, so [isLoading] renders a
/// skeleton and no figure at all.
class MonthTotalCard extends StatelessWidget {
  /// Net spend for the period — the same [PeriodTotals] every other figure in
  /// the app is built from, never a separately-queried number (NFR-A6).
  final PeriodTotals totals;

  final bool isLoading;

  /// design.md §3.4's Error state. A failed read must never render as `0.00`:
  /// a reassuring zero the user believes is worse than an error they can act
  /// on.
  final bool hasError;

  const MonthTotalCard({
    required this.totals,
    this.isLoading = false,
    this.hasError = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

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
        children: <Widget>[
          Text(
            l10n.homeThisMonth,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 6),
          _figure(context, l10n, text),
        ],
      ),
    );
  }

  Widget _figure(BuildContext context, AppLocalizations l10n, TextTheme text) {
    if (isLoading) {
      return const Padding(
        key: Key('home.monthTotal.loading'),
        padding: EdgeInsetsDirectional.symmetric(vertical: 8),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (hasError) {
      return Text(
        key: const Key('home.monthTotal.error'),
        l10n.totalsNoneForPeriod,
        style: text.bodyMedium?.copyWith(color: AppColors.error),
      );
    }
    if (totals.isEmpty) {
      // AC-E1.3 — the figure and the caption together. See the class doc.
      return Column(
        key: const Key('home.monthTotal.empty'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${formatAmountDigits(Money.zero(totals.baseCurrencyCode))} '
            '${totals.baseCurrencyCode}',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            // Digits and a currency code read left-to-right even inside an
            // Arabic layout (design.md §3.1's bidi isolation).
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.homeNoSpendThisMonth,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
        ],
      );
    }

    return PeriodTotalsText(
      key: const Key('home.monthTotal.value'),
      totals: totals,
      style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}
