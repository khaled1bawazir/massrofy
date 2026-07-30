/// **KHA-157 — the incremental watermark is seeded once, before the first
/// sweep ever reads.**
///
/// Normative spec: `docs/architecture.md` ADR-006, the `KHA-157 decision`
/// subsection, item **(G)**.
///
/// ---
///
/// ## The defect, in one sentence
///
/// `lastProcessedSmsProviderId` defaults to `0`, nothing ever seeded it away
/// from `0`, and `SmsChannel.readSince` bounds on `_id` and nothing else — so
/// the first `runIncremental()` on a fresh install read **every SMS the device
/// had ever received**. On the reporting device that put **424 messages from
/// months and years outside AC-A3.1's window** into the Needs Review inbox.
///
/// ## Why the existing suite could not catch it — and what this file does
/// differently
///
/// This is the part worth reading, because a regression test that repeats the
/// original blind spot is worse than none: it certifies the gap.
///
/// Every incremental fixture in this repository is built the same way — an
/// inbox of **in-window** messages, and a watermark left at its default of
/// `0`. Under those two conditions "0 means the beginning of everything" and
/// "0 means we are caught up" produce **identical results**, so no assertion
/// could distinguish them. The bug was not missed through carelessness; the
/// fixture was structurally incapable of expressing it. `docs/lessons.md`
/// records the same fixture-blindness from KHA-137, one version earlier.
///
/// So the fixtures here are deliberately built the other way round:
///
///  1. the inbox is dated **months before** the current window
///     ([_februaryReceivedAt]), so "read everything" and "read nothing" give
///     visibly different answers;
///  2. the watermark starts genuinely **un-seeded** — no
///     `seedWatermarkAtBeginning` anywhere in this file, unlike every other
///     ingestion suite, which now says so explicitly in its own `setUp`.
///
/// The negative control matters as much as the assertion: `pipelineOver` is
/// the real pipeline over the real bundled rule pack, and the same fixture inbox
/// **is** fully ingested once the watermark is seeded at the beginning. So a
/// zero here means "the seed stopped it", not "these messages never parse".
///
/// ## NFR-M3
///
/// Every message body below is fabricated for this file, in the shape of the
/// bundled pack's D360 English POS rule. No real bank SMS is reproduced.
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

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 7);

/// **Months before** any plausible current window — the whole point of this
/// file. February 2026, against fixtures elsewhere dated July 2026.
DateTime _februaryReceivedAt(int n) => DateTime.utc(2026, 2, 3 + n, 11);

/// A message that arrives *after* the seed. Dated far enough in the future
/// that it is unambiguously "new" whatever day the suite runs on.
DateTime _arrivesLaterAt() => DateTime.utc(2030, 1, 15, 9);

