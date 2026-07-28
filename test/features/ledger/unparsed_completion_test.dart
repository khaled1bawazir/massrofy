/// **AC-A4.2 / KHA-64 (first half)** — completing an unparsed SMS.
///
/// KHA-64's done check for this half:
///
/// > *"A fixture that lands in the review queue can be completed into a
/// > transaction that appears in period totals, carries SMS provenance with
/// > its source-message reference, and leaves the queue."*
///
/// All three clauses are asserted here, plus AC-B4.2's "saving is blocked
/// with a specific message naming the missing field" and NFR-A2's audit
/// requirement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/unparsed_completion.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 5);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late UnparsedCompletionService service;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(db, auditLogDao);
    service = UnparsedCompletionService(
      database: db,
      transactionDao: transactionDao,
      rawMessageDao: rawMessageDao,
    );
  });

  tearDown(() async => db.close());

  /// Puts a message in the review queue the way the pipeline does.
  Future<int> queueUnparsedMessage() => rawMessageDao.insert(
    smsProviderId: '901',
    sender: 'BAJ',
    receivedAt: DateTime.utc(2026, 7, 20, 9),
    sanitizedText: SmsSanitizer.sanitize('خصم من حسابك. الرصيد المتبقي 500'),
    contentHmac: 'hmac-901',
    bankId: 'bank-aljazira',
    classification: 'financial_unparsed',
    unparsedReason: 'required_field_missing',
    unparsedRuleId: 'baj-account-debit-ar',
  );

  UnparsedCompletionDraft draftFor(
    int messageId, {
    String amount = '75.50',
    String currency = 'SAR',
    DateTime? occurredAt,
    String? type = 'account_debit',
  }) => UnparsedCompletionDraft(
    rawMessageId: messageId,
    amountText: amount,
    currencyCode: currency,
    occurredAt: occurredAt ?? DateTime.utc(2026, 7, 20, 9),
    transactionType: type,
    merchantRawText: 'Cash withdrawal at branch',
  );

  group('AC-A4.2 — the happy path', () {
    test('a queued message becomes a real transaction and leaves the '
        'queue', () async {
      final int messageId = await queueUnparsedMessage();
      expect(await rawMessageDao.watchReviewQueue().first, hasLength(1));

      final CompletionResult result = await service.complete(
        draftFor(messageId),
      );

      expect(result, isA<CompletionAccepted>());
      expect(
        await rawMessageDao.watchReviewQueue().first,
        isEmpty,
        reason: 'AC-A4.2 — "the item then leaves the review list"',
      );
    });

    test('the message row is reclassified, never deleted — the dedup key and '
        'the original text both survive (AC-B1.2)', () async {
      final int messageId = await queueUnparsedMessage();
      await service.complete(draftFor(messageId));

      final RawMessageRow? row = await rawMessageDao.byId(messageId);
      expect(row, isNotNull);
      expect(row!.classification, 'financial_parsed');
      expect(row.contentHmac, 'hmac-901');
      expect(row.sanitizedBody, isNotNull);
    });

    test('NFR-A1 — provenance is SMS-with-manual-completion, and the source '
        'message reference is kept', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionAccepted accepted =
          await service.complete(draftFor(messageId)) as CompletionAccepted;

      final TransactionRow row = await transactionDao.byId(
        accepted.transactionId,
      );

      expect(
        row.provenance,
        TransactionProvenance.sms,
        reason:
            'recording this as plain `manual` would throw away a real '
            'message reference — KHA-64 is explicit that it must not',
      );
      expect(row.provenanceDetail, ProvenanceDetail.manualCompletion);
      expect(row.sourceMessageId, messageId);
      expect(
        row.ruleId,
        isNull,
        reason:
            'no rule matched; claiming one would mislead the parser-health '
            'panel about which template is failing',
      );
      expect(row.timeSource, 'user_stated');

      final LedgerTransaction txn = toLedgerTransactionOrNull(row)!;
      expect(txn.isUserEntered, isTrue);
    });

    test('the completed transaction appears in period totals', () async {
      final int messageId = await queueUnparsedMessage();
      await service.complete(draftFor(messageId));

      final PeriodTotals totals = LedgerTotals.spend(
        toLedgerTransactions(await transactionDao.all()),
        period: PeriodRange(
          startUtc: DateTime.utc(2026, 7),
          endUtcExclusive: DateTime.utc(2026, 8),
        ),
      );

      // `75.5` and `75.50` are the same Decimal value; the canonical form
      // drops the trailing zero. Padding to SAR's two minor digits is a
      // display concern (`formatAmountDigits`), not a storage one.
      expect(totals.forCurrency('SAR')!.toCanonicalString(), '75.5');
    });

    test('AC-B1.4 — the amount the user typed is stored with its exact '
        'precision', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionAccepted accepted =
          await service.complete(draftFor(messageId, amount: '1234.05'))
              as CompletionAccepted;

      expect(
        (await transactionDao.byId(accepted.transactionId)).amountAmount,
        '1234.05',
      );
    });

    test('NFR-A2 — the audit entry names the USER as the actor, not the '
        'parser', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionAccepted accepted =
          await service.complete(draftFor(messageId)) as CompletionAccepted;

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'transaction',
        accepted.transactionId.toString(),
      );
      expect(entries.single.actor, 'user');
      expect(entries.single.actorDetail, 'review_queue_completion');

      final List<AuditFieldChange> changes = auditLogDao.decodeFieldChanges(
        entries.single,
      );
      expect(
        changes.any(
          (AuditFieldChange c) =>
              c.field == 'provenance' &&
              (c.to ?? '').contains('manual_completion'),
        ),
        isTrue,
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  group('AC-B4.2 — validation names the field, and writes nothing', () {
    test('a missing amount is rejected by name', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionResult result = await service.complete(
        draftFor(messageId, amount: '   '),
      );

      expect(result, isA<CompletionRejected>());
      expect(
        (result as CompletionRejected).missingFields,
        contains(CompletionField.amount),
      );
    });

    test('an unparseable currency is reported as a currency problem, not as a '
        'missing amount', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionResult result = await service.complete(
        draftFor(messageId, currency: 'RIYAL'),
      );

      expect(
        (result as CompletionRejected).missingFields,
        contains(CompletionField.currency),
      );
    });

    test('missing date and type are both reported, so the user fixes them in '
        'one pass', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionResult result = await service.complete(
        UnparsedCompletionDraft(
          rawMessageId: messageId,
          amountText: '10.00',
          currencyCode: 'SAR',
        ),
      );

      expect(
        (result as CompletionRejected).missingFields,
        containsAll(<String>[
          CompletionField.occurredAt,
          CompletionField.transactionType,
        ]),
      );
    });

    test('a rejected attempt writes NO transaction and leaves the item in the '
        'queue', () async {
      final int messageId = await queueUnparsedMessage();
      await service.complete(draftFor(messageId, amount: ''));

      expect(await transactionDao.all(), isEmpty);
      expect(await rawMessageDao.watchReviewQueue().first, hasLength(1));
    });

    test(
      'a zero amount is VALID — zero and unknown are different facts',
      () async {
        // KHA-25 states this explicitly, and a bank can genuinely post a
        // zero-value authorisation.
        final int messageId = await queueUnparsedMessage();
        final CompletionResult result = await service.complete(
          draftFor(messageId, amount: '0'),
        );

        expect(result, isA<CompletionAccepted>());
        expect((await transactionDao.all()).single.amountAmount, '0');
      },
    );
  });

  group('the message is no longer completable', () {
    test(
      'a message that was already completed cannot be completed twice',
      () async {
        final int messageId = await queueUnparsedMessage();
        await service.complete(draftFor(messageId));

        final CompletionResult second = await service.complete(
          draftFor(messageId),
        );

        expect(second, isA<CompletionMessageUnavailable>());
        expect(
          (await transactionDao.all()).length,
          1,
          reason: 'a double-submit must not double-count the user\'s money',
        );
      },
    );

    test('a dismissed message cannot be completed', () async {
      final int messageId = await queueUnparsedMessage();
      await rawMessageDao.dismissAsNotTransaction(messageId);

      expect(
        await service.complete(draftFor(messageId)),
        isA<CompletionMessageUnavailable>(),
      );
      expect(await transactionDao.all(), isEmpty);
    });

    test('an unknown message id is a value, not an exception', () async {
      expect(
        await service.complete(draftFor(4242)),
        isA<CompletionMessageUnavailable>(),
      );
    });
  });

  group('blank optional fields are stored as unknown, not as empty', () {
    test('an empty merchant becomes NULL (AC-B1.3)', () async {
      final int messageId = await queueUnparsedMessage();
      final CompletionAccepted accepted =
          await service.complete(
                UnparsedCompletionDraft(
                  rawMessageId: messageId,
                  amountText: '10.00',
                  currencyCode: 'SAR',
                  occurredAt: DateTime.utc(2026, 7, 20, 9),
                  transactionType: 'fee',
                  merchantRawText: '   ',
                ),
              )
              as CompletionAccepted;

      expect(
        (await transactionDao.byId(accepted.transactionId)).merchantRawText,
        isNull,
      );
    });
  });
}
