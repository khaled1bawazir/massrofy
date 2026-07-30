/// **KHA-66 / AC-A4.3 — a dismissed message stays dismissed across a full
/// re-scan.** US-A4, NFR-A7, ADR-017 D1.
///
/// ---
///
/// ## Why this file exists, and why it took three attempts to get written
///
/// AC-A4.3 was found unproven by qa-tester during the KHA-48 pass on PR #4,
/// restated by code-reviewer in the merge commit of `ec23deb` as *"mobile
/// engineer owes an AC-A4.3 DAO-level regression test before P3 closes"*, and
/// deferred twice after that. The production code was correct-looking and had
/// UI-wiring coverage; what was missing was any test at all that calls
/// `RawMessageDao.dismissAsNotTransaction()` and then runs a genuine re-scan.
///
/// ## Why UI-wiring coverage could never have caught this
///
/// AC-A4.3 is a **persistence-across-re-scan** guarantee, and the historical
/// importer is explicitly resumable and re-runnable (KHA-20). A dismissal that
/// failed to persist would look completely fine in a widget test — the item
/// leaves the list — and would resurrect dismissed noise on every subsequent
/// sweep. The user would watch the review queue refill itself with things they
/// had already rejected, which attacks the trust NFR-A7 exists to protect more
/// directly than a parse failure does: the app would be visibly ignoring them.
///
/// ## Two independent mechanisms, both asserted
///
/// The dismissal survives a re-scan because of two separate facts, and a test
/// that only proved one would leave the other free to regress:
///
///  1. **`dismissAsNotTransaction` is an UPDATE, never a DELETE.** The row —
///     and with it the content HMAC — stays.
///  2. **ADR-017 D1's `content_hmac` UNIQUE constraint** means the re-scan
///     never inserts a second row for the same message, so the dismissed flag
///     is still the one being read.
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
import '../../support/watermark_seed.dart';
import 'support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 71);

/// A message from a **known** bank sender that no rule understands — the
/// safety-net case from the synthetic corpus (`baj-13-unknown-template`). It
/// reaches the review queue rather than being discarded, which is what gives
/// the user something to dismiss in the first place.
const String _unknownTemplate =
    'تنبيه: تم رصد عملية غير معتادة على حسابك. يرجى زيارة الفرع.';

