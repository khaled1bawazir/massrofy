/// **AC-E3.2 — the card-breakdown reconciliation invariant**, asserted rather
/// than assumed (KHA-37).
///
/// > *"The card breakdown totals sum to the period total shown elsewhere in the
/// > app."*
///
/// ---
///
/// ## Why this file is deliberately awkward
///
/// KHA-37's brief is explicit that this build has *"a repeated history of exactly
/// this kind of bug hiding behind shallow tests"*, and it names the gap to avoid:
///
/// > *"P5a's `totals_reconciliation_test.dart` already covers the
/// > instrument→bank→period chain and QA found a gap you should avoid repeating
/// > (the 200-generated-ledger corpus must actually include an
/// > internal-transfer-across-banks case, not just same-bank cases)."*
///
/// That gap is real. P5a's generated sweep builds every transaction as a
/// `posPurchase` or a `refund`, so **no run in it contains a transfer at all** —
/// same-bank or cross-bank. Its hand-built fixture has a `transferOut` but no
/// matching `transferIn`, so the detector never pairs anything there either. The
/// reconciliation it proves is therefore genuine but narrower than its own
/// docstring claims: *"an internal transfer split across two banks"* is listed as
/// one of the interesting cases the sweep covers, and it does not.
///
/// So the generated sweep here **plants a real cross-bank pair in every run**
/// (`_plantTransferPair`), and there is a direct fixture test that fails if the
/// pair is not excluded. If the shared analysis were ever dropped — if
/// `InstrumentBreakdown.of` re-derived the pairing per slice, or stopped passing
/// `transfers:` into `BankTreeBuilder` — the outgoing leg would start counting as
/// spend on its instrument's row while the grand total kept excluding it, and the
/// footer identity would break. `period_totals.dart` calls that *"the most
/// plausible way to reintroduce AC-B11.1 as a bug"*; these tests are what would
/// catch it.
///
/// ## The three properties, and why the third is the one that matters
///
///  1. Per-instrument figures equal hand-computed sums (an independent oracle).
///  2. The cash row exists and holds exactly what has no instrument.
///  3. **Instruments + cash == the period total**, over a hand fixture *and* over
///     200 generated ledgers. This is AC-E3.2 verbatim, and it is the one a naive
///     implementation fails the moment the user pays for anything in cash.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_breakdown.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

LedgerBank bank(int id) => LedgerBank(
  id: id,
  canonicalKey: 'bank_$id',
  displayNameAr: 'بنك $id',
  displayNameEn: 'Bank $id',
);

/// Sums the base figures of several [PeriodTotals], treating a genuinely-absent
/// figure as absent rather than as zero — the same discipline
/// `totals_reconciliation_test.dart`'s `sumOfBases` uses, and for the same reason:
/// turning an absence into a zero would let the comparison "agree" about a figure
/// neither side has.
Money? sumOfBases(Iterable<PeriodTotals> parts, String currency) {
  final List<Money> bases = <Money>[
    for (final PeriodTotals part in parts)
      if (part.base != null) part.base!,
  ];
  return bases.isEmpty ? null : Money.sum(bases, currency: currency);
}

Money? sumOfBreakdown(InstrumentBreakdown breakdown) =>
    sumOfBases(<PeriodTotals>[
      for (final InstrumentSlice slice in breakdown.instruments)
        slice.summary.totals,
      breakdown.unassigned,
    ], breakdown.baseCurrencyCode);

