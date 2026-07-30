/// **S-10 — Transaction List.** Mockup: `docs/mockups/transactions.html`.
/// **KHA-36, US-B2, AC-B4.3, AC-B7.3, AC-C4.1, NFR-U4.**
///
/// ---
///
/// ## What this screen is responsible for, and what it deliberately is not
///
/// It renders a period, a running total for that period, and the rows behind
/// that total. Every row-level acceptance criterion — manual vs SMS-derived
/// (AC-B4.3), credit vs debit without colour (AC-B7.3), the review indicator
/// (AC-C4.1) — belongs to [TransactionListItem], which every other list in the
/// app also uses. This screen owns the *set* of rows, not their appearance.
///
/// ## Search and filter arrived here in P5b — KHA-38, US-E5
///
/// P5a's version of this comment said search (S-26) and filtering (S-27) were
/// *"absent here rather than stubbed"*, and that AC-E5.3's filtered-empty state
/// was therefore unreachable copy. Both are now built, so this screen has
/// **three** distinct empty states and the difference between them is the point:
///
/// | State | Key | Means |
/// |---|---|---|
/// | true-empty | `txnList.empty` | the ledger has never held anything |
/// | empty-for-period | `txnList.emptyForPeriod` | there is data, just not in this month |
/// | **filtered-empty** | `txnList.filteredEmpty` | a filter matched nothing (AC-E5.3) |
///
/// Telling a user with two years of history that they have no transactions looks
/// exactly like data loss, which is why these are three states and not one.
///
/// ## NFR-A6 / AC-E5.2 — the total and the list cannot disagree, filtered or not
///
/// The running total is computed by `LedgerTotals.spend` over **exactly** the
/// list this screen renders — the caller filters once and hands over both the
/// rows and the figure derived from them. There is no second query and no second
/// predicate. That is what makes AC-E5.2's *"the displayed total reflects the
/// filtered subset, not the whole period"* true by construction rather than by
/// two code paths agreeing.
///
/// The figure is also **relabelled** when a filter is active ("Filtered total"),
/// because a number that silently changed meaning under an unchanged label would
/// be worse than no filter at all — a user glancing at it would read a subset as
/// their month.
///
/// Two honest exceptions are stated on screen rather than left as silent gaps:
/// rows this build cannot decode (KHA-74, [unreadableCount]) and rows an amount
/// bound could not compare because they have no base-currency figure
/// ([notComparableByAmountCount], ADR-009 case 4).
///
/// ## A pure widget, on purpose
///
/// No provider, no database, no async — the codebase's standing rule (see
/// `categorization_routes.dart`). `TransactionListHost` in `ledger_routes.dart`
/// is the single construction site.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/categories.dart';
import '../../features/categorization/learned_rules.dart';
import '../../features/ledger/base_currency.dart';
import '../../features/ledger/internal_transfer.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/period_totals.dart';
import '../../features/ledger/transaction_filter.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';
import '../widgets/filter_widgets.dart';
import '../widgets/ledger_widgets.dart';
import '../widgets/period_widgets.dart';
import '../widgets/transaction_list_item.dart';

class TransactionListScreen extends StatelessWidget {
  /// The rows for [period], newest first — already filtered by the caller.
  final List<LedgerTransaction> transactions;

  /// The figure for exactly [transactions]. Supplied rather than computed here
  /// so this widget stays free of money arithmetic; `LedgerTotals` is the one
  /// place a total is produced (ADR-002).
  final PeriodTotals totals;

  final PeriodRange period;
  final bool isCurrentMonth;

  /// Transaction id → `internal` | `candidate` | `external`, computed by the
  /// caller over the **whole** ledger — see [TransactionListItem] for why a
  /// row cannot work this out for itself.
  final Map<int, String> internalTransferStates;

  /// Transaction id → category chip, for AC-C4.1. Empty renders no chips,
  /// which is the honest rendering for a caller that has not loaded categories.
  final Map<int, CategoryAssignment> categoryAssignments;

  /// True when the ledger holds transactions in *some* period, so an empty
  /// list means "not this month" rather than "nothing ever". The two states
  /// need different copy: telling a user with two years of history that they
  /// have no transactions looks exactly like data loss.
  final bool ledgerHasAnyTransactions;

  /// KHA-74 — rows in this period whose stored amount could not be read.
  final int unreadableCount;

  /// **KHA-38 / AC-E5.2** — the filter currently applied. [TransactionFilter.none]
  /// renders the screen exactly as P5a did.
  final TransactionFilter filter;

  /// ADR-009 case 4 — rows an **amount** bound could not compare, because the app
  /// has no base-currency figure for them. Stated rather than silently dropped: a
  /// filter that quietly omits a purchase is the same defect as a total that does.
  final int notComparableByAmountCount;

  /// The currency the amount bounds are in, named in the disclosure line above.
  final String baseCurrencyCode;

