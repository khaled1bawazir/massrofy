/// **The construction sites for every ledger screen — KHA-36, and the second
/// half of KHA-113.**
///
/// ## Why this file exists
///
/// `docs/lessons.md` has the rule twice over, and `categorization_routes.dart`
/// quotes it in its own header:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code — it
/// > expires the moment someone adds a route, silently."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// KHA-113 is that rule being broken at scale: QA's first fresh-install walk
/// found **six** fully-built, fully-tested screens with zero construction sites
/// anywhere in `lib/` — `SmsPermissionRationaleScreen`, `SmsLimitedModeScreen`,
/// `BanksScreen`, `ManualEntryScreen`, `ImportProgressScreen` and
/// `InstrumentDetailScreen`. Four of them are constructed here; the two
/// onboarding screens are constructed in `onboarding_gate.dart`, which is their
/// natural home because they are a *journey*, not a destination.
///
/// So: a future reachability question about any ledger screen is answered by
/// grepping for the `open*` functions below, and nothing else.
///
/// ## The shape: hosts, not screens
///
/// Identical to `categorization_routes.dart`. Every screen is a plain widget
/// over values with no provider in it, and the `Consumer` **hosts** here do the
/// joining: watch providers, render design.md §3.4's loading/error/locked
/// states, hand the screen values plus callbacks. That is what keeps widget
/// tests pure render tests, and what keeps ADR-005's guarantee checkable — a
/// screen cannot read something the app lock has not unlocked, because it
/// cannot read anything at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/learned_rules.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/manual_entry.dart';
import '../../features/ledger/period_totals.dart';
import '../../features/ledger/transaction_edit.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/categorization_providers.dart';
import '../providers/ingestion_providers.dart';
import '../providers/ledger_providers.dart';
import '../widgets/category_widgets.dart';
import '../widgets/scoped_snack_bar.dart';
import 'banks_screen.dart';
import 'categorization_routes.dart';
import 'import_progress_screen.dart';
import 'instrument_detail_screen.dart';
import 'manual_entry_screen.dart';
import 'transaction_list_screen.dart';

// =========================================================================
// The navigation graph.
// =========================================================================

/// **S-10** — the full transaction list, pushed as a route (Home's "View all").
///
/// The same screen is *also* the second bottom-nav tab, where it is embedded
/// rather than pushed. Both go through [TransactionListHost], so there is one
/// implementation of "what the list shows".
Future<void> openTransactionList(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const TransactionListHost()));

/// **S-21** — the banks list, and everything under it.
Future<void> openBanks(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const BanksHost()));

/// **S-20 in add mode** — US-B4's manual entry.
Future<void> openManualEntry(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const ManualEntryHost()));

/// **S-20 in edit mode** — US-B5. By id, not by value: the form must start
/// from the row as it is *now*, and a value captured when the list was built
/// goes stale the moment a correction lands.
Future<void> openTransactionEdit(BuildContext context, int transactionId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManualEntryHost(editTransactionId: transactionId),
      ),
    );

// =========================================================================
// Hosts
// =========================================================================

/// **S-10.** Joins the live ledger, the period and the category resolver.
class TransactionListHost extends ConsumerWidget {
  /// Limits the list to one instrument (S-23/S-24's drill-down). Null shows
  /// everything.
  final int? instrumentId;

  /// AppBar title when scoped — the instrument's own label, so the user can
  /// see *whose* transactions they are looking at.
  final String? title;

  /// Zero in widget tests, so the correction sheet's scope strip resolves
  /// deterministically instead of racing a real 3-second timer.
  final Duration autoConfirmDelay;