void main() {
  late AppDatabase db;
  late RawMessageDao rawMessageDao;
  late IngestionPipeline pipeline;
  late FakeSmsSource source;

  final List<RawSmsRecord> inbox = <RawSmsRecord>[
    RawSmsRecord(
      providerId: 1,
      address: 'BAJ',
      body: _unknownTemplate,
      receivedAt: DateTime.utc(2026, 7, 10, 9),
    ),
  ];

  setUp(() async {
    db = openPlainTestDatabase();
    // KHA-157: the subject here is a dismissal surviving a re-scan, not where
    // the incremental sweep starts. Seed at the beginning so `runIncremental`
    // reads the whole fixture inbox.
    await seedWatermarkAtBeginning(IngestWatermarkDao(db));
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    rawMessageDao = RawMessageDao(db);
    source = FakeSmsSource(inbox);
    pipeline = IngestionPipeline(
      database: db,
      smsSource: source,
      parser: RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]),
      rawMessageDao: rawMessageDao,
      transactionDao: TransactionDao(db, auditLogDao),
      watermarkDao: IngestWatermarkDao(db),
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
    );
  });

  tearDown(() async => db.close());

  Future<List<RawMessageRow>> queue() => rawMessageDao.watchReviewQueue().first;

  /// A **full** re-scan: the same inbox, processed again from the start, the
  /// way a historical import re-run does it. `advanceWatermark: false` mirrors
  /// the importer, which walks already-delivered messages and must not move
  /// the incremental cursor.
  Future<void> rescan() => pipeline.processAll(inbox, advanceWatermark: false);

  group('AC-A4.3 — the dismissal survives a full re-scan', () {
    test('a dismissed message does not reappear in the review queue', () async {
      await pipeline.runIncremental();
      expect(
        await queue(),
        hasLength(1),
        reason: 'the safety net put it in the queue (NFR-A7)',
      );

      final int messageId = (await queue()).single.id;
      // The call KHA-66 exists to have exercised at least once.
      await rawMessageDao.dismissAsNotTransaction(messageId);
      expect(await queue(), isEmpty);

      await rescan();

      expect(
        await queue(),
        isEmpty,
        reason:
            'AC-A4.3: a dismissed message stays dismissed. If this fails, '
            'the review queue refills itself with things the user already '
            'rejected on every sweep.',
      );
    });

    test('the dismissal is persisted at the DATABASE level, not held in '
        'memory', () async {
      await pipeline.runIncremental();
      final int messageId = (await queue()).single.id;
      await rawMessageDao.dismissAsNotTransaction(messageId);

      await rescan();

      // Read the column directly. An in-memory-only filter would satisfy the
      // queue assertion above and fail here.
      final RawMessageRow row = (await rawMessageDao.byId(messageId))!;
      expect(row.dismissedAsNotTransaction, isTrue);
    });

    test('the dismissal survives MANY re-scans, not just one', () async {
      await pipeline.runIncremental();
      await rawMessageDao.dismissAsNotTransaction((await queue()).single.id);

      for (int i = 0; i < 5; i++) {
        await rescan();
      }

      expect(await queue(), isEmpty);
      expect(await rawMessageDao.all(), hasLength(1));
    });
  });

  group('the two mechanisms that make it work', () {
    test('dismissal is an UPDATE, not a DELETE — the row, and with it the '
        'content HMAC, survives', () async {
      await pipeline.runIncremental();
      final int messageId = (await queue()).single.id;

      await rawMessageDao.dismissAsNotTransaction(messageId);

      final List<RawMessageRow> all = await rawMessageDao.all();
      expect(all, hasLength(1));
      // Deleting would lose the dedup key, and the next sweep would re-ingest
      // the message — a bug that looks exactly like the app ignoring the user.
      expect(all.single.contentHmac, isNotEmpty);
      // NFR-A7's spirit: the user said "not a transaction", not "pretend you
      // never received this". The parser-health panel still counts the miss.
      expect(all.single.classification, 'financial_unparsed');
    });

    test('ADR-017 D1 — the re-scan writes no SECOND row for the same message, '
        'so there is no undismissed copy to reappear', () async {
      await pipeline.runIncremental();
      await rawMessageDao.dismissAsNotTransaction((await queue()).single.id);

      await rescan();
      await rescan();

      expect(
        await rawMessageDao.all(),
        hasLength(1),
        reason: 'the content_hmac UNIQUE constraint suppresses the redelivery',
      );
    });

    test(
      'a dismissed message never becomes a transaction on re-scan',
      () async {
        await pipeline.runIncremental();
        await rawMessageDao.dismissAsNotTransaction((await queue()).single.id);

        await rescan();

        // It was unparsable in the first place, so nothing should have been
        // written — but the assertion is worth making explicitly, because the
        // failure mode of a broken dismissal would be a re-parse attempt.
        expect(
          await TransactionDao(
            db,
            AuditLogDao(db, auditChainKey: _testChainKey),
          ).all(),
          isEmpty,
        );
      },
    );
  });

  group('the dismissal is targeted — it does not silence the queue', () {
    test('a DIFFERENT unparsed message still reaches the queue after one has '
        'been dismissed', () async {
      await pipeline.runIncremental();
      await rawMessageDao.dismissAsNotTransaction((await queue()).single.id);

      // A second, structurally different unknown-template message.
      await pipeline.processAll(<RawSmsRecord>[
        RawSmsRecord(
          providerId: 2,
          address: 'BAJ',
          body: 'تنبيه: تم تحديث بيانات حسابك لدى الفرع الرئيسي.',
          receivedAt: DateTime.utc(2026, 7, 11, 9),
        ),
      ], advanceWatermark: false);

      expect(
        await queue(),
        hasLength(1),
        reason:
            'dismissing one message must not suppress the safety net for '
            'every later one',
      );
    });
  });
}