  /// Null hides the search field and the filter button entirely — used by the
  /// scoped list an instrument or a bank pushes, where the set of rows is the
  /// screen's whole subject and filtering it again would be confusing.
  final ValueChanged<String>? onQueryChanged;
  final VoidCallback? onOpenFilterSheet;
  final ValueChanged<TransactionFilter>? onFilterChanged;
  final VoidCallback? onClearFilter;

  /// Resolves category ids for the active-filter chips.
  final CategoryResolver? filterCategoryResolver;

  /// Labels for the instrument chips, keyed by instrument id.
  final Map<int, String> filterInstrumentLabels;

  final bool isLoading;
  final bool hasError;

  final void Function(LedgerTransaction transaction)? onOpenTransaction;
  final void Function(LedgerTransaction transaction)? onEditCategory;
  final VoidCallback? onAddManually;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onCurrentMonth;

  /// Rendered as the screen's own `AppBar` when true (the tab host supplies
  /// its own scaffolding, so `false` there), and as a plain column when this
  /// screen is pushed as a route from an instrument or a bank.
  final String? title;

  const TransactionListScreen({
    required this.transactions,
    required this.totals,
    required this.period,
    required this.isCurrentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCurrentMonth,
    this.internalTransferStates = const <int, String>{},
    this.categoryAssignments = const <int, CategoryAssignment>{},
    this.ledgerHasAnyTransactions = false,
    this.unreadableCount = 0,
    this.filter = TransactionFilter.none,
    this.notComparableByAmountCount = 0,
    this.baseCurrencyCode = BaseCurrency.defaultCode,
    this.onQueryChanged,
    this.onOpenFilterSheet,
    this.onFilterChanged,
    this.onClearFilter,
    this.filterCategoryResolver,
    this.filterInstrumentLabels = const <int, String>{},
    this.isLoading = false,
    this.hasError = false,
    this.onOpenTransaction,
    this.onEditCategory,
    this.onAddManually,
    this.title,
    super.key,
  });

  /// True when the search field and filter button are offered at all.
  bool get _searchEnabled => onQueryChanged != null;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(title ?? l10n.navTransactions),
        actions: <Widget>[
          if (_searchEnabled && onOpenFilterSheet != null)
            // The badge is part of the *icon*, not only a colour change: a filter
            // silently narrowing the list is the most confusing state this screen
            // can be in, so the count is on screen and the chips below name each
            // facet (NFR-U4).
            IconButton(
              key: const Key('txnList.openFilter'),
              tooltip: l10n.filterOpen,
              onPressed: onOpenFilterSheet,
              icon: Badge(
                isLabelVisible: filter.activeFacetCount > 0,
                label: Text('${filter.activeFacetCount}'),
                child: Icon(
                  filter.isActive
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: onAddManually == null
          ? null
          : FloatingActionButton(
              key: const Key('txnList.addTransaction'),
              // Distinct from Home's. `AppShell`'s `IndexedStack` keeps both
              // tabs alive at once, and two FABs sharing Flutter's default
              // hero tag inside one route subtree is an assertion failure the
              // first time any route transition animates.
              heroTag: 'fab.transactionList',
              tooltip: l10n.homeAddManually,
              onPressed: onAddManually,
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
            child: PeriodSelector(
              period: period,
              isCurrentMonth: isCurrentMonth,
              onPreviousMonth: onPreviousMonth,
              onNextMonth: onNextMonth,
              onCurrentMonth: onCurrentMonth,
            ),
          ),
          // **S-26** — AC-E5.1's live merchant search.
          if (_searchEnabled)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
              child: TransactionSearchField(
                query: filter.query,
                onChanged: onQueryChanged!,
              ),
            ),
          // **S-27's removable chips**, and AC-E5.3's always-visible way out.
          if (_searchEnabled &&
              filter.isActive &&
              onFilterChanged != null &&
              onClearFilter != null &&
              filterCategoryResolver != null)
            ActiveFilterChips(
              filter: filter,
              resolver: filterCategoryResolver!,
              instrumentLabels: filterInstrumentLabels,
              onChanged: onFilterChanged!,
              onClearAll: onClearFilter!,
            ),
          _RunningTotal(
            totals: totals,
            isLoading: isLoading,
            hasError: hasError,
            // AC-E5.2 — the figure is relabelled when it describes a subset. An
            // unchanged label over a changed meaning is the failure mode here.
            isFiltered: filter.isActive,
            resultCount: transactions.length,
          ),
          if (unreadableCount > 0)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: Text(
                key: const Key('txnList.unreadable'),
                l10n.txnListUnreadableNote(unreadableCount),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.warningText),
              ),
            ),
          // ADR-009 case 4 under an amount bound. Counted and named, never
          // dropped silently.
          if (notComparableByAmountCount > 0)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: Text(
                key: const Key('txnList.notComparableByAmount'),
                l10n.filterNotComparableByAmount(
                  notComparableByAmountCount,
                  baseCurrencyCode,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            ),
          Expanded(child: _body(context, l10n)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLoading) {
      return const Center(
        key: Key('txnList.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (hasError) {
      // design.md §3.4's Error state, ahead of the empty check on purpose: an
      // empty list is this screen's *ordinary* state, and rendering it for a
      // failed read is the most misleading thing it can do.
      return CategorySectionError(message: l10n.transactionUnavailable);
    }
    if (transactions.isEmpty) {
      // **AC-E5.3 — the filtered-empty state, checked FIRST.**
      //
      // Order matters. A filter that matches nothing in a month that does hold
      // transactions would otherwise render "Nothing in this month", which is
      // false, unactionable, and reads as though the app had lost the month. The
      // filtered case is the more specific claim, so it wins.
      if (filter.isActive) {
        return Column(
          key: const Key('txnList.filteredEmpty'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CategoryEmptyState(
              icon: Icons.search_off_outlined,
              headline: l10n.txnListFilteredEmptyTitle,
              body: l10n.txnListFilteredEmptyBody,
            ),
            // AC-E5.3's *"way to clear the filter"*, offered inside the state
            // itself rather than only as a chip further up the screen — the chips
            // scroll away and this is the moment the user needs the action.
            if (onClearFilter != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4),
                child: FilledButton.icon(
                  key: const Key('txnList.filteredEmpty.clear'),
                  onPressed: onClearFilter,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(l10n.filterClearAll),
                ),
              ),
          ],
        );
      }
      return CategoryEmptyState(
        key: ledgerHasAnyTransactions
            ? const Key('txnList.emptyForPeriod')
            : const Key('txnList.empty'),
        icon: Icons.receipt_long_outlined,
        headline: ledgerHasAnyTransactions
            ? l10n.txnListEmptyForPeriodTitle
            : l10n.txnListEmptyTitle,
        body: ledgerHasAnyTransactions
            ? l10n.txnListEmptyForPeriodBody
            : l10n.txnListEmptyBody,
      );
    }

    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 96),
      itemCount: transactions.length,
      itemBuilder: (BuildContext context, int index) {
        final LedgerTransaction txn = transactions[index];
        return TransactionListItem(
          transaction: txn,
          internalTransferState: internalTransferStates[txn.id],
          categoryAssignment: categoryAssignments[txn.id],
          onTap: onOpenTransaction == null
              ? null
              : () => onOpenTransaction!(txn),
          // design.md §6.1's first entry point: the chip itself opens the
          // correction sheet, so the product's highest-frequency interaction
          // costs two taps from the list rather than a screen navigation.
          onTapCategory: onEditCategory == null
              ? null
              : () => onEditCategory!(txn),
        );
      },
    );
  }
}

