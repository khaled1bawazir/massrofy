/// **KHA-122's data-integrity half.** The immediate sweep must not be able to
/// double-count.
///
/// ---
///
/// ## Why this file exists, in the product-owner's own words
///
/// > *"per NFR-A7 / AC-A4.4: the immediate sweep must go through the same dedup
/// > and watermark path as the resume sweep. A prompt sweep that races the resume
/// > sweep and double-counts a transaction (AC-A5.1) or advances the watermark
/// > past an unwritten message is strictly worse than the current delay. Please
/// > cover the race explicitly in tests."*
///
/// KHA-122's fix adds a **third** trigger for `foregroundSweepProvider` (the
/// Kotlin broadcast signal) alongside the two that already existed (unlock, and
/// `AppLifecycleState.resumed`). Riverpod cannot cancel an in-flight `Future`, so
/// `ref.invalidate` while a sweep is running starts a second one **while the
/// first is still going**. That is not a hypothetical: the realistic sequence is
/// exactly the one QA will retest —
///
/// 1. an SMS lands while the app is open → the signal fires → sweep A starts;
/// 2. the user backgrounds and reopens (or the OS delivers a spurious resume)
///    → sweep B starts before A has finished.
///
/// Two concurrent `runIncremental()` calls over one inbox is therefore the
/// scenario to prove safe, and "safe" means **exactly one transaction**, not
/// "usually one".
///
/// ## What actually makes it safe (so a reviewer can check the claim, not the code)
///
/// Nothing in the KHA-122 change. The protection is pre-existing and structural,
/// which is the whole reason the fix was allowed to be a trigger wire:
///
///  - `raw_message.sms_provider_id` is `UNIQUE` — the same inbox row cannot be
///    stored twice (ADR-017 D1, and AC-A3.3's re-scan safety);
///  - `raw_message.content_hmac` is `UNIQUE` — identical content cannot be
///    stored twice even under a *new* provider id (AC-A5.1, carrier redelivery);
///  - each message is one `database.transaction(...)` covering its raw-message
///    row, its transaction row, its audit entry **and** the watermark advance,
///    so there is no window in which one exists without the others;
///  - `IngestWatermarkDao.advanceTo` is monotonic in SQL, so an older sweep
///    finishing late cannot rewind the cursor a newer one advanced.
///
/// These tests assert the *observable consequence* of all four rather than
/// re-stating them: one transaction, one raw-message row, and a watermark that
/// only ever moves forward.
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

/// The QA repro's own message shape (a BAJ Arabic POS purchase), rewritten with
/// fabricated values — NFR-M3 forbids committing real bank text, and the corpus
/// file makes the same point at length.
const String _posPurchaseBody =
    'شراء\n'
    'بطاقة:مدى-****4472\n'
    'مبلغ:312.40 SAR\n'
    'لدى:QANDA FOODS\n'
    'في:15-07-26 13:20';

