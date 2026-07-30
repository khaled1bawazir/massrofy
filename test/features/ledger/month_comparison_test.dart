/// **AC-E4.1 / AC-E4.2 — month over month** (KHA-37, US-E4).
///
/// The interesting half is AC-E4.2, not the subtraction:
///
/// > *"With fewer than two months of data, state that there isn't enough history
/// > rather than showing a misleading comparison."*
///
/// With one month of data the arithmetic still works and every number in it is
/// correct — this month 1,610.50, last month nothing, difference +1,610.50, "up
/// 100%" — while the conclusion is nonsense: the user did not increase their
/// spending infinitely, they installed the app. So the tests below spend most of
/// their effort on **when the comparison is entitled to exist** rather than on the
/// difference itself.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/month_comparison.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

/// A July 2026 purchase.
LedgerTransaction july(int id, String amount, {int day = 15}) =>
    tx(id: id, amount: amount, at: DateTime.utc(2026, 7, day, 12));

/// A June 2026 purchase.
LedgerTransaction june(int id, String amount, {int day = 15}) =>
    tx(id: id, amount: amount, at: DateTime.utc(2026, 6, day, 12));

void main() {
  group('AC-E4.2 — "enough history" is a fact this type computes', () {
    test('one month of data is NOT enough', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        july(1, '100.00'),
        july(2, '50.00'),
      ], period: july2026);

      expect(comparison.monthsWithData, 1);
      expect(comparison.hasEnoughHistory, isFalse);
      // Null even though the subtraction is perfectly computable. The screen
      // cannot render a delta it was not entitled to, even by ignoring the flag.
      expect(comparison.difference, isNull);
    });

    test('two months IS enough, even when the prior month is empty', () {
      // The distinction that matters: a user whose first month was May and who
      // spent nothing in June is entitled to a June-vs-May comparison. They have
      // two months of history and one of them was quiet, which is a real and
      // useful finding — unlike a comparison against a month that predates the
      // data entirely.
      final MonthComparison comparison = MonthComparison.of(
        <LedgerTransaction>[june(1, '400.00'), july(2, '100.00')],
        period: PeriodRange(
          startUtc: DateTime.utc(2026, 8),
          endUtcExclusive: DateTime.utc(2026, 9),
        ),
      );

      expect(comparison.monthsWithData, 2);
      expect(comparison.hasEnoughHistory, isTrue);
      // August spent nothing, July spent 100.00 → 100.00 less.
      expect(comparison.difference, Money.parse('-100.00', currency: 'SAR'));
    });

    test('a soft-deleted transaction cannot be the sole evidence a month '
        'happened', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        july(1, '100.00'),
        tx(
          id: 2,
          amount: '400.00',
          at: DateTime.utc(2026, 6, 15, 12),
          isDeleted: true,
        ),
      ], period: july2026);

      // US-B8: a deleted transaction is out of every total, so it cannot conjure
      // a month into existence either.
      expect(comparison.monthsWithData, 1);
      expect(comparison.hasEnoughHistory, isFalse);
    });

    test('an undated transaction cannot establish a month either', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        july(1, '100.00'),
        // A real case: a message can state no time at all.
        LedgerTransaction(
          id: 2,
          amount: Money.parse('55.00', currency: 'SAR'),
          direction: MovementDirection.debit,
          transactionType: TransactionType.posPurchase,
          affectsSpend: true,
        ),
      ], period: july2026);

      expect(comparison.monthsWithData, 1);
      expect(comparison.hasEnoughHistory, isFalse);
    });

    test('a month is counted by its RIYADH wall clock, not its UTC instant', () {
      // 2026-06-30T22:00Z is already 01:00 on 1 July in Riyadh, so this is a JULY
      // transaction. Counting by the UTC month would file it under June and
      // manufacture a second month of history out of one purchase — which would
      // then unlock a comparison the user has no data for.
      final int months =
          MonthComparison.distinctMonthsWithData(<LedgerTransaction>[
            tx(id: 1, amount: '100.00', at: DateTime.utc(2026, 6, 30, 22)),
            tx(id: 2, amount: '50.00', at: DateTime.utc(2026, 7, 15, 12)),
          ]);
      expect(months, 1);
    });

    test('an empty ledger has no history and no difference', () {
      final MonthComparison comparison = MonthComparison.of(
        const <LedgerTransaction>[],
        period: july2026,
      );
      expect(comparison.monthsWithData, 0);
      expect(comparison.hasEnoughHistory, isFalse);
      expect(comparison.difference, isNull);
    });
  });

  group('AC-E4.1 — the two figures and the difference', () {
    final List<LedgerTransaction> ledger = <LedgerTransaction>[
      june(1, '1000.00'),
      june(2, '500.00'),
      july(3, '1200.00'),
      july(4, '400.00'),
    ];

    test('current, prior and the difference are all exact', () {
      final MonthComparison comparison = MonthComparison.of(
        ledger,
        period: july2026,
      );

      expect(comparison.current.base, Money.parse('1600.00', currency: 'SAR'));
      expect(comparison.prior.base, Money.parse('1500.00', currency: 'SAR'));
      // Positive = spent more this period. Exact `Money`, never a tolerance:
      // ADR-002 makes the arithmetic exact, so any tolerance would only hide a
      // real disagreement.
      expect(comparison.difference, Money.parse('100.00', currency: 'SAR'));
    });

    test('the prior period is the calendar month before the visible one', () {
      final MonthComparison comparison = MonthComparison.of(
        ledger,
        period: july2026,
      );
      // A Riyadh month starts at 21:00 UTC on the previous month's last day.
      expect(comparison.priorPeriod.startUtc, DateTime.utc(2026, 5, 31, 21));
      expect(
        comparison.priorPeriod.endUtcExclusive,
        DateTime.utc(2026, 6, 30, 21),
      );
    });

    test(
      'a refund-heavy month can produce a negative difference, and it is not '
      'clamped',
      () {
        final MonthComparison comparison = MonthComparison.of(
          <LedgerTransaction>[june(1, '1000.00'), july(2, '100.00')],
          period: july2026,
        );
        expect(comparison.difference, Money.parse('-900.00', currency: 'SAR'));
      },
    );

    test('an unconvertible prior month yields a NULL difference, not a wrong '
        'one (ADR-009 case 4)', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        // June, entirely in a currency no message quoted a rate for.
        tx(
          id: 1,
          amount: '300.00',
          currency: 'EUR',
          at: DateTime.utc(2026, 6, 15, 12),
        ),
        july(2, '100.00'),
      ], period: july2026);

      expect(comparison.hasEnoughHistory, isTrue);
      expect(comparison.prior.base, isNull);
      expect(comparison.prior.isEmpty, isFalse, reason: 'June has a movement');
      expect(
        comparison.difference,
        isNull,
        reason:
            'treating an unconvertible month as zero would report "you spent '
            '200 less than last month" to someone who spent 300 EUR',
      );
      expect(comparison.isIncomplete, isTrue);
    });
  });

  group('the trail the S-31 chart renders', () {
    test('is three months, oldest first, with the visible one selected', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        tx(id: 1, amount: '100.00', at: DateTime.utc(2026, 5, 15, 12)),
        june(2, '200.00'),
        july(3, '300.00'),
      ], period: july2026);

      expect(comparison.trail.length, kMonthComparisonTrailLength);
      expect(
        comparison.trail.first.period.startUtc.isBefore(
          comparison.trail.last.period.startUtc,
        ),
        isTrue,
      );
      expect(comparison.trail.last.isSelected, isTrue);
      expect(
        comparison.trail.where((MonthBar b) => b.isSelected).length,
        1,
        reason: 'exactly one bar is the period being viewed',
      );
      expect(
        comparison.trail.map((MonthBar b) => b.totals.base).toList(),
        <Money>[
          Money.parse('100.00', currency: 'SAR'),
          Money.parse('200.00', currency: 'SAR'),
          Money.parse('300.00', currency: 'SAR'),
        ],
      );
    });

    test('a month with no data is marked empty rather than as a zero', () {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        june(1, '200.00'),
        july(2, '300.00'),
      ], period: july2026);
      // May has nothing. `isEmpty` is what makes the chart draw no bar at all,
      // which is different from a flat bar meaning "spent nothing".
      expect(comparison.trail.first.isEmpty, isTrue);
      expect(comparison.trail.first.totals.base, isNull);
    });

    test(
      'an internal transfer is excluded from every bar, over the whole set',
      () {
        // The pair spans two months, which is the case a per-period analysis would
        // get wrong: neither month contains both legs, so a detector run per bar
        // would find no pair and count the outgoing leg as spend.
        final MonthComparison comparison =
            MonthComparison.of(<LedgerTransaction>[
              july(1, '300.00'),
              tx(
                id: 2,
                amount: '900.00',
                type: TransactionType.transferOut,
                affectsSpend: false,
                at: DateTime.utc(2026, 7, 20, 12),
                on: instrument(id: 10, bankId: 1),
              ),
              tx(
                id: 3,
                amount: '900.00',
                direction: MovementDirection.credit,
                type: TransactionType.transferIn,
                affectsSpend: false,
                at: DateTime.utc(2026, 7, 20, 12, 5),
                on: instrument(id: 20, bankId: 2),
              ),
              june(4, '200.00'),
            ], period: july2026);

        expect(
          comparison.current.base,
          Money.parse('300.00', currency: 'SAR'),
          reason:
              'the 900.00 transfer must not be in July\'s figure (AC-B11.1)',
        );
        expect(comparison.difference, Money.parse('100.00', currency: 'SAR'));
      },
    );
  });
}
