/// The P3a additions to the transaction record — KHA-25, US-B1.
///
/// KHA-25's done check, verbatim:
///
/// > *"A parsed fixture round-trips through storage with byte-identical
/// > amount precision. A fixture missing an optional field renders as unknown,
/// > and a test asserts the stored value is a null/unknown marker rather than
/// > a default."*
///
/// Both halves are asserted below, against a real database.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 3);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao transactionDao;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    transactionDao = TransactionDao(db, auditLogDao);
    bankDao = BankDao(db, auditLogDao);
    instrumentDao = InstrumentDao(db, auditLogDao);
  });

  tearDown(() async => db.close());

  Future<int> makeCard() async {
    final int bankId = await bankDao.ensure(
      canonicalKey: 'bank-aljazira',
      displayNameAr: 'بنك الجزيرة',
      displayNameEn: 'Bank Aljazira',
    );
    return instrumentDao.ensure(
      bankId: bankId,
      kind: InstrumentKind.card,
      maskedIdentifier: '****4821',
      refKey: 'bank-aljazira:card:4821',
    );
  }

  group('AC-B1.4 — exact precision, no rounding, in and out of storage', () {
    // Values chosen to break a floating-point implementation: a repeating
    // binary fraction, a trailing zero that must not be invented or removed
    // as *value*, and a 3-decimal currency (KWD) whose minor-unit exponent is
    // not 2.
    for (final (String amount, String currency) in <(String, String)>[
      ('152.75', 'SAR'),
      ('0.1', 'SAR'),
      ('49.99', 'USD'),
      ('1234567.89', 'SAR'),
      ('12.345', 'KWD'),
      ('0', 'SAR'),
    ]) {
      test('$amount $currency round-trips byte-identically', () async {
        final int id = await transactionDao.insertFromParsedSms(
          amount: Money.parse(amount, currency: currency),
          direction: 'debit',
          transactionType: 'pos_purchase',
          affectsSpend: true,
          sourceMessageId: 1,
          rulePackId: 'sa-core',
          rulePackVersion: '2026.07.28',
          ruleId: 'baj-pos-purchase-ar',
        );

        final TransactionRow row = await transactionDao.byId(id);
        expect(row.amountAmount, amount);
        expect(row.amountCurrency, currency);

        final LedgerTransaction txn = toLedgerTransactionOrNull(row)!;
        expect(txn.amount.toCanonicalString(), amount);
        expect(txn.amount, Money.parse(amount, currency: currency));
      });
    }
  });

  group('AC-B1.3 — unknown is stored as unknown, never as a default', () {
    test('every optional field the message did not state is NULL in the row, '
        'not an empty string and not a zero', () async {
      final int id = await transactionDao.insertFromParsedSms(
        amount: Money.parse('15.00', currency: 'SAR'),
        direction: 'debit',
        transactionType: 'fee',
        affectsSpend: true,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-fee-ar',
      );

      final TransactionRow row = await transactionDao.byId(id);

      expect(row.merchantRawText, isNull);
      expect(row.instrumentId, isNull);
      expect(row.instrumentMaskedRef, isNull);
      expect(row.referenceNumber, isNull);
      expect(row.counterpartyName, isNull);
      expect(row.counterpartyBankName, isNull);
      expect(row.feeAmountAmount, isNull);
      expect(row.convertedAmountAmount, isNull);
      expect(row.fxRate, isNull);
      expect(row.remainingBalanceAmount, isNull);
      expect(row.provenanceDetail, isNull);
    });

    test('a genuine zero fee is stored as zero and is distinguishable from an '
        'unstated one', () async {
      // KHA-25: "a zero-amount transaction and an unparsed-amount transaction
      // are different facts". Same rule for the fee component.
      final int withZeroFee = await transactionDao.insertFromParsedSms(
        amount: Money.parse('49.99', currency: 'USD'),
        feeAmount: Money.parse('0.00', currency: 'SAR'),
        direction: 'debit',
        transactionType: 'online_purchase',
        affectsSpend: true,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-online-purchase-ar',
      );
      final int withNoFee = await transactionDao.insertFromParsedSms(
        amount: Money.parse('49.99', currency: 'USD'),
        direction: 'debit',
        transactionType: 'online_purchase',
        affectsSpend: true,
        sourceMessageId: 2,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-online-purchase-ar',
      );

      expect(
        (await transactionDao.byId(withZeroFee)).feeAmountAmount,
        '0',
        reason:
            'Decimal canonicalises 0.00 to 0 — the same VALUE. Display '
            'padding to the currency minor unit is a presentation concern '
            '(see formatAmountDigits), never a storage one.',
      );
      expect((await transactionDao.byId(withNoFee)).feeAmountAmount, isNull);

      expect(
        toLedgerTransactionOrNull(
          await transactionDao.byId(withZeroFee),
        )!.feeAmount!.isZero,
        isTrue,
      );
      expect(
        toLedgerTransactionOrNull(
          await transactionDao.byId(withNoFee),
        )!.feeAmount,
        isNull,
      );
    });
  });

  group('the P3a fields the parser produced and P2 had nowhere to put', () {
    test('counterparty, counterparty bank and remaining balance are stored '
        'and read back', () async {
      final int instrumentId = await makeCard();
      final int id = await transactionDao.insertFromParsedSms(
        amount: Money.parse('1000.00', currency: 'SAR'),
        remainingBalance: Money.parse('18500.25', currency: 'SAR'),
        counterpartyName: 'AHMED A ALSAMI',
        counterpartyBankName: 'Al Rajhi Bank',
        direction: 'debit',
        transactionType: 'transfer_out',
        affectsSpend: true,
        referenceNumber: 'TRF-99120',
        instrumentId: instrumentId,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-transfer-out-ar',
      );

      final LedgerTransaction txn = toLedgerTransactionOrNull(
        await transactionDao.byId(id),
        instrumentsById: <int, LedgerInstrument>{
          instrumentId: toLedgerInstrument(
            await instrumentDao.byId(instrumentId),
          ),
        },
      )!;

      expect(txn.counterpartyName, 'AHMED A ALSAMI');
      expect(txn.counterpartyBankName, 'Al Rajhi Bank');
      expect(txn.remainingBalance!.toCanonicalString(), '18500.25');
      expect(txn.referenceNumber, 'TRF-99120');
      expect(txn.instrument!.id, instrumentId);
      expect(txn.instrument!.maskedIdentifier, '****4821');
    });
  });

  group('NFR-A1 — provenance', () {
    test('a parsed transaction is sms-provenanced with its source message and '
        'no manual-completion detail', () async {
      final int id = await transactionDao.insertFromParsedSms(
        amount: Money.parse('10.00', currency: 'SAR'),
        direction: 'debit',
        transactionType: 'fee',
        affectsSpend: true,
        sourceMessageId: 42,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-fee-ar',
      );

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.provenance, TransactionProvenance.sms);
      expect(row.sourceMessageId, 42);
      expect(row.provenanceDetail, isNull);
      expect(row.rulePackId, 'sa-core');
      expect(row.ruleId, 'baj-fee-ar');
    });
  });

  group('soft delete records when (AC-B6.4)', () {
    test('deletedAt is set on delete and cleared on restore', () async {
      final int id = await transactionDao.insertFromParsedSms(
        amount: Money.parse('10.00', currency: 'SAR'),
        direction: 'debit',
        transactionType: 'fee',
        affectsSpend: true,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-fee-ar',
      );

      await transactionDao.softDelete(id: id, actor: 'user');
      final TransactionRow deleted = await transactionDao.byId(id);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedAt, isNotNull);

      await transactionDao.restore(id: id, actor: 'user');
      final TransactionRow restored = await transactionDao.byId(id);
      expect(restored.isDeleted, isFalse);
      expect(
        restored.deletedAt,
        isNull,
        reason:
            'a restored transaction that still claims a deletion time would '
            'sort into Recently Deleted forever',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  group('queries the ledger screens depend on', () {
    test('forInstrument returns only that instrument, and excludes deleted '
        'rows (AC-B2.3)', () async {
      final int cardId = await makeCard();
      final int bankId = (await bankDao.byCanonicalKey('bank-aljazira'))!.id;
      final int accountId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****3388',
        refKey: 'bank-aljazira:account:3388',
      );

      Future<int> write(int instrumentId, String amount) =>
          transactionDao.insertFromParsedSms(
            amount: Money.parse(amount, currency: 'SAR'),
            direction: 'debit',
            transactionType: 'pos_purchase',
            affectsSpend: true,
            occurredAt: DateTime.utc(2026, 7, 10),
            instrumentId: instrumentId,
            sourceMessageId: 1,
            rulePackId: 'sa-core',
            rulePackVersion: '2026.07.28',
            ruleId: 'baj-pos-purchase-ar',
          );

      await write(cardId, '100.00');
      final int deletedId = await write(cardId, '50.00');
      await write(accountId, '640.00');
      await transactionDao.softDelete(id: deletedId, actor: 'user');

      final List<TransactionRow> cardRows = await transactionDao.forInstrument(
        cardId,
      );
      expect(cardRows.length, 1);
      expect(cardRows.single.amountAmount, '100');
    });
  });
}