  const TransactionListHost({
    this.instrumentId,
    this.title,
    this.autoConfirmDelay = const Duration(seconds: 3),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<LedgerView> ledgerAsync = ref.watch(ledgerViewProvider);
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);
    final AsyncValue<CategoryResolver> resolver = ref.watch(
      categoryResolverProvider,
    );

    final LedgerView ledger = ledgerAsync.value ?? LedgerView.empty;
    final List<LedgerTransaction> scoped = instrumentId == null
        ? ledger.transactions
        : ledger.forInstrument(instrumentId!);
    final List<LedgerTransaction> rows = <LedgerTransaction>[
      for (final LedgerTransaction txn in scoped)
        if (period.contains(txn.occurredAt)) txn,
    ];

    return TransactionListScreen(
      title: title,
      transactions: rows,
      // **NFR-A6, in one line.** The figure is computed over exactly `rows`,
      // the same list rendered beneath it, with the internal-transfer verdicts
      // already derived from the whole ledger. No second query exists that
      // could disagree with what is on screen.
      totals: LedgerTotals.spend(rows, period: period),
      period: period,
      isCurrentMonth: periods.isCurrentMonth,
      internalTransferStates: ledger.internalTransferStates,
      categoryAssignments: resolver.value == null
          ? const <int, CategoryAssignment>{}
          : <int, CategoryAssignment>{
              for (final LedgerTransaction txn in rows)
                txn.id: assignmentForTransaction(txn, resolver.value!),
            },
      // Distinguishes "nothing this month" from "nothing ever" — see the
      // screen's two empty states.
      ledgerHasAnyTransactions: scoped.isNotEmpty,
      unreadableCount: ledger.unreadable.length,
      isLoading: ledgerAsync.isLoading,
      hasError: ledgerAsync.hasError,
      onOpenTransaction: (LedgerTransaction txn) =>
          openTransactionDetail(context, txn.id),
      onEditCategory: (LedgerTransaction txn) => correctTransactionCategory(
        context: context,
        ref: ref,
        transactionId: txn.id,
        autoConfirmDelay: autoConfirmDelay,
      ),
      onAddManually: () => openManualEntry(context),
      onPreviousMonth: () => periods.shiftMonths(-1),
      onNextMonth: () => periods.shiftMonths(1),
      onCurrentMonth: periods.showCurrentMonth,
    );
  }
}

/// **S-21 — Banks List** (AC-B2.1, AC-B12.1).
class BanksHost extends ConsumerWidget {
  const BanksHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<BankTreeNode>> tree = ref.watch(bankTreeProvider);

    return tree.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.banksTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      // Never an empty banks list on a failed read: "no banks yet" is this
      // screen's welcome state and showing it wrongly tells a user with five
      // accounts that the app has forgotten all of them.
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: Text(l10n.banksTitle)),
        body: CategorySectionError(
          message: l10n.transactionUnavailable,
          onRetry: () => ref.invalidate(bankTreeProvider),
        ),
      ),
      data: (List<BankTreeNode> banks) => BanksScreen(
        banks: banks,
        onOpenBank: (BankTreeNode node) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            // By **canonical key**, not by value. The node carries live period
            // figures, and a value captured at tap time would freeze them: an
            // ingestion sweep landing while the user is on the bank page would
            // move Home's total and leave this screen's quietly stale. That is
            // exactly the class of drift NFR-A6 exists to forbid.
            builder: (_) => BankDetailHost(bankId: node.bank.id),
          ),
        ),
      ),
    );
  }
}

/// **S-22 — Bank Detail** (AC-B2.1, AC-B2.2, AC-B12.2, AC-B13.3).
///
/// Accounts and cards reach the screen as two separate collections, so the
/// "never merged into one undifferentiated list" requirement is a property of
/// the data rather than of a widget remembering to split it — see
/// `bank_tree.dart`.
class BankDetailHost extends ConsumerWidget {
  final int bankId;

