/// **KHA-80 — AC-B11.2's other half: a transfer that cannot even become a
/// candidate must still be flagged.** Risk R-7.
///
/// ---
///
/// AC-B11.2, verbatim:
///
/// > *"Given the app cannot determine whether a transfer is to the user's own
/// > account or to a third party, when it is processed, then it is **flagged
/// > for review** rather than silently classified either way."*
///
/// P3b-1 met this for transfers the detector could **pair** but not prove
/// (`candidate`). It did not meet it for transfers the detector could not pair
/// at all — a cross-currency near-match, or a leg whose instrument never
/// resolved. Those fell through into ordinary spend carrying no flag, even
/// though `internal_transfer.dart`'s own doc comment promised one for the
/// cross-currency case.
///
/// The arithmetic was never wrong: spend is over-stated, never under-stated,
/// which is this app's deliberate bias. What was missing is the *honesty*
/// half — the user was never told the figure might include a movement to their
/// own account, so the error was invisible rather than correctable.
///
/// ## The flag fires on evidence, not on ignorance
///
/// The final group is as important as the first two. A rule that flagged every
/// unpaired transfer would fire on most of them early in the app's life (R-7's
/// bootstrapping problem), and a review inbox that lists everything is a
/// review inbox nobody opens. The flag requires an actual near-match partner.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/spend_classification.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

