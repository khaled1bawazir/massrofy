/// Riverpod wiring for the P3a domain spine (KHA-23, KHA-25, KHA-64).
///
/// ## Why these providers exist at all
///
/// The P1 review made a point this file takes seriously: *a component with no
/// production call site is library code, not shipped behaviour*. The bank
/// tree, the entity resolver and the completion service are all reachable
/// from the running app through the providers below — the resolver in
/// particular is injected into the ingestion pipeline here, which is what
/// makes auto-creation on first mention (US-B15) a thing the app does rather
/// than a thing the tests do.
///
/// ## Everything hangs off the unlocked session
///
/// Every provider here starts from `unlockedDatabaseSessionProvider` and
/// yields an empty/None value while the app is locked. That is not a
/// placeholder: ADR-005 makes the lock cryptographic, so while locked there
/// is no database to read and the honest value is "nothing", not a stale
/// cache of the last unlocked state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/bank_dao.dart';
import '../../data/dao/instrument_dao.dart';
import '../../data/db/app_database.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/bank_directory.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/internal_transfer.dart';
import '../../features/ledger/internal_transfer_decision.dart';
import '../../features/ledger/ledger_entity_resolver.dart';
import '../../features/ledger/ledger_mapping.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/manual_entry.dart';
import '../../features/ledger/period_totals.dart';
import '../../features/ledger/transaction_edit.dart';
import '../../features/ledger/transaction_merge.dart';
import '../../features/ledger/unparsed_completion.dart';
import '../../features/parsing/rule_pack.dart';
import 'app_providers.dart';
import 'ingestion_providers.dart';

/// The active packs' banks, adapted into the ledger's own [BankProfile]
/// shape.
///
/// **This adapter is the module boundary** (architecture §3): `features/
/// ledger` must not import `features/parsing`'s internals, so the conversion
/// from `RulePack` happens here, in the presentation layer, which already
/// depends on both. A rule-schema change stops at this function instead of
/// reaching the ledger.
final FutureProvider<BankDirectory> bankDirectoryProvider =
    FutureProvider<BankDirectory>((Ref ref) async {
      final List<RulePack> packs = await ref.watch(
        activeRulePacksProvider.future,
      );
      return BankDirectory(<BankProfile>[
        for (final RulePack pack in packs)
          for (final BankRule bank in pack.banks)
            BankProfile(
              canonicalKey: bank.bankId,
              displayNameAr: bank.displayNameAr,
              displayNameEn: bank.displayNameEn,
              aliases: bank.aliases,
            ),
      ]);
    });

/// The ledger DAOs for the current unlocked session.
final FutureProvider<LedgerDaos?> ledgerDaosProvider =
    FutureProvider<LedgerDaos?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        return null;
      }
      return LedgerDaos(
        bankDao: BankDao(session.database, session.auditLogDao),
        instrumentDao: InstrumentDao(session.database, session.auditLogDao),
      );
    });

/// Bundles the two P3a DAOs, mirroring [UnlockedDatabaseSession]'s shape.
class LedgerDaos {
  final BankDao bankDao;
  final InstrumentDao instrumentDao;

  const LedgerDaos({required this.bankDao, required this.instrumentDao});
}

/// The resolver the ingestion pipeline uses to auto-create banks and
/// instruments on first mention (US-B15, AC-B15.1).
final FutureProvider<LedgerEntityResolver?> ledgerEntityResolverProvider =
    FutureProvider<LedgerEntityResolver?>((Ref ref) async {
      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);
      if (daos == null) {
        return null;
      }
      return LedgerEntityResolver(
        bankDao: daos.bankDao,
        instrumentDao: daos.instrumentDao,
        directory: await ref.watch(bankDirectoryProvider.future),
      );
    });

/// The period the ledger screens are showing.
///
/// Defaults to the current calendar month, which is the period the whole
/// product is organised around (AC-A3.1's import lookback, US-G1's budgets,
/// the home screen's headline figure). A `NotifierProvider` so the period
/// selector in P5 can drive it without this file changing.
final NotifierProvider<PeriodRangeNotifier, PeriodRange> ledgerPeriodProvider =
    NotifierProvider<PeriodRangeNotifier, PeriodRange>(PeriodRangeNotifier.new);

