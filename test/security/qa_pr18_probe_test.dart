/// QA probe suite for PR #18 (P3b-1). **Not part of the PR's own claims** —
/// this file exists so QA verifies the sign-convention and combined-totals
/// claims independently rather than reading the engineer's doc comments.
///
/// Each test states what it is probing and what the PR body asserts, so a
/// failure here is legible as "the claim is wider than the code".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../support/ledger_fixtures.dart';
import '../support/plain_test_database.dart';

final List<int> _chainKey = List<int>.generate(32, (int i) => i);

void main() {
  // -------------------------------------------------------------------
  // PROBE A — the sign convention at the DAO write boundary
  // -------------------------------------------------------------------
  group('PROBE A — is a negative amount really unstorable?', () {
    late AppDatabase db;
    late TransactionDao dao;
    late AuditLogDao auditLogDao;

    setUp(() {
      db = openPlainTestDatabase();
      auditLogDao = AuditLogDao(db, auditChainKey: _chainKey);
      dao = TransactionDao(db, auditLogDao);
    });

    tearDown(() async => db.close());

    test('insertFromParsedSms rejects a negative magnitude', () async {
      // The PR claims the DAO refuses a negative magnitude at the write
      // boundary. Verified directly on the SMS path.
      //
      // Note the guard throws *synchronously*, before the returned Future is
      // created, so this must be `expect(() => ..., throwsA)` and not
      // `expectLater(future, ...)`. A caller using `.catchError` on the
      // Future would NOT catch it.
      expect(
        () => dao.insertFromParsedSms(
          amount: Money.parse('-50.00', currency: 'SAR'),
          direction: 'debit',
          transactionType: 'pos_purchase',
          occurredAt: DateTime.utc(2026, 7, 20),
          timeSource: 'sms_stated',
          affectsSpend: true,
          sourceMessageId: 1,
          rulePackId: 'sa-core',
          rulePackVersion: '1',
          ruleId: 'probe',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await dao.all(), isEmpty);
    });

    test('insertManualCompletion rejects a negative magnitude', () async {
      expect(
        () => dao.insertManualCompletion(
          amount: Money.parse('-50.00', currency: 'SAR'),
          direction: 'debit',
          transactionType: 'account_debit',
          occurredAt: DateTime.utc(2026, 7, 20),
          affectsSpend: true,
          sourceMessageId: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await dao.all(), isEmpty);
    });

    test('**GAP**: TransactionDao.create() still stores a negative amount, '
        'with a valid audit entry — the invariant is NOT enforced at every '
        'write boundary', () async {
      // The PR body says "There is no negative number anywhere in the
      // transaction table" and "TransactionDao refuses a negative magnitude
      // at the write boundary". `create()` is a third public write path on
      // the same DAO and it carries no `checkMovementAmount` guard.
      final int id = await dao.create(
        amount: Money.parse('-1.500', currency: 'KWD'),
        actor: 'user',
      );
      final TransactionRow row = await dao.byId(id);

      // If this expectation ever fails, the gap has been closed and this
      // probe should be deleted.
      expect(
        row.amountAmount,
        '-1.5',
        reason: 'a negative magnitude reached the transactions table',
      );
      expect(row.amountMinor, -1500);

      // And it is indistinguishable from a legitimate row: the audit entry
      // is well-formed, so nothing downstream can tell it apart.
      expect(
        await auditLogDao.queryFor('transaction', id.toString()),
        isNotEmpty,
      );
    });

    test('a negative row written through create() then inverts a spend '
        'total — the exact O-QA-2 shape, still reachable', () async {
      await dao.create(
        amount: Money.parse('-50.00', currency: 'SAR'),
        actor: 'user',
      );
      // Modelled as the mapper would present it: a debit carrying a negative
      // magnitude. `signedForSpend` applies +1 for a debit, so the stored
      // sign survives into the total.
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        tx(id: 1, amount: '-50.00', at: DateTime.utc(2026, 7, 20)),
      ], period: july2026);
      expect(
        totals.base!.toCanonicalString(),
        '-50',
        reason:
            'a debit of a negative amount still reduces spend — the defect '
            'O-QA-2 described, unreachable via ingestion/completion but '
            'reachable via create()',
      );
    });
  });

  // -------------------------------------------------------------------
  // PROBE B — money-math edge cases the combined test does not cover
  // -------------------------------------------------------------------
  group('PROBE B — refund larger than the original charge', () {
    test('an over-refund produces a negative net spend rather than being '
        'clamped, and the per-currency figure agrees', () {
      // AC-B7.2 covers "nets to zero, or the difference for a partial
      // refund". It does not say what happens when the refund EXCEEDS the
      // charge (a goodwill credit, or a refund of a charge from a prior
      // month). This probes that the arithmetic stays honest.
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(id: 1, amount: '100.00', at: DateTime.utc(2026, 7, 5)),
        tx(
          id: 2,
          amount: '250.00',
          direction: 'credit',
          type: TransactionType.refund,
          at: DateTime.utc(2026, 7, 6),
        ),
      ], period: july2026);
      expect(report.spend.base!.toCanonicalString(), '-150');
      expect(report.spend.forCurrency('SAR')!.toCanonicalString(), '-150');
      // And "kept" reads as a gain rather than a negative spend.
      expect(report.netKept!.toCanonicalString(), '150');
    });

    test('a foreign over-refund converts on its OWN rate before netting, '
        'not on the original purchase rate', () {
      // 100 USD purchase at the bank's stated 450.12 SAR, refunded in full
      // plus a 20 USD goodwill credit at a DIFFERENT stated rate 3.60.
      //   +450.12 − 450.12 − (20 × 3.60 = 72.00) = −72.00
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '120.00',
          currency: 'USD',
          convertedAmount: '450.12',
          fxRateSource: 'sms_implied',
          at: DateTime.utc(2026, 7, 5),
        ),
        tx(
          id: 2,
          amount: '120.00',
          currency: 'USD',
          direction: 'credit',
          type: TransactionType.refund,
          convertedAmount: '450.12',
          fxRateSource: 'sms_implied',
          at: DateTime.utc(2026, 7, 6),
        ),
        tx(
          id: 3,
          amount: '20.00',
          currency: 'USD',
          direction: 'credit',
          type: TransactionType.refund,
          fxRate: '3.6000',
          fxRateSource: 'sms_stated',
          at: DateTime.utc(2026, 7, 7),
        ),
      ], period: july2026);
      expect(report.spend.base!.toCanonicalString(), '-72');
    });
  });

  // -------------------------------------------------------------------
  // PROBE C — internal-transfer detector edge cases
  // -------------------------------------------------------------------
  group('PROBE C — internal transfers the detector may not see', () {
    final LedgerInstrument current = instrument(id: 1);
    final LedgerInstrument savings = instrument(id: 2, masked: '****1157');

    test('a transfer whose incoming leg has NO resolved instrument is not '
        'paired, so the outgoing leg counts as spend', () {
      // Risk R-7 / the bootstrapping problem. Documented behaviour: the
      // detector requires both legs on known instruments. This pins that a
      // half-resolved pair over-states rather than under-states spend.
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          reference: 'TRX-1',
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          reference: 'TRX-1',
          // No instrument — the message did not carry enough digits.
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
      ], period: july2026);
      expect(
        report.spend.base!.toCanonicalString(),
        '2000',
        reason: 'unpaired: over-stated, which is the documented safe bias',
      );
      // But it is NOT flagged for review, so the user is never told this
      // figure may include a transfer to themselves.
      expect(
        report.needsReviewCount,
        0,
        reason:
            'PROBE FINDING: an unpaired half-resolved transfer is silently '
            'counted as spend with no review flag (AC-B11.2 says an '
            'undeterminable transfer is flagged, not classified)',
      );
    });

    test('**GAP**: a month-boundary internal transfer is counted as spend '
        'when the caller passes only the period slice', () {
      // The outgoing leg posts 31 July 23:50; the credit lands 1 August
      // 00:10 (a real cross-bank pattern the 24h window is designed for).
      // A caller that filters to July BEFORE calling report() loses the
      // partner and counts 2,000 of spending that never left the user.
      final List<LedgerTransaction> whole = <LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          reference: 'TRX-EOM',
          on: current,
          at: DateTime.utc(2026, 7, 31, 23, 50),
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          reference: 'TRX-EOM',
          on: savings,
          at: DateTime.utc(2026, 8, 1, 0, 10),
        ),
      ];

      // Correct usage: pass the WHOLE ledger, let report() filter by period.
      final PeriodReport whole1 = LedgerTotals.report(whole, period: july2026);
      expect(
        whole1.spend.isEmpty,
        isTrue,
        reason: 'passed the whole ledger, the pair is seen and excluded',
      );

      // The trap: a caller that period-filters first.
      final List<LedgerTransaction> julyOnly = <LedgerTransaction>[
        for (final LedgerTransaction t in whole)
          if (july2026.contains(t.occurredAt)) t,
      ];
      final PeriodReport sliced = LedgerTotals.report(
        julyOnly,
        period: july2026,
      );
      expect(
        sliced.spend.base!.toCanonicalString(),
        '2000',
        reason:
            'PROBE FINDING: the same ledger yields two different July totals '
            'depending on whether the caller pre-filtered. Nothing in the '
            'signature prevents it and no test covers the month boundary.',
      );
    });

    test('a cross-currency internal transfer is deliberately not paired and '
        'counts as spend, unflagged', () {
      // Documented in internal_transfer.dart: pairing them needs a rate.
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          reference: 'TRX-FX',
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '533.19',
          currency: 'USD',
          direction: 'credit',
          type: TransactionType.transferIn,
          reference: 'TRX-FX',
          on: savings,
          at: DateTime.utc(2026, 7, 10, 9, 5),
        ),
      ], period: july2026);
      expect(report.spend.base!.toCanonicalString(), '2000');
      expect(
        report.needsReviewCount,
        0,
        reason:
            'PROBE FINDING: internal_transfer.dart says these "stay visible '
            'as spend AND as a review item"; the review item does not exist',
      );
    });

    test('an unproven candidate inflates INCOME as well as spend, and the '
        'income figure carries no flag of its own', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          on: savings,
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
      ], period: july2026);
      // Candidate: both legs still counted.
      expect(report.spend.base!.toCanonicalString(), '2000');
      expect(report.income.base!.toCanonicalString(), '2000');
      // netKept is invariant, which is the saving grace.
      expect(report.netKept!.toCanonicalString(), '0');
      expect(report.needsReviewCount, 2);
    });
  });

  // -------------------------------------------------------------------
  // PROBE D — does the slicing test prove what it claims?
  // -------------------------------------------------------------------
  group('PROBE D — strength of the per-instrument exclusion assertion', () {
    test('within one instrument, one transfer_out is excluded (paired) and '
        'another is counted (unpaired) — so the exclusion cannot be coming '
        'from the transaction TYPE alone', () {
      final LedgerInstrument current = instrument(id: 1);
      final LedgerInstrument savings = instrument(id: 2, masked: '****1157');
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          reference: 'R1',
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          reference: 'R1',
          on: savings,
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
        tx(
          id: 3,
          amount: '800.00',
          type: TransactionType.transferOut,
          reference: 'R2',
          on: current,
          at: DateTime.utc(2026, 7, 12, 11),
        ),
      ];
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(rows);

      // Both rows 1 and 3 are transfer_out on the same instrument with
      // affectsSpend = true. Only row 1 is excluded.
      expect(analysis.stateFor(rows[0]), InternalTransferState.internal);
      expect(analysis.stateFor(rows[2]), isNull);

      final PeriodTotals sliced = LedgerTotals.spend(
        <LedgerTransaction>[rows[0], rows[2]],
        period: july2026,
        transfers: analysis, // whole-ledger analysis handed down
      );
      expect(sliced.base!.toCanonicalString(), '800');
    });
  });
}
