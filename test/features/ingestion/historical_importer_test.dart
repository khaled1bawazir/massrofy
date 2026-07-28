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

import '../../fixtures/synthetic_sms_corpus.dart';
import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import '../../support/throwing_parser.dart';
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

  /// Builds a pipeline over the current [db] and [source].
  ///
  /// [throwForSender] swaps in [ThrowingParser] so a chosen message raises an
  /// internal error rather than returning a parse verdict. Kept separate from
  /// [build] so a test can *heal* the parser and re-run against the **same
  /// database** — which is the only way to prove that a message the importer
  /// refused to skip is genuinely retried later, rather than merely not
  /// recorded as done.
  IngestionPipeline buildPipeline({String? throwForSender}) {
    final RulePackMessageParser real = RulePackMessageParser(
      packs: <RulePack>[loadBundledRulePack()],
    );
    return IngestionPipeline(
      database: db,
      smsSource: source,
      parser: throwForSender == null
          ? real
          : ThrowingParser(real, throwForSender: throwForSender),
      rawMessageDao: RawMessageDao(db),
      transactionDao: transactionDao,
      watermarkDao: watermarkDao,
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
    );
  }

  void build(List<RawSmsRecord> messages, {String? throwForSender}) {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    transactionDao = TransactionDao(db, auditLogDao);
    watermarkDao = IngestWatermarkDao(db);
    source = FakeSmsSource(messages);
    pipeline = buildPipeline(throwForSender: throwForSender);
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
      expect(
        done.importState,
        importStateCompleted,
        reason:
            '"completed" is a terminal state distinct from the initial '
            '"idle". Writing "idle" here would make a finished import '
            'indistinguishable from one that never started.',
      );
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

      // Simulate the worst case: the watermark row is wiped back to its
      // factory state — no cursor, no recorded progress, `idle` — and the
      // whole import runs again from zero. The cursor is what makes
      // resumption *fast*; ADR-017 D1's UNIQUE constraints are what make it
      // *safe*, and this test exists to prove the second claim without the
      // first.
      //
      // Written as raw SQL rather than through the DAO on purpose. There is
      // no DAO method that un-completes an import, and there should not be —
      // the point of the test is a database in a state no code path can
      // produce (corruption, a restored backup, a botched migration), so
      // reaching for the DAO would be testing the code against itself.
      //
      // Note this deliberately does NOT use `completeImport()`, which it once
      // did. That call now writes the terminal `completed` state, so the
      // second run would correctly do nothing and this test would pass while
      // proving nothing at all — a green assertion measuring the wrong thing.
      await db.customStatement(
        'UPDATE ingest_watermark SET import_state = ?, import_cursor = NULL, '
        'import_from_date = NULL, import_processed_count = 0',
        <Object?>[importStateIdle],
      );
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

    test('a completed import does no work when run again — not one read of '
        'the inbox', () async {
      // ## What this test used to assert, and why that was the bug
      //
      // Its body once asserted `readCallCount` **increased** on the second
      // run, explained as "a second run does re-scan (it must, to find
      // newly-arrived messages)". That reasoning confuses the two cursors:
      // finding newly-arrived messages is `IngestionPipeline.runIncremental`'s
      // job, driven by the forward watermark. The historical import is a
      // one-shot backfill over a fixed window (the current calendar month at
      // first run) and has nothing to add after it finishes.
      //
      // So the test's name described the correct behaviour, its body asserted
      // the opposite, and the implementation matched the body: `completeImport`
      // wrote `idle` + null cursor, which `runOrResume` reads as "never
      // started". Since `foregroundSweepProvider` calls `runOrResume` on every
      // app foreground, the whole month was re-read, re-sanitised, re-HMACed
      // and re-queried on every app open — invisibly, because dedup made the
      // *output* correct every time.
      //
      // Now it asserts what the name always claimed, and pins the read count
      // exactly: `greaterThan`/`lessThan` on a call count is the assertion
      // shape that let this hide.
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inbox(3, from: monthStart));

      await importer().runOrResume();
      final int readsAfterFirst = source.readCallCount;

      expect(
        (await watermarkDao.current()).importState,
        importStateCompleted,
        reason: 'the first run must reach the terminal state',
      );

      final IngestionRunResult second = await importer().runOrResume();

      expect(
        source.readCallCount,
        readsAfterFirst,
        reason:
            'a completed import must not touch the inbox at all. Any increase '
            'here means the backfill is running again on every app open.',
      );
      expect(
        second.examined,
        0,
        reason: 'nothing was examined, so every bucket must be zero',
      );
      expect(second.isFullyAccountedFor, isTrue);
      expect(await transactionDao.all(), hasLength(3));
    });
  });

  group('NFR-A7 — the import cursor never advances past a failure', () {
    /// Six messages where **#3 throws**, with successful messages on both
    /// sides of it.
    ///
    /// The position matters. A failure at the end of a chunk is caught by
    /// almost any implementation; a failure in the *middle*, followed by
    /// messages that succeed, is the one that loses data — because
    /// `cursor = chunk.last.providerId` then looks entirely reasonable and
    /// quietly steps over #3 forever.
    List<RawSmsRecord> inboxFailingAtThird(DateTime from) {
      final List<RawSmsRecord> messages = inbox(6, from: from);
      final SmsFixture baj = aljaziraFixtures.first; // sender 'BAJ'
      messages[2] = RawSmsRecord(
        providerId: 3,
        address: baj.sender,
        body: baj.body,
        receivedAt: from.add(const Duration(hours: 3)),
      );
      return messages;
    }

    test('the walk stops and the cursor stays put, mirroring '
        'IngestionPipeline.runIncremental', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inboxFailingAtThird(monthStart), throwForSender: 'BAJ');

      // One chunk big enough to hold all six, so the failure and the
      // successes after it are in the same chunk — the exact shape described
      // above.
      await importer(chunkSize: 6).runOrResume();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(
        row.importCursor,
        0,
        reason:
            'advancing to 6 would strand message 3 forever: every later read '
            'asks for providerId > cursor. Re-reading 1, 2, 4, 5 and 6 costs '
            'nothing — ADR-017 D1 suppresses them — whereas losing 3 is '
            'unrecoverable.',
      );
      expect(
        row.importState,
        isNot(importStateCompleted),
        reason:
            'an import that hit an error has not finished, and must not be '
            'marked terminal — that would turn a retry into a permanent skip',
      );
      expect(row.importState, importStatePaused);

      expect(
        await transactionDao.all(),
        hasLength(5),
        reason:
            'NFR-R5 still holds: the five healthy messages were processed. '
            'Stopping the CURSOR is not the same as stopping the BATCH.',
      );
    });

    test('and the failed message is retried on the next run, not skipped '
        'forever', () async {
      final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
        _clock.nowUtc(),
      );
      build(inboxFailingAtThird(monthStart), throwForSender: 'BAJ');

      await importer(chunkSize: 6).runOrResume();

      bool hasBajPurchase(List<TransactionRow> rows) => rows.any(
        (TransactionRow t) => t.merchantRawText == 'EXTRA MART 0042',
      );

      expect(
        hasBajPurchase(await transactionDao.all()),
        isFalse,
        reason: 'message 3 failed, so it is not in the ledger yet',
      );

      // Heal the parser — the fix shipped, or the failure was transient — and
      // run again against the SAME database. This is the half that matters:
      // "did not advance the cursor" is only meaningful if the message is
      // actually picked up next time.
      pipeline = buildPipeline();
      await importer(chunkSize: 6).runOrResume();

      final List<TransactionRow> all = await transactionDao.all();
      expect(all, hasLength(6), reason: 'every message eventually lands');
      expect(
        hasBajPurchase(all),
        isTrue,
        reason:
            'the message that threw is the whole point — it must come back, '
            'not be silently absent from every total the user ever sees',
      );
      expect(
        all.map((TransactionRow t) => t.sourceMessageId).toSet(),
        hasLength(6),
        reason:
            're-reading the five successful messages must not duplicate them '
            '(ADR-017 D1)',
      );
      expect(
        (await watermarkDao.current()).importState,
        importStateCompleted,
        reason: 'a clean run to the end is what earns the terminal state',
      );
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
