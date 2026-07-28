/// ADR-017 duplicate detection, as a table of inputs and expected verdicts.
///
/// `DuplicatePolicy.decide` is pure — no database, no clock, no I/O — which
/// is what makes this table possible. Linear KHA-21's done check asks for
/// exactly this shape: *"corpus tests cover all three cases and pass. A test
/// asserts no code path deletes a transaction as a duplicate without explicit
/// user confirmation."*
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';

DuplicateCandidate candidate({
  int id = 1,
  String instrument = '****4472',
  String amount = '89.00',
  String currency = 'SAR',
  DateTime? occurredAt,
  String? reference,
  String? merchant = 'BALAD COFFEE',
  String type = 'pos_purchase',
}) => DuplicateCandidate(
  transactionId: id,
  transactionType: type,
  instrumentMaskedRef: instrument,
  amount: Money.parse(amount, currency: currency),
  occurredAt: occurredAt ?? DateTime.utc(2026, 7, 28, 9),
  referenceNumber: reference,
  merchantRawText: merchant,
);

void main() {
  group('the safety property, asserted directly (KHA-21 done check)', () {
    test('DuplicateAction has no "delete" case — there is no verdict this '
        'policy can return that removes an existing transaction', () {
      // Deliberately an assertion about the *type*, not about behaviour.
      // A future change that wanted to auto-remove would have to add an
      // enum case here, in the open, and this test would fail and force
      // the conversation ADR-017 says must happen.
      expect(DuplicateAction.values, <DuplicateAction>[
        DuplicateAction.accept,
        DuplicateAction.suppress,
        DuplicateAction.acceptAndFlag,
      ]);
    });
  });

  group('D2 — the bank\'s own reference number', () {
    test('same reference + same instrument is flagged, not removed', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****1157',
        incomingAmount: Money.parse('2000.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 26, 7, 2),
        incomingReferenceNumber: 'D360-TRF-556231',
        incomingMerchant: null,
        incomingType: 'transfer_out',
        existing: <DuplicateCandidate>[
          candidate(
            id: 7,
            instrument: '****1157',
            amount: '2000.00',
            reference: 'D360-TRF-556231',
            merchant: null,
            type: 'transfer_out',
          ),
        ],
      );

      expect(decision.tier, DuplicateTier.referenceNumber);
      expect(decision.action, DuplicateAction.acceptAndFlag);
      expect(decision.matchedTransactionId, 7);
    });

    test('the same reference on a DIFFERENT instrument is not a match', () {
      // Reference numbers are only unique within an issuer's own namespace;
      // treating a collision across two cards as the same movement would
      // flag two genuinely unrelated transfers.
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****9999',
        incomingAmount: Money.parse('2000.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 26, 7, 2),
        incomingReferenceNumber: 'D360-TRF-556231',
        incomingMerchant: null,
        incomingType: 'transfer_out',
        existing: <DuplicateCandidate>[
          candidate(
            instrument: '****1157',
            amount: '2000.00',
            reference: 'D360-TRF-556231',
            merchant: null,
          ),
        ],
      );

      expect(decision.action, DuplicateAction.accept);
    });
  });

  group('D3 — the heuristic tier', () {
    test('same instrument, amount, merchant, within the window → flagged', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 5),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(decision.tier, DuplicateTier.heuristic);
      expect(decision.action, DuplicateAction.acceptAndFlag);
      expect(decision.reviewReason, ReviewReason.possibleDuplicate);
    });

    test('AC-A5.3 — outside the 15-minute window, two identical purchases are '
        'both plainly accepted, not even flagged', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 40),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(decision.action, DuplicateAction.accept);
    });

    test('a different merchant at the same amount and time is not a match', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'ANOTHER SHOP',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(decision.action, DuplicateAction.accept);
    });

    test('the same NUMBER in a different currency is never a match — ADR-002 '
        'doing its job inside dedup', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: Money.parse('89.00', currency: 'USD'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[
          candidate(amount: '89.00', currency: 'SAR'),
        ],
      );

      expect(
        decision.action,
        DuplicateAction.accept,
        reason:
            'a cross-currency comparison that silently succeeded is exactly '
            'the class of error the Money type exists to prevent',
      );
    });

    test('a different instrument is never a match', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****8821',
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(decision.action, DuplicateAction.accept);
    });
  });

  group('missing data never becomes a guess', () {
    test('no amount → accept, never "probably a duplicate"', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: null,
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(
        decision.action,
        DuplicateAction.accept,
        reason:
            'a transaction we cannot compare is not thereby a duplicate — '
            'inferring one from absent data is how a real charge disappears',
      );
    });

    test('no instrument → accept', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: null,
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[candidate()],
      );

      expect(decision.action, DuplicateAction.accept);
    });

    test('an existing row with no occurredAt is skipped, not crashed on', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4472',
        incomingAmount: Money.parse('89.00', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 28, 9, 2),
        incomingReferenceNumber: null,
        incomingMerchant: 'BALAD COFFEE',
        incomingType: 'pos_purchase',
        existing: <DuplicateCandidate>[
          DuplicateCandidate(
            transactionId: 3,
            transactionType: 'pos_purchase',
            instrumentMaskedRef: '****4472',
            amount: Money.parse('89.00', currency: 'SAR'),
            merchantRawText: 'BALAD COFFEE',
          ),
        ],
      );

      expect(decision.action, DuplicateAction.accept);
    });
  });

  group('the P2 scope boundary, recorded as a test rather than a comment', () {
    test(
      'authorisationTypes is empty in this build, and D3 still works without '
      'it via merchant equality',
      () {
        // Neither sampled bank's nine observed message types (PRD §3.4)
        // includes a distinct authorisation template, so populating this set
        // would mean inventing one. The rule consults the set so that adding
        // a type later is the entire change — no logic edit. Until then, an
        // auth/posting pair is caught by merchant equality instead, which the
        // D3 test above covers.
        expect(DuplicatePolicy.authorisationTypes, isEmpty);
      },
    );
  });
}