  const BankDetailHost({required this.bankId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<BankTreeNode>> tree = ref.watch(bankTreeProvider);

    return tree.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.banksTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: Text(l10n.banksTitle)),
        body: CategorySectionError(message: l10n.transactionUnavailable),
      ),
      data: (List<BankTreeNode> banks) {
        final BankTreeNode? node = banks
            .where((BankTreeNode n) => n.bank.id == bankId)
            .firstOrNull;
        if (node == null) {
          // Reachable without any bug — an "erase everything" (US-F3) running
          // while this screen is open removes the bank underneath it. Saying so
          // beats a blank screen.
          return Scaffold(
            appBar: AppBar(title: Text(l10n.banksTitle)),
            body: CategoryEmptyState(
              icon: Icons.account_balance_outlined,
              headline: l10n.banksEmptyTitle,
              body: l10n.banksEmptyBody,
            ),
          );
        }
        return BankDetailScreen(
          node: node,
          onOpenInstrument: (InstrumentSummary summary) =>
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      InstrumentDetailHost(instrumentId: summary.instrument.id),
                ),
              ),
        );
      },
    );
  }
}

/// **S-23 / S-24 — Account and Card Detail** (AC-B2.3, AC-B3.1, AC-B14.2/3,
/// AC-B15.2).
///
/// ## AC-B2.3 is guaranteed here, not hoped for
///
/// *"only that instrument's transactions are listed and the total equals the
/// sum of those transactions for the period."* Both halves come from the same
/// [BankTreeNode]: `BankTreeBuilder` computed [InstrumentSummary.totals] with
/// `LedgerTotals.spend` over exactly this instrument's rows, and the list below
/// is that same filter applied to the same live ledger. There is no second
/// query and no cached column, so they cannot disagree (NFR-A6).
class InstrumentDetailHost extends ConsumerWidget {
  final int instrumentId;

  const InstrumentDetailHost({required this.instrumentId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<BankTreeNode>> tree = ref.watch(bankTreeProvider);
    final AsyncValue<LedgerView> ledgerAsync = ref.watch(ledgerViewProvider);
    final PeriodRange period = ref.watch(ledgerPeriodProvider);

    if (tree.hasError || ledgerAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.instrumentRecentTransactions)),
        body: CategorySectionError(message: l10n.transactionUnavailable),
      );
    }
    if (tree.isLoading || ledgerAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.instrumentRecentTransactions)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final InstrumentSummary? summary = _findInstrument(
      tree.value ?? const <BankTreeNode>[],
    );
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.instrumentRecentTransactions)),
        body: CategoryEmptyState(
          icon: Icons.credit_card_off_outlined,
          headline: l10n.banksEmptyTitle,
          body: l10n.banksEmptyBody,
        ),
      );
    }

    final LedgerView ledger = ledgerAsync.value ?? LedgerView.empty;
    final List<LedgerTransaction> own = <LedgerTransaction>[
      for (final LedgerTransaction txn in ledger.forInstrument(instrumentId))
        if (period.contains(txn.occurredAt)) txn,
    ];

    return InstrumentDetailScreen(
      summary: summary,
      transactions: own,
      internalTransferStates: ledger.internalTransferStates,
      onOpenTransaction: (LedgerTransaction txn) =>
          openTransactionDetail(context, txn.id),
      // **AC-B3.1 — US-B3's rename.** The change propagates everywhere because
      // every screen reads the instrument's `friendlyName` from one row, and
      // the next SMS still matches on `refKey` (AC-B3.2) because the rename
      // touches neither.
      //
      // The empty string is passed straight through rather than filtered here:
      // `InstrumentDao.rename` already treats a blank as "clear the name", so
      // the instrument falls back to its masked identifier (AC-B15.2), and
      // doing the same normalisation twice is how the two copies eventually
      // disagree.
      onRename: (String? newName) async {
        final LedgerDaos? daos = await ref.read(ledgerDaosProvider.future);
        await daos?.instrumentDao.rename(id: instrumentId, newName: newName);
      },
    );
  }

  InstrumentSummary? _findInstrument(List<BankTreeNode> banks) {
    for (final BankTreeNode node in banks) {
      for (final InstrumentSummary summary in <InstrumentSummary>[
        ...node.accounts,
        ...node.cards,
      ]) {
        if (summary.instrument.id == instrumentId) {
          return summary;
        }
      }
    }
    return null;
  }
}

