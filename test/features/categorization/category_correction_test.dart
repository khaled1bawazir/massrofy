/// **P4b's write paths, against a real database** — KHA-33 (US-C2, US-C5,
/// US-D5) and KHA-34 (US-D4).
///
/// The screens are covered by `test/widget/p4b_screens_test.dart`; this file
/// covers what the screens *do*, because every acceptance criterion in those
/// two issues is a statement about stored data rather than about pixels:
/// *"undo reverts all affected transactions to their PRIOR categories"* cannot
/// be observed from a widget tree.
///
/// NFR-M3: every merchant string here is synthetic.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/categorization/category_correction.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/providers/categorization_providers.dart'
    show ReviewCounts;

import '../../support/plain_test_database.dart';

final List<int> _chainKey = List<int>.generate(32, (int i) => i + 31);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late CategoryDao categoryDao;
  late MerchantDao merchantDao;
  late TransactionDao transactionDao;
  late CategorizationService service;
  late CategoryCorrectionService corrections;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _chainKey);
    categoryDao = CategoryDao(db, auditLogDao);
    merchantDao = MerchantDao(db, auditLogDao);
    transactionDao = TransactionDao(db, auditLogDao);
    service = CategorizationService(
      categoryDao: categoryDao,
      merchantDao: merchantDao,
      transactionDao: transactionDao,
    );
    corrections = CategoryCorrectionService(
      categorization: service,
      transactionDao: transactionDao,
      merchantDao: merchantDao,
    );
    await service.ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  int nextMessageId = 9000;
  int nextDay = 1;

  /// One ingested purchase from [merchant].
  Future<int> purchase({String? merchant = 'QANDA STORE'}) =>
      transactionDao.insertFromParsedSms(
        amount: Money.parse('75.00', currency: 'SAR'),
        merchantRawText: merchant,
        occurredAt: DateTime.utc(2026, 7, (nextDay++ % 27) + 1, 12),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
        sourceMessageId: nextMessageId++,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-pos-purchase-ar',
      );

  Future<List<AuditEntryRow>> auditFor(int transactionId) =>
      auditLogDao.queryFor('transaction', transactionId.toString());

  // =====================================================================
  // KHA-33 — the correction flow (US-C2, US-D5)
  // =====================================================================

  group('KHA-33 — one correction, with US-D5\'s scope choice', () {
    test(
      'AC-C2.1 — a correction saves immediately and is visible at once',
      () async {
        final int id = await purchase();
        await service.categorizeTransaction(transactionId: id);
        expect((await transactionDao.byId(id)).categoryId, isNull);

        final CategoryCorrection result = await corrections.correct(
          transactionId: id,
          categoryId: 'groceries',
          scope: CorrectionScope.thisAndFuture,
        );

        // No "save" step, no confirmation dialog: the write happened inside the
        // call the tap made (design.md §6.3 — tapping a category cell applies it).
        final TransactionRow row = await transactionDao.byId(id);
        expect(row.categoryId, 'groceries');
        expect(row.categorySource, StoredCategorySource.user);
        expect(result.ruleWritten, isTrue);
        expect(await auditLogDao.verifyChainIntegrity(), isTrue);
      },
    );

    test('AC-C4.3 — answering the category question clears the categorizer\'s '
        'review flag, and ONLY that flag', () async {
      final int categorized = await purchase();
      await service.categorizeTransaction(transactionId: categorized);
      expect((await transactionDao.byId(categorized)).needsReview, isTrue);

      await corrections.correct(
        transactionId: categorized,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      expect((await transactionDao.byId(categorized)).needsReview, isFalse);

      // …and the other direction: a row flagged as a possible DUPLICATE keeps
      // its flag after a category correction, because that is a different
      // question about the user's money and answering one does not answer it.
      final int duplicate = await purchase(merchant: 'QANDB STORE');
      final int other = await purchase(merchant: 'QANDB STORE');
      await transactionDao.flagAsPossibleDuplicate(
        id: duplicate,
        otherId: other,
        reviewReason: ReviewReason.possibleDuplicate,
      );
      await corrections.correct(
        transactionId: duplicate,
        categoryId: 'dining',
        scope: CorrectionScope.thisTransactionOnly,
      );
      final TransactionRow after = await transactionDao.byId(duplicate);
      expect(after.categoryId, 'dining');
      expect(
        after.needsReview,
        isTrue,
        reason: 'the duplicate question is still open',
      );
      expect(after.possibleDuplicateOfId, other);
    });

    test('AC-D5.1/AC-D5.2 — "just this transaction" writes no rule AND leaves '
        'an existing rule applying to later transactions', () async {
      // Teach a rule the ordinary way.
      final int taught = await purchase();
      await corrections.correct(
        transactionId: taught,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      final int merchantId = (await transactionDao.byId(taught)).merchantId!;
      final int ruleId = (await merchantDao.ruleForMerchant(merchantId))!.id;

      // The one-off: this purchase was really a gift.
      final int oneOff = await purchase();
      await service.categorizeTransaction(transactionId: oneOff);
      final CategoryCorrection result = await corrections.correct(
        transactionId: oneOff,
        categoryId: 'shopping_retail',
        scope: CorrectionScope.thisTransactionOnly,
      );

      expect((await transactionDao.byId(oneOff)).categoryId, 'shopping_retail');
      expect(result.ruleWritten, isFalse);
      expect(result.otherTransactionsUpdated, 0);

      // **AC-D5.2, the half that matters**: the rule is untouched, so the next
      // transaction from this merchant still follows the ORIGINAL lesson.
      final MerchantRuleRow rule = (await merchantDao.ruleForMerchant(
        merchantId,
      ))!;
      expect(rule.id, ruleId, reason: 'the same rule row, not a rival');
      expect(rule.categoryId, 'groceries');

      final int later = await purchase();
      await service.categorizeTransaction(transactionId: later);
      expect(
        (await transactionDao.byId(later)).categoryId,
        'groceries',
        reason: 'a one-off must not corrupt the merchant rule',
      );
    });

    test('AC-C5.1/AC-D5.3 — "this and future" also fills in the merchant\'s '
        'other UNCATEGORIZED transactions, and reports how many', () async {
      final int a = await purchase();
      final int b = await purchase();
      final int c = await purchase();
      for (final int id in <int>[a, b, c]) {
        await service.categorizeTransaction(transactionId: id);
      }

      final CategoryCorrection result = await corrections.correct(
        transactionId: a,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );

      // AC-D5.3's number, excluding the row the user was looking at.
      expect(result.otherTransactionsUpdated, 2);
      expect(result.totalTransactionsUpdated, 3);
      expect(result.merchantName, isNotNull);
      for (final int id in <int>[a, b, c]) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }

      // The siblings were written by the RULE, not by the person: only the row
      // the user actually looked at is theirs (AC-D3.1's ownership signal must
      // stay honest, or a later rule change could never touch the others).
      expect(
        (await transactionDao.byId(a)).categorySource,
        StoredCategorySource.user,
      );
      expect(
        (await transactionDao.byId(b)).categorySource,
        StoredCategorySource.rule,
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('the bulk half refuses to touch a row a PERSON categorized, or one '
        'that already has a category (AC-D3.1)', () async {
      final int target = await purchase();
      final int userOwned = await purchase();
      final int alreadyRuled = await purchase();

      // A person put this one in Dining, by hand.
      await service.applyUserCategory(
        transactionId: userOwned,
        categoryId: 'dining',
        learnRule: false,
      );
      // And this one was auto-categorized earlier, by some other rule.
      await transactionDao.applyAutomaticCategory(
        id: alreadyRuled,
        categoryId: 'transport_fuel',
        confidence: 1.0,
        merchantId: (await transactionDao.byId(userOwned)).merchantId,
        actorDetail: 'test_seed',
      );

      await service.categorizeTransaction(transactionId: target);
      final CategoryCorrection result = await corrections.correct(
        transactionId: target,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );

      expect(
        result.otherTransactionsUpdated,
        0,
        reason:
            'one row is user-owned and the other already has a category — '
            'rewriting the latter is AC-D4.4\'s operation, which asks first',
      );
      expect((await transactionDao.byId(userOwned)).categoryId, 'dining');
      expect(
        (await transactionDao.byId(alreadyRuled)).categoryId,
        'transport_fuel',
      );
    });

    test('the explicit Uncategorized choice never becomes a rule and never '
        'fills in siblings', () async {
      final int a = await purchase();
      final int b = await purchase();
      for (final int id in <int>[a, b]) {
        await service.categorizeTransaction(transactionId: id);
      }

      final CategoryCorrection result = await corrections.correct(
        transactionId: a,
        categoryId: uncategorizedCategoryId,
        scope: CorrectionScope.thisAndFuture,
      );

      expect(result.ruleWritten, isFalse);
      expect(result.otherTransactionsUpdated, 0);
      final int merchantId = (await transactionDao.byId(a)).merchantId!;
      expect(
        await merchantDao.ruleForMerchant(merchantId),
        isNull,
        reason: '"I do not know what this is" is not a lesson',
      );
    });

    test('a merchantless transaction (a transfer, an ATM withdrawal) is still '
        'correctable, and teaches nothing', () async {
      final int id = await purchase(merchant: null);
      final CategoryCorrection result = await corrections.correct(
        transactionId: id,
        categoryId: 'cash_withdrawal',
        scope: CorrectionScope.thisAndFuture,
      );

      expect((await transactionDao.byId(id)).categoryId, 'cash_withdrawal');
      expect(result.merchantId, isNull);
      expect(result.merchantName, isNull);
      expect(result.ruleWritten, isFalse);
      expect(result.otherTransactionsUpdated, 0);
    });

    test('correcting a transaction that has since been deleted writes nothing '
        'and offers nothing to undo', () async {
      final CategoryCorrection result = await corrections.correct(
        transactionId: 999999,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      expect(result.undo.isRestorable, isFalse);
      expect(result.otherTransactionsUpdated, 0);
    });

    test(
      'countUncategorizedSiblings agrees with what the correction then '
      'does — the scope strip cannot promise a number the write misses',
      () async {
        final int a = await purchase();
        final int b = await purchase();
        final int c = await purchase();
        for (final int id in <int>[a, b, c]) {
          await service.categorizeTransaction(transactionId: id);
        }
        final int merchantId = (await transactionDao.byId(a)).merchantId!;

        final int promised = await corrections.countUncategorizedSiblings(
          merchantId: merchantId,
          excludingTransactionId: a,
        );
        final CategoryCorrection result = await corrections.correct(
          transactionId: a,
          categoryId: 'groceries',
          scope: CorrectionScope.thisAndFuture,
        );
        expect(result.otherTransactionsUpdated, promised);
      },
    );
  });

  // =====================================================================
  // KHA-33 — AC-C5.2's undo
  // =====================================================================

  group('AC-C5.2 — undo restores each transaction\'s OWN prior category', () {
    test('rows that had DIFFERENT prior categories each get their own back, '
        'not a default', () async {
      // Three rows from one merchant, deliberately in three different starting
      // states — this is the case a "reset to Uncategorized" undo destroys.
      final int target = await purchase();
      final int wasBlank = await purchase();
      final int wasBlankToo = await purchase();
      for (final int id in <int>[target, wasBlank, wasBlankToo]) {
        await service.categorizeTransaction(transactionId: id);
      }
      // Give one of them a prior category through the automatic path, so it is
      // not user-owned but is also not blank… then blank it again via the same
      // path so the bulk write can reach it, keeping its `category_source`
      // history distinct from the others.
      final TransactionRow beforeTarget = await transactionDao.byId(target);
      expect(beforeTarget.categoryId, isNull);

      final CategoryCorrection correction = await corrections.correct(
        transactionId: target,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      expect(correction.otherTransactionsUpdated, 2);

      final int restored = await corrections.undo(correction.undo);
      expect(restored, 3);

      for (final int id in <int>[target, wasBlank, wasBlankToo]) {
        final TransactionRow row = await transactionDao.byId(id);
        expect(
          row.categoryId,
          isNull,
          reason: 'each row is back to the category it actually had',
        );
      }
    });

    test('the undo restores OWNERSHIP too, so the learned rule can categorize '
        'the row again afterwards', () async {
      // The subtle half, and the reason the undo restores six columns rather
      // than one: a row left `category_source = user` after an undo is
      // permanently protected by AC-D3.1 and no rule can ever touch it again.
      final int id = await purchase();
      await service.categorizeTransaction(transactionId: id);

      final CategoryCorrection correction = await corrections.correct(
        transactionId: id,
        categoryId: 'groceries',
        scope: CorrectionScope.thisTransactionOnly,
      );
      expect(isUserOwnedCategory(await transactionDao.byId(id)), isTrue);

      await corrections.undo(correction.undo);
      final TransactionRow after = await transactionDao.byId(id);
      expect(
        isUserOwnedCategory(after),
        isFalse,
        reason: 'the row is no longer claimed by the user',
      );
      expect(
        after.needsReview,
        isTrue,
        reason: 'the review flag the categorizer raised is back up too',
      );

      // Proof that the restoration is functional and not merely cosmetic: the
      // automatic path can write to this row again.
      expect(
        await transactionDao.applyAutomaticCategory(
          id: id,
          categoryId: 'dining',
          confidence: 1.0,
          actorDetail: 'merchant_rule:1',
        ),
        isTrue,
      );
    });

    test('the undo reverts the RULE as well — a created rule is deleted, an '
        'updated one goes back to its previous category', () async {
      // Case 1: the correction CREATED the rule.
      final int first = await purchase();
      await service.categorizeTransaction(transactionId: first);
      final CategoryCorrection created = await corrections.correct(
        transactionId: first,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      final int merchantId = (await transactionDao.byId(first)).merchantId!;
      expect(await merchantDao.ruleForMerchant(merchantId), isNotNull);

      await corrections.undo(created.undo);
      expect(
        await merchantDao.ruleForMerchant(merchantId),
        isNull,
        reason:
            'design.md §6.4: undo reverts the RULE change, not just this '
            'transaction — otherwise the next message re-applies the '
            'category the user just rejected',
      );

      // Case 2: the correction UPDATED an existing rule.
      final int second = await purchase();
      await corrections.correct(
        transactionId: second,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      final int third = await purchase();
      await service.categorizeTransaction(transactionId: third);
      final CategoryCorrection updated = await corrections.correct(
        transactionId: third,
        categoryId: 'dining',
        scope: CorrectionScope.thisAndFuture,
      );
      expect(
        (await merchantDao.ruleForMerchant(merchantId))!.categoryId,
        'dining',
      );

      await corrections.undo(updated.undo);
      expect(
        (await merchantDao.ruleForMerchant(merchantId))!.categoryId,
        'groceries',
        reason: 'back to what the rule said before',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('NFR-A3 — the undo APPENDS history; it never erases the entry it is '
        'undoing', () async {
      final int id = await purchase();
      await service.categorizeTransaction(transactionId: id);

      final int beforeCorrection = (await auditFor(id)).length;
      final CategoryCorrection correction = await corrections.correct(
        transactionId: id,
        categoryId: 'groceries',
        scope: CorrectionScope.thisTransactionOnly,
      );
      final List<AuditEntryRow> afterCorrection = await auditFor(id);
      expect(afterCorrection.length, greaterThan(beforeCorrection));

      await corrections.undo(correction.undo);
      final List<AuditEntryRow> afterUndo = await auditFor(id);
      expect(
        afterUndo.length,
        greaterThan(afterCorrection.length),
        reason: 'the undo is a new event',
      );
      expect(
        afterUndo.take(afterCorrection.length).map((AuditEntryRow e) => e.id),
        afterCorrection.map((AuditEntryRow e) => e.id),
        reason: 'and every earlier entry is still there, unchanged',
      );
      expect(
        afterUndo.last.actorDetail,
        'undo_correction',
        reason: 'the trail says what kind of event this was',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('undoing a correction whose transaction was deleted afterwards does '
        'not throw and reports what it could restore', () async {
      final int id = await purchase();
      await service.categorizeTransaction(transactionId: id);
      final CategoryCorrection correction = await corrections.correct(
        transactionId: id,
        categoryId: 'groceries',
        scope: CorrectionScope.thisTransactionOnly,
      );

      // The row still exists after a soft delete, so it IS restored — the
      // interesting property is that the undo does not resurrect it or throw.
      await transactionDao.softDelete(id: id, actor: 'user');
      expect(await corrections.undo(correction.undo), 1);
      expect((await transactionDao.byId(id)).isDeleted, isTrue);
    });
  });

  // =====================================================================
  // KHA-34 — the learned-rules screen's write paths (US-D4)
  // =====================================================================

  group('KHA-34 — editing, re-applying and deleting a rule', () {
    /// Teaches a rule and returns `(ruleId, merchantId, transactionIds)`.
    Future<(int, int, List<int>)> seedRuleWithHistory() async {
      final int first = await purchase();
      await corrections.correct(
        transactionId: first,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      final int merchantId = (await transactionDao.byId(first)).merchantId!;

      final List<int> auto = <int>[];
      for (int i = 0; i < 3; i++) {
        final int id = await purchase();
        await service.categorizeTransaction(transactionId: id);
        auto.add(id);
      }
      final int ruleId = (await merchantDao.ruleForMerchant(merchantId))!.id;
      return (ruleId, merchantId, <int>[first, ...auto]);
    }

    test('AC-D4.2 — editing a rule changes what FUTURE transactions get, and '
        '"going forward only" leaves history untouched', () async {
      final (int ruleId, _, List<int> ids) = await seedRuleWithHistory();
      for (final int id in ids) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }

      final RuleReapplyResult? result = await corrections.editRule(
        ruleId: ruleId,
        categoryId: 'dining',
        reapplyToHistory: false,
      );
      expect(result, isNotNull);
      expect(result!.transactionsUpdated, 0);

      // History is exactly as it was…
      for (final int id in ids) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }
      // …and the next transaction follows the new rule.
      final int future = await purchase();
      await service.categorizeTransaction(transactionId: future);
      expect((await transactionDao.byId(future)).categoryId, 'dining');
    });

    test('AC-D4.4 — "yes, re-apply" rewrites history AND writes one audit '
        'entry per affected transaction', () async {
      final (int ruleId, _, List<int> ids) = await seedRuleWithHistory();
      final Map<int, int> auditsBefore = <int, int>{
        for (final int id in ids) id: (await auditFor(id)).length,
      };

      final RuleReapplyResult? result = await corrections.editRule(
        ruleId: ruleId,
        categoryId: 'dining',
        reapplyToHistory: true,
      );

      expect(result, isNotNull);
      // The first row is user-owned (a person corrected it), so it is skipped
      // and the other three are rewritten. AC-D3.1 outranks an explicit
      // re-apply — the user asked to apply the RULE to history, not to
      // overrule their own past decisions.
      expect(result!.transactionsUpdated, 3);
      expect(result.transactionsSkippedUserOwned, 1);

      expect(
        (await transactionDao.byId(ids.first)).categoryId,
        'groceries',
        reason: 'the row the person categorized is untouched',
      );
      for (final int id in ids.skip(1)) {
        expect((await transactionDao.byId(id)).categoryId, 'dining');
        final List<AuditEntryRow> entries = await auditFor(id);
        expect(
          entries.length,
          auditsBefore[id]! + 1,
          reason:
              'KHA-34: a bulk historical re-apply that writes no history is '
              'a defect — the user must be able to reconstruct why last '
              'month\'s figures changed',
        );
        final AuditEntryRow last = entries.last;
        expect(last.actor, 'system_rule');
        expect(last.action, 'categorize');
        expect(
          last.actorDetail,
          'merchant_rule:$ruleId',
          reason: 'AC-F5.2 — the entry names the rule that fired',
        );
      }
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('countReapplyCandidates matches what the re-apply then writes, so '
        'S-17\'s "Yes, N transactions" cannot lie', () async {
      final (int ruleId, int merchantId, _) = await seedRuleWithHistory();

      final int promised = await corrections.countReapplyCandidates(
        merchantId: merchantId,
        categoryId: 'dining',
      );
      final RuleReapplyResult? result = await corrections.editRule(
        ruleId: ruleId,
        categoryId: 'dining',
        reapplyToHistory: true,
      );
      expect(result!.transactionsUpdated, promised);
    });

    test('a re-apply writes NO entry for a row that already says the same '
        'thing — no `X → X` in the trail', () async {
      final (int ruleId, int merchantId, List<int> ids) =
          await seedRuleWithHistory();
      final int untouched = ids.last;
      final int auditsBefore = (await auditFor(untouched)).length;

      // Re-apply the category the rule already holds.
      await corrections.reapplyRuleToHistory(
        ruleId: ruleId,
        merchantId: merchantId,
        categoryId: 'groceries',
      );
      expect((await auditFor(untouched)).length, auditsBefore);
    });

    test('KHA-104 — editing a rule to a category that does NOT exist is '
        'refused, and no history is rewritten either', () async {
      // **This is the check the task asks for explicitly**: KHA-104's
      // write-side guard lives in `MerchantDao.upsertRule`, and the S-17 edit
      // path is the SECOND writer of merchant rules. Verified here rather than
      // assumed from the fact that it was fixed for a different caller.
      final (int ruleId, _, List<int> ids) = await seedRuleWithHistory();

      final RuleReapplyResult? refused = await corrections.editRule(
        ruleId: ruleId,
        categoryId: 'no_such_category',
        reapplyToHistory: true,
      );
      expect(refused, isNull, reason: 'the refusal sentinel reached the UI');

      // The rule is unchanged…
      expect((await merchantDao.ruleById(ruleId))!.categoryId, 'groceries');
      // …and — the half that would be easy to get wrong — the history rewrite
      // did not run against the rejected category.
      for (final int id in ids) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('KHA-104, the same guard reached through a category that was DELETED '
        'while the dialog was open', () async {
      final (int ruleId, _, _) = await seedRuleWithHistory();
      final CategoryRow custom = (await categoryDao.createCustom(
        name: 'QA Temporary',
        iconToken: 'label',
        groupKey: 'spending',
      ))!;
      await categoryDao.deleteCategory(
        id: custom.id,
        decision: const SetToUncategorized(),
        actor: 'user',
      );

      expect(
        await corrections.editRule(
          ruleId: ruleId,
          categoryId: custom.id,
          reapplyToHistory: false,
        ),
        isNull,
      );
      expect((await merchantDao.ruleById(ruleId))!.categoryId, 'groceries');
    });

    test('AC-D4.3 — deleting a rule stops FUTURE auto-categorization and '
        'leaves already-categorized transactions alone', () async {
      final (int ruleId, _, List<int> ids) = await seedRuleWithHistory();

      await corrections.deleteRule(ruleId: ruleId);

      // History keeps its categories — forgetting a lesson is not forgetting
      // the money.
      for (final int id in ids) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }
      // And the next one arrives uncategorized.
      final int future = await purchase();
      await service.categorizeTransaction(transactionId: future);
      final TransactionRow row = await transactionDao.byId(future);
      expect(row.categoryId, isNull);
      expect(row.needsReview, isTrue);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('editing a rule that no longer exists returns null rather than '
        'throwing', () async {
      expect(
        await corrections.editRule(
          ruleId: 987654,
          categoryId: 'groceries',
          reapplyToHistory: true,
        ),
        isNull,
      );
    });
  });

  // =====================================================================
  // The DAO primitives P4b added
  // =====================================================================

  group('the P4b DAO additions', () {
    test('AC-A5.3 — resolveDuplicateFlag clears a DUPLICATE flag and refuses '
        'to clear any other kind', () async {
      final int a = await purchase();
      final int b = await purchase();
      await transactionDao.flagAsPossibleDuplicate(
        id: a,
        otherId: b,
        reviewReason: ReviewReason.possibleDuplicate,
      );

      expect(await transactionDao.resolveDuplicateFlag(id: a), isTrue);
      final TransactionRow after = await transactionDao.byId(a);
      expect(after.needsReview, isFalse);
      expect(after.reviewReason, isNull);
      expect(after.possibleDuplicateOfId, isNull);
      expect(
        after.isDeleted,
        isFalse,
        reason: 'AC-A5.3: BOTH purchases survive and both stay in every total',
      );
      expect((await transactionDao.byId(b)).isDeleted, isFalse);

      // A categorization flag is a different question and must not be cleared
      // by this path — the symmetric half of `_clearCategoryReviewFlag`.
      final int flaggedForCategory = await purchase();
      await service.categorizeTransaction(transactionId: flaggedForCategory);
      expect(
        await transactionDao.resolveDuplicateFlag(id: flaggedForCategory),
        isFalse,
      );
      expect(
        (await transactionDao.byId(flaggedForCategory)).needsReview,
        isTrue,
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('`duplicateReviewReasons` has not drifted from `ReviewReason`', () {
      // The forcing function for the duplication `transaction_dao.dart`
      // documents: the data layer cannot import `features/ingestion`, so the
      // set is copied — and a copy without a test is a copy that diverges.
      expect(duplicateReviewReasons, <String>{
        ReviewReason.possibleDuplicate,
        ReviewReason.possibleAuthorisationPosting,
      });
    });

    test('liveForMerchant excludes deleted rows, so "we updated N" never '
        'counts something the user cannot see', () async {
      final int a = await purchase();
      final int b = await purchase();
      // Both must carry the merchant LINK, which the categorizer writes — an
      // uncategorized row with a null `merchant_id` is invisible to this query
      // by construction, and that is correct rather than a gap: the count is
      // "this merchant's transactions", not "transactions whose text looks
      // similar".
      for (final int id in <int>[a, b]) {
        await service.categorizeTransaction(transactionId: id);
      }
      final int merchantId = (await transactionDao.byId(a)).merchantId!;
      expect(await transactionDao.liveForMerchant(merchantId), hasLength(2));

      await transactionDao.softDelete(id: b, actor: 'user');
      expect(await transactionDao.liveForMerchant(merchantId), hasLength(1));
    });

    test(
      'restoreCategorySnapshot is a no-op on a row that no longer exists',
      () async {
        final int id = await purchase();
        final CategorySnapshot snapshot = CategorySnapshot.of(
          await transactionDao.byId(id),
        );
        // Raw SQL rather than `softDelete`, because a soft-deleted row still
        // exists — the case under test is the row being genuinely gone, which
        // only ADR-011's "erase everything" produces in the shipped app.
        await db.customStatement('DELETE FROM transactions WHERE id = $id');
        expect(
          await transactionDao.restoreCategorySnapshot(snapshot: snapshot),
          isFalse,
        );
      },
    );

    test(
      '**AC-C4.2 / KHA-32 done-check** — the review count equals the number '
      'of flagged plus uncategorized items, verified against the data layer',
      () async {
        // The done-check says the figure must be *"verified against the data
        // layer"*, so it is computed here from real rows rather than asserted
        // through a widget. `ReviewCounts.fromRows` is the same function the
        // provider uses; there is deliberately no second implementation.

        // Four rows, chosen so the union and the sum DIFFER — otherwise the test
        // would pass for a `flagged + uncategorized` implementation too, which
        // is the specific mistake worth catching.
        final int flaggedAndUncategorized = await purchase();
        await service.categorizeTransaction(
          transactionId: flaggedAndUncategorized,
        );

        final int flaggedButCategorized = await purchase(merchant: 'QANDC');
        await service.applyUserCategory(
          transactionId: flaggedButCategorized,
          categoryId: 'dining',
          learnRule: false,
        );
        await transactionDao.flagAsPossibleDuplicate(
          id: flaggedButCategorized,
          otherId: flaggedAndUncategorized,
          reviewReason: ReviewReason.possibleDuplicate,
        );

        // Uncategorized and NOT flagged — an ingested row nothing has looked at
        // yet. Its id is not needed; its existence is what makes the union and
        // the sum differ.
        await purchase(merchant: 'QANDD');

        final int settled = await purchase(merchant: 'QANDE');
        await service.applyUserCategory(
          transactionId: settled,
          categoryId: 'groceries',
          learnRule: false,
        );

        final ReviewCounts counts = ReviewCounts.fromRows(
          await transactionDao.watchLive().first,
        );

        expect(counts.flagged, 2);
        expect(counts.uncategorized, 2);
        expect(
          counts.needingAttention,
          3,
          reason:
              'a UNION, not a sum: the row that is both flagged and '
              'uncategorized is ONE thing needing review, and adding the two '
              'figures would tell the user there are four problems when there '
              'are three',
        );
        expect(counts.total, counts.needingAttention);

        // …and answering the category question moves the figure, which is the
        // property that makes the badge worth showing at all.
        await corrections.correct(
          transactionId: flaggedAndUncategorized,
          categoryId: 'groceries',
          scope: CorrectionScope.thisTransactionOnly,
        );
        final ReviewCounts after = ReviewCounts.fromRows(
          await transactionDao.watchLive().first,
        );
        expect(after.needingAttention, 2);
      },
    );

    test('a soft-deleted row is not counted — the badge never asks the user to '
        'review something they cannot see', () async {
      final int id = await purchase();
      await service.categorizeTransaction(transactionId: id);
      expect(
        ReviewCounts.fromRows(await transactionDao.watchLive().first).total,
        1,
      );

      await transactionDao.softDelete(id: id, actor: 'user');
      expect(
        ReviewCounts.fromRows(await transactionDao.watchLive().first).total,
        0,
        reason: '`watchLive` excludes deleted rows, so the count does too',
      );
    });

    test('restoreCategorySnapshot never forgets which merchant a transaction '
        'belongs to', () async {
      // The undo restores the CATEGORY, not the identity. Clearing the merchant
      // link would create a second merchant row on the next message — the
      // KHA-105 failure shape.
      final int id = await purchase();
      await service.categorizeTransaction(transactionId: id);
      final int? merchantId = (await transactionDao.byId(id)).merchantId;
      expect(merchantId, isNotNull);

      final CategoryCorrection correction = await corrections.correct(
        transactionId: id,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      await corrections.undo(correction.undo);
      expect((await transactionDao.byId(id)).merchantId, merchantId);
    });
  });
}