/// The mockup's `period-row` figure — *"Total −3,214.50 SAR"*.
///
/// Signed with the spend convention, like every other period figure
/// ([TotalsSign.spend]), so a month with more refunds than purchases renders
/// `+` rather than a minus sign that would claim the opposite.
class _RunningTotal extends StatelessWidget {
  final PeriodTotals totals;
  final bool isLoading;
  final bool hasError;

  /// **AC-E5.2.** Swaps the label to "Filtered total" and shows the row count.
  ///
  /// The relabelling is the requirement, not decoration: the AC asks for the
  /// displayed total to reflect the filtered subset, and a figure that changed
  /// meaning under an unchanged label would be read as the month's spending by
  /// anyone glancing at it.
  final bool isFiltered;

  /// How many rows are behind the figure — NFR-A6's traceability in its cheapest
  /// form. Shown only when filtered, where "which rows?" is the live question.
  final int resultCount;

  const _RunningTotal({
    required this.totals,
    required this.isLoading,
    required this.hasError,
    this.isFiltered = false,
    this.resultCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (isFiltered) ...<Widget>[
            Expanded(
              child: Text(
                key: const Key('txnList.resultCount'),
                l10n.txnListResultCount(resultCount),
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            key: isFiltered
                ? const Key('txnList.total.filteredLabel')
                : const Key('txnList.total.periodLabel'),
            isFiltered ? l10n.txnListFilteredTotal : l10n.txnListTotalForPeriod,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(width: 8),
          // No figure at all while loading or after a failure — a number the
          // user may read and believe must never be shown for data we do not
          // have.
          if (isLoading)
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (hasError)
            Text(
              l10n.totalsNoneForPeriod,
              style: text.bodySmall?.copyWith(color: AppColors.error),
            )
          else
            PeriodTotalsText(
              key: const Key('txnList.total'),
              totals: totals,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

/// Exposed so the instrument-detail screen and the tests can assert the same
/// rule this screen applies: a **confirmed** internal transfer shows no sign,
/// a candidate keeps one.
bool isConfirmedInternalTransfer(String? state) =>
    state == InternalTransferState.internal;
