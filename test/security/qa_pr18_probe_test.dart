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

    // -------------------------------------------------------------------
    // **CLOSED IN P3b-2 (KHA-79).** These two probes originally documented
    // the gap: `create()` was a third public write path with no
    // `checkMovementAmount` guard, so a negative magnitude reached the
    // transactions table carrying a well-formed audit entry, indistinguishable
    // downstream from a legitimate row.
    //
    // The probes are **kept and inverted rather than deleted**, deliberately.
    // A defect that was found once can be reintroduced, and the cheapest
    // guard against that is the reproduction that found it, still running,
    // now asserting the opposite. Deleting them would leave the fix defended
    // only by tests written by the person who wrote the fix.
    // -------------------------------------------------------------------
    test('CLOSED (KHA-79): TransactionDao.create() now rejects a negative '
        'amount — the invariant holds at every write boundary', () async {
      // Note the assertion form. `checkMovementAmount` throws synchronously,
      // before the Future is constructed, so `expectLater(future, ...)` would
      // not catch it — a trap QA hit while writing the original probe.
      expect(
        () => dao.create(
          amount: Money.parse('-1.500', currency: 'KWD'),
          actor: 'user',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // And the rejection is total: no row, and no audit entry to make a bad
      // row look legitimate.
      expect(await dao.all(), isEmpty);
      expect(await auditLogDao.queryFor('transaction', '1'), isEmpty);
    });

    test('CLOSED (KHA-79): the O-QA-2 sign-inversion shape is no longer '
        'reachable through any DAO write path', () async {
      // Every public write path on this DAO is now guarded. The arithmetic
      // below is what a negative magnitude WOULD do to a total if one ever
      // reached storage — kept as the statement of why the guard matters,
      // constructed as a pure domain value rather than from the database,
      // because the database can no longer produce it.
      final PeriodTotals hypothetical = LedgerTotals.spend(<LedgerTransaction>[
        tx(id: 1, amount: '-50.00', at: DateTime.utc(2026, 7, 20)),
      ], period: july2026);
      expect(
        hypothetical.base!.toCanonicalString(),
        '-50',
        reason:
            'a debit carrying a negative magnitude would still invert spend — '
            'which is precisely why no write path may store one',
      );

      // The reachable half: all three DAO write paths refuse it.
      expect(
        () => dao.create(
          amount: Money.parse('-50.00', currency: 'SAR'),
          actor: 'user',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => dao.insertManual(
          amount: Money.parse('-50.00', currency: 'SAR'),
          occurredAt: DateTime.utc(2026, 7, 20),
          direction: 'debit',
          transactionType: 'pos_purchase',
          affectsSpend: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await dao.all(), isEmpty);
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
      // **CLOSED IN P3b-2 (KHA-80).** The over-statement was always the safe
      // direction to be wrong in, but AC-B11.2 asks for "flagged for review
      // rather than silently classified either way" — and the flag did not
      // exist, so the user was never told the figure might include a transfer
      // to themselves. `InternalTransferDetector`'s near-match pass now
      // raises `TransferReviewReason.unresolvedInstrument` for exactly this
      // shape. Both legs are counted: the outgoing one inflates spend, the
      // incoming one inflates income.
      expect(
        report.needsReviewCount,
        2,
        reason:
            'AC-B11.2: an undeterminable transfer is flagged, not silently '
            'classified. Both legs carry the flag because both figures are '
            'affected.',
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
        'counts as spend — now WITH the review flag it always promised', () {
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
      // Still counted, and still on no invented rate — ADR-009 holds.
      expect(report.spend.base!.toCanonicalString(), '2000');
      // **CLOSED IN P3b-2 (KHA-80).** `internal_transfer.dart` had always
      // claimed in its own doc comment that these "stay visible as spend AND
      // as a review item"; the review item half did not exist. It does now,
      // as `TransferReviewReason.crossCurrencyNearMatch`, on both legs.
      expect(
        report.needsReviewCount,
        2,
        reason:
            'the doc comment\'s promise is now kept: visible as spend AND as '
            'a review item',
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
