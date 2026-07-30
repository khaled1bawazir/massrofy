/// Riverpod wiring for P5b — the reports (KHA-37) and the transaction filter
/// (KHA-38).
///
/// ## Everything is derived from `ledgerViewProvider`, on purpose
///
/// Not one provider here opens its own Drift stream over the transactions table.
/// They all `watch` [ledgerViewProvider], which is the single place the ledger is
/// read, mapped and analysed for internal transfers (see its own doc comment on
/// why the detector must run over the whole set exactly once).
///
/// That is what makes AC-C1.3 and AC-E3.2 defensible rather than hopeful. Both
/// ACs are of the form *"these parts sum to the total shown elsewhere in the
/// app"*, and "elsewhere" — Home's `MonthTotalCard`, S-10's running total, S-22's
/// bank figure — reads the same emission of the same stream. A second query would
/// be a second chance for the two to disagree, and NFR-A6 exists precisely to
/// forbid a figure that cannot be traced to the rows behind it.
///
/// The cost is that a report is recomputed on every ledger emission rather than
/// cached. That is deliberate too: `docs/build-plan.md`'s P5 watch items open with
/// *"no cached totals that can drift from the ledger (NFR-A6)"*, and the work is a
/// few thousand `Decimal` additions on a screen the user opened on purpose.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/category_breakdown.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/instrument_breakdown.dart';
import '../../features/ledger/ledger_mapping.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/month_comparison.dart';
import '../../features/ledger/period_totals.dart';
import '../../features/ledger/transaction_filter.dart';
import 'app_providers.dart';
import 'categorization_providers.dart';
import 'ledger_providers.dart';

/// **S-29 — the category breakdown for the visible period** (AC-E2.1, AC-E2.3,
/// AC-C1.3).
///
/// `includeEmptyCategories: false` — a breakdown lists what happened, and thirteen
/// rows of "nothing" would bury the eight that matter. **This does not weaken
/// AC-E2.3**: that AC is about *Uncategorized with a non-zero total*, and
/// `CategoryBreakdown.of` includes any category with at least one transaction in
/// the period, Uncategorized included, with no "Other" fold and no truncation. A
/// zero-total Uncategorized row would be an empty claim, not a disclosure.
final Provider<AsyncValue<CategoryBreakdown>>
categoryBreakdownProvider = Provider<AsyncValue<CategoryBreakdown>>((Ref ref) {
  final AsyncValue<LedgerView> ledger = ref.watch(ledgerViewProvider);
  final AsyncValue<CategoryResolver> resolver = ref.watch(
    categoryResolverProvider,
  );
  final PeriodRange period = ref.watch(ledgerPeriodProvider);

  // A `Provider` over two `AsyncValue`s rather than a `FutureProvider`:
  // combining them by hand keeps the loading and error arms *distinguishable*
  // on the way to the screen, which design.md §3.4 requires each screen to
  // render differently. Collapsing to a future would turn a resolver failure
  // into "still loading" forever.
  if (ledger.hasError) {
    return AsyncValue<CategoryBreakdown>.error(
      ledger.error!,
      ledger.stackTrace ?? StackTrace.empty,
    );
  }
  if (resolver.hasError) {
    return AsyncValue<CategoryBreakdown>.error(
      resolver.error!,
      resolver.stackTrace ?? StackTrace.empty,
    );
  }
  if (ledger.value == null || resolver.value == null) {
    return const AsyncValue<CategoryBreakdown>.loading();
  }

  return AsyncValue<CategoryBreakdown>.data(
    CategoryBreakdown.of(
      ledger.value!.transactions,
      period: period,
      resolver: resolver.value!,
    ),
  );
});

