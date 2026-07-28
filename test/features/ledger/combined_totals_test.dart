/// **The P3b-1 acceptance test.** KHA-27 + KHA-28 + KHA-29 + KHA-70, together.
///
/// ---
///
/// ## Why this file exists at all
///
/// `docs/build-plan.md` groups multi-currency, refunds and internal transfers
/// into one PR because *"all three rewrite the same function"*. The corollary
/// is that testing them separately proves almost nothing: each of the three
/// can be individually correct while the combination is wrong, because they
/// interact.
///
/// The three interactions that a per-feature test cannot catch:
///
/// 1. **A refund in a foreign currency** has to be converted *and then*
///    subtracted, on **its own** recorded rate — not the original purchase's,
///    and not by subtracting a foreign figure from a base-currency total.
/// 2. **An internal transfer split across two instruments** is only visible
///    as a pair in the *whole* ledger; a per-instrument total that re-derived
///    pairs from its own slice would see one leg, find no partner, and count
///    a transfer to yourself as spending.
/// 3. **An unconvertible transaction** must be missing from the base figure
///    *and* present in the native breakdown *and* counted on the "not
///    converted" line — three places that have to agree.
///
/// ## Every figure below is hand-calculated in the comments
///
/// That is the point of the exercise. If this file only asserted that the
/// code agrees with itself, it would go green on a wrong number. The
/// arithmetic is written out so a reviewer can check the expectation without
/// running anything.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

// One bank, three instruments — all the user's own, because every instrument
// row is created from a message about the user's own account (US-B15).
const LedgerBank aljazira = LedgerBank(
  id: 1,
  canonicalKey: 'bank-aljazira',
  displayNameAr: 'بنك الجزيرة',
  displayNameEn: 'Bank Aljazira',
);

final LedgerInstrument current = instrument(id: 1, masked: '****3388');
final LedgerInstrument visa = instrument(
  id: 2,
  kind: 'card',
  masked: '****9013',
);
final LedgerInstrument savings = instrument(id: 3, masked: '****1157');

/// July 2026, as one person's month actually looks: a couple of purchases, a
/// foreign one, a refund of a foreign one, a transfer to their own savings, a
/// salary, some cash out, a card repayment, a genuine third-party transfer,
/// and one purchase in a currency the bank quoted no rate for.
List<LedgerTransaction> julyLedger({
  bool internalTransferIsProven = true,
}) => <LedgerTransaction>[
  // 1. An ordinary SAR card purchase.                    spend +152.75
  tx(id: 1, amount: '152.75', on: visa, at: DateTime.utc(2026, 7, 5, 14, 32)),

  // 2. A USD purchase the bank converted itself, with an FX fee kept
  //    separate (PRD §3.4).                              spend +450.12
  tx(
    id: 2,
    amount: '120.00',
    currency: 'USD',
    type: TransactionType.onlinePurchase,
    convertedAmount: '450.12',
    fee: '11.25',
    fxRate: '3.7510',
    fxRateDate: DateTime.utc(2026, 7, 6, 19, 47),
    fxRateSource: 'sms_stated',
    on: visa,
    at: DateTime.utc(2026, 7, 6, 19, 47),
  ),

  // 3. **Interaction 1** — a refund of a foreign purchase, carrying its
  //    own conversion.                                   spend −187.46
  tx(
    id: 3,
    amount: '49.99',
    currency: 'USD',
    direction: 'credit',
    type: TransactionType.refund,
    convertedAmount: '187.46',
    fxRateSource: 'sms_implied',
    on: visa,
    at: DateTime.utc(2026, 7, 8, 10, 15),
  ),

  // 4. **Interaction 3** — a EUR purchase the message quoted no rate for.
  //    ADR-009: excluded from the base figure, never invented.
  tx(
    id: 4,
    amount: '35.00',
    currency: 'EUR',
    conversionPending: true,
    on: visa,
    at: DateTime.utc(2026, 7, 9, 12),
  ),

  // 5 + 6. **Interaction 2** — the user moving 2,000 SAR from their
  //    current account to their own savings. Two legs, two instruments.
  tx(
    id: 5,
    amount: '2000.00',
    type: TransactionType.transferOut,
    reference: internalTransferIsProven ? 'TRX-INTERNAL-1' : null,
    on: current,
    at: DateTime.utc(2026, 7, 10, 9),
  ),
  tx(
    id: 6,
    amount: '2000.00',
    direction: 'credit',
    type: TransactionType.transferIn,
    affectsSpend: false,
    reference: internalTransferIsProven ? 'TRX-INTERNAL-1' : null,
    on: savings,
    at: DateTime.utc(2026, 7, 10, 9, 2),
  ),

  // 7. Salary.                                           income 14,500.00
  tx(
    id: 7,
    amount: '14500.00',
    direction: 'credit',
    type: TransactionType.salaryIncome,
    affectsSpend: false,
    on: current,
    at: DateTime.utc(2026, 7, 25, 5),
  ),

  // 8. Cash out of an ATM — neither spend nor income.    cash 500.00
  tx(
    id: 8,
    amount: '500.00',
    type: TransactionType.withdrawal,
    affectsSpend: false,
    on: current,
    at: DateTime.utc(2026, 7, 27, 15, 22),
  ),

  // 9. Card repayment — settles spend already counted.   excluded
  tx(
    id: 9,
    amount: '1200.00',
    type: TransactionType.cardRepayment,
    affectsSpend: false,
    on: current,
    at: DateTime.utc(2026, 7, 23, 9),
  ),

  // 10. A genuine third-party transfer. Same shape as leg 5 — the only
  //     thing that distinguishes them is whether a partner leg exists.
  tx(
    id: 10,
    amount: '800.00',
    type: TransactionType.transferOut,
    reference: 'TRX-THIRD-PARTY',
    on: current,
    at: DateTime.utc(2026, 7, 12, 11),
  ),

  // 11. **Interaction 1 again, harder** — a foreign refund with a stated
  //     *rate* and no converted amount, so the conversion has to be
  //     computed: 20.00 × 3.7500 = 75.00.                spend −75.00
  tx(
    id: 11,
    amount: '20.00',
    currency: 'USD',
    direction: 'credit',
    type: TransactionType.refund,
    fxRate: '3.7500',
    fxRateDate: DateTime.utc(2026, 7, 14, 8),
    fxRateSource: 'sms_stated',
    on: visa,
    at: DateTime.utc(2026, 7, 14, 8),
  ),
];