class PeriodRangeNotifier extends Notifier<PeriodRange> {
  @override
  PeriodRange build() => currentCalendarMonth();

  void setRange(PeriodRange range) => state = range;

  /// The calendar month containing [now], in UTC.
  ///
  /// A known simplification, stated rather than hidden: month boundaries are
  /// computed in UTC, while the product's day boundary is `Asia/Riyadh`
  /// (architecture §7.4). For the +03:00 offset that shifts the boundary by
  /// three hours, so a transaction between 00:00 and 03:00 Riyadh time on the
  /// first of a month currently falls in the previous month's figure. P5 owns
  /// period boundaries properly (it owns the period selector); this is
  /// recorded here so the next person meets a documented limitation rather
  /// than a mystery.
  static PeriodRange currentCalendarMonth({DateTime? now}) {
    final DateTime reference = (now ?? DateTime.now()).toUtc();
    final DateTime start = DateTime.utc(reference.year, reference.month);
    final DateTime end = reference.month == 12
        ? DateTime.utc(reference.year + 1)
        : DateTime.utc(reference.year, reference.month + 1);
    return PeriodRange(startUtc: start, endUtcExclusive: end);
  }
}

/// **S-21/S-22 — the bank tree with its period figures.**
///
/// A stream, so a bank or instrument auto-created by a background sweep shows
/// up without a manual refresh (architecture §7.5). Every figure is computed
/// on the fly from the transactions in the same emission — nothing is cached,
/// per NFR-A6.
final StreamProvider<List<BankTreeNode>> bankTreeProvider =
    StreamProvider<List<BankTreeNode>>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);
      if (session == null || daos == null) {
        yield const <BankTreeNode>[];
        return;
      }

      final PeriodRange period = ref.watch(ledgerPeriodProvider);

      // Three Drift streams, combined on the transaction stream because it is
      // the one that changes most often. Banks and instruments are re-read on
      // each transaction emission — they are a handful of rows, and the
      // alternative (a hand-rolled three-way combine) is a great deal of code
      // for a query that costs microseconds.
      await for (final List<TransactionRow> transactionRows
          in session.transactionDao.watchLive()) {
        final List<LedgerBank> banks = <LedgerBank>[
          for (final BankRow row in await daos.bankDao.all()) toLedgerBank(row),
        ];
        final List<LedgerInstrument> instruments = <LedgerInstrument>[
          for (final InstrumentRow row in await daos.instrumentDao.all())
            toLedgerInstrument(row),
        ];
        final Map<int, LedgerInstrument> byId = <int, LedgerInstrument>{
          for (final LedgerInstrument instrument in instruments)
            instrument.id: instrument,
        };

        yield BankTreeBuilder.build(
          banks: banks,
          instruments: instruments,
          transactions: toLedgerTransactions(
            transactionRows,
            instrumentsById: byId,
          ),
          period: period,
        );
      }
    });

/// **S-32 — the period's spent-vs-kept breakdown (AC-B10.3).**
///
/// Derived from the same `watchLive()` stream the bank tree uses, so the
/// headline figure on Home and the per-bank figures can never come from two
/// different reads of the ledger. NFR-A6 again: one source, one arithmetic.
///
/// The internal-transfer detector is run over the **whole** live set here
/// (`LedgerTotals.report` does it when `transfers` is omitted), which is the
/// only slice in which both legs of a transfer are guaranteed to be visible.
final StreamProvider<PeriodReport> periodReportProvider =
    StreamProvider<PeriodReport>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        // Locked: there is no database to read, and the honest value is "no
        // figures", not a stale cache of the last unlocked state (ADR-005).
        yield PeriodReport.empty;
        return;
      }

      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);
      final PeriodRange period = ref.watch(ledgerPeriodProvider);

      await for (final List<TransactionRow> rows
          in session.transactionDao.watchLive()) {
        final Map<int, LedgerInstrument> byId = <int, LedgerInstrument>{
          if (daos != null)
            for (final InstrumentRow row in await daos.instrumentDao.all())
              row.id: toLedgerInstrument(row),
        };
        yield LedgerTotals.report(
          toLedgerTransactions(rows, instrumentsById: byId),
          period: period,
        );
      }
    });