/// **S-30 — the per-instrument breakdown for the visible period** (AC-E3.1,
/// AC-E3.2).
///
/// Needs the bank and instrument rows as well as the transactions, because an
/// instrument with no activity still gets a row (and a card the user holds and did
/// not use is information — see `instrument_breakdown.dart`).
final StreamProvider<InstrumentBreakdown> instrumentBreakdownProvider =
    StreamProvider<InstrumentBreakdown>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);
      if (session == null || daos == null) {
        // Locked: ADR-005 makes the lock cryptographic, so "nothing" is the
        // truthful value rather than a placeholder.
        yield InstrumentBreakdown.empty;
        return;
      }

      final PeriodRange period = ref.watch(ledgerPeriodProvider);

      // Driven off the same `watchLive()` stream the bank tree uses, so S-30's
      // per-card figures and S-22's cannot come from two different reads.
      await for (final List<TransactionRow> rows
          in session.transactionDao.watchLive()) {
        final List<LedgerBank> banks = <LedgerBank>[
          for (final BankRow row in await daos.bankDao.all()) toLedgerBank(row),
        ];
        final List<LedgerInstrument> instruments = <LedgerInstrument>[
          for (final InstrumentRow row in await daos.instrumentDao.all())
            toLedgerInstrument(row),
        ];
        yield InstrumentBreakdown.of(
          toLedgerTransactions(
            rows,
            instrumentsById: <int, LedgerInstrument>{
              for (final LedgerInstrument instrument in instruments)
                instrument.id: instrument,
            },
          ),
          period: period,
          banks: banks,
          instruments: instruments,
        );
      }
    });

/// **S-31 — the month-over-month comparison** (AC-E4.1, AC-E4.2).
///
/// Takes the **whole** ledger, not a period slice: the prior month's figure needs
/// rows outside the visible period by definition, and the AC-E4.2 history count
/// needs every month there has ever been.
final Provider<AsyncValue<MonthComparison>> monthComparisonProvider =
    Provider<AsyncValue<MonthComparison>>((Ref ref) {
      final AsyncValue<LedgerView> ledger = ref.watch(ledgerViewProvider);
      final PeriodRange period = ref.watch(ledgerPeriodProvider);

      if (ledger.hasError) {
        return AsyncValue<MonthComparison>.error(
          ledger.error!,
          ledger.stackTrace ?? StackTrace.empty,
        );
      }
      if (ledger.value == null) {
        return const AsyncValue<MonthComparison>.loading();
      }
      return AsyncValue<MonthComparison>.data(
        MonthComparison.of(ledger.value!.transactions, period: period),
      );
    });

/// **KHA-38 / AC-E5.2 — the filter the transaction list is showing.**
///
/// ## Why this is app-scoped state and not a `StatefulWidget` field
///
/// Two reasons, and the second is the one that decided it:
///
///  1. `AppShell` keeps every tab alive in an `IndexedStack`, so a filter held in
///     the list screen's own `State` would survive a tab switch anyway — but only
///     by accident, and it would be lost the moment the shell was rebuilt.
///  2. **S-29 needs to set it.** AC-E2.2 — *"selecting a category lists its
///     underlying transactions"* — is implemented by pre-filtering this value and
///     navigating to the list, which is what makes the drill-down land on the
///     *same* screen, with the same total arithmetic, as the user's own filtering.
///     A second "filtered list" screen would be a second implementation of
///     AC-E5.2's total.
final NotifierProvider<TransactionFilterNotifier, TransactionFilter>
transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
      TransactionFilterNotifier.new,
    );

/// Owns the active [TransactionFilter].
///
/// **Deliberately not persisted.** NFR-S4: *"search queries and results must not
/// be logged — a search history is a record of what the user was looking for in
/// their financial life."* A filter written to `app_settings` would be exactly
/// that record, surviving reboots, in the one app that promises the opposite
/// (US-F4). It lives in memory for as long as the process does and no longer.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => TransactionFilter.none;

  void set(TransactionFilter filter) => state = filter;

  /// AC-E5.1's live search — every keystroke, other facets untouched.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// **AC-E2.2's entry point.** Replaces the whole filter with "just this
  /// category", because arriving from a breakdown row with a leftover amount bound
  /// from ten minutes ago would show a subset of the slice the user just tapped
  /// and label it as the slice.
  void showOnlyCategory(String categoryId) =>
      state = TransactionFilter(categoryIds: <String>{categoryId});

  /// AC-E5.3's clear action.
  void clear() => state = TransactionFilter.none;
}
