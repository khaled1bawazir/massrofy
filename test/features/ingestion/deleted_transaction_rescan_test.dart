/// **AC-B6.3 — a deleted transaction is NOT resurrected by re-scanning its
/// source SMS.** KHA-26, US-B6, US-B8, ADR-017 D1.
///
/// ---
///
/// ## Why this needs its own test, given soft delete "obviously" handles it
///
/// It is easy to assume the row simply still being there is the whole answer.
/// It is not, and the distinction matters because a future change could break
/// either half independently:
///
///  1. **The message never reaches the transaction layer again.**
///     `raw_message.content_hmac` is UNIQUE (ADR-017 D1), so a second sighting
///     of the same SMS is suppressed before it is parsed. *This* is the
///     mechanism that actually fires on a re-scan.
///  2. **Even if it did, there is nothing to re-create.** The deleted row was
///     never removed. A *hard* delete would have removed it, and the next
///     sweep would happily write it back — which is precisely the resurrection
///     AC-B6.3 forbids, and the reason OQ-8/X17 chose soft delete.
///
/// The tests below exercise a genuine re-scan through the real pipeline rather
/// than asserting either mechanism in isolation, so a regression in either one
/// fails here.
///
/// ## The failure this prevents is a trust failure, not a data-loss one
///
/// A user deletes a transaction they know is wrong. The next background sweep
/// puts it back. They delete it again. It returns. Nothing in the app explains
/// why, their monthly total is wrong in a way they cannot fix, and the product
/// has stopped being something they can rely on — which is the entire value
/// proposition (`docs/PRD.md`).
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
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_edit.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import 'support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 91);

final PeriodRange _july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

void main() {
  late AppDatabase db;
  late TransactionDao transactionDao;
  late TransactionEditService editService;
  late IngestionPipeline pipeline;

  /// One ordinary, fully parseable purchase — the corpus's `d360-01`.
  final List<RawSmsRecord> inbox = <RawSmsRecord>[
    RawSmsRecord(
      providerId: 1,
      address: 'D360',
      body:
          'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
          'at BALAD COFFEE ROASTERS on 28/07/2026 15:10',
      receivedAt: DateTime.utc(2026, 7, 28, 12, 10),
    ),
  ];

  setUp(() {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    transactionDao = TransactionDao(db, auditLogDao);
    editService = TransactionEditService(
      database: db,
      transactionDao: transactionDao,
    );
    pipeline = IngestionPipeline(
      database: db,
      smsSource: FakeSmsSource(inbox),
      parser: RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]),
      rawMessageDao: RawMessageDao(db),
      transactionDao: transactionDao,
      watermarkDao: IngestWatermarkDao(db),
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
    );
  });

  tearDown(() async => db.close());

  /// A **full** re-scan over the same inbox, the way a re-run of the
  /// historical importer does it.
  Future<void> rescan() => pipeline.processAll(inbox, advanceWatermark: false);

  Future<PeriodTotals> spend() async => LedgerTotals.spend(
    toLedgerTransactions(await transactionDao.all()),
    period: _july2026,
  );

  group('AC-B6.3 — the deletion survives a re-scan', () {
    test('a deleted transaction does not come back', () async {
      await pipeline.runIncremental();
      final List<TransactionRow> written = await transactionDao.all();
      expect(written, hasLength(1));

      await editService.softDelete(written.single.id);
      expect(await transactionDao.watchLive().first, isEmpty);

      await rescan();

      expect(
        await transactionDao.watchLive().first,
        isEmpty,
        reason:
            'AC-B6.3: re-scanning the source SMS must not resurrect a '
            'transaction the user deleted',
      );
    });

    test('and no SECOND transaction is written for the same message either — '
        'resurrection by duplication is the same defect wearing a different '
        'id', () async {
      await pipeline.runIncremental();
      await editService.softDelete((await transactionDao.all()).single.id);

      await rescan();
      await rescan();

      // One row, still deleted. Not two rows, one of them live.
      expect(await transactionDao.all(), hasLength(1));
      expect((await transactionDao.all()).single.isDeleted, isTrue);
    });

    test(
      'the period total stays without it across the re-scan (AC-B6.1)',
      () async {
        await pipeline.runIncremental();
        expect((await spend()).base!.toCanonicalString(), '89');

        await editService.softDelete((await transactionDao.all()).single.id);
        expect((await spend()).isEmpty, isTrue);

        await rescan();

        expect(
          (await spend()).isEmpty,
          isTrue,
          reason: 'the figure the user corrected must stay corrected',
        );
      },
    );

    test('the deleted row is retained, so US-B8 restore still works after the '
        're-scan', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;
      await editService.softDelete(id);
      await rescan();

      await editService.restore(id);

      expect((await spend()).base!.toCanonicalString(), '89');
      // Same row, same id, so the whole history is still addressable.
      expect(
        (await AuditLogDao(db, auditChainKey: _testChainKey).queryFor(
          'transaction',
          id.toString(),
        )).map((AuditEntryRow e) => e.action),
        <String>['create', 'delete', 'restore'],
      );
    });
  });

  group('the two mechanisms, separately', () {
    test('ADR-017 D1 — the re-scan never re-parses the message, because the '
        'content HMAC already exists', () async {
      await pipeline.runIncremental();
      final RawMessageDao rawMessageDao = RawMessageDao(db);
      expect(await rawMessageDao.all(), hasLength(1));

      await editService.softDelete((await transactionDao.all()).single.id);
      await rescan();

      // No second raw_message row, therefore no second parse, therefore no
      // opportunity to write a replacement transaction.
      expect(await rawMessageDao.all(), hasLength(1));
    });

    test('the soft delete left the row in place, so there is nothing missing '
        'for a sweep to fill in', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;
      await editService.softDelete(id);

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.isDeleted, isTrue);
      // Its provenance is intact, which is what would have let a naive
      // "re-import anything missing" implementation recognise it as present.
      expect(row.sourceMessageId, isNotNull);
      expect(row.amountAmount, '89');
    });

    test('a deleted transaction does not suppress or flag a genuinely NEW '
        'purchase — the protection is targeted', () async {
      await pipeline.runIncremental();
      await editService.softDelete((await transactionDao.all()).single.id);

      // A different message, same card, later the same day.
      await pipeline.processAll(<RawSmsRecord>[
        RawSmsRecord(
          providerId: 2,
          address: 'D360',
          body:
              'D360: Purchase of SAR 41.50 with Mada Debit Card ending 4472 '
              'at BALAD COFFEE ROASTERS on 28/07/2026 18:40',
          receivedAt: DateTime.utc(2026, 7, 28, 15, 40),
        ),
      ], advanceWatermark: false);

      final PeriodTotals totals = await spend();
      expect(
        totals.base!.toCanonicalString(),
        '41.5',
        reason: 'the new purchase counts; only the deleted one stays out',
      );
    });
  });
}
