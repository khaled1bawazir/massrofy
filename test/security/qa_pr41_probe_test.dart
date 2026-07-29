/// **QA probe suite for PR #41 (P5a)** — KHA-35, KHA-36, KHA-113, KHA-114,
/// KHA-115.
///
/// Written by qa-tester. **Zero production code is changed by this file**; it
/// only exercises what PR #41 shipped, and it deliberately attacks the claims
/// the PR body makes rather than re-stating the engineer's own tests.
///
/// TIER: personal — so this is a focused set, not an exhaustive suite. Each
/// probe exists because the shipped tests leave a specific hole, and each one
/// says which hole.
///
/// ---
///
/// ## Where the shipped tests stop, and why these probes start there
///
/// **NFR-A6 (the money invariant).** `totals_reconciliation_test.dart` is a
/// genuinely good three-layer test, but its own doc comment claims the 200
/// generated ledgers cover *"an internal transfer split across two banks"* and
/// they do not: the generator only ever emits `posPurchase` and `refund`, all
/// in SAR. That matters, because `LedgerTotals.report`'s own doc names
/// transfer-slicing as *"the most plausible way to reintroduce AC-B11.1 as a
/// bug"*, and currency conversion is where additivity classically breaks.
/// Probes A1–A4 close both gaps and add an independent business oracle.
///
/// **KHA-113 (the app never asked for SMS permission).** The shipped gate tests
/// prove the *screens* are reached and that `request()` is called. Nothing
/// anywhere in `test/` references `foregroundSweepProvider` — the provider that
/// actually turns permission into a ledger. So the exact real-world case a human
/// hit ("I granted it in Android Settings, does the import run?") is untested.
/// Probes B1–B3.
///
/// **NFR-S3 (the lock-gate stack collapse).** `p5a_lock_collapses_stack_test`
/// re-implements `_AppLockGateway`'s collapse inside the test file and drives
/// the copy. It would keep passing if the production line were deleted. Probe C1
/// drives the real `MassrofyApp`.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/app.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/data/dao/app_settings_dao.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/spend_classification.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/providers/app_providers.dart';
import 'package:massrofy/presentation/providers/ingestion_providers.dart';

import '../features/ingestion/support/load_bundled_pack.dart';
import '../support/app_test_harness.dart';
import '../support/fake_sms_source.dart';
import '../support/ledger_fixtures.dart';
import '../support/plain_test_database.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

LedgerBank probeBank(int id) => LedgerBank(
  id: id,
  canonicalKey: 'bank_$id',
  displayNameAr: 'بنك $id',
  displayNameEn: 'Bank $id',
);

/// Sums the base figures of several [PeriodTotals], returning null when none of
/// them had one. Same semantics as `PeriodTotals.base` so an absence is never
/// silently turned into a zero and called agreement.
Money? sumBases(Iterable<PeriodTotals> parts, {String currency = 'SAR'}) {
  final List<Money> bases = <Money>[
    for (final PeriodTotals p in parts)
      if (p.base != null) p.base!,
  ];
  return bases.isEmpty ? null : Money.sum(bases, currency: currency);
}

int sumUnconvertedCounts(Iterable<PeriodTotals> parts) => parts.fold<int>(
  0,
  (int running, PeriodTotals p) => running + p.unconvertedCount,
);

/// Every instrument-bearing transaction, i.e. the subset the bank tree can
/// possibly account for. Cash (no instrument) is the one place the chain
/// deliberately does not close.
List<LedgerTransaction> onInstruments(List<LedgerTransaction> all) =>
    <LedgerTransaction>[
      for (final LedgerTransaction t in all)
        if (t.instrument != null) t,
    ];

