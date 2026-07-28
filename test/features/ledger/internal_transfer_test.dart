/// Internal transfers — KHA-29, US-B11, AC-B11.1, AC-B11.2, risk R-7.
///
/// The invariant under test is the one `docs/PRD.md`, `docs/architecture.md`
/// and `docs/build-plan.md` all state independently: **moving money to
/// yourself is not spending**. The interesting half is the *other* clause —
/// when the app cannot prove a transfer is internal it must say so rather than
/// resolve the doubt in either direction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

final LedgerInstrument current = instrument(id: 1, masked: '****3388');
final LedgerInstrument savings = instrument(id: 2, masked: '****1157');
final LedgerInstrument card = instrument(
  id: 3,
  kind: 'card',
  masked: '****9013',
);

void main() {
  group('AC-B11.1 — a proven pair is internal', () {
    test('two legs on different own instruments sharing a reference number '
        'are determined internal', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '2000.00',
              type: TransactionType.transferOut,
              reference: 'TRX-99001',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '2000.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              affectsSpend: false,
              reference: 'TRX-99001',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9, 1),
            ),
          ]);

      expect(analysis.links, hasLength(1));
      expect(
        analysis.links.single.evidence,
        InternalTransferEvidence.referenceMatch,
      );
      expect(analysis.links.single.isDetermined, isTrue);
      expect(
        analysis.stateFor(
          tx(id: 1, amount: '2000.00', type: TransactionType.transferOut),
        ),
        InternalTransferState.internal,
      );
    });

    test('reference numbers match case-insensitively — the two legs come from '
        'two separately-formatted templates', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '500.00',
              type: TransactionType.transferOut,
              reference: 'd360-trf-556231',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '500.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: ' D360-TRF-556231 ',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 12),
            ),
          ]);

      expect(
        analysis.links.single.evidence,
        InternalTransferEvidence.referenceMatch,
      );
    });

    test('the legs may be up to 24 hours apart — a cross-bank transfer posts '
        'the credit the next working day', () {
      final InternalTransferAnalysis withinWindow =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '750.00',
              type: TransactionType.transferOut,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '750.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R1',
              on: savings,
              at: DateTime.utc(2026, 7, 11, 8),
            ),
          ]);
      expect(withinWindow.links, hasLength(1));

      final InternalTransferAnalysis outsideWindow =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '750.00',
              type: TransactionType.transferOut,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '750.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R1',
              on: savings,
              at: DateTime.utc(2026, 7, 12, 9),
            ),
          ]);
      expect(
        outsideWindow.links,
        isEmpty,
        reason:
            'a window long enough to pair anything would start pairing '
            'unrelated same-amount transfers',
      );
    });
  });

  group('AC-B11.2 — an unproven pair is a candidate, not a decision', () {
    test('matching amount and time without a shared reference gives a '
        'candidate, which still counts as spend', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '1200.00',
              type: TransactionType.transferOut,
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '1200.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              on: savings,
              at: DateTime.utc(2026, 7, 10, 10),
            ),
          ]);

      expect(
        analysis.links.single.evidence,
        InternalTransferEvidence.amountAndTime,
      );
      expect(analysis.links.single.isDetermined, isFalse);
      expect(
        analysis.stateFor(
          tx(id: 1, amount: '1200.00', type: TransactionType.transferOut),
        ),
        InternalTransferState.candidate,
        reason:
            'architecture §4.2: candidates do not change spend totals until '
            'confirmed. An over-stated total is visible and correctable; an '
            'under-stated one is invisible.',
      );
    });
  });

  group('what never pairs, and why each exclusion matters', () {
    test('a transfer whose instrument could not be resolved is never paired — '
        'we know nothing about whose account it hit', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '300.00',
              type: TransactionType.transferOut,
              reference: 'R1',
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '300.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R1',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
          ]);
      expect(analysis.links, isEmpty);
    });

    test('the same instrument cannot transfer to itself — otherwise a bank '
        'that sends both an "out" and an "in" message for one leg would '
        'delete real spend from the total', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '300.00',
              type: TransactionType.transferOut,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '300.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
          ]);
      expect(analysis.links, isEmpty);
    });

    test('different currencies never pair — netting them would need a rate, '
        'and inventing one is forbidden (ADR-009)', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '100.00',
              currency: 'USD',
              type: TransactionType.transferOut,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '100.00',
              type: TransactionType.transferIn,
              direction: 'credit',
              reference: 'R1',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
          ]);
      expect(analysis.links, isEmpty);
    });

    test('a soft-deleted leg never pairs — a row the user threw away must not '
        'silently remove a live transfer from the total', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '300.00',
              type: TransactionType.transferOut,
              reference: 'R1',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '300.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R1',
              on: savings,
              at: DateTime.utc(2026, 7, 10, 9),
              isDeleted: true,
            ),
          ]);
      expect(analysis.links, isEmpty);
    });

    test('a purchase is not a transfer, however well it matches', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(id: 1, amount: '300.00', on: current, reference: 'R1'),
            tx(
              id: 2,
              amount: '300.00',
              direction: 'credit',
              type: TransactionType.refund,
              on: savings,
              reference: 'R1',
            ),
          ]);
      expect(analysis.links, isEmpty);
    });
  });

  group('pairing is one-to-one and deterministic', () {
    test('three same-amount transfers do not produce contradictory pairings, '
        'and the strongest evidence wins', () {
      // Without one-to-one matching this produces a different total depending
      // on iteration order — the kind of bug that is nearly impossible to
      // reproduce and destroys trust in a banking figure.
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        tx(
          id: 1,
          amount: '500.00',
          type: TransactionType.transferOut,
          on: current,
          at: DateTime.utc(2026, 7, 10, 9),
        ),
        tx(
          id: 2,
          amount: '500.00',
          type: TransactionType.transferOut,
          reference: 'REF-B',
          on: current,
          at: DateTime.utc(2026, 7, 10, 10),
        ),
        tx(
          id: 3,
          amount: '500.00',
          direction: 'credit',
          type: TransactionType.transferIn,
          reference: 'REF-B',
          on: savings,
          at: DateTime.utc(2026, 7, 10, 10, 1),
        ),
      ];

      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(rows);

      expect(analysis.links, hasLength(1));
      expect(analysis.links.single.outTransactionId, 2);
      expect(analysis.links.single.inTransactionId, 3);
      expect(
        analysis.linkFor(1),
        isNull,
        reason:
            'transaction 1 has no partner left; a second pairing would double-'
            'count the same incoming leg',
      );

      // Re-running over a reversed list must produce the same answer.
      final InternalTransferAnalysis again = InternalTransferDetector.analyze(
        rows.reversed,
      );
      expect(again.links.single.groupId, analysis.links.single.groupId);
    });

    test('the group id is derived from the two ids, so it is stable across '
        'rebuilds', () {
      expect(
        InternalTransferDetector.groupIdFor(
          outTransactionId: 7,
          inTransactionId: 9,
        ),
        'itl:7:9',
      );
    });
  });

  group('a persisted decision outranks a derived one', () {
    test('a user-confirmed internal transfer stays internal even with no '
        'partner in the slice', () {
      // The screen must not silently overrule the user by re-deriving.
      expect(
        InternalTransferAnalysis.empty.stateFor(
          tx(
            id: 1,
            amount: '400.00',
            type: TransactionType.transferOut,
            on: current,
            transferState: InternalTransferState.internal,
          ),
        ),
        InternalTransferState.internal,
      );
    });

    test(
      'a user-marked external transfer is not re-derived into a candidate',
      () {
        final InternalTransferAnalysis analysis =
            InternalTransferDetector.analyze(<LedgerTransaction>[
              tx(
                id: 1,
                amount: '600.00',
                type: TransactionType.transferOut,
                on: current,
                at: DateTime.utc(2026, 7, 10, 9),
                transferState: InternalTransferState.external,
              ),
              tx(
                id: 2,
                amount: '600.00',
                direction: 'credit',
                type: TransactionType.transferIn,
                on: savings,
                at: DateTime.utc(2026, 7, 10, 10),
              ),
            ]);

        expect(
          analysis.stateFor(
            tx(
              id: 1,
              amount: '600.00',
              type: TransactionType.transferOut,
              transferState: InternalTransferState.external,
            ),
          ),
          InternalTransferState.external,
        );
      },
    );

    test('an unrecognised persisted state falls back to the derived one '
        '(§5.2 forward compatibility)', () {
      expect(
        InternalTransferAnalysis.empty.stateFor(
          tx(
            id: 1,
            amount: '400.00',
            type: TransactionType.transferOut,
            transferState: 'quantum',
          ),
        ),
        isNull,
      );
    });
  });

  group('a card is a valid leg too', () {
    test('an account-to-card movement pairs like any other', () {
      final InternalTransferAnalysis analysis =
          InternalTransferDetector.analyze(<LedgerTransaction>[
            tx(
              id: 1,
              amount: '800.00',
              type: TransactionType.transferOut,
              reference: 'R9',
              on: current,
              at: DateTime.utc(2026, 7, 10, 9),
            ),
            tx(
              id: 2,
              amount: '800.00',
              direction: 'credit',
              type: TransactionType.transferIn,
              reference: 'R9',
              on: card,
              at: DateTime.utc(2026, 7, 10, 9, 5),
            ),
          ]);
      expect(analysis.links, hasLength(1));
    });
  });
}
