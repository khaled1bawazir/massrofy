/// **KHA-31's store half** — the merchant identity table, the alias table and
/// the learned-rule table (ADR-008, AC-D1.1, AC-D1.2, AC-D3.1, AC-D3.2).
///
/// All merchant strings are synthetic (NFR-M3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 31);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late MerchantDao merchantDao;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    merchantDao = MerchantDao(db, auditLogDao);
    // **KHA-104.** `upsertRule` now validates `category_id` against the
    // `category` table, so a rule-store test needs real categories to point at.
    // That dependency is the fix, not an inconvenience: a rule naming a
    // category that was never created used to be writable, and the matcher then
    // stamped it onto real transactions — a row saying "categorized" while
    // every screen rendered "Uncategorized".
    //
    // Seeded through the service, the same way `category_dao_test.dart` does
    // it, so there is exactly one implementation of design §4's starter list.
    await CategorizationService(
      categoryDao: CategoryDao(db, auditLogDao),
      merchantDao: merchantDao,
      transactionDao: TransactionDao(db, auditLogDao),
    ).ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  group('merchant identity', () {
    test('ensureMerchant is resolve-or-create, never create-twice', () async {
      final int first = await merchantDao.ensureMerchant(
        merchantKey: 'PANDA FOODS',
        canonicalName: 'Panda Foods',
      );
      final int second = await merchantDao.ensureMerchant(
        merchantKey: 'PANDA FOODS',
        canonicalName: 'PANDA FOODS 1420',
      );

      expect(second, first);
      expect(await merchantDao.allMerchants(), hasLength(1));
    });

    test(
      'the first raw spelling is kept for display and not overwritten',
      () async {
        await merchantDao.ensureMerchant(
          merchantKey: 'PANDA FOODS',
          canonicalName: 'Panda Foods',
        );
        await merchantDao.ensureMerchant(
          merchantKey: 'PANDA FOODS',
          canonicalName: 'PANDA FOODS STORE 1420',
        );
        expect(
          (await merchantDao.byKey('PANDA FOODS'))!.canonicalName,
          'Panda Foods',
        );
      },
    );

    test('auto-creating a merchant writes no audit entry — the transaction\'s '
        'own history already records the merchant text', () async {
      final int id = await merchantDao.ensureMerchant(
        merchantKey: 'PANDA FOODS',
        canonicalName: 'Panda Foods',
      );
      expect(await auditLogDao.queryFor('merchant', id.toString()), isEmpty);
    });
  });

  group('aliases — ADR-008\'s cross-script answer (R-5)', () {
    test('an alias links a second spelling to one merchant, and is audited '
        'because a person asserted it', () async {
      final int merchant = await merchantDao.ensureMerchant(
        merchantKey: 'AL BAIK',
        canonicalName: 'Al Baik',
      );

      final int? alias = await merchantDao.linkAlias(
        merchantId: merchant,
        aliasKey: 'البيك',
        script: 'arabic',
      );

      expect(alias, isNotNull);
      expect(await merchantDao.allAliases(), hasLength(1));
      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'merchant_alias',
        alias.toString(),
      );
      expect(history.single.actor, 'user');
      expect(history.single.actorDetail, 'merchant:$merchant');
    });

    test('one spelling cannot name two merchants', () async {
      final int a = await merchantDao.ensureMerchant(
        merchantKey: 'AL BAIK',
        canonicalName: 'Al Baik',
      );
      final int b = await merchantDao.ensureMerchant(
        merchantKey: 'OTHER SHOP',
        canonicalName: 'Other Shop',
      );
      await merchantDao.linkAlias(
        merchantId: a,
        aliasKey: 'البيك',
        script: 'arabic',
      );

      expect(
        await merchantDao.linkAlias(
          merchantId: b,
          aliasKey: 'البيك',
          script: 'arabic',
        ),
        isNull,
        reason:
            'silently repointing an alias would move every future message '
            'from one shop onto another\'s rule',
      );
    });
  });

  group('rules — AC-D1.1, AC-D1.2, AC-D3.1', () {
    Future<int> merchant(String key) =>
        merchantDao.ensureMerchant(merchantKey: key, canonicalName: key);

    test('KHA-104 — a rule naming a category that does not exist is REFUSED, '
        'because SQLite is not checking it for us', () async {
      // `merchant_rule.category_id` has no foreign key, and the
      // `category_no_delete_while_in_use` trigger guards only the *delete*
      // direction. So a rule could be written for a category id that was never
      // created, and the matcher then confidently stamped it onto real
      // transactions: the row said "categorized" while every screen rendered
      // "Uncategorized" — AC-C1.1's explicit fallback state reached by
      // accident rather than by decision.
      final int id = await merchant('SEC KAHRABA');

      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'no_such_category',
        source: 'user',
        actor: 'user',
      );
      expect(await merchantDao.allRules(), isEmpty);
      expect(await merchantDao.ruleForMerchant(id), isNull);

      // A no-op, not a throw: the reachable caller is a person correcting a
      // category in the UI, and a crash is the wrong answer to stale data. The
      // sentinel is negative, so a caller that ignores it cannot mistake it for
      // a real `merchant_rule.id`.
      expect(
        await merchantDao.upsertRule(
          merchantId: id,
          categoryId: 'no_such_category',
          source: 'user',
          actor: 'user',
        ),
        lessThan(0),
      );

      // A refusal must also not disturb a rule that is already there.
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'no_such_category',
        source: 'user',
        actor: 'user',
      );
      expect(
        (await merchantDao.ruleForMerchant(id))!.categoryId,
        'utilities_bills',
        reason:
            'a refused write must leave the stored rule exactly as it was, '
            'not blank it',
      );
    });

    test('categorizing creates a rule, visible in the learned-rules list '
        '(AC-D1.1)', () async {
      final int id = await merchant('SEC KAHRABA');
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );

      final List<MerchantRuleRow> rules = await merchantDao.allRules();
      expect(rules, hasLength(1));
      expect(rules.single.categoryId, 'utilities_bills');
      expect(rules.single.source, 'user');
    });

    test('re-categorizing UPDATES the rule instead of adding a rival '
        '(AC-D1.2)', () async {
      final int id = await merchant('SEC KAHRABA');
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'fees_charges',
        source: 'user',
        actor: 'user',
      );

      final List<MerchantRuleRow> rules = await merchantDao.allRules();
      expect(
        rules,
        hasLength(1),
        reason:
            'a merchant with two live rules is a matcher that has to guess, '
            'which is a coin toss with the user\'s money-tracking',
      );
      expect(rules.single.categoryId, 'fees_charges');
    });

    test('the rule\'s previous category survives in the audit trail — the '
        'store holds what is true now, history lives in the trail', () async {
      final int id = await merchant('SEC KAHRABA');
      final int ruleId = await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'fees_charges',
        source: 'user',
        actor: 'user',
      );

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'merchant_rule',
        ruleId.toString(),
      );
      expect(history, hasLength(2));
      expect(history.first.action, 'create');
      expect(history.last.action, 'update');
      final AuditFieldChange change = auditLogDao
          .decodeFieldChanges(history.last)
          .first;
      expect(change.from, 'utilities_bills');
      expect(change.to, 'fees_charges');
    });

    test('a seed source never demotes a user rule (AC-D3.1)', () async {
      final int id = await merchant('SEC KAHRABA');
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'fees_charges',
        source: 'seed',
        actor: 'importer',
      );

      expect(
        (await merchantDao.ruleForMerchant(id))!.source,
        'user',
        reason:
            'demoting the provenance would discard the fact that a person '
            'decided this, and with it the tie-break that makes "user '
            'correction always wins" true',
      );
    });

    test('recordRuleApplied counts firings and writes no audit entry of its '
        'own', () async {
      final int id = await merchant('SEC KAHRABA');
      final int ruleId = await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      final int entriesBefore = (await auditLogDao.queryFor(
        'merchant_rule',
        ruleId.toString(),
      )).length;

      await merchantDao.recordRuleApplied(
        ruleId: ruleId,
        at: DateTime.utc(2026, 7, 20),
      );
      await merchantDao.recordRuleApplied(
        ruleId: ruleId,
        at: DateTime.utc(2026, 7, 21),
      );

      final MerchantRuleRow rule = (await merchantDao.ruleById(ruleId))!;
      expect(rule.appliedCount, 2);
      // Drift stores a `DateTimeColumn` as a Unix timestamp and hands it back
      // in the device's local zone, so the comparison is made in UTC — the
      // same care `audit_log_dao.dart` takes over its hashed timestamps.
      expect(rule.lastAppliedAt!.toUtc(), DateTime.utc(2026, 7, 21));
      expect(
        await auditLogDao.queryFor('merchant_rule', ruleId.toString()),
        hasLength(entriesBefore),
        reason:
            'the firing is recorded once, against the transaction it changed',
      );
    });

    test('recordRuleApplied on a rule that no longer exists is a no-op, not a '
        'crash', () async {
      await merchantDao.recordRuleApplied(ruleId: 9999);
    });

    test('a disabled rule is excluded from the matcher\'s input but stays in '
        'the list', () async {
      final int id = await merchant('SEC KAHRABA');
      final int ruleId = await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );
      await db.customStatement(
        'UPDATE merchant_rule SET is_enabled = 0 WHERE id = ?;',
        <Object?>[ruleId],
      );

      expect(await merchantDao.enabledRules(), isEmpty);
      expect(await merchantDao.allRules(), hasLength(1));
    });

    test('deleting a rule forgets the lesson, not the money', () async {
      final int id = await merchant('SEC KAHRABA');
      final int ruleId = await merchantDao.upsertRule(
        merchantId: id,
        categoryId: 'utilities_bills',
        source: 'user',
        actor: 'user',
      );

      await merchantDao.deleteRule(id: ruleId);

      expect(await merchantDao.allRules(), isEmpty);
      expect(await merchantDao.byId(id), isNotNull);
      expect(
        (await auditLogDao.queryFor(
          'merchant_rule',
          ruleId.toString(),
        )).last.action,
        'delete',
      );
    });
  });
}
