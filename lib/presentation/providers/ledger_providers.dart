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

import '../../core/time/clock.dart';
import '../../data/dao/bank_dao.dart';
import '../../data/dao/instrument_dao.dart';
import '../../data/db/app_database.dart';
import '../../features/categorization/categorization_service.dart';
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
import 'categorization_providers.dart';
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

/// **AC-E1.4's period selector.** Owns "which calendar month am I looking at".
///
/// ## P5a closes the UTC-boundary limitation P3a documented here
///
/// The previous implementation computed month boundaries in UTC and said so:
/// *"a transaction between 00:00 and 03:00 Riyadh time on the first of a month
/// currently falls in the previous month's figure. P5 owns period boundaries
/// properly."* This is P5. Boundaries now come from
/// [RiyadhCalendar.monthWindowUtc], which is the same arithmetic the
/// historical import's AC-A3.1 lookback uses — so "the month the import starts
/// from" and "the month the home screen totals" are the same month by
/// construction rather than by two functions happening to agree.
///
/// ## Why "am I still tracking the current month" is tracked explicitly
///
/// AC-E1.4 asks for two things that pull in opposite directions: on the 1st
/// the total must **reset** to the new month, and the prior month must stay
/// **viewable**. A notifier that recomputed the current month on every resume
/// would satisfy the first and break the second — a user who paged back to
/// June to check something, then took a phone call, would come back to July
/// with no explanation. So the rollover only happens while the user has not
/// navigated ([_followsCurrentMonth]), and paging back pins the period until
/// they page forward again.
class PeriodRangeNotifier extends Notifier<PeriodRange> {
  /// True while the selector is showing "this month" rather than a month the
  /// user chose. Only then may the clock move the period underneath them.
  bool _followsCurrentMonth = true;

  @override
  PeriodRange build() => currentCalendarMonth();

  /// True when the visible period **is** the live current month.
  ///
  /// A pure function of [state], deliberately *not* a read of
  /// [_followsCurrentMonth]. The two answer different questions and conflating
  /// them causes a subtle UI bug: the flag is plain mutable state that Riverpod
  /// does not watch, so a change to it alone would not rebuild the selector,
  /// and the forward arrow could be left enabled on the current month.
  ///
  ///  - *"Is there a month after this one?"* — a fact about the range, and what
  ///    the selector needs.
  ///  - *"Has the user pinned a month?"* — a fact about intent, and what the
  ///    AC-E1.4 rollover needs. That one stays private.
  bool get isCurrentMonth => state.startUtc == currentCalendarMonth().startUtc;

  void setRange(PeriodRange range) {
    _followsCurrentMonth = false;
    state = range;
  }

  /// Moves [delta] calendar months from the visible period (negative = older).
  ///
  /// Landing back on the live current month re-arms the rollover, so paging
  /// June → July does not leave the app permanently pinned to a July that will
  /// be stale on 1 August.
  void shiftMonths(int delta, {DateTime? now}) {
    if (delta == 0) {
      return;
    }
    final (DateTime start, DateTime end) = RiyadhCalendar.monthWindowUtc(
      // Mid-window rather than the boundary instant: `startUtc` is 21:00 on
      // the previous month's last day in UTC, so shifting from it directly
      // would be off by one month. Adding a day lands unambiguously inside the
      // month being shifted from.
      state.startUtc.add(const Duration(days: 1)),
      monthOffset: delta,
    );
    final PeriodRange moved = PeriodRange(
      startUtc: start,
      endUtcExclusive: end,
    );
    _followsCurrentMonth =
        moved.startUtc == currentCalendarMonth(now: now).startUtc;
    state = moved;
  }

  /// Jumps back to the live current month (the period selector's "This month"
  /// affordance) and re-arms the AC-E1.4 rollover.
  void showCurrentMonth({DateTime? now}) {
    _followsCurrentMonth = true;
    state = currentCalendarMonth(now: now);
  }

  /// **AC-E1.4 — "when the user opens the app on the 1st, the current-month
  /// total resets to the new month".**
  ///
  /// Called on every foreground resume (see `app.dart`). A no-op unless the
  /// month has genuinely turned over *and* the user is still tracking the
  /// current month, so it can be called unconditionally and cheaply.
  void refreshIfTrackingCurrentMonth({DateTime? now}) {
    if (!_followsCurrentMonth) {
      return;
    }
    final PeriodRange fresh = currentCalendarMonth(now: now);
    if (fresh.startUtc != state.startUtc) {
      state = fresh;
    }
  }