void main() {
  // -----------------------------------------------------------------------
  //   Bank 1
  //     account #10   −1,000.00   bill payment
  //     card    #11   −  400.00   POS purchase
  //                   +  100.00   refund (REDUCES spend, US-B7)
  //   Bank 2
  //     card    #21   −2,000.00   online purchase
  //     account #22   (no activity — still gets a row)
  //   No instrument
  //     cash          −   60.00   manual entry (US-B4)
  //
  //   An internal transfer ACROSS banks, 750.00 out of #10 into #21's account
  //   #22 — excluded from spend on both legs (AC-B11.1).
  //
  //   Hand-computed net spend:
  //     1000.00 + 400.00 − 100.00 + 2000.00 + 60.00 = 3,360.00
  // -----------------------------------------------------------------------
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
  final LedgerInstrument account22 = instrument(id: 22, bankId: 2);

  final List<LedgerBank> banks = <LedgerBank>[bank(1), bank(2)];
  final List<LedgerInstrument> instruments = <LedgerInstrument>[
    account10,
    card11,
    card21,
    account22,
  ];

  final List<LedgerTransaction> ledger = <LedgerTransaction>[
    tx(
      id: 1,
      amount: '1000.00',
      type: TransactionType.billPayment,
      on: account10,
    ),
    tx(id: 2, amount: '400.00', on: card11),
    tx(
      id: 3,
      amount: '100.00',
      direction: MovementDirection.credit,
      type: TransactionType.refund,
      on: card11,
    ),
    tx(
      id: 4,
      amount: '2000.00',
      type: TransactionType.onlinePurchase,
      on: card21,
    ),
    // Cash — no instrument at all. THE row that makes a naive card breakdown
    // disagree with the period total.
    tx(id: 5, amount: '60.00'),
    // The cross-bank internal transfer, both legs, same amount, minutes apart —
    // which is what `InternalTransferDetector` pairs on.
    tx(
      id: 6,
      amount: '750.00',
      type: TransactionType.transferOut,
      affectsSpend: false,
      at: DateTime.utc(2026, 7, 15, 10),
      on: account10,
    ),
    tx(
      id: 7,
      amount: '750.00',
      direction: MovementDirection.credit,
      type: TransactionType.transferIn,
      affectsSpend: false,
      at: DateTime.utc(2026, 7, 15, 10, 5),
      on: account22,
    ),
  ];

  InstrumentBreakdown build([List<LedgerTransaction>? rows]) =>
      InstrumentBreakdown.of(
        rows ?? ledger,
        period: july2026,
        banks: banks,
        instruments: instruments,
      );

  group('AC-E3.1 — every instrument gets a row with its own figure', () {
    test('per-instrument figures equal hand-computed sums', () {
      final InstrumentBreakdown breakdown = build();

      Money? figureFor(int instrumentId) => breakdown.instruments
          .firstWhere(
            (InstrumentSlice s) => s.summary.instrument.id == instrumentId,
          )
          .summary
          .totals
          .base;

      // 1000.00 only — the 750.00 transfer out of this same account is excluded
      // (AC-B11.1), and that exclusion is the point of the fixture.
      expect(figureFor(10), Money.parse('1000.00', currency: 'SAR'));
      // 400.00 − 100.00.
      expect(figureFor(11), Money.parse('300.00', currency: 'SAR'));
      expect(figureFor(21), Money.parse('2000.00', currency: 'SAR'));
      // The incoming transfer leg was never spend to begin with.
      expect(figureFor(22), isNull);
    });

    test('an instrument with no SPEND still gets a row, at "no figure" rather '
        'than at zero — and its count still shows the activity', () {
      final InstrumentBreakdown breakdown = build();
      final InstrumentSlice idle = breakdown.instruments.firstWhere(
        (InstrumentSlice s) => s.summary.instrument.id == 22,
      );

      // The approved mockup (S-30) shows a row like this. `null`, not
      // `Money.zero`: *"we measured nothing"* and *"you spent nothing"* stay
      // different facts (`PeriodTotals.base`'s nullability exists for this).
      expect(idle.summary.totals.base, isNull);
      // And `isEmpty` is genuinely true, because the only movement on this
      // account is the **incoming** leg of an internal transfer, which is
      // excluded from spend on both legs (AC-B11.1) — so the spend accumulator
      // received nothing at all, not even a zero.
      expect(idle.summary.totals.isEmpty, isTrue);
      // The count is what stops that reading as "nothing happened here". This is
      // exactly the pair of values `InstrumentBreakdownScreen` renders as
      // "Not used this period" versus a bank subtitle, and the reason
      // `transactionCount` is not derived from the figure.
      expect(
        idle.transactionCount,
        1,
        reason:
            'a figure of "nothing" beside a count of 1 is the honest rendering '
            'of "one movement, none of it spending" — not a discrepancy',
      );
    });

    test('the transaction count counts every movement, not only spend', () {
      final InstrumentBreakdown breakdown = build();
      final InstrumentSlice account = breakdown.instruments.firstWhere(
        (InstrumentSlice s) => s.summary.instrument.id == 10,
      );
      // The bill payment AND the transfer out. A count that matched the figure
      // would hide the transfer from a user who tapped through expecting to see
      // it.
      expect(account.transactionCount, 2);
    });
  });

  group('AC-E3.2 — the breakdown sums to the period total', () {
    test('the hand fixture reconciles, cash included', () {
      final InstrumentBreakdown breakdown = build();

      // The independent oracle: five numbers added up by a person in the comment
      // at the top of this file.
      expect(breakdown.total.base, Money.parse('3360.00', currency: 'SAR'));
      expect(sumOfBreakdown(breakdown), breakdown.total.base);
      expect(breakdown.reconciles, isTrue);
    });

    test('the cash row holds exactly what has no instrument, and is the reason '
        'the footer closes', () {
      final InstrumentBreakdown breakdown = build();

      expect(breakdown.hasUnassigned, isTrue);
      expect(breakdown.unassignedCount, 1);
      expect(breakdown.unassigned.base, Money.parse('60.00', currency: 'SAR'));

      // The counterfactual, which is what makes this test worth its lines: the
      // instrument rows ALONE do not sum to the period total. Any implementation
      // that omitted the cash row would print 3,300.00 under a heading claiming
      // to be the period total, on the screen whose whole job is traceability.
      expect(
        sumOfBases(<PeriodTotals>[
          for (final InstrumentSlice slice in breakdown.instruments)
            slice.summary.totals,
        ], 'SAR'),
        Money.parse('3300.00', currency: 'SAR'),
      );
    });

    test(
      'with no cash at all the row is hidden and the footer still closes',
      () {
        final InstrumentBreakdown breakdown = build(<LedgerTransaction>[
          for (final LedgerTransaction txn in ledger)
            if (txn.instrument != null) txn,
        ]);

        expect(breakdown.hasUnassigned, isFalse);
        expect(breakdown.total.base, Money.parse('3300.00', currency: 'SAR'));
        expect(breakdown.reconciles, isTrue);
      },
    );

    test('**the cross-bank internal transfer is excluded from BOTH sides** — '
        'the gap P5a\'s corpus never exercised', () {
      final InstrumentBreakdown breakdown = build();

      // If the shared analysis were dropped, `BankTreeBuilder` would re-derive
      // the pairing from each instrument's own slice, find no counterpart, and
      // count the 750.00 outgoing leg as spend on account #10. Both assertions
      // below would then fail — the first by 750.00, the second because the
      // grand total (computed over the whole set, where the pair IS visible)
      // would still exclude it.
      expect(
        breakdown.instruments
            .firstWhere((InstrumentSlice s) => s.summary.instrument.id == 10)
            .summary
            .totals
            .base,
        Money.parse('1000.00', currency: 'SAR'),
        reason: 'the 750.00 transfer leg must not appear on this row',
      );
      expect(breakdown.reconciles, isTrue);
      expect(breakdown.total.base, Money.parse('3360.00', currency: 'SAR'));
    });

    test('a soft-deleted transaction leaves both sides at once', () {
      final InstrumentBreakdown breakdown = build(<LedgerTransaction>[
        ...ledger,
        tx(id: 99, amount: '77.00', isDeleted: true, on: card11),
      ]);
      expect(breakdown.total.base, Money.parse('3360.00', currency: 'SAR'));
      expect(breakdown.reconciles, isTrue);
    });

    test('a foreign purchase with no rate is out of both sides and said so on '
        'both (ADR-009 case 4)', () {
      final InstrumentBreakdown breakdown = build(<LedgerTransaction>[
        ...ledger,
        tx(id: 50, amount: '30.00', currency: 'EUR', on: card11),
      ]);

      expect(breakdown.total.isIncomplete, isTrue);
      final InstrumentSlice card = breakdown.instruments.firstWhere(
        (InstrumentSlice s) => s.summary.instrument.id == 11,
      );
      expect(
        card.summary.totals.isIncomplete,
        isTrue,
        reason:
            'an instrument row must never look more certain than the total it '
            'came from',
      );
      // …and the identity still holds precisely because both sides left it out.
      expect(breakdown.reconciles, isTrue);
      expect(breakdown.total.base, Money.parse('3360.00', currency: 'SAR'));
    });

    test(
      'an empty ledger reconciles trivially rather than dividing by zero',
      () {
        final InstrumentBreakdown breakdown = build(
          const <LedgerTransaction>[],
        );
        expect(breakdown.total.base, isNull);
        expect(breakdown.hasUnassigned, isFalse);
        expect(breakdown.reconciles, isTrue);
        expect(breakdown.isEmpty, isTrue);
      },
    );
  });

  group('AC-E3.2 holds over generated ledgers', () {
    test('200 pseudo-random ledgers reconcile, and EVERY one of them contains '
        'a cross-bank internal transfer', () {
      // A fixed seed: a property test that cannot be reproduced from its own
      // failure message gets marked flaky and deleted.
      final Random random = Random(20260730);
      int runsWithPlantedPair = 0;

      for (int run = 0; run < 200; run++) {
        // At least two banks, always — a cross-bank pair needs two.
        final int bankCount = 2 + random.nextInt(2);
        final List<LedgerBank> generatedBanks = <LedgerBank>[
          for (int b = 1; b <= bankCount; b++) bank(b),
        ];

        // At least one instrument per bank, so the planted pair always has two
        // instruments on two different banks to sit on.
        final List<LedgerInstrument> generatedInstruments =
            <LedgerInstrument>[];
        int nextId = 1;
        for (final LedgerBank b in generatedBanks) {
          final int count = 1 + random.nextInt(3);
          for (int i = 0; i < count; i++) {
            generatedInstruments.add(
              instrument(
                id: nextId++,
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
              // A sixth of rows are cash, which is what exercises the
              // [InstrumentBreakdown.unassigned] row rather than leaving it
              // always empty.
              on: random.nextInt(6) == 0
                  ? null
                  : generatedInstruments[random.nextInt(
                      generatedInstruments.length,
                    )],
            ),
          );
        }

        // **The planted cross-bank pair — the gap this file exists to close.**
        //
        // Two instruments on two *different* banks, equal amounts, minutes apart,
        // opposite directions. `InternalTransferDetector` pairs them only when the
        // analysis runs over the whole set, which is precisely the property
        // AC-E3.2 depends on.
        final LedgerInstrument outLeg = generatedInstruments.firstWhere(
          (LedgerInstrument i) => i.bankId == generatedBanks.first.id,
        );
        final LedgerInstrument inLeg = generatedInstruments.firstWhere(
          (LedgerInstrument i) => i.bankId == generatedBanks[1].id,
        );
        final String transferAmount =
            '${100 + random.nextInt(4000)}.${random.nextInt(100).toString().padLeft(2, '0')}';
        final DateTime transferAt = DateTime.utc(
          2026,
          7,
          1 + random.nextInt(28),
          9,
        );
        transactions.addAll(<LedgerTransaction>[
          tx(
            id: 5000,
            amount: transferAmount,
            type: TransactionType.transferOut,
            affectsSpend: false,
            at: transferAt,
            on: outLeg,
          ),
          tx(
            id: 5001,
            amount: transferAmount,
            direction: MovementDirection.credit,
            type: TransactionType.transferIn,
            affectsSpend: false,
            at: transferAt.add(const Duration(minutes: 4)),
            on: inLeg,
          ),
        ]);
        runsWithPlantedPair += 1;

        final InstrumentBreakdown breakdown = InstrumentBreakdown.of(
          transactions,
          period: july2026,
          banks: generatedBanks,
          instruments: generatedInstruments,
        );

        expect(
          sumOfBreakdown(breakdown),
          breakdown.total.base,
          reason:
              'run $run: AC-E3.2 broken — the instrument rows plus the cash row '
              'no longer sum to the period total',
        );
        expect(breakdown.reconciles, isTrue, reason: 'run $run');

        // A second, independent check that the transfer really is out of the
        // total: recomputing the period figure without the two planted legs must
        // give the same answer.
        final List<LedgerTransaction> withoutPair = <LedgerTransaction>[
          for (final LedgerTransaction txn in transactions)
            if (txn.id != 5000 && txn.id != 5001) txn,
        ];
        expect(
          breakdown.total.base,
          LedgerTotals.spend(withoutPair, period: july2026).base,
          reason:
              'run $run: the internal-transfer pair changed the period total, '
              'so it was not excluded (AC-B11.1)',
        );
      }

      // Guards the guard: if a future refactor stopped planting the pair, the
      // reconciliation assertions above would still pass and this suite would
      // silently regress to P5a\'s narrower coverage.
      expect(runsWithPlantedPair, 200);
    });
  });
}