/// KHA-64's S-19 write path, bound to the unlocked session.
final FutureProvider<UnparsedCompletionService?>
unparsedCompletionServiceProvider = FutureProvider<UnparsedCompletionService?>((
  Ref ref,
) async {
  final UnlockedDatabaseSession? session = await ref.watch(
    unlockedDatabaseSessionProvider.future,
  );
  if (session == null) {
    return null;
  }
  return UnparsedCompletionService(
    database: session.database,
    transactionDao: session.transactionDao,
    rawMessageDao: session.rawMessageDao,
  );
});

// -----------------------------------------------------------------------
// P3b-2 — the mutation surface (KHA-26, KHA-64, KHA-74, KHA-78, KHA-80)
//
// Every service below writes to the ledger, so every one of them is null
// while the app is locked. That is not defensive coding: ADR-005 makes the
// lock cryptographic, so there is genuinely no database to write to, and a
// screen holding a stale service across a lock event would be holding a
// closed connection.
// -----------------------------------------------------------------------

/// **US-B4** — the manual-entry write path (KHA-26).
final FutureProvider<ManualEntryService?> manualEntryServiceProvider =
    FutureProvider<ManualEntryService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      return session == null
          ? null
          : ManualEntryService(transactionDao: session.transactionDao);
    });

/// **US-B5/B6/B8** — edit, soft delete and restore (KHA-26).
final FutureProvider<TransactionEditService?> transactionEditServiceProvider =
    FutureProvider<TransactionEditService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      return session == null
          ? null
          : TransactionEditService(
              database: session.database,
              transactionDao: session.transactionDao,
            );
    });

/// **ADR-017 D2** — the enrichment merge (KHA-64).
///
/// This provider is the *only* place the merge service is constructed in
/// production, which is what keeps risk R-8's "never automatic" property
/// checkable: an automatic merge would need a background caller, and a
/// background caller would need to appear here.
final FutureProvider<TransactionMergeService?> transactionMergeServiceProvider =
    FutureProvider<TransactionMergeService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      return session == null
          ? null
          : TransactionMergeService(
              database: session.database,
              transactionDao: session.transactionDao,
            );
    });

/// **AC-B11.2** — the user's verdict on an internal transfer (KHA-78).
final FutureProvider<InternalTransferDecisionService?>
internalTransferDecisionServiceProvider =
    FutureProvider<InternalTransferDecisionService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      return session == null
          ? null
          : InternalTransferDecisionService(
              transactionDao: session.transactionDao,
            );
    });

/// **S-44 — Recently Deleted** (US-B8), including rows a merge absorbed.
///
/// [RecentlyDeletedView.mergedInto] lets the screen label a merged row as
/// merged rather than as deleted; see `recently_deleted_screen.dart` for why
/// that distinction matters to a user looking for reassurance that nothing was
/// lost.
final StreamProvider<RecentlyDeletedView> recentlyDeletedProvider =
    StreamProvider<RecentlyDeletedView>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield RecentlyDeletedView.empty;
        return;
      }
      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);

      await for (final List<TransactionRow> rows
          in session.transactionDao.watchDeleted()) {
        final Map<int, LedgerInstrument> byId = <int, LedgerInstrument>{
          if (daos != null)
            for (final InstrumentRow row in await daos.instrumentDao.all())
              row.id: toLedgerInstrument(row),
        };
        yield RecentlyDeletedView(
          transactions: toLedgerTransactions(rows, instrumentsById: byId),
          mergedInto: <int, int>{
            for (final TransactionRow row in rows)
              if (row.mergedIntoId != null) row.id: row.mergedIntoId!,
          },
        );
      }
    });

/// What S-44 renders.
class RecentlyDeletedView {
  final List<LedgerTransaction> transactions;

  /// Transaction id → the survivor it was merged into. Absent for rows the
  /// user deleted directly.
  final Map<int, int> mergedInto;

  const RecentlyDeletedView({
    required this.transactions,
    required this.mergedInto,
  });

  static const RecentlyDeletedView empty = RecentlyDeletedView(
    transactions: <LedgerTransaction>[],
    mergedInto: <int, int>{},
  );
}