void main() {
  final LedgerInstrument current = instrument(id: 1);
  final LedgerInstrument savings = instrument(id: 2, masked: '****1157');

  /// QA's PROBE C case (a): 2,000.00 SAR out of the current account and
  /// 533.19 USD into savings, same reference, five minutes apart.
  List<LedgerTransaction> crossCurrencyPair({String? outState}) =>
      <LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          reference: 'TRX-FX',
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
          transferState: outState,
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
      ];

  /// QA's PROBE C case (b): the incoming leg's message carried too few digits
  /// to key on, so its instrument never resolved.
  List<LedgerTransaction> halfResolvedPair() => <LedgerTransaction>[
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
      at: DateTime.utc(2026, 7, 10, 9, 2),
    ),
  ];

  group('KHA-80 case (a) — a cross-currency near-match', () {
    test('is still counted as spend on no invented rate (ADR-009 holds)', () {
      final PeriodReport report = LedgerTotals.report(
        crossCurrencyPair(),
        period: july2026,
      );
      expect(report.spend.base!.toCanonicalString(), '2000');
    });

    test(
      'is now FLAGGED, which is what internal_transfer.dart always claimed',
      () {
        final InternalTransferAnalysis analysis =
            InternalTransferDetector.analyze(crossCurrencyPair());

        expect(
          analysis.unpairableReasonFor(crossCurrencyPair().first),
          TransferReviewReason.crossCurrencyNearMatch,
        );
      },
    );

    test('BOTH legs are flagged — the incoming one inflates income by the '
        'same movement', () {
      final PeriodReport report = LedgerTotals.report(
        crossCurrencyPair(),
        period: july2026,
      );
      expect(report.needsReviewCount, 2);
    });

    test('the classification carries the SPECIFIC reason, so the inbox can '
        'use the right sentence', () {
      final List<LedgerTransaction> pair = crossCurrencyPair();
      final SpendClassification classification = SpendClassification.of(
        pair.first,
        transfers: InternalTransferDetector.analyze(pair),
      );
      expect(classification.needsReview, isTrue);
      expect(
        classification.transferReviewReason,
        TransferReviewReason.crossCurrencyNearMatch,
      );
    });

    test(
      'the pair is NOT netted — no rate was invented to make them match',
      () {
        final InternalTransferAnalysis analysis =
            InternalTransferDetector.analyze(crossCurrencyPair());
        expect(analysis.links, isEmpty);
      },
    );
  });

  group('KHA-80 case (b) — a leg whose instrument never resolved (R-7 in its '
      'purest form)', () {
    test('is still counted as spend — the documented safe bias', () {
      final PeriodReport report = LedgerTotals.report(
        halfResolvedPair(),
        period: july2026,
      );
      expect(report.spend.base!.toCanonicalString(), '2000');
    });

    test('is now flagged with the unresolved-instrument reason', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(halfResolvedPair());
      expect(
        analysis.unpairableReasonFor(halfResolvedPair().first),
        TransferReviewReason.unresolvedInstrument,
      );
      expect(
        analysis.unpairableReasonFor(halfResolvedPair().last),
        TransferReviewReason.unresolvedInstrument,
      );
    });

    test('the review count is 2, not 0 (the exact PROBE C1 assertion, '
        'inverted)', () {
      expect(
        LedgerTotals.report(
          halfResolvedPair(),
          period: july2026,
        ).needsReviewCount,
        2,
      );
    });

    test('the amounts must match exactly — without a resolved instrument, '
        'amount and time are the ONLY evidence there is', () {
      final List<LedgerTransaction> notAMatch = <LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '1999.00', // different movement
          direction: 'credit',
          type: TransactionType.transferIn,
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
      ];
      expect(
        LedgerTotals.report(notAMatch, period: july2026).needsReviewCount,
        0,
      );
    });
  });

  group('the flag fires on EVIDENCE, not on every unpaired transfer', () {
    test('a lone third-party transfer with no counterpart anywhere is NOT '
        'flagged — it is correctly a payment', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '750.00',
          type: TransactionType.transferOut,
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
      ], period: july2026);

      expect(report.spend.base!.toCanonicalString(), '750');
      expect(
        report.needsReviewCount,
        0,
        reason:
            'flagging every unpaired transfer would fill the review '
            'inbox on a new install and make it worthless (R-7)',
      );
    });

    test('a near-match OUTSIDE the pairing window is not flagged — two '
        'transfers a week apart are unrelated', () {
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
          amount: '533.19',
          currency: 'USD',
          direction: 'credit',
          type: TransactionType.transferIn,
          on: savings,
          at: DateTime.utc(2026, 7, 17, 9),
        ),
      ], period: july2026);
      expect(report.needsReviewCount, 0);
    });

    test('a properly PAIRED transfer is unaffected — it is excluded, not '
        'flagged as unpairable (AC-B11.1 still holds)', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
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
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
      ], period: july2026);

      expect(report.spend.isEmpty, isTrue);
      expect(report.needsReviewCount, 0);
    });

    test('neither leg resolving is not a near-match — there is no evidence at '
        'all, only two unknowns', () {
      final PeriodReport report = LedgerTotals.report(<LedgerTransaction>[
        tx(
          id: 1,
          amount: '2000.00',
          type: TransactionType.transferOut,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '2000.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          at: DateTime.utc(2026, 7, 10, 9, 2),
        ),
      ], period: july2026);
      expect(report.needsReviewCount, 0);
    });

    test('a deleted transfer never produces a flag — it is out of every total '
        'and every question (US-B8)', () {
      final List<LedgerTransaction> withDeleted = <LedgerTransaction>[
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
          at: DateTime.utc(2026, 7, 10, 9, 2),
          isDeleted: true,
        ),
      ];
      expect(
        LedgerTotals.report(withDeleted, period: july2026).needsReviewCount,
        0,
      );
    });
  });

  group('a persisted decision suppresses the flag (KHA-78 durability)', () {
    test('once the user marks a cross-currency leg external, it stops being '
        'raised — the app does not argue with them', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(
            crossCurrencyPair(outState: InternalTransferState.external),
          );

      final LedgerTransaction ruled = crossCurrencyPair(
        outState: InternalTransferState.external,
      ).first;
      expect(analysis.unpairableReasonFor(ruled), isNull);
    });

    test('and the transaction stops contributing to the review count', () {
      final PeriodReport report = LedgerTotals.report(
        crossCurrencyPair(outState: InternalTransferState.external),
        period: july2026,
      );
      // Only the still-undecided incoming leg remains flagged.
      expect(report.needsReviewCount, 1);
    });
  });
}
