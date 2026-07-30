/// **QA probes for PR #44 (P5b — KHA-37 reports, KHA-38 search/filter,
/// KHA-122 immediate foreground sweep).**
///
/// Written by qa-tester, measured on `feature/p5b-reports-search-immediate-sweep`
/// @ `4308d7a`. **Zero production code is touched by this file or by the branch
/// it lands on** — every probe reads the shipped implementation.
///
/// ---
///
/// ## What each group is for
///
/// | Group | Purpose |
/// |---|---|
/// | KHA-137 | **Characterises a live High defect.** Locks in the exact shape of the AC-A5.1 redelivery failure I reproduced on a device, so the fix has a definition of done and so the defect cannot be "fixed" by a change that does not address it. |
/// | KHA-139 | Demonstrates, from the QA side, that the corrected internal-transfer fixture *is* load-bearing — the evidence behind that issue's suggested fix. |
/// | Riyadh boundary | The 00:00–03:00 gap the mobile-engineer's self-review caught and fixed in the date picker, which **no test currently covers**. |
/// | AC-E5.2 oracle | The filtered total recomputed by a second path, over realistic-shaped rows. |
///
/// A characterisation probe is not an endorsement. Where a group asserts wrong
/// behaviour it says so loudly and names the issue that must invert it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/ingestion/content_hmac.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_breakdown.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_filter.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../support/ledger_fixtures.dart';

/// An arbitrary 32-byte key. Nothing here is a security assertion; the probes
/// only compare two digests produced with the *same* key.
final List<int> _probeKey = List<int>.generate(32, (int i) => 0xA0 ^ i);

/// The normalised form of one fabricated BAJ Arabic POS purchase. Values are
/// invented — NFR-M3 forbids committing real bank text.
const String _normalisedBody =
    'شراء بطاقة:مدى-****4472 مبلغ:312.40 SAR لدى:QANDA FOODS في:15-07-26 13:20';

LedgerBank _bank(int id) => LedgerBank(
  id: id,
  canonicalKey: 'bank_$id',
  displayNameAr: 'بنك $id',
  displayNameEn: 'Bank $id',
);

