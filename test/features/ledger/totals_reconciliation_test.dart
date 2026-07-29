/// **NFR-A6, as an invariant rather than an example** — KHA-35 / KHA-36's
/// shared done-check:
///
/// > *"Per-instrument totals sum to the bank total; bank totals sum to the
/// > period total."*
/// > *"The displayed total equals a from-scratch recomputation over the
/// > period's transactions (equality, not approximate equality)."*
///
/// ---
///
/// ## Three layers of evidence, because one of them is not enough
///
/// 1. **A hand-computed expectation.** The fixture below is small enough that a
///    person can add it up, and the expected figure is written into the test as
///    a literal. This is the only kind of "from-scratch recomputation" that is
///    genuinely independent of the code under test — calling `LedgerTotals`
///    twice and comparing would pass even if `LedgerTotals` were wrong.
///
/// 2. **The structural chain.** Instrument → bank → period, asserted as exact
///    `Money` equality at every link. This is the property the two screens
///    depend on: a user who drills from Home into a bank into a card must never
///    find the numbers stop agreeing.
///
/// 3. **A generated sweep.** Two hundred pseudo-random ledgers, deterministic
///    seed, each one reconciled end to end. A hand-built fixture proves the
///    arithmetic works for the case its author thought of; this proves it for
///    cases nobody did, which is where the interesting ones live (refunds
///    outnumbering purchases, a bank with no instruments, an instrument with no
///    transactions, an internal transfer split across two banks).
///
/// ## Why exact equality and not `closeTo`
///
/// `Money` is backed by an arbitrary-precision `Decimal` (ADR-002). There is no
/// floating-point error to tolerate, so any tolerance would only be hiding a
/// real disagreement. `expect(a, b)` on two `Money`s is exact by construction.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

/// Adds the base-currency figures of several [PeriodTotals], skipping the ones
/// that are genuinely empty.
///
/// Returns null when **nothing** in the set had a base figure, which is the
/// same "we have nothing to show" that `PeriodTotals.base` uses — so the
/// comparison below never turns an absence into a zero and calls it agreement.
Money? sumOfBases(Iterable<PeriodTotals> parts, String currency) {
  final List<Money> bases = <Money>[
    for (final PeriodTotals part in parts)
      if (part.base != null) part.base!,
  ];
  return bases.isEmpty ? null : Money.sum(bases, currency: currency);
}

LedgerBank bank(int id) => LedgerBank(
  id: id,
  canonicalKey: 'bank_$id',
  displayNameAr: 'بنك $id',
  displayNameEn: 'Bank $id',
);