void main() {
  group('the combined period figure (AC-B9.2 + AC-B7.1 + AC-B11.1)', () {
    late PeriodReport report;

    setUp(() {
      report = LedgerTotals.report(julyLedger(), period: july2026);
    });

    test('net spend in the base currency is 1,140.41 SAR', () {
      //   +152.75   SAR purchase                                 (1)
      //   +450.12   USD purchase, bank's own conversion          (2)
      //   −187.46   USD refund, bank's own conversion            (3)
      //   +800.00   third-party transfer out                    (10)
      //   − 75.00   USD refund at the stated rate 20 × 3.75     (11)
      //   ────────
      //    1140.41
      //
      // Not in this figure, each for a different reason:
      //   (4)  EUR 35.00 — no rate, so not convertible (ADR-009)
      //   (5)(6) the internal transfer — not spending (AC-B11.1)
      //   (7)  salary — income
      //   (8)  cash withdrawal — custody moved, nothing spent
      //   (9)  card repayment — settles spend already counted
      expect(report.spend.base!.toCanonicalString(), '1140.41');
      expect(report.spend.baseCurrencyCode, 'SAR');
      expect(report.spend.convertedCount, 5);
    });

    test('the native per-currency breakdown reconciles with the same five '
        'transactions, plus the unconvertible one', () {
      // SAR: 152.75 + 800.00                      = 952.75 over 2
      // USD: 120.00 − 49.99 − 20.00               =  50.01 over 3
      // EUR: 35.00                                =  35    over 1
      expect(report.spend.forCurrency('SAR')!.toCanonicalString(), '952.75');
      expect(report.spend.forCurrency('USD')!.toCanonicalString(), '50.01');
      expect(report.spend.forCurrency('EUR')!.toCanonicalString(), '35');

      // Ordered by transaction count, so the currency the user transacts in
      // most leads.
      expect(
        report.spend.byCurrency.map((CurrencyTotal t) => t.currencyCode),
        <String>['USD', 'SAR', 'EUR'],
      );
    });

    test('the EUR purchase is missing from the base figure AND visible on the '
        '"not converted" line — ADR-009', () {
      expect(report.spend.isIncomplete, isTrue);
      expect(report.spend.unconvertedCount, 1);
      expect(report.spend.unconverted.single.currencyCode, 'EUR');
      expect(report.spend.unconverted.single.net.toCanonicalString(), '35');
      expect(
        report.isIncomplete,
        isTrue,
        reason:
            'the whole report is flagged, not only the one line, so a screen '
            'cannot label the wrong figure as provisional',
      );
    });

    test('AC-B10.3 — spent vs kept nets income against spend and nothing '
        'else', () {
      // 14,500.00 received − 1,140.41 spent = 13,359.59 kept.
      expect(report.income.base!.toCanonicalString(), '14500');
      expect(report.netKept!.toCanonicalString(), '13359.59');

      // Cash withdrawn is reported, deliberately NOT subtracted: the money is
      // still the user's, and a user who wants to treat it as spent can see
      // the figure and decide.
      expect(report.cashWithdrawals.base!.toCanonicalString(), '500');
    });

    test('the internal transfer is excluded from spend and shown as its own '
        'auditable figure — ONE movement, not two rows (NFR-A6)', () {
      // 2,000.00, not 4,000.00. The figure has to reconcile: it is exactly
      // the amount by which net spend differs from a naive sum of the user's
      // debits, which is the outgoing leg. Reporting both legs would claim
      // twice the money moved.
      expect(report.internalTransfers.base!.toCanonicalString(), '2000');
      expect(report.internalTransfers.convertedCount, 1);
    });

    test('the FX fee is its own figure and is not inside net spend '
        '(PRD §3.4)', () {
      expect(report.fees.base!.toCanonicalString(), '11.25');
      // The failure this pins: 1,140.41 + 11.25 = 1,151.66 would mean the fee
      // was folded in and became invisible.
      expect(report.spend.base!.toCanonicalString(), isNot('1151.66'));
    });

    test('nothing needs review — every classification here is determinate', () {
      expect(report.needsReviewCount, 0);
    });
  });

  group('AC-B11.2 — the same month with an UNPROVEN internal transfer', () {
    late PeriodReport report;

    setUp(() {
      // The only change: neither leg carries a reference number, so the pair
      // is plausible but not provable.
      report = LedgerTotals.report(
        julyLedger(internalTransferIsProven: false),
        period: july2026,
      );
    });

    test('the candidate keeps counting as spend — 1,140.41 + 2,000.00', () {
      // architecture §4.2: candidates do not change spend totals until
      // confirmed. The bias is deliberate: an over-stated total is visible on
      // screen and correctable in one tap; an under-stated one is invisible
      // and the user never learns they were told the wrong number.
      expect(report.spend.base!.toCanonicalString(), '3140.41');
    });

    test('…and the user is told the figure is provisional', () {
      expect(report.needsReviewCount, greaterThan(0));
      expect(report.internalTransfers.isEmpty, isTrue);
    });
  });

  group('AC-C1.3 / AC-E3.2 — the parts sum to the whole through the bank '
      'tree', () {
    late List<BankTreeNode> tree;

    setUp(() {
      tree = BankTreeBuilder.build(
        banks: const <LedgerBank>[aljazira],
        instruments: <LedgerInstrument>[current, visa, savings],
        transactions: julyLedger(),
        period: july2026,
      );
    });

    test('**the slicing test**: a per-instrument total still excludes the '
        'internal transfer, even though its partner leg is on another '
        'instrument', () {
      // This is the single most plausible way to reintroduce AC-B11.1 as a
      // bug. The current account holds only the OUTGOING leg; a detector run
      // over that slice alone would find no partner and count 2,000.00 SAR of
      // "spending" that never left the user. `BankTreeBuilder` therefore
      // analyses the whole set once and hands the result down.
      final InstrumentSummary currentAccount = tree.single.accounts.firstWhere(
        (InstrumentSummary s) => s.instrument.id == current.id,
      );

      // Account: only the genuine third-party transfer (10) counts.
      expect(currentAccount.totals.base!.toCanonicalString(), '800');
      expect(
        currentAccount.totals.base!.toCanonicalString(),
        isNot('2800'),
        reason:
            'a per-slice re-derivation would produce exactly this wrong '
            'figure, and it would look entirely plausible',
      );
    });

    test('the savings account, which holds only the incoming leg, shows no '
        'spend at all', () {
      final InstrumentSummary savingsAccount = tree.single.accounts.firstWhere(
        (InstrumentSummary s) => s.instrument.id == savings.id,
      );
      expect(savingsAccount.totals.base, isNull);
      expect(savingsAccount.totals.isEmpty, isTrue);
    });

    test('the card carries the multi-currency half: 340.41 SAR plus one '
        'unconverted EUR purchase', () {
      //   +152.75 − 187.46 + 450.12 − 75.00 = 340.41
      final InstrumentSummary cardSummary = tree.single.cards.single;
      expect(cardSummary.totals.base!.toCanonicalString(), '340.41');
      expect(cardSummary.totals.unconvertedCount, 1);
    });

    test('the bank total equals the sum of its instruments, which equals the '
        'period total', () {
      // 800.00 (current) + 0 (savings) + 340.41 (card) = 1,140.41
      expect(tree.single.totals.base!.toCanonicalString(), '1140.41');
      expect(
        tree.single.totals.base!.toCanonicalString(),
        LedgerTotals.report(
          julyLedger(),
          period: july2026,
        ).spend.base!.toCanonicalString(),
        reason:
            'AC-C1.3 and AC-E3.2 both reduce to this: the breakdown and the '
            'headline must be the same number, computed from the same list',
      );
    });
  });

  group(
    'a base currency other than SAR (NFR-A5 — no hard-coded assumption)',
    () {
      test('the same month reported in USD converts what it can and reports '
          'the rest as unconverted', () {
        final PeriodReport usd = LedgerTotals.report(
          julyLedger(),
          period: july2026,
          baseCurrencyCode: 'USD',
        );

        // Only the two native-USD refunds and the USD purchase can be expressed
        // in USD from what each record carries: +120.00 − 49.99 − 20.00 = 50.01.
        // The SAR and EUR transactions have no USD conversion recorded, and
        // ADR-009 forbids reaching for one.
        expect(usd.spend.base!.toCanonicalString(), '50.01');
        expect(usd.spend.baseCurrencyCode, 'USD');
        expect(
          usd.spend.unconvertedCount,
          3,
          reason: 'the two SAR movements and the EUR purchase',
        );
        // The invariant that matters: nothing was blended. A SAR figure never
        // entered a USD total.
        expect(
          usd.spend.unconverted.map((UnconvertedGroup g) => g.currencyCode),
          containsAll(<String>['SAR', 'EUR']),
        );
      });
    },
  );

  group('soft delete cuts across all three features', () {
    test('deleting the foreign refund raises net spend by exactly its '
        'converted value, and nothing else moves', () {
      final List<LedgerTransaction> rows = julyLedger();
      final List<LedgerTransaction> withoutRefund = <LedgerTransaction>[
        for (final LedgerTransaction row in rows)
          if (row.id == 3)
            tx(
              id: 3,
              amount: '49.99',
              currency: 'USD',
              direction: 'credit',
              type: TransactionType.refund,
              convertedAmount: '187.46',
              on: visa,
              at: DateTime.utc(2026, 7, 8, 10, 15),
              isDeleted: true,
            )
          else
            row,
      ];

      // 1,140.41 + 187.46 = 1,327.87
      expect(
        LedgerTotals.report(
          withoutRefund,
          period: july2026,
        ).spend.base!.toCanonicalString(),
        '1327.87',
      );
    });

    test('deleting one leg of the internal transfer un-pairs it, so the '
        'surviving leg counts as spend again — and the user can see why', () {
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        for (final LedgerTransaction row in julyLedger())
          if (row.id == 6)
            tx(
              id: 6,
              amount: '2000.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              affectsSpend: false,
              reference: 'TRX-INTERNAL-1',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9, 2),
              isDeleted: true,
            )
          else
            row,
      ];

      // Deliberate, and worth stating: a deleted row is out of every total
      // (US-B8), so it can no longer prove anything about the row it was
      // paired with. The outgoing leg becomes ordinary spend again rather
      // than silently keeping an exclusion granted by a transaction that no
      // longer exists.
      final PeriodReport report = LedgerTotals.report(rows, period: july2026);
      expect(report.spend.base!.toCanonicalString(), '3140.41');
      expect(report.internalTransfers.isEmpty, isTrue);
    });
  });
}
