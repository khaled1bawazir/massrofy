/// What a movement means for the totals — KHA-28, KHA-29, AC-B7.1,
/// AC-B10.1/2, AC-B11.1.
///
/// `spend_classification.dart` is the single place the question "does this
/// count as spend?" is answered. These tests pin the answers, and in
/// particular the two that a rule pack must not be able to change.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/spend_classification.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

SpendClassification classify({
  required String type,
  String direction = 'debit',
  bool affectsSpend = true,
  String? transferState,
}) => SpendClassification.of(
  tx(
    id: 1,
    amount: '100.00',
    type: type,
    direction: direction,
    affectsSpend: affectsSpend,
    transferState: transferState,
  ),
  transfers: InternalTransferAnalysis.empty,
);

void main() {
  group('spending', () {
    test('the ordinary debit types all count as spend', () {
      for (final String type in <String>[
        TransactionType.posPurchase,
        TransactionType.onlinePurchase,
        TransactionType.billPayment,
        TransactionType.fee,
        TransactionType.installment,
        TransactionType.accountDebit,
        TransactionType.transferOut,
      ]) {
        expect(
          classify(type: type).movementClass,
          MovementClass.spend,
          reason: type,
        );
      }
    });
  });

  group('AC-B7.1 — a credit reduces spend', () {
    test('a refund is a spend credit', () {
      expect(
        classify(
          type: TransactionType.refund,
          direction: 'credit',
        ).movementClass,
        MovementClass.spendCredit,
      );
    });

    test('a credit arriving on a purchase template still nets against spend — '
        'the money genuinely came back', () {
      expect(
        classify(
          type: TransactionType.posPurchase,
          direction: 'credit',
        ).movementClass,
        MovementClass.spendCredit,
      );
    });

    test('a refund recorded as a DEBIT is a contradiction: excluded and '
        'flagged, never silently added to spend', () {
      final SpendClassification result = classify(type: TransactionType.refund);
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.unclassifiable);
      expect(result.needsReview, isTrue);
    });
  });

  group('AC-B10.1/B10.2 — money in, and money that merely moved', () {
    test('salary and third-party incoming transfers are income', () {
      expect(
        classify(
          type: TransactionType.salaryIncome,
          direction: 'credit',
        ).movementClass,
        MovementClass.income,
      );
      expect(
        classify(
          type: TransactionType.transferIn,
          direction: 'credit',
        ).movementClass,
        MovementClass.income,
      );
    });

    test('an ATM withdrawal is neither spend nor income', () {
      // Treating it as spend double-counts every cash purchase the user later
      // enters by hand (US-B4); treating it as income is nonsense.
      expect(
        classify(type: TransactionType.withdrawal).movementClass,
        MovementClass.cashWithdrawal,
      );
    });

    test('a card repayment is excluded — it settles spend already counted', () {
      final SpendClassification result = classify(
        type: TransactionType.cardRepayment,
        affectsSpend: false,
      );
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.cardRepayment);
    });

    test('a card repayment stays excluded even if a pack claims it is spend — '
        'the type decides, not the flag', () {
      expect(
        classify(type: TransactionType.cardRepayment).movementClass,
        MovementClass.excluded,
      );
    });
  });

  group('AC-B11.1 — the invariant no rule pack can override', () {
    test('a determined internal transfer is excluded even when the pack says '
        'affectsSpend: true and the type is a plain transfer out', () {
      // This is the assertion that matters most in the file. An imported pack
      // (risk R-11) could set any flag it likes; moving money to yourself is
      // still not spending.
      final SpendClassification result = classify(
        type: TransactionType.transferOut,
        transferState: InternalTransferState.internal,
      );
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.internalTransfer);
    });

    test('the incoming leg of an internal transfer is not counted as income '
        'either — the money never left the user', () {
      final SpendClassification result = classify(
        type: TransactionType.transferIn,
        direction: 'credit',
        affectsSpend: false,
        transferState: InternalTransferState.internal,
      );
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.internalTransfer);
    });

    test('AC-B11.2 — a candidate keeps counting as spend, and is flagged', () {
      final SpendClassification result = classify(
        type: TransactionType.transferOut,
        transferState: InternalTransferState.candidate,
      );
      expect(result.movementClass, MovementClass.spend);
      expect(result.needsReview, isTrue);
    });
  });

  group("the pack's flag is a one-way veto", () {
    test('affectsSpend: false is honoured on a spend-shaped type', () {
      final SpendClassification result = classify(
        type: TransactionType.posPurchase,
        affectsSpend: false,
      );
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.packDeclaredNonSpend);
    });
  });

  group('degrading gracefully on the unknown (§5.2)', () {
    test('an unrecognised transaction type is excluded and flagged, not '
        'guessed at', () {
      final SpendClassification result = classify(type: 'crypto_staking');
      expect(result.movementClass, MovementClass.excluded);
      expect(result.exclusionReason, ExclusionReason.unclassifiable);
      expect(
        result.needsReview,
        isTrue,
        reason:
            'NFR-A7: it is recorded and listed, but counting a movement we '
            'cannot name makes a total unexplainable',
      );
    });

    test('an unrecognised direction is excluded and flagged', () {
      final SpendClassification result = classify(
        type: TransactionType.posPurchase,
        direction: 'sideways',
      );
      expect(result.movementClass, MovementClass.excluded);
      expect(result.needsReview, isTrue);
    });
  });

  group('MovementClass.isSpendComponent', () {
    test('only spend and spendCredit make up net spend', () {
      expect(MovementClass.spend.isSpendComponent, isTrue);
      expect(MovementClass.spendCredit.isSpendComponent, isTrue);
      expect(MovementClass.income.isSpendComponent, isFalse);
      expect(MovementClass.cashWithdrawal.isSpendComponent, isFalse);
      expect(MovementClass.excluded.isSpendComponent, isFalse);
    });
  });
}
