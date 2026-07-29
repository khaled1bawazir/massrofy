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
/// Search (S-26) and filtering (S-27) are **KHA-38 in P5b** and are absent
/// here rather than stubbed. That is why the empty states below cover
/// "nothing ever" and "nothing this month" but not AC-E5.3's filtered-empty:
/// there is no filter yet, and inventing a third empty state for a control
/// that does not exist would be copy nobody can reach.
///
/// ## NFR-A6 — the total and the list cannot disagree
///
/// The running total is computed by `LedgerTotals.spend` over **exactly** the
/// list this screen renders, using the same [PeriodRange.contains] predicate
/// that decided which rows to render. There is no second query. A user who
/// distrusts the figure can add the rows up and will get it — which is what
/// NFR-A6's *"no derived figure that cannot be traced back to its constituent
/// transactions"* means in practice.
///
/// The one honest exception is stated on screen: rows this build cannot decode
/// (KHA-74) are counted in [unreadableCount] and named, because a shorter list
/// with no explanation is indistinguishable from lost data.
///
/// ## A pure widget, on purpose
///
/// No provider, no database, no async — the codebase's standing rule (see
/// `categorization_routes.dart`). `TransactionListHost` in `ledger_routes.dart`
/// is the single construction site.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/learned_rules.dart';
import '../../features/ledger/internal_transfer.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';
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
    this.isLoading = false,
    this.hasError = false,
    this.onOpenTransaction,
    this.onEditCategory,
    this.onAddManually,
    this.title,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(title ?? l10n.navTransactions)),
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
          _RunningTotal(
            totals: totals,
            isLoading: isLoading,
            hasError: hasError,
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

  const _RunningTotal({
    required this.totals,
    required this.isLoading,
    required this.hasError,
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
          Text(
            l10n.txnListTotalForPeriod,
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