void main() {
  // =========================================================================
  // A — NFR-A6: the total-reconciliation chain, attacked where the shipped
  //     test does not reach.
  // =========================================================================
  group('PROBE A — NFR-A6, instrument → bank → period, adversarially', () {
    test(
      'A1: an internal transfer split across TWO banks is excluded from both '
      'bank totals AND the period total, and the chain still closes',
      () {
        // The case `totals_reconciliation_test.dart` claims its generated sweep
        // covers and does not: the two legs of a transfer live on instruments
        // at *different* banks, so a detector run per instrument slice would
        // see one leg, find no pair, and count 2,000.00 as spend at Bank 1 —
        // inflating the bank total while the period total (analysed over the
        // whole set) stayed correct. That is a broken chain the user would meet
        // by drilling in from Home.
        final LedgerInstrument bank1Account = instrument(id: 10, bankId: 1);
        final LedgerInstrument bank1Card = instrument(
          id: 11,
          bankId: 1,
          kind: InstrumentKind.card,
          masked: '****4472',
        );
        final LedgerInstrument bank2Account = instrument(id: 20, bankId: 2);
        final LedgerInstrument bank2Card = instrument(
          id: 21,
          bankId: 2,
          kind: InstrumentKind.card,
          masked: '****9002',
        );

        // A shared reference number is what upgrades a *candidate* pair to
        // determined `internal` (see `internal_transfer.dart`), so this is the
        // realistic shape of a proven own-account transfer.
        final List<LedgerTransaction> ledger = <LedgerTransaction>[
          tx(
            id: 1,
            amount: '2000.00',
            type: TransactionType.transferOut,
            reference: 'TRF20260715991',
            on: bank1Account,
          ),
          tx(
            id: 2,
            amount: '2000.00',
            direction: MovementDirection.credit,
            type: TransactionType.transferIn,
            reference: 'TRF20260715991',
            on: bank2Account,
          ),
          tx(id: 3, amount: '512.75', on: bank1Card),
          tx(id: 4, amount: '287.25', on: bank2Card),
        ];

        // Sanity: the detector really did rule both legs internal. Without
        // this, the assertions below could pass for the wrong reason (e.g. the
        // transfer counted at both banks and cancelled out).
        final InternalTransferAnalysis analysis =
            InternalTransferDetector.analyze(ledger);
        expect(
          analysis.stateFor(ledger[0]),
          InternalTransferState.internal,
          reason:
              'the probe is only meaningful if the pair is DETERMINED '
              'internal; a candidate still counts as spend by design',
        );

        final List<BankTreeNode> tree = BankTreeBuilder.build(
          banks: <LedgerBank>[probeBank(1), probeBank(2)],
          instruments: <LedgerInstrument>[
            bank1Account,
            bank1Card,
            bank2Account,
            bank2Card,
          ],
          transactions: ledger,
          period: july2026,
        );

        final BankTreeNode bank1 = tree.firstWhere(
          (BankTreeNode n) => n.bank.id == 1,
        );
        final BankTreeNode bank2 = tree.firstWhere(
          (BankTreeNode n) => n.bank.id == 2,
        );

        // Hand-computed: 512.75 at Bank 1's card, 287.25 at Bank 2's card, and
        // nothing at either account because the transfer is internal.
        expect(
          bank1.totals.base,
          Money.parse('512.75', currency: 'SAR'),
          reason:
              'Bank 1 must NOT show the 2,000.00 outgoing leg — moving money '
              'to yourself is not spending (AC-B11.1)',
        );
        expect(bank2.totals.base, Money.parse('287.25', currency: 'SAR'));
        expect(bank1.accounts.single.totals.base, isNull);
        expect(bank2.accounts.single.totals.base, isNull);

        // The chain: instruments → bank → period, exact Money equality.
        expect(
          sumBases(<PeriodTotals>[
            bank1.accounts.single.totals,
            bank1.cards.single.totals,
          ]),
          bank1.totals.base,
        );
        expect(
          sumBases(tree.map((BankTreeNode n) => n.totals)),
          LedgerTotals.spend(ledger, period: july2026).base,
        );
        expect(
          LedgerTotals.spend(ledger, period: july2026).base,
          Money.parse('800.00', currency: 'SAR'),
          reason: '512.75 + 287.25, computed by hand from the fixture above',
        );
      },
    );

    test('A2: the chain closes exactly under currency conversion, and the '
        '"N not converted" counts reconcile too', () {
      // FX is where additivity classically breaks: if a per-bank figure were
      // produced by converting a *summed* native amount, sum-of-rounded and
      // rounded-of-sum would disagree by fractions of a riyal and the bank
      // pages would stop adding up to Home. The shipped generated sweep is
      // SAR-only, so nothing pins this.
      final LedgerInstrument bank1Card = instrument(
        id: 11,
        bankId: 1,
        kind: InstrumentKind.card,
        masked: '****4472',
      );
      final LedgerInstrument bank2Card = instrument(
        id: 21,
        bankId: 2,
        kind: InstrumentKind.card,
        masked: '****9002',
      );

      final List<LedgerTransaction> ledger = <LedgerTransaction>[
        // Amounts chosen so the converted figures do not divide evenly — a
        // rounding bug would surface as a one-halala disagreement.
        tx(
          id: 1,
          amount: '100.00',
          currency: 'USD',
          type: TransactionType.onlinePurchase,
          convertedAmount: '375.07',
          on: bank1Card,
        ),
        tx(
          id: 2,
          amount: '33.33',
          currency: 'USD',
          type: TransactionType.onlinePurchase,
          convertedAmount: '125.03',
          on: bank1Card,
        ),
        tx(
          id: 3,
          amount: '200.00',
          currency: 'EUR',
          type: TransactionType.onlinePurchase,
          convertedAmount: '812.11',
          on: bank2Card,
        ),
        // Unconvertible: a foreign purchase whose message quoted no rate.
        // ADR-009 requires it be left OUT of the base figure and counted.
        tx(
          id: 4,
          amount: '77.00',
          currency: 'GBP',
          type: TransactionType.onlinePurchase,
          on: bank2Card,
        ),
      ];

      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[probeBank(1), probeBank(2)],
        instruments: <LedgerInstrument>[bank1Card, bank2Card],
        transactions: ledger,
        period: july2026,
      );
      final PeriodTotals period = LedgerTotals.spend(ledger, period: july2026);

      // Hand-computed: 375.07 + 125.03 + 812.11 = 1,312.21, with the GBP
      // purchase absent from the base figure and declared instead.
      expect(period.base, Money.parse('1312.21', currency: 'SAR'));
      expect(period.unconvertedCount, 1);

      expect(
        sumBases(tree.map((BankTreeNode n) => n.totals)),
        period.base,
        reason:
            'sum-of-converted must equal converted-of-sum; if a figure were '
            'produced by converting an aggregate, this is where it breaks',
      );
      // The honesty clause has to reconcile as well. A bank page saying
      // "+1 not converted" while Home says nothing is missing is an NFR-A6
      // traceability failure even though every base figure agrees.
      expect(
        sumUnconvertedCounts(tree.map((BankTreeNode n) => n.totals)),
        period.unconvertedCount,
      );
      expect(
        sumUnconvertedCounts(<PeriodTotals>[
          for (final BankTreeNode n in tree)
            for (final InstrumentSummary s in <InstrumentSummary>[
              ...n.accounts,
              ...n.cards,
            ])
              s.totals,
        ]),
        period.unconvertedCount,
      );
    });

    test(
      'A3: 200 generated ledgers with the transaction types the shipped sweep '
      'never emits — transfers, income, cash, fees, three currencies',
      () {
        // A different seed and a much richer generator than
        // `totals_reconciliation_test.dart`'s, on purpose: its generator emits
        // only posPurchase/refund in SAR, so the exclusion rules that actually
        // decide what "spend" means are never exercised by the property test
        // that claims to cover the cases nobody thought of.
        final Random random = Random(41041);

        for (int run = 0; run < 200; run++) {
          final int bankCount = 1 + random.nextInt(3);
          final List<LedgerBank> banks = <LedgerBank>[
            for (int b = 1; b <= bankCount; b++) probeBank(b),
          ];

          final List<LedgerInstrument> instruments = <LedgerInstrument>[];
          int nextId = 1;
          for (final LedgerBank b in banks) {
            for (int i = 0; i < random.nextInt(4); i++) {
              instruments.add(
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

          const List<String> types = <String>[
            TransactionType.posPurchase,
            TransactionType.onlinePurchase,
            TransactionType.billPayment,
            TransactionType.fee,
            TransactionType.installment,
            TransactionType.accountDebit,
            TransactionType.withdrawal,
            TransactionType.cardRepayment,
            TransactionType.unknown,
          ];
          const List<String> creditTypes = <String>[
            TransactionType.refund,
            TransactionType.salaryIncome,
            TransactionType.transferIn,
          ];

          final List<LedgerTransaction> transactions = <LedgerTransaction>[];
          int nextTxId = 1000;

          String amount() =>
              '${random.nextInt(5000)}.'
              '${random.nextInt(100).toString().padLeft(2, '0')}';

          LedgerInstrument? pick() => instruments.isEmpty
              ? null
              : instruments[random.nextInt(instruments.length)];

          for (int t = 0; t < random.nextInt(20); t++) {
            final bool credit = random.nextInt(4) == 0;
            final bool foreign = random.nextInt(5) == 0;
            final String native = amount();
            transactions.add(
              tx(
                id: nextTxId++,
                amount: native,
                currency: foreign ? (random.nextBool() ? 'USD' : 'EUR') : 'SAR',
                // A foreign row sometimes carries a rate and sometimes does
                // not, so both the converted and the unconverted paths run.
                convertedAmount: foreign
                    ? (random.nextBool() ? amount() : null)
                    : null,
                direction: credit
                    ? MovementDirection.credit
                    : MovementDirection.debit,
                type: credit
                    ? creditTypes[random.nextInt(creditTypes.length)]
                    : types[random.nextInt(types.length)],
                fee: random.nextInt(6) == 0 ? '15.00' : null,
                isDeleted: random.nextInt(8) == 0,
                at: random.nextInt(9) == 0
                    ? DateTime.utc(2026, 6, 1 + random.nextInt(28), 12)
                    : DateTime.utc(2026, 7, 1 + random.nextInt(28), 12),
                on: random.nextInt(6) == 0 ? null : pick(),
              ),
            );
          }

          // Internal transfers, deliberately across whichever two instruments
          // the generator happens to pick — frequently at two different banks,
          // which is the slicing trap.
          for (int p = 0; p < random.nextInt(3); p++) {
            if (instruments.length < 2) {
              break;
            }
            final String legAmount = amount();
            final String reference = 'TRF$run$p';
            final LedgerInstrument out =
                instruments[random.nextInt(instruments.length)];
            final LedgerInstrument into =
                instruments[random.nextInt(instruments.length)];
            final DateTime when = DateTime.utc(
              2026,
              7,
              1 + random.nextInt(28),
              9,
            );
            transactions.add(
              tx(
                id: nextTxId++,
                amount: legAmount,
                type: TransactionType.transferOut,
                reference: reference,
                at: when,
                on: out,
              ),
            );
            transactions.add(
              tx(
                id: nextTxId++,
                amount: legAmount,
                direction: MovementDirection.credit,
                type: TransactionType.transferIn,
                reference: reference,
                at: when,
                on: into,
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
              sumBases(<PeriodTotals>[
                for (final InstrumentSummary s in node.accounts) s.totals,
                for (final InstrumentSummary s in node.cards) s.totals,
              ]),
              node.totals.base,
              reason: 'run $run, bank ${node.bank.id}: instrument → bank',
            );
            expect(
              sumUnconvertedCounts(<PeriodTotals>[
                for (final InstrumentSummary s in node.accounts) s.totals,
                for (final InstrumentSummary s in node.cards) s.totals,
              ]),
              node.totals.unconvertedCount,
              reason: 'run $run, bank ${node.bank.id}: unconverted counts',
            );
          }

          expect(
            sumBases(tree.map((BankTreeNode n) => n.totals)),
            LedgerTotals.spend(
              onInstruments(transactions),
              period: july2026,
              // The whole set, because a slice cannot see both legs of a
              // transfer — the same argument `BankTreeBuilder` makes.
              transfers: InternalTransferDetector.analyze(transactions),
            ).base,
            reason: 'run $run: bank → period',
          );
        }
      },
    );

    test('A4: business oracle — the period total equals an independent '
        'recomputation over a realistic 17-transaction month', () {
      // "A total appeared" is not a pass. This recomputes the answer by a
      // completely different route — a hand-written fold that applies the
      // exclusion rules directly from the PRD, with no call into
      // `LedgerTotals` — and asserts exact equality with what the app shows.
      final LedgerInstrument current = instrument(
        id: 10,
        bankId: 1,
        masked: '****3388',
      );
      final LedgerInstrument visa = instrument(
        id: 11,
        bankId: 1,
        kind: InstrumentKind.card,
        masked: '****4472',
      );
      final LedgerInstrument mada = instrument(
        id: 21,
        bankId: 2,
        kind: InstrumentKind.card,
        masked: '****9002',
      );

      final List<LedgerTransaction> month = <LedgerTransaction>[
        tx(id: 1, amount: '312.40', on: visa), // POS
        tx(id: 2, amount: '89.95', on: visa), // POS
        tx(
          id: 3,
          amount: '1240.00',
          type: TransactionType.billPayment,
          on: current,
        ),
        tx(id: 4, amount: '45.00', type: TransactionType.fee, on: current),
        tx(
          id: 5,
          amount: '2350.75',
          type: TransactionType.installment,
          on: current,
        ),
        tx(id: 6, amount: '18.40', on: mada),
        tx(
          id: 7,
          amount: '660.00',
          type: TransactionType.onlinePurchase,
          on: mada,
        ),
        // A refund nets DOWN (US-B7).
        tx(
          id: 8,
          amount: '89.95',
          direction: MovementDirection.credit,
          type: TransactionType.refund,
          on: visa,
        ),
        // Salary — income, not negative spend.
        tx(
          id: 9,
          amount: '18500.00',
          direction: MovementDirection.credit,
          type: TransactionType.salaryIncome,
          on: current,
        ),
        // Cash out — its own line, never spend (AC-B10.2).
        tx(
          id: 10,
          amount: '1000.00',
          type: TransactionType.withdrawal,
          on: current,
        ),
        // Card repayment — already counted when the card was used.
        tx(
          id: 11,
          amount: '3000.00',
          type: TransactionType.cardRepayment,
          on: current,
        ),
        // Proven internal transfer, both legs.
        tx(
          id: 12,
          amount: '5000.00',
          type: TransactionType.transferOut,
          reference: 'TRF778',
          on: current,
        ),
        tx(
          id: 13,
          amount: '5000.00',
          direction: MovementDirection.credit,
          type: TransactionType.transferIn,
          reference: 'TRF778',
          on: mada,
        ),
        // Third-party transfer out — genuinely spend.
        tx(
          id: 14,
          amount: '750.00',
          type: TransactionType.transferOut,
          reference: 'TRF901',
          on: current,
        ),
        // Soft-deleted — out of every total until restored.
        tx(id: 15, amount: '999.99', isDeleted: true, on: visa),
        // Last month — outside the period.
        tx(
          id: 16,
          amount: '410.00',
          at: DateTime.utc(2026, 6, 20, 10),
          on: visa,
        ),
        // Cash, no instrument at all (US-B4).
        tx(id: 17, amount: '60.00'),
      ];

      // ---- The independent recomputation -------------------------------
      // Deliberately re-derives "what counts" from the PRD rather than
      // asking the code: US-B10/B11 exclude income, cash withdrawals, card
      // repayments and internal transfers; US-B8 excludes deleted rows;
      // AC-E1.4 excludes other months; US-B7 nets refunds down.
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            for (final LedgerTransaction t in month)
              if (!t.isDeleted) t,
          ]);
      const Set<String> notSpend = <String>{
        TransactionType.salaryIncome,
        TransactionType.transferIn,
        TransactionType.withdrawal,
        TransactionType.cardRepayment,
        TransactionType.unknown,
      };
      Money oracle = Money.zero('SAR');
      int counted = 0;
      for (final LedgerTransaction t in month) {
        if (t.isDeleted) {
          continue;
        }
        if (!july2026.contains(t.occurredAt)) {
          continue;
        }
        if (notSpend.contains(t.transactionType)) {
          continue;
        }
        if (analysis.stateFor(t) == InternalTransferState.internal) {
          continue;
        }
        oracle = oracle + signedForSpend(t.amount, direction: t.direction);
        counted++;
      }

      // And a literal, so a bug in the oracle itself cannot hide a bug in
      // the app. Written out from the fixture by hand:
      //   312.40 + 89.95 + 1240.00 + 45.00 + 2350.75 + 18.40 + 660.00
      //   − 89.95 (refund) + 750.00 (third-party transfer) + 60.00 (cash)
      //   = 5,436.55
      expect(
        oracle,
        Money.parse('5436.55', currency: 'SAR'),
        reason: 'the oracle itself must agree with the hand-written literal',
      );
      expect(counted, 10);

      final PeriodTotals shown = LedgerTotals.spend(month, period: july2026);
      expect(
        shown.base,
        oracle,
        reason:
            'the figure on Home must equal the answer these 17 transactions '
            'actually produce, recomputed by a different path',
      );
      expect(shown.convertedCount, counted);

      // And the drill-down still reconciles against it, minus the cash row
      // the banks screen has nowhere to put.
      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[probeBank(1), probeBank(2)],
        instruments: <LedgerInstrument>[current, visa, mada],
        transactions: month,
        period: july2026,
      );
      expect(
        sumBases(tree.map((BankTreeNode n) => n.totals)),
        Money.parse('5376.55', currency: 'SAR'),
        reason: '5,436.55 − 60.00 cash, which sits under no bank',
      );
    });

    test('A5: a CANDIDATE transfer (paired, but no matching reference) still '
        'counts as spend — the deliberate over-statement bias, pinned', () {
      // Asserted here because it is the inverse of A1 and the two together
      // are what stop a future "fix" from silently excluding unproven pairs,
      // which would UNDER-state spend invisibly (risk R-7).
      final LedgerInstrument a = instrument(id: 10, bankId: 1);
      final LedgerInstrument b = instrument(id: 20, bankId: 2);
      final List<LedgerTransaction> ledger = <LedgerTransaction>[
        tx(id: 1, amount: '1500.00', type: TransactionType.transferOut, on: a),
        tx(
          id: 2,
          amount: '1500.00',
          direction: MovementDirection.credit,
          type: TransactionType.transferIn,
          on: b,
        ),
      ];

      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(ledger);
      expect(analysis.stateFor(ledger[0]), InternalTransferState.candidate);

      final PeriodTotals total = LedgerTotals.spend(ledger, period: july2026);
      expect(
        total.base,
        Money.parse('1500.00', currency: 'SAR'),
        reason:
            'an unproven pair must keep counting and shout (AC-B11.2), not '
            'quietly disappear — an under-stated total is invisible',
      );
      expect(
        SpendClassification.of(ledger[0], transfers: analysis).needsReview,
        isTrue,
      );
    });
  });

  // =========================================================================
  // B — KHA-113: does permission actually turn into a ledger?
  // =========================================================================
  group('PROBE B — KHA-113, the import must run however permission arrived', () {
    late AppDatabase db;
    late UnlockedDatabaseSession session;
    late FakeSmsSource inbox;
    late FakeSmsPermissionService permissions;
    late ProviderContainer container;

    /// A real D360 purchase, in the format the bundled pack parses.
    RawSmsRecord purchase(int n) => RawSmsRecord(
      providerId: n,
      address: 'D360',
      body:
          'D360: Purchase of SAR ${100 + n}.00 with Mada Debit Card ending '
          '4472 at MERCHANT $n on ${(n % 28) + 1 < 10 ? '0' : ''}'
          '${(n % 28) + 1}/07/2026 1${n % 10}:00',
      receivedAt: DateTime.utc(2026, 7, 10 + n, 12),
    );

    setUp(() {
      db = openPlainTestDatabase();
      final AuditLogDao auditLogDao = AuditLogDao(
        db,
        auditChainKey: List<int>.generate(32, (int i) => i),
      );
      session = UnlockedDatabaseSession(
        database: db,
        auditLogDao: auditLogDao,
        transactionDao: TransactionDao(db, auditLogDao),
        rawMessageDao: RawMessageDao(db),
        appSettingsDao: AppSettingsDao(db),
      );
      inbox = FakeSmsSource(<RawSmsRecord>[
        purchase(1),
        purchase(2),
        purchase(3),
      ]);
      permissions = FakeSmsPermissionService();

      container = ProviderContainer(
        overrides: [
          unlockedDatabaseSessionProvider.overrideWith(
            (Ref ref) async => session,
          ),
          smsPermissionServiceProvider.overrideWithValue(permissions),
          smsSourceProvider.overrideWithValue(inbox),
          // The only reason this is overridden: the real provider reads the
          // pack through `rootBundle`, which `flutter test` does not serve.
          // Same pack, loaded from disk.
          activeRulePacksProvider.overrideWith(
            (Ref ref) async => <RulePack>[loadBundledRulePack()],
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('B1: **the human\'s real scenario** — permission granted OUTSIDE the '
        'app (Android Settings), never through the rationale screen, and the '
        'initial import still runs', () async {
      // The onboarding gate short-circuits straight to the app shell in this
      // case (`permission.allowsIngestion`), so `request()` is never called
      // and `onboarding_complete` is never written. Nothing in the shipped
      // tests then proves ingestion starts. This is that proof.
      permissions.current = SmsPermissionStatus.granted;

      final IngestionRunResult? result = await container.read(
        foregroundSweepProvider.future,
      );

      expect(
        result,
        isNotNull,
        reason:
            'the sweep is the only thing that turns a granted permission '
            'into a ledger; a null result means nothing ran',
      );
      expect(permissions.requestCalls, 0, reason: 'granted out of band');

      final List<TransactionRow> rows = await session.transactionDao
          .watchLive()
          .first;
      expect(
        rows,
        hasLength(3),
        reason:
            'all three inbox messages must have become transactions — this '
            'is KHA-113\'s "the value proposition activates" in one line',
      );
    });

    test(
      'B2: the control — with permission DENIED the sweep writes nothing, so '
      'B1 is known to be about the permission',
      () async {
        permissions.current = SmsPermissionStatus.denied;

        final IngestionRunResult? result = await container.read(
          foregroundSweepProvider.future,
        );

        expect(result, isNull);
        final List<TransactionRow> rows = await session.transactionDao
            .watchLive()
            .first;
        expect(rows, isEmpty);
      },
    );

    test(
      'B3: granting LATER (out of band, then a foreground) starts the import '
      'on the very next sweep — no relaunch, no onboarding replay',
      () async {
        permissions.current = SmsPermissionStatus.denied;
        await container.read(foregroundSweepProvider.future);
        expect(await session.transactionDao.watchLive().first, isEmpty);

        // The user leaves, grants in Settings, comes back. `app.dart`'s resume
        // handler invalidates both providers; this is that pair of calls.
        permissions.current = SmsPermissionStatus.granted;
        container.invalidate(smsPermissionStatusProvider);
        container.invalidate(foregroundSweepProvider);

        final IngestionRunResult? result = await container.read(
          foregroundSweepProvider.future,
        );
        expect(result, isNotNull);
        expect(await session.transactionDao.watchLive().first, hasLength(3));
      },
    );
  });

  // =========================================================================
  // C — NFR-S3 against the REAL production widget.
  // =========================================================================
  group('PROBE C — NFR-S3, the lock collapses the real app\'s stack', () {
    testWidgets(
      'C1: a route pushed over MassrofyApp\'s home is gone after a lock — '
      'driven through the production `MassrofyApp`, not a copy of it',
      (WidgetTester tester) async {
        // `p5a_lock_collapses_stack_test.dart` re-implements the gateway inside
        // the test file, so deleting `_collapseToLockGate()` from `app.dart`
        // would not fail it. This probe pumps the real widget.
        final TestSession testSession = TestSession.open();
        addTearDown(testSession.close);
        final _DrivableLock lock = _DrivableLock();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appLockControllerProvider.overrideWith(() => lock),
              unlockedDatabaseSessionProvider.overrideWith(
                (Ref ref) async => testSession.session,
              ),
              smsPermissionServiceProvider.overrideWithValue(
                FakeSmsPermissionService(current: SmsPermissionStatus.granted),
              ),
              smsSourceProvider.overrideWithValue(
                FakeSmsSource(const <RawSmsRecord>[]),
              ),
              activeRulePacksProvider.overrideWith(
                (Ref ref) async => <RulePack>[loadBundledRulePack()],
              ),
            ],
            child: const MassrofyApp(),
          ),
        );
        await pumpHostFrames(tester);

        // Push a screen with a money figure on it, exactly as Banks → Bank
        // detail does.
        final NavigatorState navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaitedPush(navigator);
        await pumpHostFrames(tester);
        expect(find.text('BANK DETAIL — 12,400.00 SAR'), findsOneWidget);

        lock.lockNow();
        await pumpHostFrames(tester);

        expect(
          find.text('BANK DETAIL — 12,400.00 SAR'),
          findsNothing,
          reason:
              'NFR-S3: after a lock nothing may remain drawn above the gate. '
              'This fails if `_collapseToLockGate` is removed from app.dart',
        );

        await disposeHost(tester);
      },
    );
  });
}

/// Pushes a screen carrying a figure, so its survival after a lock is visible.
void unawaitedPush(NavigatorState navigator) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: Center(child: Text('BANK DETAIL — 12,400.00 SAR')),
      ),
    ),
  );
}

/// A lock controller a probe can drive. Starts unlocked.
class _DrivableLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(status: AppLockStatus.unlocked);

  void lockNow() => state = const AppLockState(status: AppLockStatus.locked);
}