/// **S-20 — Manual Transaction Entry / Edit** (US-B4, US-B5).
///
/// One host for both modes, because design.md S-20 is explicit that entry and
/// edit share their field set and the screen already switches on `existing`.
/// Two hosts would be two places for a validation rule to be added to one and
/// forgotten on the other.
class ManualEntryHost extends ConsumerStatefulWidget {
  /// Null for US-B4 (adding), non-null for US-B5 (editing).
  final int? editTransactionId;

  const ManualEntryHost({this.editTransactionId, super.key});

  @override
  ConsumerState<ManualEntryHost> createState() => _ManualEntryHostState();
}

class _ManualEntryHostState extends ConsumerState<ManualEntryHost> {
  /// Field names a **service** rejected, fed back into the form so the message
  /// lands on the input the user is looking at (AC-B4.2) rather than in a
  /// snackbar they have to map back to a field themselves.
  List<String> _rejectedFields = const <String>[];
  bool _amountWasNegative = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<BankTreeNode>> tree = ref.watch(bankTreeProvider);
    final AsyncValue<LedgerView> ledgerAsync = ref.watch(ledgerViewProvider);

    final List<InstrumentSummary> instruments = <InstrumentSummary>[
      for (final BankTreeNode node in tree.value ?? const <BankTreeNode>[])
        ...node.accounts,
      // Cards after accounts, matching S-22's segmented order: the account is
      // what funds the cards, so it leads.
      for (final BankTreeNode node in tree.value ?? const <BankTreeNode>[])
        ...node.cards,
    ];

    final int? editing = widget.editTransactionId;
    if (editing == null) {
      return ManualEntryScreen(
        instruments: instruments,
        rejectedFields: _rejectedFields,
        amountWasNegative: _amountWasNegative,
        onAdd: (ManualTransactionDraft draft) => _add(draft),
      );
    }

