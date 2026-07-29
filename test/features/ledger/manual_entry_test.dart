/// **US-B4 — manual entry.** KHA-26, AC-B4.1, AC-B4.2, AC-B4.3, and defect
/// O-QA-2's validation contract.
///
/// AC-B4.2 is the criterion most of this file is about, and it is worth
/// stating why it deserves this much coverage: *"a missing required field
/// blocks saving with a message NAMING the missing field"*. A validator that
/// merely returns false satisfies "blocks saving" and fails the user
/// completely. So every test below asserts **which** field came back, not just
/// that something did.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/manual_entry.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 21);

void main() {
  late AppDatabase db;
  late TransactionDao dao;
  late ManualEntryService service;

  setUp(() {
    db = openPlainTestDatabase();
    dao = TransactionDao(db, AuditLogDao(db, auditChainKey: _testChainKey));
    service = ManualEntryService(transactionDao: dao);
  });

  tearDown(() async => db.close());

  ManualTransactionDraft draft({
    String amount = '85.50',
    String currency = 'SAR',
    DateTime? at,
    String? type = TransactionType.posPurchase,
    String direction = 'debit',
    String? merchant = 'CORNER SHOP',
    int? instrumentId,
  }) => ManualTransactionDraft(
    amountText: amount,
    currencyCode: currency,
    occurredAt: at ?? DateTime.utc(2026, 7, 15, 13),
    transactionType: type,
    direction: direction,
    merchantRawText: merchant,
    instrumentId: instrumentId,
  );

  group('AC-B4.1 — the transaction joins every total and breakdown', () {
    test('a cash purchase is written and counts toward period spend', () async {
      final ManualEntryResult result = await service.add(draft());
      expect(result, isA<ManualEntryAccepted>());

      // Read it back through the same mapper every screen uses, then through
      // the same totals function every figure comes from — so this asserts
      // the row genuinely reaches the number the user sees, not merely that
      // an INSERT happened.
      final List<LedgerTransaction> ledger = toLedgerTransactions(
        await dao.all(),
      );
      final PeriodTotals spend = LedgerTotals.spend(ledger, period: july2026);
      expect(spend.base!.toCanonicalString(), '85.5');
      expect(spend.convertedCount, 1);
    });

    test('a manually entered refund NETS against spend, like any other credit '
        '(US-B7)', () async {
      await service.add(draft());
      await service.add(
        draft(
          amount: '25.50',
          type: TransactionType.refund,
          direction: 'credit',
        ),
      );

      final PeriodTotals spend = LedgerTotals.spend(
        toLedgerTransactions(await dao.all()),
        period: july2026,
      );
      expect(spend.base!.toCanonicalString(), '60');
    });

    test('a manually entered withdrawal is neither spend nor income '
        '(AC-B10.2)', () async {
      await service.add(
        draft(amount: '500.00', type: TransactionType.withdrawal),
      );

      final PeriodReport report = LedgerTotals.report(
        toLedgerTransactions(await dao.all()),
        period: july2026,
      );
      expect(report.spend.isEmpty, isTrue);
      expect(report.income.isEmpty, isTrue);
      expect(report.cashWithdrawals.base!.toCanonicalString(), '500');
    });

    test('a hand-entered outgoing transfer DOES count as spend until proven '
        'internal — the P3a bug this set had', () async {
      await service.add(
        draft(amount: '300.00', type: TransactionType.transferOut),
      );
      final PeriodTotals spend = LedgerTotals.spend(
        toLedgerTransactions(await dao.all()),
        period: july2026,
      );
      // Whether a transfer is internal is a property of the PAIR (AC-B11.2,
      // risk R-7). A form filling in one leg cannot know, so it must not
      // silently drop a genuine third-party payment from spend.
      expect(spend.base!.toCanonicalString(), '300');
    });
  });

  group('AC-B4.2 — validation names the missing field', () {
    test('a missing amount names the amount field, and nothing else', () async {
      final ManualEntryResult result = await service.add(draft(amount: ''));
      final ManualEntryRejected rejected = result as ManualEntryRejected;

      expect(rejected.missingFields, <String>[ManualEntryField.amount]);
      expect(rejected.amountProblem, AmountProblem.missing);
      expect(await dao.all(), isEmpty);
    });

    test('a missing date names the date field', () async {
      final ManualEntryResult result = await service.add(
        ManualTransactionDraft(
          amountText: '10.00',
          currencyCode: 'SAR',
          transactionType: TransactionType.posPurchase,
        ),
      );
      expect(
        (result as ManualEntryRejected).missingFields,
        contains(ManualEntryField.occurredAt),
      );
    });

    test('a missing type names the type field', () async {
      final ManualEntryResult result = await service.add(draft(type: null));
      expect(
        (result as ManualEntryRejected).missingFields,
        contains(ManualEntryField.transactionType),
      );
    });

    test(
      'several missing fields are ALL named at once, not one per attempt',
      () async {
        final ManualEntryResult result = await service.add(
          const ManualTransactionDraft(amountText: '', currencyCode: 'SAR'),
        );
        final ManualEntryRejected rejected = result as ManualEntryRejected;
        expect(
          rejected.missingFields,
          containsAll(<String>[
            ManualEntryField.amount,
            ManualEntryField.occurredAt,
            ManualEntryField.transactionType,
          ]),
        );
      },
    );

    test('an unreadable amount in an UNRECOGNISED currency names both fields '
        '— pointing only at the amount would send the user to fix a number '
        'that was already right', () async {
      final ManualEntryResult result = await service.add(
        draft(amount: '10.00', currency: 'RIYAL'),
      );
      final ManualEntryRejected rejected = result as ManualEntryRejected;
      expect(rejected.missingFields, contains(ManualEntryField.amount));
      expect(rejected.missingFields, contains(ManualEntryField.currency));
      expect(rejected.amountProblem, AmountProblem.unparsable);
    });

    test(
      'an unknown direction is refused rather than defaulted to debit',
      () async {
        final ManualEntryResult result = await service.add(
          draft(direction: 'sideways'),
        );
        expect(
          (result as ManualEntryRejected).missingFields,
          contains(ManualEntryField.direction),
        );
      },
    );
  });

  group('O-QA-2 / the sign convention — the contract this form was written '
      'for', () {
    test('a negative amount is REJECTED, not absolute-valued', () async {
      final ManualEntryResult result = await service.add(
        draft(amount: '-50.00'),
      );
      final ManualEntryRejected rejected = result as ManualEntryRejected;
      expect(rejected.amountProblem, AmountProblem.negative);
      expect(await dao.all(), isEmpty);
    });

    test('a negative amount is NOT reinterpreted as "this is a credit" — that '
        'would invent a refund the bank never issued', () async {
      await service.add(draft(amount: '-50.00'));
      expect(await dao.all(), isEmpty);

      // The direction control is the only way to say "credit", and it works.
      await service.add(
        draft(
          amount: '50.00',
          direction: 'credit',
          type: TransactionType.refund,
        ),
      );
      final TransactionRow row = (await dao.all()).single;
      expect(row.amountAmount, '50');
      expect(row.direction, 'credit');
    });

    test('ZERO is accepted — settled deliberately the other way (KHA-25: '
        'unknown and zero are different facts)', () async {
      final ManualEntryResult result = await service.add(draft(amount: '0.00'));
      expect(result, isA<ManualEntryAccepted>());
      expect((await dao.all()).single.amountAmount, '0');
    });

    test('Arabic-Indic digits are accepted — parsing happens once, in Money, '
        'which an Arabic-first app requires', () async {
      final ManualEntryResult result = await service.add(
        draft(amount: '٨٥٫٥٠'),
      );
      expect(result, isA<ManualEntryAccepted>());
      expect(
        Money.parse(
          (await dao.all()).single.amountAmount,
          currency: 'SAR',
        ).toCanonicalString(),
        '85.5',
      );
    });
  });

  group('AC-B4.3 — visually distinguishable from SMS-derived', () {
    test('provenance is `manual`, which is what drives the badge', () async {
      await service.add(draft());
      final LedgerTransaction txn = toLedgerTransactions(
        await dao.all(),
      ).single;

      expect(txn.provenance, TransactionProvenance.manual);
      expect(txn.isUserEntered, isTrue);
      // AC-B1.2's "show me the original SMS" panel must be able to say
      // honestly that there is none.
      expect(txn.sourceMessageId, isNull);
    });

    test('a completed unparsed message stays `sms` and is ALSO user-entered — '
        'the two manual paths are distinguishable from each other', () async {
      await dao.insertManualCompletion(
        amount: Money.parse('40.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 16),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
        sourceMessageId: 7,
      );
      final LedgerTransaction txn = toLedgerTransactions(
        await dao.all(),
      ).single;

      expect(txn.provenance, TransactionProvenance.sms);
      expect(txn.provenanceDetail, ProvenanceDetail.manualCompletion);
      expect(txn.isUserEntered, isTrue);
      // NFR-A1: the source-message reference survives.
      expect(txn.sourceMessageId, 7);
    });
  });

  group('empty text is "not stated", not an empty-string value (AC-B1.3)', () {
    test('a blank merchant is stored as NULL', () async {
      await service.add(draft(merchant: '   '));
      expect((await dao.all()).single.merchantRawText, isNull);
    });
  });
}