void main() {
  // =======================================================================
  //  KHA-137 (HIGH) — AC-A5.1's carrier-retry dedup does not hold
  // =======================================================================
  //
  // Reproduced on a device during this gate: the byte-identical SMS delivered
  // twice, ~43 seconds apart, produced TWO transactions and doubled the month
  // total from −312.40 SAR to −624.80 SAR.
  //   docs/evidence/qa-pr44/06-after-sms-5s.png  → one row, correct
  //   docs/evidence/qa-pr44/07-redelivered.png   → two rows, doubled
  //
  // These probes pin the mechanism rather than the screen, because the
  // mechanism is what the fix has to change.
  group('KHA-137 — the D1 content HMAC is not stable across a redelivery', () {
    test('two deliveries of the SAME body from the SAME sender produce '
        'DIFFERENT hmacs when they arrive at different moments', () {
      // A carrier retry cannot arrive at the same instant as the original —
      // Android stamps each inbox row with its own `date`. On the device the
      // two rows were 43,287 ms apart; 40 s here is the same shape.
      final DateTime firstDelivery = DateTime.utc(2026, 7, 15, 10, 20, 0);
      final DateTime retry = firstDelivery.add(const Duration(seconds: 40));

      String hmacAt(DateTime deliveredAt) => ContentHmac.compute(
        key: _probeKey,
        normalizedBody: _normalisedBody,
        sender: 'BAJ',
        smsTimestampUtc: deliveredAt,
      );

      expect(
        hmacAt(firstDelivery),
        isNot(hmacAt(retry)),
        reason:
            'KHA-137. `content_hmac.dart` says the normalised body is chosen so '
            'that "a carrier redelivery ... would hash differently and dedup '
            'would silently fail" cannot happen — "this is the exact case D1 '
            'exists for". Folding the delivery timestamp into the key '
            'reintroduces that failure: the two digests differ, so '
            '`findByContentHmac` misses and a second transaction is written. '
            'INVERT THIS PROBE WHEN KHA-137 IS FIXED — the two must then be equal.',
      );
    });

    test('the hmac IS stable when only the provider id differs — which is why '
        'the existing race test passes and the device does not', () {
      // `immediate_sweep_race_test.dart`'s redelivery case builds both records
      // through one helper with a fixed `receivedAt` and varies only the
      // provider id. The provider id is not an input to the HMAC at all, so
      // that fixture necessarily observes a suppression the field never gets.
      final DateTime fixed = DateTime.utc(2026, 7, 15, 10, 20);
      final String a = ContentHmac.compute(
        key: _probeKey,
        normalizedBody: _normalisedBody,
        sender: 'BAJ',
        smsTimestampUtc: fixed,
      );
      final String b = ContentHmac.compute(
        key: _probeKey,
        normalizedBody: _normalisedBody,
        sender: 'BAJ',
        smsTimestampUtc: fixed,
      );
      expect(
        a,
        b,
        reason:
            'not a defect — this is the (correct) behaviour the existing test '
            'exercises. It is here so the two probes read side by side and the '
            'unsound variable in that fixture is obvious: `receivedAt`.',
      );
    });

    test('even a ONE-MILLISECOND difference in delivery time defeats the '
        'dedup — so no realistic retry can ever be suppressed', () {
      final DateTime first = DateTime.utc(2026, 7, 15, 10, 20, 0, 0);
      final DateTime oneMsLater = DateTime.utc(2026, 7, 15, 10, 20, 0, 1);

      expect(
        ContentHmac.compute(
          key: _probeKey,
          normalizedBody: _normalisedBody,
          sender: 'BAJ',
          smsTimestampUtc: first,
        ),
        isNot(
          ContentHmac.compute(
            key: _probeKey,
            normalizedBody: _normalisedBody,
            sender: 'BAJ',
            smsTimestampUtc: oneMsLater,
          ),
        ),
        reason:
            'KHA-137. `ContentHmac.compute` folds the timestamp at millisecond '
            'precision, so the tolerance for "the same message" is zero. There '
            'is no delivery-timing window in which D1 fires.',
      );
    });
  });

  // =======================================================================
  //  KHA-139 (MEDIUM) — what a load-bearing cross-bank transfer looks like
  // =======================================================================
  //
  // `instrument_breakdown_test.dart` plants a pair with `affectsSpend: false`
  // on the outgoing leg. The shipped rule pack sets `affectsSpend: TRUE` for
  // transfer_out (assets/rule_packs/sa-core.json — baj-transfer-out-ar,
  // d360-transfer-out-en), so that fixture is excluded by the pack-flag veto
  // in `_spendOrVeto`, never by `InternalTransferDetector`.
  //
  // These probes build the pair the way production would see it and show the
  // analysis genuinely doing the work.
  group('KHA-139 — a REALISTIC cross-bank internal transfer, excluded by the '
      'analysis rather than by a pack flag', () {
    final LedgerInstrument accountBank1 = instrument(id: 10, bankId: 1);
    final LedgerInstrument accountBank2 = instrument(id: 20, bankId: 2);
    final LedgerInstrument cardBank1 = instrument(
      id: 11,
      bankId: 1,
      kind: InstrumentKind.card,
      masked: '****4821',
    );

    final List<LedgerBank> banks = <LedgerBank>[_bank(1), _bank(2)];
    final List<LedgerInstrument> instruments = <LedgerInstrument>[
      accountBank1,
      cardBank1,
      accountBank2,
    ];

    /// One ordinary purchase plus a cross-bank transfer whose two legs share a
    /// bank reference number — `InternalTransferEvidence.referenceMatch`, which
    /// is what promotes a pair from `candidate` to `internal`.
    ///
    /// [sharedReference] false drops the reference, leaving the pair at
    /// `candidate`.
    List<LedgerTransaction> ledger({required bool sharedReference}) =>
        <LedgerTransaction>[
          tx(id: 1, amount: '1250.75', on: cardBank1),
          tx(
            id: 2,
            amount: '3000.00',
            type: TransactionType.transferOut,
            // Production's value. This is the whole point of the probe.
            affectsSpend: true,
            at: DateTime.utc(2026, 7, 15, 10),
            reference: sharedReference ? 'FT26071500918' : null,
            on: accountBank1,
          ),
          tx(
            id: 3,
            amount: '3000.00',
            direction: MovementDirection.credit,
            type: TransactionType.transferIn,
            affectsSpend: false,
            at: DateTime.utc(2026, 7, 15, 10, 4),
            reference: sharedReference ? 'FT26071500918' : null,
            on: accountBank2,
          ),
        ];

    test('with a shared reference the detector rates the pair INTERNAL — the '
        'state the reconciliation arithmetic actually depends on', () {
      final InternalTransferAnalysis analysis = InternalTransferDetector.analyze(
        ledger(sharedReference: true),
      );
      final LedgerTransaction outgoing = ledger(
        sharedReference: true,
      ).firstWhere((LedgerTransaction t) => t.id == 2);

      expect(
        analysis.stateFor(outgoing),
        InternalTransferState.internal,
        reason:
            'this is the assertion `instrument_breakdown_test.dart`\'s '
            '"guard the guard" (`expect(runsWithPlantedPair, 200)`) was meant '
            'to be. That one counts plantings, which is 200 == 200; this one '
            'checks the detector reached a verdict.',
      );
    });

    test('AC-E3.2 still closes with a REALISTIC transfer — the outgoing leg is '
        'off its own instrument row AND off the period total', () {
      final InstrumentBreakdown breakdown = InstrumentBreakdown.of(
        ledger(sharedReference: true),
        period: july2026,
        banks: banks,
        instruments: instruments,
      );

      // Independent oracle: only the 1,250.75 purchase is spend. Both transfer
      // legs are internal (AC-B11.1) and the incoming leg was never spend.
      expect(breakdown.total.base, Money.parse('1250.75', currency: 'SAR'));
      expect(
        breakdown.instruments
            .firstWhere((InstrumentSlice s) => s.summary.instrument.id == 10)
            .summary
            .totals
            .base,
        isNull,
        reason:
            'the 3,000.00 leg is the ONLY movement on account #10, and it is '
            'excluded — so this row has no figure at all, not a zero',
      );
      expect(breakdown.reconciles, isTrue);
    });

    test('**AC-B11.2** — WITHOUT a shared reference the same pair is only a '
        'candidate, and a candidate IS counted as spend', () {
      // Deliberately pinned. This is documented, intended behaviour
      // (`internal_transfer.dart`: "Still counted, and flagged for review"),
      // and nothing at the breakdown level asserted it before. It is also the
      // realistic cross-bank case — two banks rarely issue the same reference —
      // so it is the arithmetic the user most often sees.
      final InstrumentBreakdown breakdown = InstrumentBreakdown.of(
        ledger(sharedReference: false),
        period: july2026,
        banks: banks,
        instruments: instruments,
      );

      // 1,250.75 purchase + the 3,000.00 unproven transfer out.
      expect(
        breakdown.total.base,
        Money.parse('4250.75', currency: 'SAR'),
        reason:
            'an unproven internal transfer keeps counting — the bias is toward '
            'over-stating spend rather than silently hiding money (AC-B11.2). '
            'If this ever changes, AC-B11.2 changed and the PRD must say so.',
      );
      // And the footer identity holds either way, which is the real invariant.
      expect(breakdown.reconciles, isTrue);
    });

    test('dropping the shared analysis is undetectable HERE, and the reason is '
        'benign — BankTreeBuilder re-derives over the same whole set', () {
      // Documented so KHA-139's Finding 2 is reproducible: `InstrumentBreakdown.of`
      // hands `build` the WHOLE live list, and `build` falls back to
      // `transfers ?? InternalTransferDetector.analyze(transactions)`.
      final List<LedgerTransaction> rows = ledger(sharedReference: true);
      final List<BankTreeNode> withAnalysis = BankTreeBuilder.build(
        banks: banks,
        instruments: instruments,
        transactions: rows,
        period: july2026,
        transfers: InternalTransferDetector.analyze(rows),
      );
      final List<BankTreeNode> withoutAnalysis = BankTreeBuilder.build(
        banks: banks,
        instruments: instruments,
        transactions: rows,
        period: july2026,
      );

      Money? figure(List<BankTreeNode> tree, int instrumentId) {
        for (final BankTreeNode node in tree) {
          for (final InstrumentSummary s in <InstrumentSummary>[
            ...node.accounts,
            ...node.cards,
          ]) {
            if (s.instrument.id == instrumentId) {
              return s.totals.base;
            }
          }
        }
        return null;
      }

      expect(
        figure(withoutAnalysis, 10),
        figure(withAnalysis, 10),
        reason:
            'identical, because the fallback analyses the same whole set. The '
            '`transfers:` parameter is a consistency/efficiency aid at this call '
            'site, NOT a correctness requirement — so the docstring claiming a '
            'test would catch its removal should be corrected instead of a test '
            'being written that cannot exist.',
      );
    });
  });

  // =======================================================================
  //  The Riyadh date-picker boundary (self-review fix, currently untested)
  // =======================================================================
  //
  // `filter_widgets.dart`'s `_pickDate` was changed during the engineer's
  // self-review from `DateTime.utc(y, m, d)` to
  // `RiyadhCalendar.riyadhLocalToUtc(...)`. Riyadh is UTC+3, so a UTC-midnight
  // bound is three hours LATE — every transaction between 00:00 and 03:00
  // Riyadh time on the range's first day falls outside a filter the user
  // believes includes that whole day.
  //
  // The fix is in the shipped code and I verified it by reading; no test
  // covered it, so a refactor could silently reinstate the bug. These probes
  // assert the property at the model level (the picker's private `_pickDate`
  // is not reachable from a test, but the bound it constructs is).
  group('AC-E5.2 — a date-range bound must be RIYADH midnight, not UTC '
      'midnight', () {
    final CategoryResolver resolver = CategoryResolver.defaults();

    /// 01:00 on 3 July 2026, Riyadh wall clock = 2026-07-02T22:00Z.
    final DateTime earlyMorningRiyadh = RiyadhCalendar.riyadhLocalToUtc(
      DateTime.utc(2026, 7, 3, 1, 0),
    );

    /// 23:30 on 3 July 2026, Riyadh = 2026-07-03T20:30Z. The other end of the
    /// same calendar day, which must also be inside a "3 July to 3 July" range.
    final DateTime lateEveningRiyadh = RiyadhCalendar.riyadhLocalToUtc(
      DateTime.utc(2026, 7, 3, 23, 30),
    );

    List<LedgerTransaction> rows() => <LedgerTransaction>[
      tx(id: 1, amount: '48.25', at: earlyMorningRiyadh),
      tx(id: 2, amount: '910.00', at: lateEveningRiyadh),
    ];

    test('a 3-July-to-3-July range built the way _pickDate builds it keeps '
        'BOTH ends of the Riyadh day', () {
      // Exactly `filter_widgets.dart`'s construction: Riyadh midnight, plus one
      // day for the exclusive upper bound.
      final DateTime dayStartUtc = RiyadhCalendar.riyadhLocalToUtc(
        DateTime.utc(2026, 7, 3),
      );
      final TransactionFilter filter = TransactionFilter(
        fromUtc: dayStartUtc,
        toUtcExclusive: dayStartUtc.add(const Duration(days: 1)),
      );

      final FilterOutcome outcome = filter.apply(rows(), resolver: resolver);
      expect(
        outcome.transactions.map((LedgerTransaction t) => t.id).toList(),
        <int>[1, 2],
        reason:
            'both purchases happened on 3 July in Riyadh, which is the only '
            'calendar the user has. Dropping either is data the user filtered '
            'FOR and did not get back.',
      );
    });

    test('**the regression this pins** — a UTC-midnight bound silently drops '
        'the 01:00 Riyadh purchase', () {
      // The pre-self-review construction, reproduced here so the defect has a
      // shape. If `_pickDate` ever reverts to `DateTime.utc(y, m, d)`, this is
      // the behaviour that returns.
      final DateTime utcMidnight = DateTime.utc(2026, 7, 3);
      final TransactionFilter naive = TransactionFilter(
        fromUtc: utcMidnight,
        toUtcExclusive: utcMidnight.add(const Duration(days: 1)),
      );

      final FilterOutcome outcome = naive.apply(rows(), resolver: resolver);
      expect(
        outcome.transactions.map((LedgerTransaction t) => t.id).toList(),
        <int>[2],
        reason:
            'the 48.25 purchase at 01:00 Riyadh is 22:00Z on 2 July, so a '
            'UTC-midnight lower bound excludes it — a three-hour window on '
            'every range start, losing exactly the late-night spending a user '
            'is most likely to be checking on.',
      );
    });

    test('the picker reads a stored bound back through the SAME wall clock, so '
        'the chip cannot name the day before', () {
      // `filter_widgets.dart` displays `toRiyadhWallClock(fromUtc)`; this is the
      // round trip that has to survive the 21:00Z-is-tomorrow case.
      final DateTime dayStartUtc = RiyadhCalendar.riyadhLocalToUtc(
        DateTime.utc(2026, 7, 3),
      );
      expect(dayStartUtc, DateTime.utc(2026, 7, 2, 21));
      expect(
        RiyadhCalendar.toRiyadhWallClock(dayStartUtc),
        DateTime.utc(2026, 7, 3),
        reason:
            'stored as 2 July 21:00Z, shown as 3 July. A chip that read the raw '
            'UTC value would say "2 July" for a range the user set to 3 July.',
      );

      // And the upper bound, which the screen shows as `to - 1 day`.
      final DateTime toExclusive = dayStartUtc.add(const Duration(days: 1));
      expect(
        RiyadhCalendar.toRiyadhWallClock(
          toExclusive.subtract(const Duration(days: 1)),
        ),
        DateTime.utc(2026, 7, 3),
      );
    });
  });

  // =======================================================================
  //  AC-E5.2 — the filtered total, recomputed by a second path
  // =======================================================================
  group('AC-E5.2 — the displayed total reflects the FILTERED subset', () {
    final CategoryResolver resolver = CategoryResolver.defaults();
    final LedgerInstrument mada = instrument(
      id: 41,
      bankId: 1,
      kind: InstrumentKind.card,
      masked: '****4472',
    );
    final LedgerInstrument visa = instrument(
      id: 42,
      bankId: 1,
      kind: InstrumentKind.card,
      masked: '****9002',
    );

    // Realistic shapes, mirroring the rows I put through the app on the
    // emulator during this gate (docs/evidence/qa-pr44/14-search-noon.png).
    final List<LedgerTransaction> ledger = <LedgerTransaction>[
      tx(id: 1, amount: '312.40', on: mada), // QANDA FOODS
      tx(id: 2, amount: '660.00', on: visa), // NOON.COM purchase
      tx(
        id: 3,
        amount: '60.00',
        direction: MovementDirection.credit,
        type: TransactionType.refund,
        on: visa,
      ), // NOON.COM refund
      tx(id: 4, amount: '89.90', on: mada), // an unrelated row
    ];

    test('an instrument filter yields a total equal to a HAND-COMPUTED sum of '
        'exactly the visible rows', () {
      final TransactionFilter filter = TransactionFilter(
        instrumentIds: <int>{visa.id},
      );
      final FilterOutcome outcome = filter.apply(ledger, resolver: resolver);

      expect(outcome.transactions.length, 2);
      expect(outcome.wasActive, isTrue);

      final PeriodTotals filtered = LedgerTotals.spend(
        outcome.transactions,
        period: july2026,
      );
      // The oracle: 660.00 purchase MINUS the 60.00 refund (US-B7), added up
      // here by hand rather than by the code under test.
      expect(
        filtered.base,
        Money.parse('600.00', currency: 'SAR'),
        reason:
            'this is the "Filtered total −600.00 SAR" I read off the device '
            'against the same four rows',
      );

      // And it is NOT the period total, which is the half of AC-E5.2 that a
      // naive implementation gets wrong.
      final PeriodTotals whole = LedgerTotals.spend(ledger, period: july2026);
      expect(whole.base, Money.parse('1002.30', currency: 'SAR'));
      expect(filtered.base, isNot(whole.base));
    });

    test('the filtered subset and its complement sum back to the whole — the '
        'filter cannot invent or lose money', () {
      final TransactionFilter filter = TransactionFilter(
        instrumentIds: <int>{visa.id},
      );
      final FilterOutcome kept = filter.apply(ledger, resolver: resolver);
      final Set<int> keptIds = kept.transactions
          .map((LedgerTransaction t) => t.id)
          .toSet();
      final List<LedgerTransaction> complement = <LedgerTransaction>[
        for (final LedgerTransaction t in ledger)
          if (!keptIds.contains(t.id)) t,
      ];

      expect(
        Money.sum(<Money>[
          LedgerTotals.spend(kept.transactions, period: july2026).base!,
          LedgerTotals.spend(complement, period: july2026).base!,
        ], currency: 'SAR'),
        LedgerTotals.spend(ledger, period: july2026).base,
        reason:
            'a partition of the rows must partition the money. This is the '
            'NFR-A6 traceability property applied to the filter rather than to '
            'a report footer.',
      );
    });

    test('**NFR-S4** — the filter never carries its own values into a string', () {
      final TransactionFilter filter = TransactionFilter(
        query: 'QANDA',
        minAmount: Money.parse('300.00', currency: 'SAR'),
        fromUtc: DateTime.utc(2026, 7, 3),
        instrumentIds: <int>{mada.id},
      );
      final String rendered = filter.toString();
      for (final String secret in <String>['QANDA', '300', '2026-07-03', '41']) {
        expect(
          rendered.contains(secret),
          isFalse,
          reason:
              'found "$secret" in TransactionFilter.toString(). A toString ends '
              'up in debuggers, assertion messages and (by accident) logs, and a '
              'search query is a record of what the user was looking for in '
              'their financial life. Rendered: $rendered',
        );
      }
    });
  });
}
