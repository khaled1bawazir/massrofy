/// **KHA-78 — internal-transfer candidates reach the review inbox and can be
/// confirmed or rejected.** AC-B11.2, US-B11, risk R-7.
///
/// ---
///
/// KHA-78's done check, which this file follows line by line:
///
/// > *"A candidate pair appears in the review inbox; confirming it writes
/// > `internal` to both legs plus an audit entry; the period total drops by the
/// > outgoing leg's converted amount; re-running the detector does not overturn
/// > the user's decision; rejecting it marks `external` and the pair stops
/// > being proposed."*
///
/// The fourth clause is the one that matters most and is easiest to satisfy by
/// accident. `InternalTransferAnalysis.stateFor` already gave a persisted value
/// precedence over a derived one — but "already gives" is a claim, and the
/// whole point of R-7 is that resolving the flag must *teach* the app. The
/// durability group below re-runs the detector over the written state and
/// checks the decision survives.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/internal_transfer_decision.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/providers/ledger_providers.dart';

import '../../support/ledger_fixtures.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 51);

void main() {
  final LedgerInstrument current = instrument(id: 1);
  final LedgerInstrument savings = instrument(id: 2, masked: '****1157');

  /// A pair with matching amount and time but **no** shared reference number:
  /// the detector's `amountAndTime` evidence, which yields a *candidate*
  /// rather than a determination.
  List<LedgerTransaction> candidatePair({String? outState, String? inState}) =>
      <LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
          transferState: outState,
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          on: savings,
          at: DateTime.utc(2026, 7, 10, 9, 3),
          transferState: inState,
        ),
      ];

  group('the candidate reaches the review inbox (the KHA-78 gap)', () {
    test('a derived candidate produces exactly ONE review item for the pair, '
        'carrying both leg ids', () {
      final List<TransferReviewItem> items = buildTransferReviewItems(
        candidatePair(),
      );

      expect(items, hasLength(1));
      // One movement, one decision. Two cards would let the user confirm one
      // side and reject the other.
      final TransferReviewItem item = items.single;
      expect(item.transactionId, 1);
      expect(item.counterpartTransactionId, 2);
      expect(item.groupId, 'itl:1:2');
      expect(item.isPair, isTrue);
      // The outgoing leg carries the card: it is the one inflating the spend
      // figure the user is looking at.
      expect(item.amount, '2000');
    });

    test('a PROVEN internal transfer produces no review item — it is already '
        'excluded and there is nothing to ask', () {
      final List<TransferReviewItem> items =
          buildTransferReviewItems(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '2000.00',
              type: TransactionType.transferOut,
              reference: 'TRX-9',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '2000.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'TRX-9',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9, 3),
            ),
          ]);
      expect(items, isEmpty);
    });

    test('an unpairable transfer produces a SINGLE-leg item with its reason '
        '(KHA-80)', () {
      final List<TransferReviewItem> items =
          buildTransferReviewItems(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '2000.00',
              type: TransactionType.transferOut,
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '533.19',
              currency: 'USD',
              direction: 'credit',
              type: TransactionType.transferIn,
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9, 3),
            ),
          ]);

      expect(items, hasLength(2));
      expect(items.first.isPair, isFalse);
      expect(
        items.first.unpairableReasonKey,
        TransferReviewReasonKey.crossCurrency,
      );
    });

    test('a pair the user has already ruled on is ABSENT from the inbox', () {
      expect(
        buildTransferReviewItems(
          candidatePair(
            outState: InternalTransferState.internal,
            inState: InternalTransferState.internal,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('confirm and reject, against a real database', () {
    late AppDatabase db;
    late AuditLogDao auditLogDao;
    late TransactionDao dao;
    late InternalTransferDecisionService decisions;
    late InstrumentDao instrumentDao;
    late int outId;
    late int inId;

    setUp(() async {
      db = openPlainTestDatabase();
      auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
      dao = TransactionDao(db, auditLogDao);
      decisions = InternalTransferDecisionService(transactionDao: dao);

      final BankDao bankDao = BankDao(db, auditLogDao);
      instrumentDao = InstrumentDao(db, auditLogDao);
      final int bankId = await bankDao.ensure(
        canonicalKey: 'bank-aljazira',
        displayNameAr: 'بنك الجزيرة',
        displayNameEn: 'Bank Aljazira',
      );
      final int currentId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****3388',
        refKey: 'bank-aljazira:account:3388',
      );
      final int savingsId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****1157',
        refKey: 'bank-aljazira:account:1157',
      );

      outId = await dao.insertFromParsedSms(
        amount: Money.parse('2000.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 10, 9),
        direction: 'debit',
        transactionType: TransactionType.transferOut,
        affectsSpend: true,
        instrumentId: currentId,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-transfer-out',
      );
      inId = await dao.insertFromParsedSms(
        amount: Money.parse('2000.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 10, 9, 3),
        direction: 'credit',
        transactionType: TransactionType.transferIn,
        affectsSpend: false,
        instrumentId: savingsId,
        sourceMessageId: 2,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-transfer-in',
      );
    });

    tearDown(() async => db.close());

    InternalTransferLink link() => InternalTransferLink(
      groupId: InternalTransferDetector.groupIdFor(
        outTransactionId: outId,
        inTransactionId: inId,
      ),
      outTransactionId: outId,
      inTransactionId: inId,
      evidence: InternalTransferEvidence.amountAndTime,
    );

    /// The ledger as a screen sees it — **with instruments resolved**.
    ///
    /// Passing `instrumentsById` is not optional decoration here. The detector
    /// requires both legs to have landed on a *known* instrument before it
    /// will pair them at all, so a helper that omitted the map would leave
    /// every `instrument` null, no pair would ever be derived, and half the
    /// assertions in this group would pass vacuously — "no candidate in the
    /// inbox" would be true because there was never a candidate, not because
    /// the user's decision removed one.
    Future<List<LedgerTransaction>> ledger() async {
      final Map<int, LedgerInstrument> byId = <int, LedgerInstrument>{
        for (final InstrumentRow row in await instrumentDao.all())
          row.id: toLedgerInstrument(row),
      };
      return toLedgerTransactions(await dao.all(), instrumentsById: byId);
    }

    test(
      'confirming writes `internal` to BOTH legs, with the group id',
      () async {
        await decisions.decidePair(
          link(),
          InternalTransferVerdict.confirmedInternal,
        );

        for (final int id in <int>[outId, inId]) {
          final TransactionRow row = await dao.byId(id);
          expect(row.internalTransferState, InternalTransferState.internal);
          expect(row.internalTransferGroupId, link().groupId);
        }
      },
    );

    test('confirming moves the pair OUT of spend on the next total', () async {
      expect(
        LedgerTotals.report(
          await ledger(),
          period: july2026,
        ).spend.base!.toCanonicalString(),
        '2000',
        reason:
            'a candidate keeps counting until confirmed (architecture '
            '§4.2)',
      );

      await decisions.decidePair(
        link(),
        InternalTransferVerdict.confirmedInternal,
      );

      final PeriodReport after = LedgerTotals.report(
        await ledger(),
        period: july2026,
      );
      expect(after.spend.isEmpty, isTrue);
      // And the exclusion is auditable rather than a silent gap (NFR-A6):
      // only the outgoing leg, because one movement is one figure.
      expect(after.internalTransfers.base!.toCanonicalString(), '2000');
      expect(after.needsReviewCount, 0);
    });

    test('confirming writes an audit entry per leg, in the same database '
        'transaction as the state (NFR-A2)', () async {
      await decisions.decidePair(
        link(),
        InternalTransferVerdict.confirmedInternal,
      );

      for (final int id in <int>[outId, inId]) {
        final List<AuditEntryRow> entries = await auditLogDao.queryFor(
          'transaction',
          id.toString(),
        );
        expect(entries.last.action, 'update');
        expect(entries.last.actor, 'user');
        expect(entries.last.actorDetail, 'internal_transfer_confirmedInternal');
      }
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('rejecting writes `external` and does NOT invent a group id — the '
        'rows are not a pair, and saying they are would assert what the user '
        'just denied', () async {
      await decisions.decidePair(
        link(),
        InternalTransferVerdict.rejectedExternal,
      );

      for (final int id in <int>[outId, inId]) {
        final TransactionRow row = await dao.byId(id);
        expect(row.internalTransferState, InternalTransferState.external);
        expect(row.internalTransferGroupId, isNull);
      }
    });

    test('rejecting leaves the money in spend and clears the flag', () async {
      await decisions.decidePair(
        link(),
        InternalTransferVerdict.rejectedExternal,
      );

      final PeriodReport report = LedgerTotals.report(
        await ledger(),
        period: july2026,
      );
      expect(report.spend.base!.toCanonicalString(), '2000');
      expect(report.needsReviewCount, 0);
    });

    test('dismissUnpairable marks a lone transfer external — the only verdict '
        'offered without a partner', () async {
      await decisions.dismissUnpairable(outId);

      final TransactionRow row = await dao.byId(outId);
      expect(row.internalTransferState, InternalTransferState.external);
      expect(row.internalTransferGroupId, isNull);
      expect(
        (await auditLogDao.queryFor(
          'transaction',
          outId.toString(),
        )).last.actorDetail,
        'internal_transfer_unpairable_dismissed',
      );
    });

    group('R-7 — the decision must SURVIVE re-derivation', () {
      test(
        're-running the detector does not overturn a confirmation',
        () async {
          await decisions.decidePair(
            link(),
            InternalTransferVerdict.confirmedInternal,
          );

          // The detector would derive `candidate` from this evidence
          // (amount-and-time, no shared reference). The persisted decision must
          // win — `stateFor` gives it precedence, and this is the test that
          // proves that claim rather than restating it.
          final List<LedgerTransaction> rows = await ledger();
          final InternalTransferAnalysis analysis =
              InternalTransferDetector.analyze(rows);
          expect(analysis.stateFor(rows.first), InternalTransferState.internal);
          expect(
            LedgerTotals.report(rows, period: july2026).spend.isEmpty,
            isTrue,
          );
        },
      );

      test('a rejected pair stops being PROPOSED — it disappears from the '
          'review inbox instead of being asked again forever', () async {
        expect(buildTransferReviewItems(await ledger()), hasLength(1));

        await decisions.decidePair(
          link(),
          InternalTransferVerdict.rejectedExternal,
        );

        expect(buildTransferReviewItems(await ledger()), isEmpty);
      });

      test('a confirmed pair also leaves the inbox', () async {
        await decisions.decidePair(
          link(),
          InternalTransferVerdict.confirmedInternal,
        );
        expect(buildTransferReviewItems(await ledger()), isEmpty);
      });
    });
  });
}