/// **S-18's transfer tab and data-integrity banner** — AC-B11.2 (KHA-78,
/// KHA-80) and KHA-74.
///
/// ## Why this is derived here rather than read from a column
///
/// The transfer states are **derived at read time** over the whole live set
/// (`internal_transfer.dart` explains why: the two legs routinely arrive hours
/// apart, so a decision taken at ingestion would have to be revisited). The
/// Needs Review inbox previously read only the persisted `needsReview` column,
/// which is exactly why derived candidates never reached it — KHA-78's
/// finding. Running the detector here, over the same stream every total is
/// computed from, is what makes the inbox agree with the figures.
///
/// A transfer with a **persisted** decision is absent from this list, because
/// `InternalTransferAnalysis` suppresses both the derived state and the
/// unpairable reason once the user has ruled. That is the durability KHA-78
/// asks for, observed from the outside.
final StreamProvider<ReviewInboxView> reviewInboxProvider =
    StreamProvider<ReviewInboxView>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield ReviewInboxView.empty;
        return;
      }
      final LedgerDaos? daos = await ref.watch(ledgerDaosProvider.future);

      await for (final List<TransactionRow> rows
          in session.transactionDao.watchLive()) {
        final Map<int, LedgerInstrument> byId = <int, LedgerInstrument>{
          if (daos != null)
            for (final InstrumentRow row in await daos.instrumentDao.all())
              row.id: toLedgerInstrument(row),
        };

        // KHA-74: `mapLedgerTransactions` reports what it could not read
        // instead of dropping it silently.
        final LedgerMappingOutcome outcome = mapLedgerTransactions(
          rows,
          instrumentsById: byId,
        );
        yield ReviewInboxView(
          transfers: buildTransferReviewItems(outcome.transactions),
          unreadable: outcome.unreadable,
        );
      }
    });

/// What S-18 needs beyond the two lists P2 already fed it.
class ReviewInboxView {
  final List<TransferReviewItem> transfers;
  final List<UnreadableTransaction> unreadable;

  const ReviewInboxView({required this.transfers, required this.unreadable});

  static const ReviewInboxView empty = ReviewInboxView(
    transfers: <TransferReviewItem>[],
    unreadable: <UnreadableTransaction>[],
  );
}

/// Turns the detector's output into review-inbox cards.
///
/// Exposed (rather than private) so it can be tested directly over a list of
/// [LedgerTransaction]s with no database at all — the same discipline the rest
/// of `features/ledger` follows.
///
/// A **pair** yields one card, not two: the two legs are one movement and one
/// decision, and offering the same question twice would let a user confirm one
/// side and reject the other. The outgoing leg carries the card because it is
/// the one inflating the spend figure the user is looking at.
List<TransferReviewItem> buildTransferReviewItems(
  List<LedgerTransaction> transactions,
) {
  final InternalTransferAnalysis analysis = InternalTransferDetector.analyze(
    transactions,
  );
  final Map<int, LedgerTransaction> byId = <int, LedgerTransaction>{
    for (final LedgerTransaction txn in transactions) txn.id: txn,
  };

  final List<TransferReviewItem> items = <TransferReviewItem>[];

  // KHA-78 — pairs the detector found but cannot prove.
  for (final InternalTransferLink link in analysis.links) {
    final LedgerTransaction? out = byId[link.outTransactionId];
    if (out == null ||
        analysis.stateFor(out) != InternalTransferState.candidate) {
      continue;
    }
    items.add(
      TransferReviewItem(
        transactionId: link.outTransactionId,
        counterpartTransactionId: link.inTransactionId,
        groupId: link.groupId,
        amount: out.amount.toCanonicalString(),
        currencyCode: out.amount.currencyCode,
        counterpartyName: out.counterpartyName,
        occurredAt: out.occurredAt,
      ),
    );
  }

  // KHA-80 — transfers that could not be paired at all. One card per
  // transaction, since by definition there is no pair to speak for.
  for (final LedgerTransaction txn in transactions) {
    final TransferReviewReason? reason = analysis.unpairableReasonFor(txn);
    if (reason == null) {
      continue;
    }
    items.add(
      TransferReviewItem(
        transactionId: txn.id,
        amount: txn.amount.toCanonicalString(),
        currencyCode: txn.amount.currencyCode,
        counterpartyName: txn.counterpartyName,
        occurredAt: txn.occurredAt,
        unpairableReasonKey: TransferReviewReasonKey.forReason(reason),
      ),
    );
  }

  return items;
}