  /// The Riyadh calendar month containing [now], as UTC instants.
  static PeriodRange currentCalendarMonth({DateTime? now}) {
    final (DateTime start, DateTime end) = RiyadhCalendar.monthWindowUtc(
      (now ?? DateTime.now()).toUtc(),
    );
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

/// **S-10 / S-23 / S-24 — the live ledger, mapped once for every screen that
/// lists transactions** (KHA-36).
///
/// ## Why one provider rather than one per screen
///
/// Three P5a surfaces need "the transactions, newest first, each with its
/// internal-transfer verdict": the transaction list, the instrument detail
/// page, and the home screen's recent-activity preview. Giving each its own
/// stream would give each its own chance to slice the ledger *before* running
/// `InternalTransferDetector` — and the detector is only correct over the
/// **whole** set, because the two legs of a transfer live on two different
/// instruments (see `bank_tree.dart`'s note on the same trap). Running it here,
/// once, over everything, means a screen physically cannot get that wrong: it
/// receives a verdict, never the responsibility for computing one.
///
/// Nothing is cached (NFR-A6): every emission is recomputed from the rows in
/// that same emission.
final StreamProvider<LedgerView> ledgerViewProvider =
    StreamProvider<LedgerView>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        // Locked: ADR-005 makes the lock cryptographic, so "nothing" is the
        // truthful value rather than a placeholder.
        yield LedgerView.empty;
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

        // KHA-74: rows this build cannot read are reported, never dropped
        // silently into a shorter list the user has no way to notice.
        final LedgerMappingOutcome outcome = mapLedgerTransactions(
          rows,
          instrumentsById: byId,
        );
        final InternalTransferAnalysis analysis =
            InternalTransferDetector.analyze(outcome.transactions);

        // Newest first — the order every list in the mockups uses. Sorted here
        // rather than in SQL so an undated row (`occurredAt == null`, a real
        // case: a message can state no time) has one defined position instead
        // of whatever the database's NULL ordering happens to be. Undated rows
        // sort last: they are the least likely to be what the user opened the
        // list to find.
        final List<LedgerTransaction> ordered =
            List<LedgerTransaction>.of(outcome.transactions)
              ..sort((LedgerTransaction a, LedgerTransaction b) {
                final DateTime? left = a.occurredAt;
                final DateTime? right = b.occurredAt;
                if (left == null && right == null) {
                  return b.id.compareTo(a.id);
                }
                if (left == null) {
                  return 1;
                }
                if (right == null) {
                  return -1;
                }
                final int byTime = right.compareTo(left);
                // Ties broken by id so the order is stable across rebuilds; a
                // list that reshuffles between frames reads as data changing.
                return byTime != 0 ? byTime : b.id.compareTo(a.id);
              });

        yield LedgerView(
          transactions: ordered,
          internalTransferStates: <int, String>{
            for (final LedgerTransaction txn in outcome.transactions)
              if (analysis.stateFor(txn) != null)
                txn.id: analysis.stateFor(txn)!,
          },
          unreadable: outcome.unreadable,
        );
      }
    });

/// What every P5a list screen renders.
final class LedgerView {
  /// Live (non-deleted) transactions, newest first, across **all** periods.
  /// Screens filter by [PeriodRange]; the unfiltered set is what makes the
  /// internal-transfer analysis below correct.
  final List<LedgerTransaction> transactions;

  /// Transaction id → `internal` | `candidate` | `external`, computed over the
  /// whole set. Absent means "the detector had nothing to say".
  final Map<int, String> internalTransferStates;

  /// KHA-74's data-problem rows — surfaced by the review inbox, and counted
  /// here so a list screen can say the ledger is incomplete rather than
  /// quietly showing fewer rows than exist.
  final List<UnreadableTransaction> unreadable;

  const LedgerView({
    required this.transactions,
    required this.internalTransferStates,
    required this.unreadable,
  });

  static const LedgerView empty = LedgerView(
    transactions: <LedgerTransaction>[],
    internalTransferStates: <int, String>{},
    unreadable: <UnreadableTransaction>[],
  );

