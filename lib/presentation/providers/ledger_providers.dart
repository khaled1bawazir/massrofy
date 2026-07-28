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
import '../../features/ledger/bank_directory.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/ledger_entity_resolver.dart';
import '../../features/ledger/ledger_mapping.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/period_totals.dart';
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