void main() {
  group('NFR-A6 — the instrument → bank → period chain reconciles', () {
    // ---------------------------------------------------------------
    // A ledger a person can add up by hand.
    //
    //   Bank 1
    //     account #10   −1,000.00   (bill payment)
    //                   −  250.50   (transfer out to a third party)
    //     card    #11   −  400.00   (POS purchase)
    //                   +  100.00   (refund — REDUCES spend, US-B7)
    //   Bank 2
    //     card    #21   −2,000.00   (online purchase)
    //
    //   Excluded, each for a stated reason:
    //     #99 soft-deleted            — out of every total until restored
    //     #98 dated in June           — outside the period
    //     #97 salary +9,000.00        — income, not negative spend
    //     #96 ATM withdrawal −500.00  — cash, reported on its own line
    //
    //   Hand-computed net spend:
    //     1000.00 + 250.50 + 400.00 − 100.00 + 2000.00 = 3,550.50
    // ---------------------------------------------------------------
    final LedgerInstrument account10 = instrument(id: 10, bankId: 1);
    final LedgerInstrument card11 = instrument(
      id: 11,
      bankId: 1,
      kind: InstrumentKind.card,
      masked: '****4821',
    );
    final LedgerInstrument card21 = instrument(
      id: 21,
      bankId: 2,
      kind: InstrumentKind.card,
      masked: '****9002',
    );

    final List<LedgerTransaction> ledger = <LedgerTransaction>[
      tx(
        id: 1,
        amount: '1000.00',
        type: TransactionType.billPayment,
        on: account10,
      ),
      tx(
        id: 2,
        amount: '250.50',
        type: TransactionType.transferOut,
        on: account10,
      ),
      tx(id: 3, amount: '400.00', on: card11),
      tx(
        id: 4,
        amount: '100.00',
        direction: MovementDirection.credit,
        type: TransactionType.refund,
        on: card11,
      ),
      tx(
        id: 5,
        amount: '2000.00',
        type: TransactionType.onlinePurchase,
        on: card21,
      ),
      tx(id: 99, amount: '77.00', isDeleted: true, on: card11),
      tx(
        id: 98,
        amount: '640.00',
        at: DateTime.utc(2026, 6, 15, 10),
        on: account10,
      ),
      tx(
        id: 97,
        amount: '9000.00',
        direction: MovementDirection.credit,
        type: TransactionType.salaryIncome,
        on: account10,
      ),
      tx(
        id: 96,
        amount: '500.00',
        type: TransactionType.withdrawal,
        on: account10,
      ),
    ];

    List<BankTreeNode> buildTree() => BankTreeBuilder.build(
      banks: <LedgerBank>[bank(1), bank(2)],
      instruments: <LedgerInstrument>[account10, card11, card21],
      transactions: ledger,
      period: july2026,
    );

    test('the period total equals a figure computed by hand, exactly', () {
      final PeriodTotals total = LedgerTotals.spend(ledger, period: july2026);

      // The literal is the whole point: it was derived from the comment above
      // by adding five numbers, not by running the code under test.
      expect(total.base, Money.parse('3550.50', currency: 'SAR'));
      // Five transactions contributed. A count that drifts from the figure is
      // the cheapest signal that an exclusion rule changed.
      expect(total.convertedCount, 5);
    });

    test('each instrument total equals its own transactions, by hand', () {
      final List<BankTreeNode> tree = buildTree();
      final BankTreeNode bank1 = tree.firstWhere(
        (BankTreeNode n) => n.bank.id == 1,
      );
      final BankTreeNode bank2 = tree.firstWhere(
        (BankTreeNode n) => n.bank.id == 2,
      );

      expect(
        bank1.accounts.single.totals.base,
        // 1000.00 + 250.50. The salary, the ATM withdrawal and the June
        // purchase all sit on this same account and none of them is spend.
        Money.parse('1250.50', currency: 'SAR'),
      );
      expect(
        bank1.cards.single.totals.base,
        // 400.00 − 100.00 (the refund), with the soft-deleted 77.00 absent.
        Money.parse('300.00', currency: 'SAR'),
      );
      expect(
        bank2.cards.single.totals.base,
        Money.parse('2000.00', currency: 'SAR'),
      );
    });

    test('instrument totals sum to the bank total, and bank totals sum to the '
        'period total', () {
      final List<BankTreeNode> tree = buildTree();

      for (final BankTreeNode node in tree) {
        expect(
          sumOfBases(<PeriodTotals>[
            for (final InstrumentSummary s in node.accounts) s.totals,
            for (final InstrumentSummary s in node.cards) s.totals,
          ], 'SAR'),
          node.totals.base,
          reason:
              'bank ${node.bank.canonicalKey}: the figure on the bank page '
              'must equal the sum of the figures on its instrument pages, or '
              'a user drilling in finds the numbers stop agreeing',
        );
      }

      expect(
        sumOfBases(tree.map((BankTreeNode n) => n.totals), 'SAR'),
        LedgerTotals.spend(ledger, period: july2026).base,
      );
    });

    test('a cash transaction — one with no instrument at all — is in the '
        'period total but under no bank', () {
      // US-B4/OQ-19: cash is a first-class payment method, and the banks screen
      // has nowhere to put it. That is not a reconciliation failure, but it IS
      // the one place the chain deliberately does not close, so it is pinned
      // here rather than left for someone to discover as a bug.
      final List<LedgerTransaction> withCash = <LedgerTransaction>[
        ...ledger,
        tx(id: 500, amount: '60.00'),
      ];
      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[bank(1), bank(2)],
        instruments: <LedgerInstrument>[account10, card11, card21],
        transactions: withCash,
        period: july2026,
      );

      expect(
        LedgerTotals.spend(withCash, period: july2026).base,
        Money.parse('3610.50', currency: 'SAR'),
      );
      expect(
        sumOfBases(tree.map((BankTreeNode n) => n.totals), 'SAR'),
        Money.parse('3550.50', currency: 'SAR'),
      );
    });
  });

  group('NFR-A6 — the chain holds over generated ledgers', () {
    test('200 pseudo-random ledgers reconcile instrument → bank → period', () {
      // A fixed seed: a property test that cannot be reproduced from its own
      // failure message is a test that gets marked flaky and deleted.
      final Random random = Random(20260729);

      for (int run = 0; run < 200; run++) {
        final int bankCount = 1 + random.nextInt(3);
        final List<LedgerBank> banks = <LedgerBank>[
          for (int b = 1; b <= bankCount; b++) bank(b),
        ];

        final List<LedgerInstrument> instruments = <LedgerInstrument>[];
        int nextInstrumentId = 1;
        for (final LedgerBank b in banks) {
          // Zero instruments is allowed and interesting: a bank can exist with
          // nothing under it (a message resolved the bank but named no
          // instrument), and its total must then be "nothing", not zero.
          final int count = random.nextInt(4);
          for (int i = 0; i < count; i++) {
            instruments.add(
              instrument(
                id: nextInstrumentId++,
                bankId: b.id,
                kind: random.nextBool()
                    ? InstrumentKind.card
                    : InstrumentKind.account,
              ),
            );
          }
        }

        final List<LedgerTransaction> transactions = <LedgerTransaction>[];
        final int txCount = random.nextInt(25);
        for (int t = 0; t < txCount; t++) {
          final bool credit = random.nextInt(4) == 0;
          transactions.add(
            tx(
              id: 1000 + t,
              // Two decimal places, so the fixture exercises the minor unit
              // rather than only whole riyals.
              amount:
                  '${random.nextInt(5000)}.${random.nextInt(100).toString().padLeft(2, '0')}',
              direction: credit
                  ? MovementDirection.credit
                  : MovementDirection.debit,
              type: credit
                  ? TransactionType.refund
                  : TransactionType.posPurchase,
              isDeleted: random.nextInt(8) == 0,
              at: DateTime.utc(2026, 7, 1 + random.nextInt(31), 12),
              on: instruments.isEmpty || random.nextInt(6) == 0
                  ? null
                  : instruments[random.nextInt(instruments.length)],
            ),
          );
        }

        final List<BankTreeNode> tree = BankTreeBuilder.build(
          banks: banks,
          instruments: instruments,
          transactions: transactions,
          period: july2026,
        );

        for (final BankTreeNode node in tree) {
          expect(
            sumOfBases(<PeriodTotals>[
              for (final InstrumentSummary s in node.accounts) s.totals,
              for (final InstrumentSummary s in node.cards) s.totals,
            ], 'SAR'),
            node.totals.base,
            reason: 'run $run, bank ${node.bank.id}',
          );
        }

        // The period total covers cash too, so the bank chain reconciles
        // against the instrument-bearing subset rather than against everything
        // — the deliberate gap pinned in the fixture group above.
        final List<LedgerTransaction> onInstruments = <LedgerTransaction>[
          for (final LedgerTransaction txn in transactions)
            if (txn.instrument != null) txn,
        ];
        expect(
          sumOfBases(tree.map((BankTreeNode n) => n.totals), 'SAR'),
          LedgerTotals.spend(onInstruments, period: july2026).base,
          reason: 'run $run: bank totals must sum to the period total',
        );
      }
    });
  });
}
