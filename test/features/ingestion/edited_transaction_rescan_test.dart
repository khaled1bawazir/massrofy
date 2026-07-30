/// **QA probe — the AC-B5.3 half PR #20 did not test.** KHA-26, PR #20 head
/// `61efd7b`, written by qa-tester 2026-07-29.
///
/// ---
///
/// ## Why this file exists separately from `qa_pr20_probe_test.dart`
///
/// It needs the real `IngestionPipeline`, the real rule pack and the real
/// `RawMessageDao` — the same rig `deleted_transaction_rescan_test.dart` uses
/// — rather than the bare DAO harness the merge probes run on.
///
/// **P3b-3 (KHA-89 / D-QA-13): moved here from `test/security/` and renamed**,
/// as QA asked, so it sits beside `deleted_transaction_rescan_test.dart` — its
/// exact sibling, one AC apart. It is a re-scan test, not a security probe;
/// filing it by the rig it happened to be written next to would have hidden it
/// from whoever next goes looking for "what covers AC-B5.3's re-scan half?".
///
/// ## The gap
///
/// AC-B5.3 has two halves. KHA-26 states them together:
///
/// > *"A later re-scan of SMS must NOT overwrite the user's edit (AC-B5.3).
/// > User intent outranks the parser, always."*
///
/// and its done-check names the test explicitly: *"edit-then-rescan preserves
/// the edit"*.
///
/// PR #20 tests the **enrichment-merge** half thoroughly (the AC-B5.3 group in
/// `transaction_edit_test.dart` asserts `MergePlan.between` refuses to fill a
/// protected field, including the cleared-field case). It does **not** test the
/// **re-scan** half against the real pipeline. That is precisely the shape of
/// gap the engineer's own self-review caught for AC-B6.3 and closed with
/// `deleted_transaction_rescan_test.dart` — the symmetric edit case was not
/// closed with it.
///
/// The mechanism is believed to hold structurally (ADR-017 D1's content-HMAC
/// uniqueness means a re-scan never re-parses the message, so there is no
/// second write to overwrite anything). That was also the argument for AC-B6.3,
/// and it still got an executed test, because "believed to hold structurally"
/// is what a regression quietly falsifies.
///
/// **Result: the property HOLDS.** These probes pass. The finding is a missing
/// regression test, not wrong behaviour — filed as a coverage defect so the
/// test lands in the repo rather than only in a QA report.
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
import '../../support/watermark_seed.dart';
import 'support/load_bundled_pack.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 101);

final PeriodRange _july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

void main() {
  late AppDatabase db;
  late TransactionDao transactionDao;
  late TransactionEditService editService;
  late IngestionPipeline pipeline;

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

  setUp(() async {
    db = openPlainTestDatabase();
    // KHA-157: the subject is a user edit surviving a re-scan. Seed at the
    // beginning so `runIncremental` reads the whole fixture inbox.
    await seedWatermarkAtBeginning(IngestWatermarkDao(db));
    final AuditLogDao auditLogDao = AuditLogDao(db, auditChainKey: _qaChainKey);
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
      contentHmacKey: _qaChainKey,
    );
  });

  tearDown(() async => db.close());

  /// A full re-scan over the same inbox, as the resumable historical importer
  /// (KHA-20) re-runs it.
  Future<void> rescan() => pipeline.processAll(inbox, advanceWatermark: false);

  group('AC-B5.3 — a user edit survives a real re-scan (the untested half)', () {
    test('an edited merchant is NOT reverted to the parser\'s text', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;
      expect(
        (await transactionDao.byId(id)).merchantRawText,
        'BALAD COFFEE ROASTERS',
      );

      await editService.edit(
        id,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('Balad Coffee'),
        ),
      );

      await rescan();
      await rescan();

      expect(
        (await transactionDao.byId(id)).merchantRawText,
        'Balad Coffee',
        reason: 'AC-B5.3: user intent outranks the parser, always',
      );
      // And the protection is recorded, so a FUTURE automated writer (P7's
      // statement import) sees it too — the reason the rule lives in a column.
      expect(
        decodeUserEditedFields(
          (await transactionDao.byId(id)).userEditedFields,
        ),
        contains(TransactionField.merchantRawText),
      );
    });

    test('an edited AMOUNT is not reverted, and the period total keeps the '
        'corrected figure across the re-scan', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;

      await editService.edit(
        id,
        const TransactionEditDraft(
          amountText: Edited<String>('91.50'),
          currencyCode: 'SAR',
        ),
      );

      await rescan();

      expect((await transactionDao.byId(id)).amountAmount, '91.5');
      expect(
        LedgerTotals.spend(
          toLedgerTransactions(await transactionDao.all()),
          period: _july2026,
        ).base!.toCanonicalString(),
        '91.5',
        reason: 'the figure the user corrected stays corrected',
      );
    });

    test('a user edit that CLEARED a field is not refilled by the re-scan '
        'either — "the user deleted this" is not "this is missing"', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;

      await editService.edit(
        id,
        const TransactionEditDraft(merchantRawText: Edited<String?>(null)),
      );

      await rescan();

      expect((await transactionDao.byId(id)).merchantRawText, isNull);
    });

    test('the re-scan writes no SECOND transaction for the edited message, so '
        'the edit cannot be shadowed by a fresh unedited row', () async {
      await pipeline.runIncremental();
      final int id = (await transactionDao.all()).single.id;
      await editService.edit(
        id,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('Balad Coffee'),
        ),
      );

      await rescan();

      expect(await transactionDao.all(), hasLength(1));
      expect(await RawMessageDao(db).all(), hasLength(1));
    });
  });
}
