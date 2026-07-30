/// **KHA-128, the half that only a pipeline test can prove.**
///
/// `test/features/parsing/sender_recognition_test.dart` proves the *parser*
/// recognises all seven confirmed sender ids. This file proves the **pipeline
/// acts on that correctly for a bank with `messageRules: []`** — that a
/// recognised sender with no template lands in the Needs Review queue, with
/// its sanitised text, and is neither discarded nor a crash.
///
/// ## Why that needed its own test rather than being obvious
///
/// The five banks KHA-128 adds carry zero parsing rules on purpose (no real
/// message sample exists yet; NFR-M3 forbids inventing one). Reading the
/// engine, the path is:
///
/// ```
/// _resolveBank(sender)          -> matched, so NOT NotFinancialSender
/// for (rule in messageRules)    -> iterates ZERO times
/// step 4 fall-through           -> UnparsedMessage(noRuleMatched, ruleId: '')
/// pipeline                      -> rawMessageDao.insert(financial_unparsed)
/// ```
///
/// Every step of that is a claim about code nobody had ever run with an empty
/// rule list. `ruleId: ''` in particular is a value the pipeline special-cases
/// (`rule?.ruleId.isEmpty ?? true ? null : …`) — the kind of expression that is
/// either exactly right or off by one `null`, and it decides whether the insert
/// succeeds or throws. AC-A6.5's entire argument — *"a linked bank is
/// immediately useful with zero rules written"* — rests on this working, so it
/// is asserted end to end against a real database rather than reasoned about.
///
/// ## NFR-M3
///
/// Every message body below is **fabricated** for this file. No real bank SMS
/// is reproduced, quoted, or paraphrased from a real device. The bank names and
/// sender ids are real (they are public brands, and the sender id is the thing
/// under test); nothing else here is.
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
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import 'support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

/// One fabricated inbox row per confirmed sender id.
///
/// The bodies are *bank-shaped* rather than empty, so the test exercises a
/// realistic amount of text through the sanitiser and normaliser — but they
/// match no template for any bank, which is the point: five of these banks
/// have no templates at all, and for the two that do, none of these shapes is
/// one of theirs.
const Map<String, String> _syntheticMessagePerSender = <String, String>{
  'nera': 'nera: Card payment 61.25 SAR at SAMPLE STORE 12. Ref TS00119.',
  'AlRajhi Bank':
      'AlRajhi Bank: 240.00 SAR spent, acct ending 7788, 30-07-26 09:14.',
  'STC Bank': 'STC Bank: Wallet debit 18.90 SAR - EXAMPLE VENDOR ONE.',
  'SAIB': 'SAIB: Payment of SAR 512.00 completed. Reference QQ4410.',
  'SAB': 'SAB: SAR 75.40 debited. Merchant SAMPLE GROCER 3. Ref ZZ0088.',
  // The two previously-configured banks, whose confirmed sender ids KHA-128
  // also fixes. Included here so the "no sender is discarded" assertion covers
  // all seven, not just the five new ones.
  'Jazira Bank': 'Jazira Bank: عملية بمبلغ ٩٩٫٥٠ ريال. رقم مرجعي MM7001.',
  'D360 Bank': 'D360 Bank: Amount 33.00 SAR settled. Reference DD5512.',
};

