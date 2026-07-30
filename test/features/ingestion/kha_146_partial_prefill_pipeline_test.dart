/// **KHA-146, the half only a pipeline test can prove**: that what the parser
/// read actually reaches the database, and comes back out intact.
///
/// `test/features/parsing/kha_146_partial_extraction_test.dart` proves the
/// *parser* carries the partial extraction. This file proves the rest of the
/// chain the user's complaint actually travels:
///
/// ```
/// parse (requiredFields fails) -> UnparsedMessage.partialExtraction
///   -> IngestionPipeline        -> raw_message.partial_extraction (JSON)
///   -> watchReviewQueue()       -> the row the review-queue provider maps
///   -> PartialExtraction.tryDecode  -> what the completion form pre-fills
/// ```
///
/// Each arrow is a place the values could be dropped, and one of them
/// (the first) is exactly where they were being dropped.
///
/// ## NFR-M3
///
/// The rule and every message body come from
/// `test/support/kha146_synthetic_pack.dart` — all fabricated. No real bank
/// SMS is reproduced here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/partial_extraction.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/kha146_synthetic_pack.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

void main() {
  late AppDatabase db;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late IngestWatermarkDao watermarkDao;
  late RulePackMessageParser parser;

  setUp(() {
    db = openPlainTestDatabase();
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(
      db,
      AuditLogDao(db, auditChainKey: _testChainKey),
    );
    watermarkDao = IngestWatermarkDao(db);
    parser = RulePackMessageParser(packs: <RulePack>[syntheticRulePack()]);
  });

  tearDown(() async => db.close());

  IngestionPipeline pipelineFor(List<RawSmsRecord> inbox) => IngestionPipeline(
    database: db,
    smsSource: FakeSmsSource(inbox),
    parser: parser,
    rawMessageDao: rawMessageDao,
    transactionDao: transactionDao,
    watermarkDao: watermarkDao,
    logger: SafeLogger(DiagnosticRingBuffer()),
    contentHmacKey: _testChainKey,
  );

  RawSmsRecord record(int providerId, String body) => RawSmsRecord(
    providerId: providerId,
    address: syntheticSender,
    body: body,
    receivedAt: DateTime.utc(2026, 7, 30, 9).add(Duration(minutes: providerId)),
  );

  /// Runs one message end to end and returns the queued row.
  Future<RawMessageRow> ingestOne(String body) async {
    final IngestionRunResult result = await pipelineFor(<RawSmsRecord>[
      record(1, body),
    ]).runIncremental();

    expect(result.failedWithError, 0, reason: '$result');
    expect(
      result.isFullyAccountedFor,
      isTrue,
      reason: 'NFR-A7 as arithmetic. $result',
    );

    final List<RawMessageRow> queue = await rawMessageDao
        .watchReviewQueue()
        .first;
    expect(queue, hasLength(1));
    return queue.single;
  }

  group('case (b) — one required field missing', () {
    test(
      'the row keeps its sanitised text AND the fields the parser read',
      () async {
        final RawMessageRow row = await ingestOne(
          syntheticMissingOneRequiredField,
        );

        expect(row.classification, 'financial_unparsed');
        expect(row.unparsedReason, 'required_field_missing');
        expect(
          row.sanitizedBody,
          isNotNull,
          reason:
              'AC-A4.1 is unchanged by this fix — the text still has to be '
              'there for the user to read',
        );
        expect(
          row.partialExtraction,
          isNotNull,
          reason:
              'this column is the whole fix. Null here means the parser\'s work '
              'was thrown away between the parse and the insert, which is the '
              'defect KHA-146 reports.',
        );
      },
    );

    test('every field arrives at the completion form intact — the done-check, '
        'stated as data', () async {
      final RawMessageRow row = await ingestOne(
        syntheticMissingOneRequiredField,
      );

      // Exactly the decode the review-queue provider performs before handing
      // a `ReviewQueueItem` to S-19.
      final PartialExtraction? partial = PartialExtraction.tryDecode(
        row.partialExtraction,
      );

      expect(partial, isNotNull);
      expect(partial!.amountText, '152.75');
      expect(partial.currencyCode, 'SAR');
      expect(partial.merchantRawText, 'SAMPLE MARKET 7');
      expect(partial.instrumentKind, 'card');
      expect(partial.instrumentMaskedRef, '****4821');
      expect(partial.occurredAtUtc, isNotNull);
      expect(partial.transactionType, 'pos_purchase');
      expect(
        partial.missingFields,
        <String>['remainingBalance'],
        reason: 'the ONE field the user genuinely has to supply',
      );
    });

    test('nothing about this becomes a transaction on its own', () async {
      await ingestOne(syntheticMissingOneRequiredField);

      expect(
        await transactionDao.all(),
        isEmpty,
        reason:
            'a partial extraction is a suggestion for a form, never a '
            'transaction. The only thing that may write to the ledger from '
            'here is the user pressing "Save as transaction".',
      );
    });

    test('the stored JSON holds no unmasked identifier (NFR-S2)', () async {
      final RawMessageRow row = await ingestOne(
        syntheticMissingOneRequiredField,
      );

      // The fixture's card is `4821` and the rule masks to last-4, so the
      // masked form is all there ever is. Asserted anyway, because this column
      // is new and is the kind of place a future rule-pack change could start
      // writing more than it should.
      expect(row.partialExtraction, contains('****4821'));
      expect(row.partialExtraction, isNot(matches(RegExp(r'\d{5,}'))));
    });
  });

  group('case (a) — no rule matched', () {
    test('reaches the queue with NO partial extraction, so the form is '
        'correctly blank (no regression)', () async {
      final RawMessageRow row = await ingestOne(syntheticNoRuleMatches);

      expect(row.classification, 'financial_unparsed');
      expect(row.unparsedReason, 'no_rule_matched');
      expect(row.sanitizedBody, isNotNull);
      expect(
        row.partialExtraction,
        isNull,
        reason:
            'nothing was extracted, so there is nothing honest to pre-fill. '
            'A non-null value here would make the form announce a pre-fill it '
            'never did.',
      );
      expect(PartialExtraction.tryDecode(row.partialExtraction), isNull);
    });
  });

  group('the pipeline\'s own amount guard (the second place this lived)', () {
    test(
      'a rule that does not require an amount still routes to review when '
      'the amount is unreadable — and carries everything EXCEPT the amount',
      () async {
        // An **imported** pack (ADR-007's answer to R-11) is not obliged to list
        // `amount` in `requiredFields`, so the parser can return a
        // `ParsedMessage` with no amount and the pipeline's own guard catches it.
        // That branch had a fully-populated `fields` in hand and wrote none of
        // it — the same defect as KHA-146's, one layer down.
        final MessageRule permissive = MessageRule(
          ruleId: syntheticPurchaseRule().ruleId,
          priority: syntheticPurchaseRule().priority,
          messageType: syntheticPurchaseRule().messageType,
          intent: syntheticPurchaseRule().intent,
          match: syntheticPurchaseRule().match,
          regex: syntheticPurchaseRule().regex,
          extract: syntheticPurchaseRule().extract,
          sign: syntheticPurchaseRule().sign,
          affectsSpend: syntheticPurchaseRule().affectsSpend,
          // Requires nothing at all: the shape an imported pack may legally have.
          requiredFields: const <String>[],
          redact: syntheticPurchaseRule().redact,
        );
        parser = RulePackMessageParser(
          packs: <RulePack>[
            RulePack(
              schemaVersion: 1,
              packId: 'synthetic-test',
              packVersion: '2026.07.30',
              locales: const <String>['en'],
              banks: <BankRule>[
                BankRule(
                  bankId: syntheticBankId,
                  displayNameAr: 'بنك تجريبي',
                  displayNameEn: 'Synth Bank',
                  aliases: const <String>[],
                  senderPatterns: <RegExp>[RegExp('^$syntheticSender\$')],
                  messageRules: <MessageRule>[permissive],
                ),
              ],
            ),
          ],
        );

        // A body whose merchant, card and date read fine, and whose amount
        // satisfies the rule's capture group but is not a valid decimal — so the
        // regex matches, `requiredFields` is vacuously satisfied, and the
        // pipeline's own guard is what catches it.
        final RawMessageRow row = await ingestOne(
          'purchase 1.2.3 SAR card 4821 at SAMPLE MARKET 7 on 30/07/26 09:14',
        );

        final PartialExtraction? partial = PartialExtraction.tryDecode(
          row.partialExtraction,
        );

        expect(partial, isNotNull);
        expect(partial!.merchantRawText, 'SAMPLE MARKET 7');
        expect(partial.instrumentMaskedRef, '****4821');
        expect(partial.occurredAtUtc, isNotNull);
        expect(partial.transactionType, 'pos_purchase');
        expect(
          partial.amountText,
          isNull,
          reason:
              'the amount is precisely what was rejected. Pre-filling a figure '
              'the pipeline refused would be the one direction a spending '
              'tracker must never be wrong in.',
        );
        expect(partial.currencyCode, isNull);
        expect(partial.missingFields, <String>['amount']);
      },
    );
  });

  group('the control case', () {
    test('the same shape WITH every required field still becomes a '
        'transaction, and writes no partial extraction', () async {
      final IngestionRunResult result = await pipelineFor(<RawSmsRecord>[
        record(1, syntheticComplete),
      ]).runIncremental();

      expect(result.transactionsWritten, 1, reason: '$result');
      expect(result.routedToReviewQueue, 0);

      final List<RawMessageRow> rows = await rawMessageDao.all();
      expect(rows, hasLength(1));
      expect(rows.single.classification, 'financial_parsed');
      expect(
        rows.single.partialExtraction,
        isNull,
        reason:
            'a parsed message has a real transaction carrying its fields. A '
            'second, unconfirmed copy of them on the raw message would be a '
            'place for the two to disagree.',
      );
    });
  });
}