/// Fabricated, in the shape of the bundled pack's `d360-pos-purchase-en` rule.
String _purchaseBody(int n) =>
    'D360: Purchase of SAR ${30 + n}.00 with Mada Debit Card ending 4472 '
    'at SYNTHETIC STORE $n on 0${(n % 9) + 1}/02/2026 1${n % 10}:05';

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
    // **No seed here, deliberately.** This is the one suite whose subject is
    // the un-seeded state, so it is the one suite that must not call
    // `seedWatermarkAtBeginning` in `setUp`.
  });

  tearDown(() async => db.close());

  IngestionPipeline pipelineOver(FakeSmsSource source) => IngestionPipeline(
    database: db,
    smsSource: source,
    parser: parser,
    rawMessageDao: rawMessageDao,
    transactionDao: transactionDao,
    watermarkDao: watermarkDao,
    logger: SafeLogger(DiagnosticRingBuffer()),
    contentHmacKey: _testChainKey,
  );

  /// An inbox of [count] out-of-window messages, oldest first.
  FakeSmsSource oldInbox({int count = 5}) => FakeSmsSource(<RawSmsRecord>[
    for (int n = 1; n <= count; n++)
      RawSmsRecord(
        providerId: n,
        address: 'D360',
        body: _purchaseBody(n),
        receivedAt: _februaryReceivedAt(n),
      ),
  ]);

  Future<int> reviewQueueLength() async =>
      (await rawMessageDao.watchReviewQueue().first).length;

  group('(G) the regression: a fresh watermark examines ZERO out-of-window '
      'messages', () {
    test('**the defect, pinned** — the first runIncremental over an inbox of '
        'months-old messages examines none of them', () async {
      final FakeSmsSource inbox = oldInbox();

      final IngestionRunResult first = await pipelineOver(
        inbox,
      ).runIncremental();

      expect(
        first.examined,
        0,
        reason:
            'before KHA-157 this was 5 — and 424 on the reporting device. '
            'A fresh watermark means "we have never ingested", not "start '
            'from the beginning of the phone".',
      );
      expect(await transactionDao.all(), isEmpty);
      expect(await reviewQueueLength(), 0);
      expect(
        await rawMessageDao.all(),
        isEmpty,
        reason:
            'nothing may be RETAINED either. AC-A3.1 never authorised keeping '
            'text from outside the window, so the fix must reduce what is '
            'stored, not merely what is counted (NFR-P4).',
      );
    });

    test('**the negative control** — the very same inbox IS fully ingested '
        'once the watermark is seeded at the beginning, so the zero above is '
        'the seed and not a parsing failure', () async {
      await seedWatermarkAtBeginning(watermarkDao);

      final IngestionRunResult result = await pipelineOver(
        oldInbox(),
      ).runIncremental();

      expect(result.examined, 5);
      expect(result.transactionsWritten, 5);
      expect(await transactionDao.all(), hasLength(5));
    });

    test('the seed lands ON the newest inbox row, not past it and not before '
        'it', () async {
      await pipelineOver(oldInbox()).runIncremental();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.lastProcessedSmsProviderId, 5);
      expect(row.lastProcessedSmsDate, isNotNull);
      expect(
        row.lastProcessedSmsDate!.toUtc(),
        _februaryReceivedAt(5),
        reason:
            'both columns are written together — item (B). A provider id '
            'without a date would destroy the "never seeded" discriminator '
            'permanently, because there is no path back to null.',
      );
    });

    test('the historical import cursor is untouched by the seed — item (D), '
        'the two cursors answer different questions', () async {
      await pipelineOver(oldInbox()).runIncremental();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.importState, importStateIdle);
      expect(row.importCursor, isNull);
      expect(
        row.importFromDate,
        isNull,
        reason:
            '"where does the future start" and "how far back do we look" are '
            'independent, and the importer is the one that honours AC-A3.1',
      );
    });
  });

  group('(G) the property the seed must not break: new messages still arrive', () {
    test(
      '**a message that arrives AFTER the seed is ingested normally**',
      () async {
        final FakeSmsSource inbox = oldInbox();

        // Sweep 1: seeds at provider id 5, ingests nothing.
        expect((await pipelineOver(inbox).runIncremental()).examined, 0);

        // The phone receives a new bank SMS.
        inbox.deliver(
          RawSmsRecord(
            providerId: 6,
            address: 'D360',
            body:
                'D360: Purchase of SAR 64.00 with Mada Debit Card ending 4472 '
                'at SYNTHETIC STORE 6 on 15/01/2030 09:05',
            receivedAt: _arrivesLaterAt(),
          ),
        );

        // Sweep 2: the watermark is seeded now, so this is a genuine
        // incremental read.
        final IngestionRunResult second = await pipelineOver(
          inbox,
        ).runIncremental();

        expect(
          second.examined,
          1,
          reason:
              'exactly the new one. If this were 6 the seed would not have '
              'held; if it were 0 the seed would have swallowed the future, '
              'which is the failure mode worth fearing more.',
        );
        expect(second.transactionsWritten, 1);
        expect(await transactionDao.all(), hasLength(1));
        expect((await watermarkDao.current()).lastProcessedSmsProviderId, 6);
      },
    );

    test('a message arriving in the window BETWEEN the read and the write is '
        'not lost — item (C)\'s ordering rule', () async {
      final FakeSmsSource inbox = oldInbox();

      // The seed reads the high-water mark (5) and writes it. A message that
      // lands during that window has an id ABOVE what was written, which is
      // the whole reason the ADR requires read-then-write and forbids
      // re-reading afterwards.
      await pipelineOver(inbox).runIncremental();
      inbox.deliver(
        RawSmsRecord(
          providerId: 6,
          address: 'D360',
          body:
              'D360: Purchase of SAR 12.00 with Mada Debit Card ending 4472 '
              'at SYNTHETIC STORE 7 on 15/01/2030 09:06',
          receivedAt: _arrivesLaterAt(),
        ),
      );

      expect(
        (await pipelineOver(inbox).runIncremental()).transactionsWritten,
        1,
      );
    });

    test('the seed happens exactly once — a second sweep reads the inbox '
        'normally rather than re-seeding', () async {
      final FakeSmsSource inbox = oldInbox();
      final IngestionPipeline pipeline = pipelineOver(inbox);

      await pipeline.runIncremental();
      await pipeline.runIncremental();
      await pipeline.runIncremental();

      expect(
        inbox.highWaterMarkCallCount,
        1,
        reason:
            'the guard is `lastProcessedSmsDate IS NULL`, and one write leaves '
            'that state forever',
      );
    });
  });

  group('(A) an unreadable inbox is NOT an empty one', () {
    test(
      '**the load-bearing distinction** — with no permission the watermark '
      'is left un-seeded, so granting permission later does not flood',
      () async {
        final FakeSmsSource inbox = oldInbox()..isReadable = false;

        final IngestionRunResult denied = await pipelineOver(
          inbox,
        ).runIncremental();

        expect(denied.examined, 0);
        expect(
          (await watermarkDao.current()).lastProcessedSmsDate,
          isNull,
          reason:
              'seeding while the inbox is unreadable would record 0, mark the '
              'watermark seeded, and hand the entire device history to the '
              'first sweep that HAS permission — reproducing this exact bug',
        );

        // The user grants permission in Android Settings. No callback fires;
        // the next ordinary sweep is what notices (item (C)).
        inbox.isReadable = true;
        final IngestionRunResult granted = await pipelineOver(
          inbox,
        ).runIncremental();

        expect(
          granted.examined,
          0,
          reason: 'it seeds now, and still ingests nothing out of window',
        );
        expect((await watermarkDao.current()).lastProcessedSmsProviderId, 5);
        expect(await rawMessageDao.all(), isEmpty);
      },
    );

    test('a readable but EMPTY inbox seeds at 0 with a real date, so a device '
        'with no SMS yet still ingests its first message', () async {
      final FakeSmsSource empty = FakeSmsSource(
        <RawSmsRecord>[],
        emptyInboxNowUtc: DateTime.utc(2026, 7, 30, 9),
      );

      await pipelineOver(empty).runIncremental();

      final IngestWatermarkRow row = await watermarkDao.current();
      expect(row.lastProcessedSmsProviderId, 0);
      expect(
        row.lastProcessedSmsDate,
        isNotNull,
        reason:
            'the DATE is what marks it seeded (item (B)); an empty inbox that '
            'left it null would re-seed on every sweep forever',
      );

      empty.deliver(
        RawSmsRecord(
          providerId: 1,
          address: 'D360',
          body: _purchaseBody(1),
          receivedAt: DateTime.utc(2026, 7, 30, 10),
        ),
      );

      expect((await pipelineOver(empty).runIncremental()).examined, 1);
    });
  });
}
