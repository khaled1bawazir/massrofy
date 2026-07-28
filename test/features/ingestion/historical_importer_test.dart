/// AC-A3.1 / A3.2 / A3.3 — the resumable historical import.
///
/// The interesting test in this file is the interruption one. It is the only
/// place in the suite that simulates the device killing the app mid-work,
/// which on a first run over a busy inbox is the *most likely* thing to
/// happen and the hardest thing to check by hand.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/historical_importer.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import 'support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

/// 28 July 2026, 12:00 UTC → 15:00 in Riyadh.
final FixedClock _clock = FixedClock(DateTime.utc(2026, 7, 28, 12));

/// A distinct-but-valid D360 purchase for each provider id, so every message
/// has its own content HMAC and none is suppressed as an exact duplicate.
/// Amounts and times differ; the merchant deliberately does too, so ADR-017's
/// D3 heuristic does not flag them either.
String purchaseBody(int n) =>
    'D360: Purchase of SAR ${100 + n}.00 with Mada Debit Card ending 4472 '
    'at MERCHANT $n on ${(n % 28) + 1 < 10 ? '0' : ''}${(n % 28) + 1}'
    '/07/2026 1${n % 10}:00';

void main() {
  late AppDatabase db;
  late TransactionDao transactionDao;
  late IngestWatermarkDao watermarkDao;
  late IngestionPipeline pipeline;
  late FakeSmsSource source;

  List<RawSmsRecord> inbox(int count, {required DateTime from}) =>
      <RawSmsRecord>[
        for (int i = 1; i <= count; i++)
          RawSmsRecord(
            providerId: i,
            address: 'D360',
            body: purchaseBody(i),
            receivedAt: from.add(Duration(hours: i)),
          ),
      ];

  void build(List<RawSmsRecord> messages) {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    transactionDao = TransactionDao(db, auditLogDao);
    watermarkDao = IngestWatermarkDao(db);
    source = FakeSmsSource(messages);
    pipeline = IngestionPipeline(
      database: db,
      smsSource: source,
      parser: RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]),
      rawMessageDao: RawMessageDao(db),
      transactionDao: transactionDao,
      watermarkDao: watermarkDao,
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
    );
  }

  tearDown(() async => db.close());

  HistoricalImporter importer({int chunkSize = 5}) => HistoricalImporter(
    smsSource: source,
    pipeline: pipeline,
    watermarkDao: watermarkDao,
    clock: _clock,
    logger: SafeLogger(DiagnosticRingBuffer()),
    chunkSize: chunkSize,
  );

  group('AC-A3.1 — the window is the current calendar month, in Riyadh', () {
    test('messages from before the 1st of the month are not imported (OQ-11: '
        'not full history)', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );

      build(<RawSmsRecord>[
        // Last month. Must be ignored.
        RawSmsRecord(
          providerId: 1,
          address: 'D360',
          body: purchaseBody(1),
          receivedAt: monthStart.subtract(const Duration(days: 3)),
        ),
        // This month. Must be imported.
        RawSmsRecord(
          providerId: 2,
          address: 'D360',
          body: purchaseBody(2),
          receivedAt: monthStart.add(const Duration(days: 3)),
        ),
      ]);

      await importer().runOrResume();

      expect(await transactionDao.all(), hasLength(1));
    });

    test('the month boundary is computed in Asia/Riyadh, not UTC — the first '
        'three hours of the month are not silently dropped', () {
      // At 2026-07-01T00:30Z it is already 03:30 on 1 July in Riyadh, so
      // the month began at 2026-06-30T21:00Z — BEFORE the current UTC
      // instant's own UTC month boundary. Getting this backwards loses
      // every message in that window, every month, invisibly.
      final DateTime start = RiyadhCalendar.startOfCurrentMonthUtc(
        DateTime.utc(2026, 7, 1, 0, 30),
      );
      expect(start, DateTime.utc(2026, 6, 30, 21));
    });
  });

  group('AC-A3.3 — interruption and resumption', () {
    test('an interrupted import resumes and does not duplicate', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inbox(12, from: monthStart));

      // Stop after the first chunk of 5, exactly as a process kill would.
      int chunksAllowed = 1;
      await importer(
        chunkSize: 5,
      ).runOrResume(shouldContinue: () => chunksAllowed-- > 0);

      final IngestWatermarkRow afterInterrupt = await watermarkDao.current();
      expect(
        afterInterrupt.importState,
        importStatePaused,
        reason:
            '"paused" (not "idle") is what tells the next run there is '
            'unfinished work; "idle" would silently restart from scratch',
      );
      expect(afterInterrupt.importCursor, 5);
      final int afterFirstRun = (await transactionDao.all()).length;
      expect(afterFirstRun, 5);

      // Restart. This is the whole point of the test.
      await importer(chunkSize: 5).runOrResume();

      final List<TransactionRow> all = await transactionDao.all();
      expect(all, hasLength(12), reason: 'every message imported');
      expect(
        all.map((TransactionRow t) => t.sourceMessageId).toSet(),
        hasLength(12),
        reason:
            'twelve distinct source messages — a duplicate would show up as '
            'two transactions sharing one sourceMessageId',
      );

      final IngestWatermarkRow done = await watermarkDao.current();
      expect(done.importState, importStateIdle);
      expect(done.importCursor, isNull);
    });

    test('even a TOTAL cursor loss cannot create duplicates — dedup is the '
        'independent second mechanism', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inbox(8, from: monthStart));

      await importer(chunkSize: 4).runOrResume();
      expect(await transactionDao.all(), hasLength(8));

      // Simulate the worst case: the watermark row is wiped and the whole
      // import runs again from zero. The cursor is what makes resumption
      // *fast*; ADR-017 D1's UNIQUE constraints are what make it *safe*.
      await watermarkDao.completeImport();
      await importer(chunkSize: 4).runOrResume();

      expect(
        await transactionDao.all(),
        hasLength(8),
        reason:
            'relying on the cursor alone would be hoping; the UNIQUE '
            'constraints on sms_provider_id and content_hmac are what make '
            'AC-A3.3 true regardless',
      );
    });

    test('a completed import does no work when run again', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inbox(3, from: monthStart));

      await importer().runOrResume();
      final int readsAfterFirst = source.readCallCount;

      await importer().runOrResume();

      expect(
        source.readCallCount,
        greaterThan(readsAfterFirst),
        reason:
            'a second run does re-scan (it must, to find newly-arrived '
            'messages) — but it must not produce anything new',
      );
      expect(await transactionDao.all(), hasLength(3));
    });
  });

  group('AC-A3.2 — progress is reportable without exposing content', () {
    test('the watermark carries counts the UI can bind to', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inbox(7, from: monthStart));

      await importer(chunkSize: 3).runOrResume();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.importTotalCandidates, 7);
      expect(row.importProcessedCount, 7);

      // `.toUtc()` is load-bearing, and worth understanding rather than
      // copying.
      //
      // Drift's default `DateTimeColumn` storage is a Unix timestamp, and a
      // timestamp carries an instant but not a timezone flag. So a UTC
      // `DateTime` written in survives the round-trip as the *same instant*
      // but comes back marked local. `DateTime.==` compares the flag as well
      // as the instant, so `expect(row.importFromDate, monthStart)` fails on
      // a machine that is not at UTC+0 even though nothing is actually wrong.
      //
      // Every comparison this codebase actually depends on — `isBefore`,
      // `isAfter`, `difference` — operates on the absolute instant and is
      // unaffected. Normalising with `.toUtc()` before an equality assertion
      // is the correct fix; switching the whole schema to text-stored dates
      // would be a migration of every existing row to satisfy one test.
      expect(row.importFromDate!.toUtc(), monthStart);
    });
  });

  group('the two cursors are kept separate on purpose', () {
    test(
      'the historical import does NOT move the incremental watermark — '
      'conflating them would skip messages that arrive during the import',
      () async {
        final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
          _clock.nowUtc(),
        );
        build(inbox(5, from: monthStart));

        await importer().runOrResume();

        final IngestWatermarkRow row = await watermarkDao.current();
        expect(
          row.lastProcessedSmsProviderId,
          0,
          reason:
              'the import walks backwards in time through already-delivered '
              'messages; moving the forward watermark would mean anything '
              'arriving mid-import is never picked up',
        );
      },
    );
  });
}