  /// This view's transactions that fall inside [period], order preserved.
  ///
  /// Uses [PeriodRange.contains], which is the **same** predicate
  /// `LedgerTotals` uses to decide what goes into a figure — so "the rows on
  /// screen" and "the rows behind the total above them" are the same set by
  /// construction, which is what NFR-A6 actually asks for. An undated row is
  /// excluded from both, together.
  List<LedgerTransaction> inPeriod(PeriodRange period) => <LedgerTransaction>[
    for (final LedgerTransaction txn in transactions)
      if (period.contains(txn.occurredAt)) txn,
  ];

  /// Only [instrumentId]'s transactions — AC-B2.3's *"only that instrument's
  /// transactions are listed"*, as a filter over the same list every other
  /// screen reads.
  List<LedgerTransaction> forInstrument(int instrumentId) =>
      <LedgerTransaction>[
        for (final LedgerTransaction txn in transactions)
          if (txn.instrument?.id == instrumentId) txn,
      ];
}

/// **AC-B1.2 — the sanitised body of the SMS a transaction came from**, so the
/// user can check every parsed number against the sentence it came from
/// (P5a, KHA-114's neighbouring gap).
///
/// Null for a manual entry, for a transaction whose source message has been
/// erased, and while the app is locked. All three are the same answer to the
/// screen — *"there is no original text"* — and S-11 says so rather than
/// rendering an empty box.
///
/// A `family` keyed on the transaction id rather than a field on
/// [ledgerViewProvider]: raw message bodies are the most sensitive thing this
/// app stores, and loading every one of them into memory to render a list would
/// be the opposite of the "one deliberate tap away" treatment design.md §5
/// gives the panel. Auto-disposed when the detail screen closes.
// ignore: always_specify_types — the family's generated type name is an
// implementation detail of Riverpod's codegen-free API and is not meant to be
// written out by hand; `final` keeps this readable and still fully typed.
final originalMessageTextProvider = FutureProvider.family<String?, int>((
  Ref ref,
  int transactionId,
) async {
  final UnlockedDatabaseSession? session = await ref.watch(
    unlockedDatabaseSessionProvider.future,
  );
  if (session == null) {
    return null;
  }
  final TransactionRow? row = await session.transactionDao.byIdOrNull(
    transactionId,
  );
  final int? messageId = row?.sourceMessageId;
  if (messageId == null) {
    return null; // A manual entry. There is no original text to show.
  }
  final RawMessageRow? message = await session.rawMessageDao.byId(messageId);
  // The stored body is already redacted at the ingestion boundary
  // (ADR-013), so what reaches the screen has no PAN in it to leak into a
  // screenshot or an accessibility tree.
  return message?.sanitizedBody;
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
///
/// ## The `learnCategoryRule` binding (KHA-101)
///
/// This is the composition root for the seam described on [LearnCategoryRule]:
/// `features/ledger` may not import `features/categorization` (the arrow
/// already runs the other way, via `category_breakdown.dart`), so the two are
/// joined *here*, in the presentation layer that already depends on both. It is
/// the same technique `categorization_providers.dart` uses to bind the
/// categorizer into `IngestionPipeline`.
///
/// The effect: correcting a category from the transaction detail form now
/// teaches the same `merchant → category` rule that correcting it from the
/// categorization surface does. Without this line the edit form would keep the
/// half of KHA-101 that lives above the DAO.
final FutureProvider<TransactionEditService?> transactionEditServiceProvider =
    FutureProvider<TransactionEditService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        return null;
      }
      // Null while locked. Also null if the categorization service failed to
      // build — and **that fallback is the point of the `?` on the seam**:
      // learning a rule is an enhancement to an edit, so a categorization
      // failure must degrade the edit form to "correct this one transaction"
      // rather than make US-B5 unavailable. Editing money is the more
      // important of the two capabilities and it must not depend on the less
      // important one.
      CategorizationService? categorization;
      try {
        categorization = await ref.watch(categorizationServiceProvider.future);
      } on Object {
        // Deliberately swallowed and not logged: the failure is already
        // surfaced by `categorizationServiceProvider` itself to anything that
        // watches it directly, and NFR-S4 keeps this layer out of the business
        // of writing diagnostics that could carry a merchant name.
        categorization = null;
      }
      return TransactionEditService(
        database: session.database,
        transactionDao: session.transactionDao,
        learnCategoryRule: categorization?.learnRuleFromCorrection,
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
