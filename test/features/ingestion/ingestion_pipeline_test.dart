/// End-to-end tests for the ingestion pipeline: a fake inbox, the **real**
/// bundled rule pack, and a real (unencrypted, in-memory) database.
///
/// This is where the P2 exit check's second half is proved *against the
/// database*, not only against the parser:
///
/// > *"no fixture is silently discarded (NFR-A7) — every input either parses
/// > successfully or lands in the review queue, nothing vanishes."*
///
/// `rule_pack_corpus_test.dart` proves the parser reaches the right verdict.
/// This file proves the pipeline **acts** on that verdict correctly: writes
/// the transaction, or writes the review-queue row, or writes the
/// content-free counter row, or writes nothing at all — and that the counts
/// add up in every case.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
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

  IngestionPipeline buildPipeline(FakeSmsSource source) => IngestionPipeline(
    database: db,
    smsSource: source,
    parser: parser,
    rawMessageDao: rawMessageDao,
    transactionDao: transactionDao,
    watermarkDao: watermarkDao,
    logger: logger,
    contentHmacKey: _testChainKey,
  );

  /// Turns a corpus fixture into an inbox row.
  RawSmsRecord asRecord(SmsFixture fixture, int providerId) => RawSmsRecord(
    providerId: providerId,
    address: fixture.sender,
    body: fixture.body,
    receivedAt: DateTime.utc(
      2026,
      7,
      28,
      12,
    ).add(Duration(minutes: providerId)),
  );

  group('the whole synthetic corpus, through the real pipeline', () {
    test('NFR-A7 — every message is accounted for, none vanish', () async {
      final List<RawSmsRecord> inbox = <RawSmsRecord>[
        for (int i = 0; i < allFixtures.length; i++)
          asRecord(allFixtures[i], i + 1),
      ];
      final FakeSmsSource source = FakeSmsSource(inbox);
      final IngestionPipeline pipeline = buildPipeline(source);

      final IngestionRunResult result = await pipeline.runIncremental();

      expect(result.examined, inbox.length);
      expect(
        result.isFullyAccountedFor,
        isTrue,
        reason:
            'a message fell through an unhandled path — this is the alarm '
            'NFR-A7 exists to raise, and it is arithmetic, not a hunch. $result',
      );
      expect(
        result.failedWithError,
        0,
        reason:
            'no fixture should throw; a throw here means NFR-R5 is being '
            'relied on to paper over a real bug',
      );
    });

    test('every financial message ends as a transaction, a review item, or a '
        'content-free counter row — and non-financial senders leave NO row '
        '(NFR-P4)', () async {
      final List<RawSmsRecord> inbox = <RawSmsRecord>[
        for (int i = 0; i < allFixtures.length; i++)
          asRecord(allFixtures[i], i + 1),
      ];
      await buildPipeline(FakeSmsSource(inbox)).runIncremental();

      final List<RawMessageRow> rows = await rawMessageDao.all();
      final int nonFinancialCount = allFixtures
          .where((SmsFixture f) => f.expect == ExpectedOutcome.notFinancial)
          .length;

      expect(
        rows.length,
        allFixtures.length - nonFinancialCount,
        reason:
            'exactly the financial messages get a row. A non-financial '
            'sender must leave no trace at all — not even a timestamp — '
            'which is a promise the transparency screen (US-F4) makes out '
            'loud.',
      );

      // …and none of the senders we did not recognise appears anywhere.
      final Set<String> storedSenders = rows
          .map((RawMessageRow r) => r.sender)
          .toSet();
      for (final SmsFixture fixture in allFixtures) {
        if (fixture.expect == ExpectedOutcome.notFinancial) {
          expect(storedSenders, isNot(contains(fixture.sender)));
        }
      }
    });

    test('an ignored (OTP/marketing/balance) message stores NO body — only a '
        'counter row (NFR-P4, architecture §4.2 retention rules)', () async {
      final SmsFixture otp = aljaziraFixtures.firstWhere(
        (SmsFixture f) => f.id.contains('otp'),
      );
      await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[asRecord(otp, 1)]),
      ).runIncremental();

      final List<RawMessageRow> rows = await rawMessageDao.all();
      expect(rows, hasLength(1));
      expect(rows.single.classification, 'ignored_otp');
      expect(
        rows.single.sanitizedBody,
        isNull,
        reason:
            'storing an OTP body — even redacted — would retain a security '
            'code we have no business keeping. NFR-P4 permits the bank, the '
            'classification and the timestamp, and nothing else.',
      );
    });

    test(
      'an unparsed financial message reaches the review queue WITH its '
      'sanitised text, so the user can complete it (US-A4, AC-A4.1/A4.2)',
      () async {
        final SmsFixture unknown = aljaziraFixtures.firstWhere(
          (SmsFixture f) => f.id.contains('unknown-template'),
        );
        await buildPipeline(
          FakeSmsSource(<RawSmsRecord>[asRecord(unknown, 1)]),
        ).runIncremental();

        final List<RawMessageRow> queue = await rawMessageDao
            .watchReviewQueue()
            .first;

        expect(queue, hasLength(1));
        expect(queue.single.classification, 'financial_unparsed');
        expect(queue.single.sanitizedBody, isNotNull);
        expect(queue.single.bankId, 'bank-aljazira');
        expect(queue.single.unparsedReason, 'no_rule_matched');
        expect(
          await transactionDao.all(),
          isEmpty,
          reason:
              'a message we did not understand must never become a '
              'half-invented transaction',
        );
      },
    );
  });

  group('ADR-006 — one message is one database transaction', () {
    test('a write that fails midway leaves NO trace, so D1 cannot suppress '
        'the retry', () async {
      // ## The crash window this pins down
      //
      // `_writeTransaction` writes the raw-message row first and the
      // transaction row second. The raw-message row carries the
      // `content_hmac` that ADR-017 D1 dedups on. So if the first write
      // committed and the second did not, the next sweep would look up the
      // HMAC, find it, conclude "already processed", and suppress the message
      // — permanently. The transaction row would never be written and nothing
      // anywhere would say so: a financial message lost *through* the
      // mechanism that exists to protect it (NFR-A7).
      //
      // The fix is that each message is processed inside
      // `database.transaction(...)`, so both rows commit together or neither
      // does. This test simulates the failure by making the audit-chain write
      // — which happens inside `insertFromParsedSms`, i.e. after the
      // raw-message row — throw.
      final SmsFixture purchase = d360Fixtures.first;
      final IngestionPipeline failing = IngestionPipeline(
        database: db,
        smsSource: FakeSmsSource(<RawSmsRecord>[]),
        parser: parser,
        rawMessageDao: rawMessageDao,
        transactionDao: TransactionDao(
          db,
          _FailingAuditLogDao(db, auditChainKey: _testChainKey),
        ),
        watermarkDao: watermarkDao,
        logger: logger,
        contentHmacKey: _testChainKey,
      );

      final IngestionRunResult result = await failing.processAll(<RawSmsRecord>[
        asRecord(purchase, 1),
      ], advanceWatermark: true);

      expect(result.failedWithError, 1);
      expect(
        await rawMessageDao.all(),
        isEmpty,
        reason:
            'the raw-message row must have been rolled back. If it survives, '
            'its content_hmac makes the message look already-processed and '
            'the transaction is never written — silently, forever.',
      );
      expect(
        (await watermarkDao.current()).lastProcessedSmsProviderId,
        0,
        reason:
            'nothing was successfully processed, so nothing to advance past',
      );

      // The other half: with the failure gone, the message is picked up
      // normally. "Rolled back" is only useful if the retry then works.
      await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[asRecord(purchase, 1)]),
      ).runIncremental();

      expect(await transactionDao.all(), hasLength(1));
      expect((await watermarkDao.current()).lastProcessedSmsProviderId, 1);
    });
  });

  group('ADR-017 D1 — exact duplicates', () {
    test('the same message re-read from the provider produces one transaction, '
        'not two (AC-A3.3 — re-scan idempotency)', () async {
      final SmsFixture purchase = d360Fixtures.first;
      final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
        asRecord(purchase, 1),
      ]);
      final IngestionPipeline pipeline = buildPipeline(source);

      await pipeline.runIncremental();
      // Force a re-read of the same row by rewinding nothing — instead,
      // process the identical record again directly, which is exactly what
      // a watermark reset (or a restored SMS database) would cause.
      final IngestionRunResult second = await pipeline.processAll(
        <RawSmsRecord>[asRecord(purchase, 1)],
        advanceWatermark: false,
      );

      expect(second.suppressedAsExactDuplicate, 1);
      expect(await transactionDao.all(), hasLength(1));
    });

    test(
      'a carrier redelivery — same content, NEW provider id, arriving '
      '43 s LATER — is also suppressed (AC-A5.1, the content-HMAC key)',
      () async {
        final SmsFixture purchase = d360Fixtures.first;
        final IngestionPipeline pipeline = buildPipeline(
          FakeSmsSource(<RawSmsRecord>[]),
        );

        final RawSmsRecord first = asRecord(purchase, 1);
        // Same body, same sender; different `_id` **and a different
        // `receivedAt`**. Both differences are essential and this test used to
        // have only the first (KHA-137):
        //
        //  - a new `_id`, because a redelivery lands as a new inbox row, so
        //    the `sms_provider_id` key cannot help — that is why ADR-017 D1
        //    has two keys rather than one;
        //  - a **later** `receivedAt`, because a redelivery is *defined* by
        //    arriving at a different instant. Holding it fixed (as this test
        //    originally did) is the one thing a real redelivery cannot do, so
        //    the old test passed against a `content_hmac` that folded the
        //    delivery time in and therefore could never have caught the field
        //    failure. QA's device repro measured the real gap at 43,287 ms.
        //
        // 43 s is used literally: this is the shape that reproduced the bug.
        final RawSmsRecord redelivered = RawSmsRecord(
          providerId: 2,
          address: first.address,
          body: first.body,
          receivedAt: first.receivedAt.add(const Duration(seconds: 43)),
        );

        final IngestionRunResult result = await pipeline.processAll(
          <RawSmsRecord>[first, redelivered],
          advanceWatermark: true,
        );

        expect(await transactionDao.all(), hasLength(1));
        // Not just "one transaction" — one transaction *because the second was
        // recognised as a duplicate*. Without this, the assertion above would
        // also pass if the second message had failed to parse for some
        // unrelated reason.
        expect(result.suppressedAsExactDuplicate, 1);
      },
    );

    test('the redelivery gap does not matter — an hour later is still one '
        'transaction (AC-A5.1)', () async {
      // A store-and-forward retry can be far more than a minute late. Any
      // window-based mitigation would fail here, which is part of why the
      // KHA-137 decision rejected one; this pins that the digest is genuinely
      // time-independent rather than merely tolerant of small gaps.
      final SmsFixture purchase = d360Fixtures.first;
      final IngestionPipeline pipeline = buildPipeline(
        FakeSmsSource(<RawSmsRecord>[]),
      );
      final RawSmsRecord first = asRecord(purchase, 1);

      final IngestionRunResult result = await pipeline
          .processAll(<RawSmsRecord>[
            first,
            RawSmsRecord(
              providerId: 2,
              address: first.address,
              body: first.body,
              receivedAt: first.receivedAt.add(const Duration(hours: 1)),
            ),
          ], advanceWatermark: true);

      expect(await transactionDao.all(), hasLength(1));
      expect(result.suppressedAsExactDuplicate, 1);
    });

    test('a PRE-FIX row (stale v1 digest, same provider id) is re-scanned as a '
        'counted duplicate, not a pipeline stall (KHA-137 (D))', () async {
      // The migration hazard KHA-137's decision calls non-negotiable, tested
      // end to end rather than argued.
      //
      // v2 shifts *every* stored digest, so the first re-scan over a message
      // ingested before the update misses on `content_hmac`. If that were the
      // only pre-check, the write would then hit `sms_provider_id UNIQUE`,
      // throw, and the run would report `failedWithError` — which sets
      // `advancingIsSafe = false` and pauses the import. A benign duplicate
      // would be shown to the user as a stalled pipeline.
      //
      // KHA-133 item (F)'s `findBySmsProviderId` pre-check is what prevents
      // that, and this asserts the two changes actually compose. The stale row
      // is planted with a digest that is deliberately NOT recomputable under
      // v2 — that is the whole point: it stands in for a v1 digest.
      final SmsFixture purchase = d360Fixtures.first;
      final RawSmsRecord record = asRecord(purchase, 1);

      await rawMessageDao.insert(
        smsProviderId: '1',
        sender: record.address,
        receivedAt: record.receivedAt,
        sanitizedText: SmsSanitizer.sanitize(record.body),
        contentHmac: 'stale-v1-digest-from-before-the-KHA-137-update',
        bankId: 'd360',
        classification: 'financial_parsed',
      );

      final IngestionRunResult rescan = await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[record]),
      ).processAll(<RawSmsRecord>[record], advanceWatermark: true);

      expect(
        rescan.failedWithError,
        0,
        reason:
            'a stale digest must not become an unhandled UNIQUE violation — '
            'that is the stall KHA-137 (D) exists to prevent',
      );
      expect(rescan.suppressedAsExactDuplicate, 1);
      expect(rescan.transactionsWritten, 0);
    });

    test('a redelivery whose SENDER differs only in CASE is still suppressed '
        '(KHA-137 — the sender is canonicalised too)', () async {
      // `senderPatterns` compile with `caseSensitive: false`, so the parser
      // reads `D360` and `d360` as one bank. Before KHA-137 the digest read
      // them as two messages, so the two layers disagreed about what "the
      // same message" is — the same class of defect as the timestamp, one
      // level down.
      //
      // **Scope note, measured rather than assumed.** `ContentHmac` also runs
      // the sender through `SmsTextNormalizer.normalize`, which strips bidi
      // and zero-width marks. That half is NOT asserted here, because it is
      // unreachable from this seam: a sender carrying, say, a U+200F prefix
      // fails `senderPatterns` first and the message is discarded as
      // non-financial before any digest is computed. The normalisation is
      // still right (it costs nothing and keeps the sender and body halves
      // consistent), but the property that would need a test is
      // sender *recognition*, not dedup — a different layer, pre-existing,
      // and out of KHA-137's scope.
      final SmsFixture purchase = d360Fixtures.first;
      final IngestionPipeline pipeline = buildPipeline(
        FakeSmsSource(<RawSmsRecord>[]),
      );
      final RawSmsRecord first = asRecord(purchase, 1);

      final IngestionRunResult result = await pipeline
          .processAll(<RawSmsRecord>[
            first,
            RawSmsRecord(
              providerId: 2,
              address: first.address.toLowerCase(),
              body: first.body,
              receivedAt: first.receivedAt.add(const Duration(seconds: 43)),
            ),
          ], advanceWatermark: true);

      expect(await transactionDao.all(), hasLength(1));
      expect(result.suppressedAsExactDuplicate, 1);
    });

    test(
      'AC-A5.3 — two genuinely separate purchases at the same merchant, same '
      'amount, same day are BOTH retained',
      () async {
        // Identical merchant and amount, 40 minutes apart: outside ADR-017
        // D3's 15-minute window, so not even flagged. Both must survive.
        const String bodyA =
            'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
            'at BALAD COFFEE ROASTERS on 28/07/2026 09:00';
        const String bodyB =
            'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
            'at BALAD COFFEE ROASTERS on 28/07/2026 09:40';

        await buildPipeline(
          FakeSmsSource(<RawSmsRecord>[]),
        ).processAll(<RawSmsRecord>[
          RawSmsRecord(
            providerId: 1,
            address: 'D360',
            body: bodyA,
            receivedAt: DateTime.utc(2026, 7, 28, 6),
          ),
          RawSmsRecord(
            providerId: 2,
            address: 'D360',
            body: bodyB,
            receivedAt: DateTime.utc(2026, 7, 28, 6, 40),
          ),
        ], advanceWatermark: true);

        expect(
          await transactionDao.all(),
          hasLength(2),
          reason:
              'silently deleting one of two real purchases is the '
              'unrecoverable failure ADR-017 biases away from',
        );
      },
    );

    test('AC-A5.2 — a same-instrument, same-amount, same-merchant pair inside '
        'the window is FLAGGED on both sides and neither is removed', () async {
      const String body =
          'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
          'at BALAD COFFEE ROASTERS on 28/07/2026 09:00';
      // Same charge, second alert five minutes later. Different body text
      // (so D1 does not catch it) but the same parsed facts.
      const String bodyPosting =
          'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
          'at BALAD COFFEE ROASTERS on 28/07/2026 09:05';

      await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[]),
      ).processAll(<RawSmsRecord>[
        RawSmsRecord(
          providerId: 1,
          address: 'D360',
          body: body,
          receivedAt: DateTime.utc(2026, 7, 28, 6),
        ),
        RawSmsRecord(
          providerId: 2,
          address: 'D360',
          body: bodyPosting,
          receivedAt: DateTime.utc(2026, 7, 28, 6, 5),
        ),
      ], advanceWatermark: true);

      final List<TransactionRow> rows = await transactionDao.all();
      expect(rows, hasLength(2), reason: 'never auto-removed');
      expect(
        rows.every((TransactionRow r) => r.needsReview),
        isTrue,
        reason:
            'both sides must be flagged — a flag on only one is invisible '
            'from the other, which is how the user misses it',
      );
      expect(
        rows.every((TransactionRow r) => r.possibleDuplicateOfId != null),
        isTrue,
      );
      expect(
        rows.every((TransactionRow r) => !r.isDeleted),
        isTrue,
        reason: 'ADR-017 forbids any automatic removal, full stop',
      );
    });
  });

  group('ADR-006 — the watermark', () {
    test('advances past every processed message', () async {
      final List<RawSmsRecord> inbox = <RawSmsRecord>[
        for (int i = 0; i < 5; i++) asRecord(d360Fixtures[i], i + 1),
      ];
      await buildPipeline(FakeSmsSource(inbox)).runIncremental();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.lastProcessedSmsProviderId, 5);
    });

    test('a second run picks up only what is new — the whole point of the '
        'watermark', () async {
      final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
        asRecord(d360Fixtures[0], 1),
      ]);
      final IngestionPipeline pipeline = buildPipeline(source);
      await pipeline.runIncremental();

      source.messages.add(asRecord(d360Fixtures[2], 2));
      final IngestionRunResult second = await pipeline.runIncremental();

      expect(
        second.examined,
        1,
        reason: 'the already-processed message must not be re-examined',
      );
    });

    test('the watermark is monotonic — a slow concurrent sweep finishing last '
        'cannot rewind a faster one', () async {
      await watermarkDao.advanceTo(
        smsProviderId: 100,
        smsDate: DateTime.utc(2026, 7, 28),
      );
      await watermarkDao.advanceTo(
        smsProviderId: 42,
        smsDate: DateTime.utc(2026, 7, 27),
      );

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(
        row.lastProcessedSmsProviderId,
        100,
        reason:
            'rewinding would make every subsequent sweep re-read the same '
            'messages forever',
      );
    });
  });

  group('NFR-A1 — provenance is written at the moment of the write', () {
    test('a parsed transaction records its pack, version and rule', () async {
      await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[asRecord(d360Fixtures[0], 1)]),
      ).runIncremental();

      final TransactionRow row = (await transactionDao.all()).single;
      expect(row.provenance, 'sms');
      expect(row.rulePackId, 'sa-core');
      expect(row.rulePackVersion, isNotNull);
      expect(row.ruleId, 'd360-pos-purchase-en');
      expect(
        row.sourceMessageId,
        isNotNull,
        reason:
            'AC-B1.2 lets the user open a transaction and read the message it '
            'came from; that needs the link stored, not recomputed',
      );
    });

    test(
      'the audit entry names the PARSER as actor, with the rule — not a bare '
      '"created" (NFR-A2, US-F5)',
      () async {
        await buildPipeline(
          FakeSmsSource(<RawSmsRecord>[asRecord(d360Fixtures[0], 1)]),
        ).runIncremental();

        final TransactionRow row = (await transactionDao.all()).single;
        final AuditLogDao auditDao = AuditLogDao(
          db,
          auditChainKey: _testChainKey,
        );
        final List<AuditEntryRow> entries = await auditDao.queryFor(
          'transaction',
          row.id.toString(),
        );

        expect(entries, isNotEmpty);
        final AuditEntryRow created = entries.firstWhere(
          (AuditEntryRow e) => e.action == 'create',
        );
        expect(
          created.actor,
          'parser',
          reason:
              'NFR-A2 distinguishes "the user did this" from "a rule did '
              'this"; recording ingestion as a user action would make the '
              'change history actively misleading',
        );
        expect(created.actorDetail, contains('d360-pos-purchase-en'));
      },
    );
  });

  group('NFR-R5 — one bad message never stops the batch', () {
    test(
      'a message that throws is counted, and the messages after it are still '
      'processed',
      () async {
        // A parser that throws for one specific sender, to simulate a genuine
        // internal failure rather than a parse *verdict*.
        final IngestionPipeline pipeline = IngestionPipeline(
          database: db,
          smsSource: FakeSmsSource(<RawSmsRecord>[]),
          parser: ThrowingParser(parser, throwForSender: 'BAJ'),
          rawMessageDao: rawMessageDao,
          transactionDao: transactionDao,
          watermarkDao: watermarkDao,
          logger: logger,
          contentHmacKey: _testChainKey,
        );

        final IngestionRunResult result = await pipeline.processAll(
          <RawSmsRecord>[
            asRecord(aljaziraFixtures[0], 1), // throws
            asRecord(d360Fixtures[0], 2), // must still be processed
          ],
          advanceWatermark: true,
        );

        expect(result.failedWithError, 1);
        expect(result.transactionsWritten, 1);
        expect(result.isFullyAccountedFor, isTrue);
        expect(await transactionDao.all(), hasLength(1));
      },
    );

    test(
      'the watermark does NOT advance past a failed message, even though the '
      'messages after it were processed',
      () async {
        // The subtle, silent bug this pins down:
        //
        // Messages are processed oldest-first and the watermark is monotonic.
        // If #1 throws and #2 then succeeds, naively advancing to #2 moves
        // the watermark PAST #1 — and since every later sweep reads only
        // `_id > watermark`, #1 would never be read again. It would be lost
        // permanently, silently, with nothing anywhere indicating a problem.
        // That is precisely the failure NFR-A7 exists to make impossible.
        final IngestionPipeline pipeline = IngestionPipeline(
          database: db,
          smsSource: FakeSmsSource(<RawSmsRecord>[]),
          parser: ThrowingParser(parser, throwForSender: 'BAJ'),
          rawMessageDao: rawMessageDao,
          transactionDao: transactionDao,
          watermarkDao: watermarkDao,
          logger: logger,
          contentHmacKey: _testChainKey,
        );

        await pipeline.processAll(<RawSmsRecord>[
          asRecord(aljaziraFixtures[0], 1), // throws
          asRecord(d360Fixtures[0], 2), // succeeds
        ], advanceWatermark: true);

        final IngestWatermarkRow row = await watermarkDao.current();
        expect(
          row.lastProcessedSmsProviderId,
          0,
          reason:
              'advancing to 2 would strand message 1 forever. Re-reading '
              'message 2 on the next sweep costs nothing — ADR-017 D1 '
              'suppresses it — whereas losing message 1 is unrecoverable.',
        );
      },
    );

    test('a successful run with NO failures does advance the watermark — the '
        'guard above must not be a permanent brake', () async {
      await buildPipeline(
        FakeSmsSource(<RawSmsRecord>[
          asRecord(d360Fixtures[0], 1),
          asRecord(d360Fixtures[2], 2),
        ]),
      ).runIncremental();

      expect((await watermarkDao.current()).lastProcessedSmsProviderId, 2);
    });
  });

  group('a backlog is drained across batches, not one batch per sweep', () {
    test(
      'a single runIncremental picks up more than one batch — a user coming '
      'back after a week does not get their inbox a hundred at a time',
      () async {
        // Twelve distinct purchases, a batch limit of 5. One sweep must
        // process all twelve, not five.
        final List<RawSmsRecord> inbox = <RawSmsRecord>[
          for (int i = 1; i <= 12; i++)
            RawSmsRecord(
              providerId: i,
              address: 'D360',
              // Distinct amount, merchant and time per message, so none is
              // suppressed by ADR-017 D1 (identical content) or flagged by
              // D3 (same instrument + amount + merchant inside 15 minutes) —
              // this test is about batching, and either would muddy it.
              body:
                  'D360: Purchase of SAR ${100 + i}.00 with Mada Debit Card '
                  'ending 4472 at MERCHANT $i on '
                  '${i.toString().padLeft(2, '0')}/07/2026 1${i % 10}:00',
              receivedAt: DateTime.utc(
                2026,
                7,
                28,
                6,
              ).add(Duration(minutes: i)),
            ),
        ];

        final IngestionPipeline pipeline = IngestionPipeline(
          database: db,
          smsSource: FakeSmsSource(inbox),
          parser: parser,
          rawMessageDao: rawMessageDao,
          transactionDao: transactionDao,
          watermarkDao: watermarkDao,
          logger: logger,
          contentHmacKey: _testChainKey,
          batchLimit: 5,
        );

        final IngestionRunResult result = await pipeline.runIncremental();

        expect(result.examined, 12);
        expect(result.isFullyAccountedFor, isTrue);
        expect((await watermarkDao.current()).lastProcessedSmsProviderId, 12);
      },
    );
  });
}

/// An [AuditLogDao] whose `append` always throws.
///
/// Used to fail a write **after** the raw-message row is inserted but before
/// the transaction row is committed — the audit entry is written inside
/// `TransactionDao.insertFromParsedSms`, which is exactly the middle of the
/// unit of work. That is the one crash window in the pipeline that could lose
/// a message permanently, so it is the one worth simulating.
final class _FailingAuditLogDao extends AuditLogDao {
  _FailingAuditLogDao(super.attachedDatabase, {required super.auditChainKey});

  @override
  Future<int> append({
    required String entityType,
    required String entityId,
    required String action,
    required String actor,
    String? actorDetail,
    required DateTime changedAt,
    required List<AuditFieldChange> fieldChanges,
  }) async {
    throw StateError('simulated failure partway through the write');
  }
}