/// A sender that genuinely belongs to nobody — the control case, so the test
/// proves the counter it asserts is zero *can* be non-zero.
const String _unknownSender = 'MYFRIEND';

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
    parser = RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]);
  });

  tearDown(() async => db.close());

  IngestionPipeline buildPipeline(List<RawSmsRecord> inbox) =>
      IngestionPipeline(
        database: db,
        smsSource: FakeSmsSource(inbox),
        parser: parser,
        rawMessageDao: rawMessageDao,
        transactionDao: transactionDao,
        watermarkDao: watermarkDao,
        logger: SafeLogger(DiagnosticRingBuffer()),
        contentHmacKey: _testChainKey,
      );

  RawSmsRecord record(int providerId, String sender, String body) =>
      RawSmsRecord(
        providerId: providerId,
        address: sender,
        body: body,
        receivedAt: DateTime.utc(
          2026,
          7,
          30,
          9,
        ).add(Duration(minutes: providerId)),
      );

  group('a recognised sender with no template (AC-A6.5)', () {
    test('SAB — lands in the Needs Review queue with its sanitised text, '
        'rather than crashing or vanishing', () async {
      final IngestionRunResult result = await buildPipeline(<RawSmsRecord>[
        record(1, 'SAB', _syntheticMessagePerSender['SAB']!),
      ]).runIncremental();

      expect(result.examined, 1);
      expect(
        result.routedToReviewQueue,
        1,
        reason:
            'AC-A6.5: a linked sender with zero parsing rules is immediately '
            'useful — every message visible, every one completable by hand '
            '(US-A4 / S-19). That is the whole reason shipping gate 1 alone '
            'is worth doing.',
      );
      expect(
        result.discardedNonFinancialSender,
        0,
        reason:
            'this is the KHA-128 regression in one number. Before the fix '
            'this counter was 1 and NOTHING else happened — no row, no '
            'counter the user could see, no way to diagnose it from inside '
            'the app.',
      );
      expect(
        result.failedWithError,
        0,
        reason:
            'an empty `messageRules` list must fall through the engine\'s '
            'rule loop, not throw. If this is 1, the pipeline is being saved '
            'by NFR-R5\'s per-message catch and the message is retried '
            'forever.',
      );
      expect(result.transactionsWritten, 0);
      expect(
        result.isFullyAccountedFor,
        isTrue,
        reason: 'NFR-A7 as arithmetic. $result',
      );

      final List<RawMessageRow> queue = await rawMessageDao
          .watchReviewQueue()
          .first;
      expect(queue, hasLength(1));
      expect(queue.single.sender, 'SAB');
      expect(queue.single.bankId, 'sab');
      expect(queue.single.classification, 'financial_unparsed');
      expect(
        queue.single.unparsedReason,
        'no_rule_matched',
        reason:
            'the same reason a fully-configured bank reports when it changes '
            'a template — a sender-only bank is not a special case '
            'downstream, which is exactly why it needed no engine change',
      );
      expect(
        queue.single.sanitizedBody,
        isNotNull,
        reason:
            'AC-A4.2 — the user completes the transaction by reading the '
            'original text. A review item with no text is not reviewable.',
      );
      expect(
        queue.single.unparsedRuleId,
        isNull,
        reason:
            'no rule matched, so there is no rule to name. The pipeline maps '
            'the engine\'s empty `ruleId` to NULL rather than storing an '
            'empty string that would look like a real rule id in the '
            'parser-health panel.',
      );
      expect(await transactionDao.all(), isEmpty);
    });

    test('all seven confirmed senders are recognised; only a genuinely '
        'unknown sender is discarded', () async {
      final List<RawSmsRecord> inbox = <RawSmsRecord>[];
      int providerId = 0;
      _syntheticMessagePerSender.forEach((String sender, String body) {
        inbox.add(record(++providerId, sender, body));
      });
      inbox.add(
        record(++providerId, _unknownSender, 'Are we still on for tonight?'),
      );

      final IngestionRunResult result = await buildPipeline(
        inbox,
      ).runIncremental();

      expect(result.examined, inbox.length);
      expect(
        result.discardedNonFinancialSender,
        1,
        reason:
            'exactly one — the friend. Seven bank senders must all be past '
            'gate 1. A value of 8 is the shipped defect; a value of 0 would '
            'mean this test proves nothing because the counter never moves.',
      );
      expect(
        result.routedToReviewQueue,
        _syntheticMessagePerSender.length,
        reason:
            'all seven bank messages are visible to the user. None of these '
            'fabricated shapes matches a real template, so review — not a '
            'transaction — is the correct destination for every one.',
      );
      expect(result.failedWithError, 0);
      expect(result.isFullyAccountedFor, isTrue, reason: '$result');

      // NFR-P4's strictest clause, unchanged by this fix: the unrecognised
      // sender leaves no row at all — not even a timestamp.
      final Set<String> storedSenders = (await rawMessageDao.all())
          .map((RawMessageRow r) => r.sender)
          .toSet();
      expect(storedSenders, isNot(contains(_unknownSender)));
      expect(storedSenders, containsAll(_syntheticMessagePerSender.keys));
    });

    test('the watermark still advances past a sender-only bank\'s message, so '
        'the next sweep does not re-read it forever', () async {
      // A message that produced no transaction is still *examined*. If the
      // watermark stalled here, every subsequent sweep would re-read the same
      // message — cheap in a test, a battery and a duplicate-suppression
      // treadmill on a device.
      await buildPipeline(<RawSmsRecord>[
        record(41, 'nera', _syntheticMessagePerSender['nera']!),
      ]).runIncremental();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.lastProcessedSmsProviderId, 41);
    });
  });
}