void main() {
  late AppDatabase db;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late IngestWatermarkDao watermarkDao;
  late RulePackMessageParser parser;
  late SafeLogger logger;

  setUp(() {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(db, auditLogDao);
    watermarkDao = IngestWatermarkDao(db);
    parser = RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]);
    logger = SafeLogger(DiagnosticRingBuffer());
  });

  tearDown(() async => db.close());

  /// A pipeline over [source].
  ///
  /// Built fresh per call on purpose: the immediate sweep and the resume sweep
  /// are two *separate* provider builds in the app, so two separate pipeline
  /// instances over one database is the faithful shape. Sharing one instance
  /// would accidentally serialise them through shared in-Dart state and prove
  /// nothing.
  IngestionPipeline pipeline(FakeSmsSource source) => IngestionPipeline(
    database: db,
    smsSource: source,
    parser: parser,
    rawMessageDao: rawMessageDao,
    transactionDao: transactionDao,
    watermarkDao: watermarkDao,
    logger: logger,
    contentHmacKey: _testChainKey,
  );

  RawSmsRecord record({int providerId = 1, String body = _posPurchaseBody}) =>
      RawSmsRecord(
        providerId: providerId,
        address: 'BAJ',
        body: body,
        receivedAt: DateTime.utc(2026, 7, 15, 10, 20),
      );

  Future<int> transactionCount() async => (await transactionDao.all())
      .where((TransactionRow r) => !r.isDeleted)
      .length;

  group('KHA-122 — an immediate sweep racing a resume sweep', () {
    test('two CONCURRENT sweeps over one new SMS produce exactly one '
        'transaction (AC-A5.1)', () async {
      final FakeSmsSource inbox = FakeSmsSource(<RawSmsRecord>[record()]);

      // Both futures started before either is awaited: this is the interleaving
      // `ref.invalidate` produces, since Dart cannot cancel the first sweep.
      final Future<IngestionRunResult> immediate = pipeline(
        inbox,
      ).runIncremental();
      final Future<IngestionRunResult> resume = pipeline(
        inbox,
      ).runIncremental();
      final List<IngestionRunResult> results = await Future.wait(
        <Future<IngestionRunResult>>[immediate, resume],
      );

      expect(
        await transactionCount(),
        1,
        reason:
            'the whole point of KHA-122: a prompt sweep that double-counts is '
            'worse than the delay it replaced',
      );
      // One raw-message row too — the transaction count could be right while
      // the message was stored twice, which would corrupt every later dedup
      // decision about it.
      expect((await rawMessageDao.all()).length, 1);

      // Exactly one of the two runs wrote it; the other either suppressed it as
      // a duplicate or never saw it (the watermark had already moved). Summed
      // across both runs, "written" must be 1 — not 0, and not 2.
      final int written = results.fold<int>(
        0,
        (int running, IngestionRunResult r) => running + r.transactionsWritten,
      );
      expect(
        written,
        1,
        reason:
            'written=0 would mean the message was lost (NFR-A7); written=2 '
            'would mean the UNIQUE constraints did not hold. Results: $results',
      );
      for (final IngestionRunResult result in results) {
        expect(
          result.isFullyAccountedFor,
          isTrue,
          reason: 'NFR-A7 arithmetic must hold per run as well: $result',
        );
      }
    });

    test('the SEQUENTIAL case QA will retest — immediate sweep, then a resume '
        'sweep moments later — also yields exactly one', () async {
      final FakeSmsSource inbox = FakeSmsSource(<RawSmsRecord>[record()]);

      final IngestionRunResult immediate = await pipeline(
        inbox,
      ).runIncremental();
      expect(immediate.transactionsWritten, 1);

      final IngestionRunResult resume = await pipeline(inbox).runIncremental();

      expect(await transactionCount(), 1);
      expect(
        resume.transactionsWritten,
        0,
        reason:
            'the second sweep must find nothing new: the watermark advanced in '
            'the same database transaction as the write',
      );
      // Nothing was even examined, because the watermark excluded it from the
      // read. That is stronger than "dedup caught it" — the cheap path worked.
      expect(resume.examined, 0);
    });

    test('a RE-DELIVERED SMS after an immediate sweep still yields exactly one '
        'transaction (AC-A5.1, product-owner retest step 3)', () async {
      // A carrier redelivery arrives as a *new* inbox row with identical
      // content, so the provider-id UNIQUE constraint cannot help — only the
      // content HMAC can. Same body, new provider id, past the watermark.
      final FakeSmsSource first = FakeSmsSource(<RawSmsRecord>[record()]);
      await pipeline(first).runIncremental();
      expect(await transactionCount(), 1);

      final FakeSmsSource redelivered = FakeSmsSource(<RawSmsRecord>[
        record(),
        record(providerId: 2),
      ]);
      final IngestionRunResult second = await pipeline(
        redelivered,
      ).runIncremental();

      expect(second.examined, 1, reason: 'only the new provider row is read');
      expect(second.suppressedAsExactDuplicate, 1);
      expect(second.transactionsWritten, 0);
      expect(
        await transactionCount(),
        1,
        reason: 'content_hmac is what catches a redelivery under a new id',
      );
    });

    test(
      'the watermark never rewinds when a slower sweep finishes last',
      () async {
        // Three messages, and the two sweeps are started one microtask apart so
        // they genuinely interleave mid-batch rather than one finishing first.
        final FakeSmsSource inbox = FakeSmsSource(<RawSmsRecord>[
          record(providerId: 1),
          record(
            providerId: 2,
            body: _posPurchaseBody.replaceAll('312.40', '44.00'),
          ),
          record(
            providerId: 3,
            body: _posPurchaseBody.replaceAll('312.40', '9.90'),
          ),
        ]);

        final Future<IngestionRunResult> a = pipeline(inbox).runIncremental();
        await Future<void>.delayed(Duration.zero);
        final Future<IngestionRunResult> b = pipeline(inbox).runIncremental();
        await Future.wait(<Future<IngestionRunResult>>[a, b]);

        expect(
          await transactionCount(),
          3,
          reason:
              'three distinct messages, three transactions — no more, no less',
        );
        final IngestWatermarkRow mark = await watermarkDao.current();
        expect(
          mark.lastProcessedSmsProviderId,
          3,
          reason:
              'advanceTo is monotonic in SQL, so the sweep that finishes second '
              'cannot pull the cursor back to where it had got to',
        );

        // And a third sweep afterwards is a genuine no-op, which is what proves
        // the cursor is where it claims to be rather than merely large.
        final IngestionRunResult third = await pipeline(inbox).runIncremental();
        expect(third.examined, 0);
        expect(await transactionCount(), 3);
      },
    );
  });
}
