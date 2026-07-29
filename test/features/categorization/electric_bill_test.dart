/// **AC-D2.1, the electric-bill case, end to end** — KHA-31's done check.
///
/// > *Once the user has categorized a payment to the electric utility as
/// > Utilities, a new message from that same utility arrives ALREADY
/// > categorized as Utilities, with no user action.*
///
/// The second group runs it through the **real bundled rule pack and the real
/// ingestion pipeline**, because "arrives already categorized" is a claim
/// about what happens when a message lands, not about what happens when a
/// test calls a service. The two SMS bodies are synthetic, built from the
/// shape in `test/fixtures/synthetic_sms_corpus.dart` (NFR-M3: no real
/// merchant string is in this repository).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
// `CategoryReviewReason` and `StoredCategorySource` arrive through
// `transaction_dao.dart`'s re-export of the shared stored vocabulary, which is
// why `categories.dart` is not imported here.
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import '../ingestion/support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 21);

/// A synthetic Bank Aljazira bill-payment message for the electric utility,
/// in the shape the bundled pack's `baj-bill-payment-ar` rule matches.
String electricBillBody({
  required String amount,
  required String invoice,
  required String at,
}) =>
    'سداد فاتورة\n'
    'من حساب:****3388\n'
    'مبلغ:$amount SAR\n'
    'المفوتر:SEC-KAHRABA\n'
    'رقم الفاتورة:$invoice\n'
    'في:$at';

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao transactionDao;
  late MerchantDao merchantDao;
  late CategorizationService service;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    transactionDao = TransactionDao(db, auditLogDao);
    merchantDao = MerchantDao(db, auditLogDao);
    service = CategorizationService(
      categoryDao: CategoryDao(db, auditLogDao),
      merchantDao: merchantDao,
      transactionDao: transactionDao,
    );
    await service.ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  Future<int> billFrom(String merchant, {String amount = '412.30'}) =>
      transactionDao.insertManual(
        amount: Money.parse(amount, currency: 'SAR'),
        merchantRawText: merchant,
        occurredAt: DateTime.utc(2026, 7, 24, 16, 41),
        direction: 'debit',
        transactionType: 'bill_payment',
        affectsSpend: true,
      );

  group('the learning loop, at the service level', () {
    test('AC-D2.1 — categorize once, and the next bill from the same utility '
        'arrives already categorized with no user action', () async {
      // 1. The first bill. Nothing is known about this merchant yet.
      final int first = await billFrom('SEC-KAHRABA');
      final CategorizationOutcome firstPass = await service
          .categorizeTransaction(transactionId: first);

      expect(firstPass.result, CategorizationResult.flaggedUnknownMerchant);
      expect((await transactionDao.byId(first)).categoryId, isNull);
      expect((await transactionDao.byId(first)).needsReview, isTrue);
      expect(
        (await transactionDao.byId(first)).reviewReason,
        CategoryReviewReason.unknownMerchant,
      );

      // 2. The user says it is Utilities & Bills. That is the whole of the
      //    user's involvement in this test.
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );

      // The rule is now visible in the learned-rules list (AC-D1.1).
      final List<MerchantRuleRow> rules = await merchantDao.allRules();
      expect(rules, hasLength(1));
      expect(rules.single.categoryId, 'utilities_bills');
      expect(rules.single.source, 'user');

      // 3. A month later, the next bill arrives.
      final int second = await billFrom('SEC-KAHRABA', amount: '388.10');
      final CategorizationOutcome secondPass = await service
          .categorizeTransaction(transactionId: second);

      expect(secondPass.result, CategorizationResult.applied);
      final TransactionRow row = await transactionDao.byId(second);
      expect(row.categoryId, 'utilities_bills');
      expect(row.categorySource, StoredCategorySource.rule);
      expect(row.categoryConfidence, 1.0);
      expect(row.categoryRuleId, rules.single.id);
      expect(
        row.needsReview,
        isFalse,
        reason: 'nothing needs the user\'s attention — that is the point',
      );
    });

    test('AC-D2.2/AC-F5.2 — the automatic categorization is attributed to the '
        'SYSTEM and names the rule that fired', () async {
      final int first = await billFrom('SEC-KAHRABA');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );
      final int ruleId = (await merchantDao.allRules()).single.id;

      final int second = await billFrom('SEC-KAHRABA', amount: '388.10');
      await service.categorizeTransaction(transactionId: second);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        second.toString(),
      );
      expect(history.last.action, 'categorize');
      expect(history.last.actor, 'system_rule');
      expect(
        history.last.actorDetail,
        'merchant_rule:$ruleId',
        reason:
            'the user must always be able to answer "why is this in this '
            'category?"',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('the rule\'s applied count records that it earned its keep', () async {
      final int first = await billFrom('SEC-KAHRABA');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );

      for (final String amount in <String>['388.10', '401.55', '377.00']) {
        final int id = await billFrom('SEC-KAHRABA', amount: amount);
        await service.categorizeTransaction(transactionId: id);
      }

      expect((await merchantDao.allRules()).single.appliedCount, 3);
    });

    test(
      'AC-D2.3 — a cosmetic variant of the same biller matches the rule',
      () async {
        final int first = await billFrom('SEC-KAHRABA');
        await service.applyUserCategory(
          transactionId: first,
          categoryId: 'utilities_bills',
        );

        final int variant = await billFrom('sec kahraba 0042');
        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: variant);

        expect(outcome.result, CategorizationResult.applied);
        expect(
          (await transactionDao.byId(variant)).categoryId,
          'utilities_bills',
        );
      },
    );

    test('AC-D2.3 — an unrelated biller does NOT inherit the rule', () async {
      final int first = await billFrom('SEC-KAHRABA');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );

      final int other = await billFrom('MOBILY-POSTPAID');
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: other,
      );

      expect(outcome.result, CategorizationResult.flaggedUnknownMerchant);
      expect((await transactionDao.byId(other)).categoryId, isNull);
    });

    test('AC-D2.4 — a never-before-seen merchant is never confidently '
        'categorized by coincidence', () async {
      // Four rules in the store, and a novel merchant that resembles none of
      // them closely enough. The assertion is not "it got the right answer" —
      // it is that it gave *no* answer.
      for (final MapEntry<String, String> lesson in <String, String>{
        'SEC-KAHRABA': 'utilities_bills',
        'PANDA FOODS': 'groceries',
        'NORTHWIND COFFEE': 'dining',
        'MOBILY-POSTPAID': 'utilities_bills',
      }.entries) {
        final int id = await billFrom(lesson.key);
        await service.applyUserCategory(
          transactionId: id,
          categoryId: lesson.value,
        );
      }

      final int novel = await billFrom('SYNTHETIC BOOKSHOP');
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: novel,
      );

      expect(outcome.result, CategorizationResult.flaggedUnknownMerchant);
      final TransactionRow row = await transactionDao.byId(novel);
      expect(row.categoryId, isNull);
      expect(row.categorySource, StoredCategorySource.none);
      expect(row.needsReview, isTrue);
      expect(
        row.merchantId,
        isNotNull,
        reason:
            'the shop is recorded so the NEXT message from it resolves to the '
            'same identity — recognising is not categorizing',
      );
    });

    test('a recognised merchant with no rule is flagged as such, not as an '
        'unknown merchant', () async {
      // Two different questions for the user: "is this a shop you know?" and
      // "where does this shop's spending belong?". The review inbox asks a
      // different one for each, so the reason has to distinguish them.
      final int first = await billFrom('SEC-KAHRABA');
      await service.categorizeTransaction(transactionId: first);
      expect(
        (await transactionDao.byId(first)).reviewReason,
        CategoryReviewReason.unknownMerchant,
      );

      final int second = await billFrom('SEC-KAHRABA', amount: '388.10');
      await service.categorizeTransaction(transactionId: second);
      expect(
        (await transactionDao.byId(second)).reviewReason,
        CategoryReviewReason.noRuleForMerchant,
        reason: 'the merchant row now exists; only the lesson is missing',
      );
    });

    test(
      'a categorization does not clear a duplicate flag raised by ADR-017',
      () async {
        // Answering the category question does not answer the "is this the same
        // purchase twice?" question, and clearing it would hide an unresolved
        // money question behind an unrelated action.
        final int id = await billFrom('SEC-KAHRABA');
        await transactionDao.flagAsPossibleDuplicate(
          id: id,
          otherId: 999,
          reviewReason: 'possible_duplicate',
        );

        await service.applyUserCategory(
          transactionId: id,
          categoryId: 'utilities_bills',
        );

        final TransactionRow row = await transactionDao.byId(id);
        expect(row.categoryId, 'utilities_bills');
        expect(row.needsReview, isTrue);
        expect(row.reviewReason, 'possible_duplicate');
      },
    );

    test('a categorization DOES clear the flag the categorizer itself raised '
        '(AC-C4.3)', () async {
      final int id = await billFrom('SEC-KAHRABA');
      await service.categorizeTransaction(transactionId: id);
      expect((await transactionDao.byId(id)).needsReview, isTrue);

      await service.applyUserCategory(
        transactionId: id,
        categoryId: 'utilities_bills',
      );

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.needsReview, isFalse);
      expect(row.reviewReason, isNull);
    });

    test('AC-D1.2 — correcting a second transaction from the same merchant '
        'updates the rule instead of adding one', () async {
      final int first = await billFrom('SEC-KAHRABA');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );
      final int second = await billFrom('SEC-KAHRABA', amount: '388.10');
      await service.applyUserCategory(
        transactionId: second,
        categoryId: 'fees_charges',
      );

      final List<MerchantRuleRow> rules = await merchantDao.allRules();
      expect(rules, hasLength(1));
      expect(rules.single.categoryId, 'fees_charges');
    });

    test('US-D5\'s "this transaction only" does not create a rule, and leaves '
        'an existing one applying (AC-D5.2)', () async {
      final int first = await billFrom('SEC-KAHRABA');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'utilities_bills',
      );

      final int oneOff = await billFrom('SEC-KAHRABA', amount: '388.10');
      await service.applyUserCategory(
        transactionId: oneOff,
        categoryId: 'fees_charges',
        learnRule: false,
      );

      expect(
        (await merchantDao.allRules()).single.categoryId,
        'utilities_bills',
        reason: 'a one-off correction must not become a lesson',
      );

      final int later = await billFrom('SEC-KAHRABA', amount: '399.00');
      await service.categorizeTransaction(transactionId: later);
      expect(
        (await transactionDao.byId(later)).categoryId,
        'utilities_bills',
        reason: 'the previously learned rule still applies',
      );
    });
  });

  group(
    'AC-D3.1/D3.2 — no automatic process overwrites a user-set category',
    () {
      test(
        'a rule that says otherwise cannot move a category the user set',
        () async {
          // Teach the app that this biller is Utilities…
          final int teaching = await billFrom('SEC-KAHRABA');
          await service.applyUserCategory(
            transactionId: teaching,
            categoryId: 'utilities_bills',
          );

          // …then have the user put ONE transaction from that same biller
          // somewhere else, without learning a rule for it.
          final int corrected = await billFrom('SEC-KAHRABA', amount: '388.10');
          await service.applyUserCategory(
            transactionId: corrected,
            categoryId: 'fees_charges',
            learnRule: false,
          );

          // Now let the automatic path run over it as many times as it likes.
          for (int i = 0; i < 3; i++) {
            final CategorizationOutcome outcome = await service
                .categorizeTransaction(transactionId: corrected);
            expect(outcome.result, CategorizationResult.skippedAlreadyDecided);
          }

          final TransactionRow row = await transactionDao.byId(corrected);
          expect(row.categoryId, 'fees_charges');
          expect(row.categorySource, StoredCategorySource.user);
        },
      );

      test(
        'the refusal holds at the DAO even if a caller bypasses the service',
        () async {
          final int id = await billFrom('SEC-KAHRABA');
          await service.applyUserCategory(
            transactionId: id,
            categoryId: 'fees_charges',
          );

          expect(
            await transactionDao.applyAutomaticCategory(
              id: id,
              categoryId: 'utilities_bills',
              confidence: 1.0,
              ruleId: 1,
              actorDetail: 'merchant_rule:1',
            ),
            isFalse,
          );
          expect((await transactionDao.byId(id)).categoryId, 'fees_charges');
        },
      );

      test('re-running the categorizer over an already-auto-categorized row '
          'changes nothing', () async {
        final int teaching = await billFrom('SEC-KAHRABA');
        await service.applyUserCategory(
          transactionId: teaching,
          categoryId: 'utilities_bills',
        );
        final int auto = await billFrom('SEC-KAHRABA', amount: '388.10');
        await service.categorizeTransaction(transactionId: auto);

        final int entriesBefore = (await auditLogDao.queryFor(
          'transaction',
          auto.toString(),
        )).length;
        final CategorizationOutcome again = await service.categorizeTransaction(
          transactionId: auto,
        );

        expect(again.result, CategorizationResult.skippedAlreadyDecided);
        expect(
          await auditLogDao.queryFor('transaction', auto.toString()),
          hasLength(entriesBefore),
        );
      });

      test('a transaction with no merchant at all is skipped, not filed under '
          'some empty-string merchant', () async {
        final int id = await transactionDao.insertManual(
          amount: Money.parse('300.00', currency: 'SAR'),
          occurredAt: DateTime.utc(2026, 7, 24, 12),
          direction: 'debit',
          transactionType: 'atm_withdrawal',
          affectsSpend: false,
        );

        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: id);

        expect(outcome.result, CategorizationResult.skippedNoMerchant);
        expect(await merchantDao.allMerchants(), isEmpty);
        expect((await transactionDao.byId(id)).needsReview, isFalse);
      });
    },
  );

  group('the same case through the real ingestion pipeline', () {
    late IngestionPipeline pipeline;

    IngestionPipeline pipelineFor(List<RawSmsRecord> records) {
      final RulePack pack = loadBundledRulePack();
      return IngestionPipeline(
        database: db,
        smsSource: FakeSmsSource(records),
        parser: RulePackMessageParser(packs: <RulePack>[pack]),
        rawMessageDao: RawMessageDao(db),
        transactionDao: transactionDao,
        watermarkDao: IngestWatermarkDao(db),
        logger: SafeLogger(DiagnosticRingBuffer()),
        contentHmacKey: _testChainKey,
        // The same adapter `categorization_providers.dart` binds in the app.
        categorizer: (int transactionId) =>
            service.categorizeTransaction(transactionId: transactionId),
      );
    }

    test('AC-D2.1 end to end: the second bill is categorized on arrival, with '
        'no user action between the two runs', () async {
      // --- Run 1: the first bill lands, uncategorized and flagged ----------
      pipeline = pipelineFor(<RawSmsRecord>[
        RawSmsRecord(
          providerId: 1,
          address: 'BAJ',
          body: electricBillBody(
            amount: '412.30',
            invoice: 'INV77120934',
            at: '24-07-26 19:41',
          ),
          receivedAt: DateTime.utc(2026, 7, 24, 16, 42),
        ),
      ]);
      await pipeline.runIncremental();

      final List<TransactionRow> afterFirst = await transactionDao.all();
      expect(afterFirst, hasLength(1));
      expect(afterFirst.single.merchantRawText, 'SEC-KAHRABA');
      expect(afterFirst.single.categoryId, isNull);
      expect(afterFirst.single.needsReview, isTrue);

      // --- The user's one and only action ----------------------------------
      await service.applyUserCategory(
        transactionId: afterFirst.single.id,
        categoryId: 'utilities_bills',
      );

      // --- Run 2: next month's bill ----------------------------------------
      pipeline = pipelineFor(<RawSmsRecord>[
        RawSmsRecord(
          providerId: 2,
          address: 'BAJ',
          body: electricBillBody(
            amount: '388.10',
            invoice: 'INV77998812',
            at: '24-08-26 19:12',
          ),
          receivedAt: DateTime.utc(2026, 8, 24, 16, 13),
        ),
      ]);
      await pipeline.runIncremental();

      final List<TransactionRow> all = await transactionDao.all();
      expect(all, hasLength(2));
      final TransactionRow second = all.last;
      expect(
        second.categoryId,
        'utilities_bills',
        reason: 'AC-D2.1: it arrived already categorized, with no user action',
      );
      expect(second.categorySource, StoredCategorySource.rule);
      expect(second.needsReview, isFalse);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        second.id.toString(),
      );
      expect(history.last.actor, 'system_rule');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('a pipeline with no categorizer still records every transaction — '
        'categorization is an addition, never a gate on money', () async {
      final RulePack pack = loadBundledRulePack();
      final IngestionPipeline bare = IngestionPipeline(
        database: db,
        smsSource: FakeSmsSource(<RawSmsRecord>[
          RawSmsRecord(
            providerId: 1,
            address: 'BAJ',
            body: electricBillBody(
              amount: '412.30',
              invoice: 'INV77120934',
              at: '24-07-26 19:41',
            ),
            receivedAt: DateTime.utc(2026, 7, 24, 16, 42),
          ),
        ]),
        parser: RulePackMessageParser(packs: <RulePack>[pack]),
        rawMessageDao: RawMessageDao(db),
        transactionDao: transactionDao,
        watermarkDao: IngestWatermarkDao(db),
        logger: SafeLogger(DiagnosticRingBuffer()),
        contentHmacKey: _testChainKey,
      );

      await bare.runIncremental();

      final List<TransactionRow> all = await transactionDao.all();
      expect(all, hasLength(1));
      expect(all.single.categoryId, isNull);
      expect(
        all.single.categorySource,
        isNull,
        reason:
            'nothing looked at it, which is a different fact from "looked '
            'and found nothing"',
      );
    });
  });
}