    final LedgerTransaction? existing = (ledgerAsync.value ?? LedgerView.empty)
        .transactions
        .where((LedgerTransaction txn) => txn.id == editing)
        .firstOrNull;
    if (ledgerAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.txnEditTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (existing == null) {
      // Deleted or merged away while the form was being opened. A real case,
      // not defensive coding — the detail screen offers Delete right next to
      // Edit.
      return Scaffold(
        appBar: AppBar(title: Text(l10n.txnEditTitle)),
        body: CategoryEmptyState(
          icon: Icons.receipt_long_outlined,
          headline: l10n.transactionGoneTitle,
          body: l10n.transactionGoneBody,
        ),
      );
    }

    return FutureBuilder<TransactionEditHistory>(
      // **AC-B5.2** — "the detail view shows BOTH the original auto-detected
      // value and the user-edited value". Read from the audit trail rather than
      // a duplicate column, so the form cannot disagree with the change
      // history (see `transaction_edit.dart`).
      future: _loadEditHistory(editing),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<TransactionEditHistory> snapshot,
          ) => ManualEntryScreen(
            existing: existing,
            // `TransactionEditHistory.none` while the trail is still loading:
            // the form is fully usable without it, and blocking the whole
            // screen on an optional caption would be the wrong trade.
            editHistory: snapshot.data ?? TransactionEditHistory.none,
            instruments: instruments,
            rejectedFields: _rejectedFields,
            amountWasNegative: _amountWasNegative,
            onEdit: (TransactionEditDraft draft) => _edit(editing, draft),
          ),
    );
  }

  Future<TransactionEditHistory> _loadEditHistory(int transactionId) async {
    final UnlockedDatabaseSession? session = await ref.read(
      unlockedDatabaseSessionProvider.future,
    );
    if (session == null) {
      return TransactionEditHistory.none;
    }
    final List<AuditEntryRow> entries = await session.auditLogDao.queryFor(
      'transaction',
      '$transactionId',
    );
    return TransactionEditHistory.fromAuditEntries(
      entries,
      session.auditLogDao,
    );
  }

  Future<void> _add(ManualTransactionDraft draft) async {
    final ManualEntryService? service = await ref.read(
      manualEntryServiceProvider.future,
    );
    if (service == null || !mounted) {
      return;
    }
    final ManualEntryResult result = await service.add(draft);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ManualEntryAccepted(:final int transactionId):
        Navigator.of(context).pop();
        // Straight to the new transaction, which is where its category can be
        // set — the same landing the unparsed-completion flow uses, for the
        // same reason (S-20 has no category picker of its own, and adding a
        // second one with different behaviour is the two-surfaces-disagreeing
        // shape KHA-101 was filed for).
        await openTransactionDetail(context, transactionId);
      case ManualEntryRejected(
        :final List<String> missingFields,
        :final AmountProblem? amountProblem,
      ):
        setState(() {
          _rejectedFields = missingFields;
          _amountWasNegative = amountProblem == AmountProblem.negative;
        });
    }
  }

  Future<void> _edit(int transactionId, TransactionEditDraft draft) async {
    final TransactionEditService? service = await ref.read(
      transactionEditServiceProvider.future,
    );
    if (service == null || !mounted) {
      return;
    }
    final TransactionEditResult result = await service.edit(
      transactionId,
      draft,
    );
    if (!mounted) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (result) {
      case TransactionEditApplied(:final List<String> changedFields):
        Navigator.of(context).pop();
        showScopedSnackBar(
          context: context,
          message: changedFields.isEmpty
              // A no-op Save writes no audit entry, and saying "updated" for a
              // change that did not happen would put a claim in the user's head
              // that the change history will not corroborate.
              ? l10n.txnEditNoChanges
              : l10n.txnEditSavedConfirmation,
        );
      case TransactionEditRejected(
        :final List<String> invalidFields,
        :final AmountProblemOnEdit? amountProblem,
      ):
        setState(() {
          _rejectedFields = invalidFields;
          _amountWasNegative = amountProblem == AmountProblemOnEdit.negative;
        });
      case TransactionEditTargetMissing():
        Navigator.of(context).pop();
        showScopedSnackBar(
          context: context,
          message: l10n.txnEditTargetMissing,
        );
    }
  }
}

/// **S-05 — Historical Import Progress** (AC-A3.2).
///
/// Constructed by `onboarding_gate.dart` on first run, and reachable nowhere
/// else on purpose: an import that is already running in the background does
/// not need a screen, it needs to not be in the way (NFR-R2). The "continue in
/// the background" action is the requirement, not the decoration.
class ImportProgressHost extends ConsumerWidget {
  final VoidCallback onContinueInBackground;

  const ImportProgressHost({required this.onContinueInBackground, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ImportProgress progress =
        ref.watch(importProgressProvider).value ?? ImportProgress.idle;
    final LedgerView ledger =
        ref.watch(ledgerViewProvider).value ?? LedgerView.empty;

    // "Transactions found" counts what the import has actually produced, which
    // is the number the mockup shows and the one the user cares about — not the
    // message count, most of which are not transactions at all. Bounded by the
    // import's own lower date bound (AC-A3.1) so a resumed import does not
    // claim credit for rows that were already there.
    final DateTime? from = progress.fromDateUtc;
    final int found = from == null
        ? 0
        : ledger.transactions
              .where(
                (LedgerTransaction txn) =>
                    txn.occurredAt != null && !txn.occurredAt!.isBefore(from),
              )
              .length;

    return ImportProgressScreen(
      processed: progress.processed,
      total: progress.totalCandidates,
      transactionsFound: found,
      onContinueInBackground: onContinueInBackground,
    );
  }
}
