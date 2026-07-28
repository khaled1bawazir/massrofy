/// Period totals — AC-B2.3, AC-B7.1, US-B10/B11, ADR-002, ADR-009, NFR-A4.
///
/// Every test here pins an exact decimal string. A loose matcher would let a
/// wrong-but-plausible figure pass green, which for a spending tracker is the
/// only failure that actually matters: a number the user trusts and should
/// not.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';

final PeriodRange july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

LedgerTransaction txn({
  int id = 1,
  required String amount,
  String currency = 'SAR',
  String direction = 'debit',
  bool affectsSpend = true,
  bool isDeleted = false,
  DateTime? occurredAt,
  String type = 'pos_purchase',
  String? feeAmount,
  String feeCurrency = 'SAR',
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: currency),
  direction: direction,
  transactionType: type,
  affectsSpend: affectsSpend,
  isDeleted: isDeleted,
  occurredAt: occurredAt ?? DateTime.utc(2026, 7, 15, 10),
  feeAmount: feeAmount == null
      ? null
      : Money.parse(feeAmount, currency: feeCurrency),
);

void main() {
  group('AC-B2.3 — the total equals the sum of those transactions', () {
    test('three debits sum exactly', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '152.75'),
        txn(id: 2, amount: '49.99'),
        txn(id: 3, amount: '0.01'),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '202.75');
      expect(totals.byCurrency.single.transactionCount, 3);
    });

    test('NFR-A4 — the arithmetic is exact decimal, not floating point', () {
      // The canonical demonstration: 0.1 + 0.2 is 0.30000000000000004 in
      // IEEE-754 and exactly 0.3 here. If Money were ever swapped for a
      // double this test is what fails.
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '0.1'),
        txn(id: 2, amount: '0.2'),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '0.3');
    });
  });

  group('AC-B7.1 — a credit reduces spend, never increases it', () {
    test('a refund subtracts from the period figure', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '200.00'),
        txn(id: 2, amount: '50.00', direction: 'credit', type: 'refund'),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '150');
    });

    test('a month with more refunds than purchases goes negative rather than '
        'being clamped to zero', () {
      // Clamping would hide a real fact from the user. A negative month is
      // unusual, not impossible.
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '20.00'),
        txn(id: 2, amount: '75.50', direction: 'credit', type: 'refund'),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '-55.5');
      expect(totals.forCurrency('SAR')!.isNegative, isTrue);
    });
  });

  group('US-B10/B11 — money movements that are not spending', () {
    test('affectsSpend == false is excluded — a card repayment does not '
        'double-count the purchases it settles', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '100.00'),
        txn(
          id: 2,
          amount: '1500.00',
          type: 'card_repayment',
          affectsSpend: false,
        ),
        txn(
          id: 3,
          amount: '9000.00',
          direction: 'credit',
          type: 'transfer_in',
          affectsSpend: false,
        ),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '100');
      expect(totals.byCurrency.single.transactionCount, 1);
    });
  });

  group('what is excluded, and why', () {
    test('US-B8 — a soft-deleted transaction is in no total', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '100.00'),
        txn(id: 2, amount: '250.00', isDeleted: true),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '100');
    });

    test('a transaction outside the period is excluded', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '100.00'),
        txn(id: 2, amount: '999.00', occurredAt: DateTime.utc(2026, 6, 30, 23)),
      ], period: july2026);

      expect(totals.forCurrency('SAR')!.toCanonicalString(), '100');
    });

    test('the period is half-open, so a transaction at the boundary lands in '
        'exactly one month', () {
      expect(july2026.contains(DateTime.utc(2026, 7)), isTrue);
      expect(july2026.contains(DateTime.utc(2026, 8)), isFalse);
      expect(july2026.contains(DateTime.utc(2026, 7, 31, 23, 59, 59)), isTrue);
    });

    test('an undated transaction is in no bounded period — and is not '
        'silently placed in the current one', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        LedgerTransaction(
          id: 1,
          amount: Money.parse('40.00', currency: 'SAR'),
          direction: 'debit',
          transactionType: 'account_debit',
          affectsSpend: true,
        ),
      ], period: july2026);

      expect(totals.isEmpty, isTrue);
    });
  });

  group('ADR-009 — currencies are never summed together', () {
    test('a SAR total and a USD total are two figures, not one', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '100.00'),
        txn(id: 2, amount: '200.00'),
        txn(id: 3, amount: '49.99', currency: 'USD'),
      ], period: july2026);

      expect(totals.byCurrency.length, 2);
      expect(totals.forCurrency('SAR')!.toCanonicalString(), '300');
      expect(totals.forCurrency('USD')!.toCanonicalString(), '49.99');
    });

    test('the everyday currency leads, and the order is stable', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '10.00', currency: 'USD'),
        txn(id: 2, amount: '10.00'),
        txn(id: 3, amount: '10.00'),
      ], period: july2026);

      expect(totals.byCurrency.first.currencyCode, 'SAR');
    });
  });

  group('empty is not zero', () {
    test('no matching transactions yields an empty total, not 0.00', () {
      // "You spent nothing" and "we have nothing to show you" are different
      // statements, and only one of them is true here.
      final PeriodTotals totals = LedgerTotals.spend(
        const <LedgerTransaction>[],
        period: july2026,
      );
      expect(totals.isEmpty, isTrue);
      expect(totals.forCurrency('SAR'), isNull);
    });
  });

  group('the base-currency figure (KHA-27, AC-B9.2)', () {
    test('a SAR-only period puts the same number in `base` and in the SAR '
        'native line, and reports nothing unconverted', () {
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '152.75'),
        txn(id: 2, amount: '49.99'),
      ], period: july2026);

      expect(totals.base!.toCanonicalString(), '202.74');
      expect(totals.baseCurrencyCode, 'SAR');
      expect(totals.convertedCount, 2);
      expect(totals.isIncomplete, isFalse);
      expect(totals.unconvertedCount, 0);
    });

    test('a period whose only transaction cannot be converted has NO base '
        'figure at all — null, not zero', () {
      // Money.zero would claim the user spent nothing this month. What is
      // true is that we cannot express what they spent in the base currency.
      final PeriodTotals totals = LedgerTotals.spend(<LedgerTransaction>[
        txn(id: 1, amount: '35.00', currency: 'EUR'),
      ], period: july2026);

      expect(totals.base, isNull);
      expect(totals.isEmpty, isFalse, reason: 'there IS a transaction');
      expect(totals.unconvertedCount, 1);
      expect(totals.forCurrency('EUR')!.toCanonicalString(), '35');
    });
  });

  group('PeriodReport — the components of a period (AC-B10.3)', () {
    test('spent-vs-kept is null when neither side has a base figure, rather '
        'than a confident zero', () {
      final PeriodReport report = LedgerTotals.report(
        const <LedgerTransaction>[],
        period: july2026,
      );
      expect(report.netKept, isNull);
      expect(report.spend.isEmpty, isTrue);
    });

    test('spend alone still yields a net — a month with outgoings and no '
        'income is a negative "kept", not an absent one', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        txn(id: 1, amount: '250.00'),
      ], period: july2026);

      expect(report.netKept!.toCanonicalString(), '-250');
    });

    test('income is accumulated as a magnitude, so an income figure never '
        'renders negative', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        txn(
          id: 1,
          amount: '14500.00',
          direction: 'credit',
          type: 'salary_income',
          affectsSpend: false,
        ),
      ], period: july2026);

      expect(report.income.base!.toCanonicalString(), '14500');
      expect(report.income.base!.isNegative, isFalse);
    });
  });

  group('fees are their own figure (PRD 3.4)', () {
    test('a fee is not folded into the spend total', () {
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        txn(id: 1, amount: '49.99', currency: 'USD', feeAmount: '4.69'),
      ];

      expect(
        LedgerTotals.spend(
          rows,
          period: july2026,
        ).forCurrency('USD')!.toCanonicalString(),
        '49.99',
        reason:
            'the fee rides alongside the amount; folding it in would '
            'overstate what the merchant charged',
      );
      expect(
        LedgerTotals.feesFor(
          rows,
          period: july2026,
        ).forCurrency('SAR')!.toCanonicalString(),
        '4.69',
      );
    });

    test('a fee on a NON-spend movement is still counted — "what did FX cost '
        'me this month" is a question about all of them', () {
      final PeriodTotals fees = LedgerTotals.feesFor(<LedgerTransaction>[
        txn(
          id: 1,
          amount: '2000.00',
          type: 'transfer_out',
          affectsSpend: false,
          feeAmount: '15.00',
        ),
      ], period: july2026);

      expect(fees.forCurrency('SAR')!.toCanonicalString(), '15');
    });
  });
}
