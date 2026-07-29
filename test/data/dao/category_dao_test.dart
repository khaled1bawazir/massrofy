/// **KHA-30's DAO half** — US-C1, US-C3, AC-C1.1, AC-C3.1-4.
///
/// Runs against a real database (a plain in-memory one — see
/// `plain_test_database.dart` for why encryption is not what these tests are
/// about), so the schema's `UNIQUE` constraints and the category-delete
/// trigger are genuinely in play rather than mocked away.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 30);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late CategoryDao categoryDao;
  late TransactionDao transactionDao;
  late CategorizationService service;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    categoryDao = CategoryDao(db, auditLogDao);
    transactionDao = TransactionDao(db, auditLogDao);
    service = CategorizationService(
      categoryDao: categoryDao,
      merchantDao: MerchantDao(db, auditLogDao),
      transactionDao: transactionDao,
    );
    await service.ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  Future<int> transactionIn(String? categoryId) async {
    final int id = await transactionDao.insertManual(
      amount: Money.parse('50.00', currency: 'SAR'),
      merchantRawText: 'SYNTHETIC SHOP',
      occurredAt: DateTime.utc(2026, 7, 15, 10),
      direction: 'debit',
      transactionType: 'pos_purchase',
      affectsSpend: true,
    );
    if (categoryId != null) {
      await transactionDao.setUserCategory(id: id, categoryId: categoryId);
    }
    return id;
  }

  group('seeding (design §4)', () {
    test('writes all 13 categories', () async {
      expect(await categoryDao.all(), hasLength(13));
    });

    test('is idempotent — running it again changes nothing', () async {
      await service.ensureDefaultsSeeded();
      await service.ensureDefaultsSeeded();
      expect(await categoryDao.all(), hasLength(13));
    });

    test('writes no audit entries — installing the app\'s own list is not a '
        'change to the user\'s data', () async {
      expect(
        await auditLogDao.queryFor('category', CategoryIds.uncategorized),
        isEmpty,
      );
    });

    test('does not overwrite a user\'s rename of a seeded category', () async {
      // The idempotent seed uses INSERT OR IGNORE, so re-seeding on the next
      // unlocked session must not undo an edit. A seed that clobbered a rename
      // would make AC-C3.4 last exactly until the app restarted.
      await categoryDao.rename(id: 'groceries', newName: 'Food shopping');
      await service.ensureDefaultsSeeded();
      expect((await categoryDao.byId('groceries'))!.nameEn, 'Food shopping');
    });
  });

  group('AC-C3.1/C3.2 — custom categories and duplicate names', () {
    test('a custom category is created and appears in the list', () async {
      final CategoryRow? created = await categoryDao.createCustom(
        name: 'Kids',
        iconToken: 'child_care',
        groupKey: CategoryGroup.spending.key,
      );

      expect(created, isNotNull);
      expect(created!.isSystem, isFalse);
      expect(await categoryDao.all(), hasLength(14));
      expect(
        (await service.categories()).map((Category c) => c.nameEn),
        contains('Kids'),
      );
    });

    test('the user\'s single name is stored in both language columns, '
        'untranslated', () async {
      final CategoryRow created = (await categoryDao.createCustom(
        name: 'Kids',
        iconToken: 'child_care',
        groupKey: CategoryGroup.spending.key,
      ))!;
      expect(created.nameAr, 'Kids');
      expect(created.nameEn, 'Kids');
    });

    test('a duplicate name is rejected — and case, spacing and Arabic '
        'orthography do not make it a different name', () async {
      await categoryDao.createCustom(
        name: 'Kids',
        iconToken: 'child_care',
        groupKey: CategoryGroup.spending.key,
      );

      for (final String duplicate in <String>['Kids', 'kids', '  KIDS  ']) {
        expect(
          await categoryDao.createCustom(
            name: duplicate,
            iconToken: 'child_care',
            groupKey: CategoryGroup.spending.key,
          ),
          isNull,
          reason: '"$duplicate" is the same name',
        );
      }
      expect(await categoryDao.all(), hasLength(14));
    });

    test(
      'a custom name colliding with a seed\'s ENGLISH name is rejected',
      () async {
        expect(
          await categoryDao.createCustom(
            name: 'Groceries',
            iconToken: 'shopping_cart',
            groupKey: CategoryGroup.spending.key,
          ),
          isNull,
        );
      },
    );

    test('a custom name colliding with a seed\'s ARABIC name is rejected — '
        'one UNIQUE column could not have caught both', () async {
      expect(
        await categoryDao.createCustom(
          name: 'البقالة',
          iconToken: 'shopping_cart',
          groupKey: CategoryGroup.spending.key,
        ),
        isNull,
      );
    });

    test('an empty name is rejected', () async {
      expect(
        await categoryDao.createCustom(
          name: '   ',
          iconToken: 'label',
          groupKey: CategoryGroup.spending.key,
        ),
        isNull,
      );
    });

    test(
      'creating a category writes an audit entry attributed to the user',
      () async {
        final CategoryRow created = (await categoryDao.createCustom(
          name: 'Kids',
          iconToken: 'child_care',
          groupKey: CategoryGroup.spending.key,
        ))!;
        final List<AuditEntryRow> history = await auditLogDao.queryFor(
          'category',
          created.id,
        );
        expect(history.single.action, 'create');
        expect(history.single.actor, 'user');
      },
    );
  });

  group('AC-C3.4 — renaming preserves history', () {
    test('a rename changes the name and touches no transaction', () async {
      final int txn = await transactionIn('groceries');
      final int auditBefore = (await auditLogDao.queryFor(
        'transaction',
        txn.toString(),
      )).length;

      await categoryDao.rename(id: 'groceries', newName: 'Food shopping');

      final TransactionRow row = await transactionDao.byId(txn);
      expect(
        row.categoryId,
        'groceries',
        reason:
            'the link is by id, so a rename cannot move a transaction — which '
            'is exactly why every historical transaction shows the new name',
      );
      expect(
        await auditLogDao.queryFor('transaction', txn.toString()),
        hasLength(auditBefore),
        reason:
            'rewriting transactions on rename would produce thousands of '
            'audit entries recording a change that did not happen to them',
      );
      expect((await categoryDao.byId('groceries'))!.nameEn, 'Food shopping');
    });

    test('renaming to an existing name is rejected', () async {
      expect(
        await categoryDao.rename(id: 'groceries', newName: 'Dining & Cafés'),
        isNull,
      );
      expect((await categoryDao.byId('groceries'))!.nameEn, 'Groceries');
    });

    test('renaming a category to its own name is allowed (a no-op edit is not '
        'a duplicate)', () async {
      expect(
        await categoryDao.rename(id: 'groceries', newName: 'Groceries'),
        isNotNull,
      );
    });

    test('Uncategorized cannot be renamed (design §4)', () async {
      await expectLater(
        categoryDao.rename(
          id: CategoryIds.uncategorized,
          newName: 'Miscellaneous',
        ),
        throwsA(isA<ProtectedCategoryError>()),
      );
    });
  });

  group('AC-C3.3 — deleting a category REQUIRES a decision', () {
    test(
      'delete-with-reassign moves every transaction to the new category',
      () async {
        final int a = await transactionIn('groceries');
        final int b = await transactionIn('groceries');

        final CategoryDeleteOutcome outcome = await categoryDao.deleteCategory(
          id: 'groceries',
          decision: const ReassignTo('dining'),
        );

        expect(outcome.deleted, isTrue);
        expect(outcome.transactionsMoved, 2);
        expect((await transactionDao.byId(a)).categoryId, 'dining');
        expect((await transactionDao.byId(b)).categoryId, 'dining');
        expect(await categoryDao.byId('groceries'), isNull);
      },
    );

    test('delete-with-uncategorize sets them to NULL, the stored form of '
        'Uncategorized', () async {
      final int a = await transactionIn('groceries');

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const SetToUncategorized(),
      );

      expect((await transactionDao.byId(a)).categoryId, isNull);
      expect(
        CategoryResolver.defaults()
            .resolve((await transactionDao.byId(a)).categoryId)
            .id,
        CategoryIds.uncategorized,
        reason: 'AC-C1.1: it still shows a category, never a blank',
      );
    });

    test('a soft-deleted transaction is repointed too — a restore must not '
        'resurrect a dangling reference', () async {
      final int a = await transactionIn('groceries');
      await transactionDao.softDelete(id: a, actor: 'user');

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const SetToUncategorized(),
      );

      await transactionDao.restore(id: a, actor: 'user');
      expect((await transactionDao.byId(a)).categoryId, isNull);
    });

    test(
      'each repointed transaction gets its own audit entry (NFR-A2)',
      () async {
        final int a = await transactionIn('groceries');
        final int before = (await auditLogDao.queryFor(
          'transaction',
          a.toString(),
        )).length;

        await categoryDao.deleteCategory(
          id: 'groceries',
          decision: const ReassignTo('dining'),
        );

        final List<AuditEntryRow> history = await auditLogDao.queryFor(
          'transaction',
          a.toString(),
        );
        expect(history, hasLength(before + 1));
        expect(history.last.action, 'categorize');
        expect(history.last.actorDetail, 'category_deleted:groceries');
      },
    );

    test('reassigning to a category that does not exist is refused before '
        'anything is written', () async {
      final int a = await transactionIn('groceries');

      await expectLater(
        categoryDao.deleteCategory(
          id: 'groceries',
          decision: const ReassignTo('no_such_category'),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await categoryDao.byId('groceries'), isNotNull);
      expect((await transactionDao.byId(a)).categoryId, 'groceries');
    });

    test('reassigning a category to itself is refused', () async {
      await expectLater(
        categoryDao.deleteCategory(
          id: 'groceries',
          decision: const ReassignTo('groceries'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'Uncategorized cannot be deleted (AC-C1.1 depends on it existing)',
      () async {
        await expectLater(
          categoryDao.deleteCategory(
            id: CategoryIds.uncategorized,
            decision: const SetToUncategorized(),
          ),
          throwsA(isA<ProtectedCategoryError>()),
        );
      },
    );

    test('no orphaned category reference is reachable after any delete '
        '(KHA-30 done check)', () async {
      await transactionIn('groceries');
      await transactionIn('dining');
      await transactionIn(null);

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const ReassignTo('dining'),
      );
      await categoryDao.deleteCategory(
        id: 'dining',
        decision: const SetToUncategorized(),
      );

      final Set<String> knownIds = <String>{
        for (final CategoryRow row in await categoryDao.all()) row.id,
      };
      for (final TransactionRow row in await transactionDao.all()) {
        if (row.categoryId != null) {
          expect(
            knownIds,
            contains(row.categoryId),
            reason: 'transaction #${row.id} points at a missing category',
          );
        }
      }
    });

    test('a learned rule naming the deleted category is repointed, and the '
        'change is audited (NFR-A2)', () async {
      final MerchantDao merchantDao = MerchantDao(db, auditLogDao);
      final int merchant = await merchantDao.ensureMerchant(
        merchantKey: 'SYNTHETIC SHOP',
        canonicalName: 'Synthetic Shop',
      );
      final int ruleId = await merchantDao.upsertRule(
        merchantId: merchant,
        categoryId: 'groceries',
        source: 'user',
        actor: 'user',
      );

      final CategoryDeleteOutcome outcome = await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const ReassignTo('dining'),
      );

      expect(outcome.rulesMoved, 1);
      expect((await merchantDao.ruleById(ruleId))!.categoryId, 'dining');
      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'merchant_rule',
        ruleId.toString(),
      );
      expect(history.last.action, 'update');
      expect(history.last.actorDetail, 'category_deleted:groceries');
    });

    test('a learned rule is destroyed with an uncategorized delete, and that '
        'is audited too — "why did my bills stop being categorised?" needs an '
        'answer', () async {
      final MerchantDao merchantDao = MerchantDao(db, auditLogDao);
      final int merchant = await merchantDao.ensureMerchant(
        merchantKey: 'SYNTHETIC SHOP',
        canonicalName: 'Synthetic Shop',
      );
      final int ruleId = await merchantDao.upsertRule(
        merchantId: merchant,
        categoryId: 'groceries',
        source: 'user',
        actor: 'user',
      );

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const SetToUncategorized(),
      );

      expect(await merchantDao.allRules(), isEmpty);
      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'merchant_rule',
        ruleId.toString(),
      );
      expect(history.last.action, 'delete');
      expect(
        auditLogDao.decodeFieldChanges(history.last).single.from,
        'groceries',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('countTransactionsUsing reports what S-15\'s dialog shows', () async {
      await transactionIn('groceries');
      await transactionIn('groceries');
      await transactionIn('dining');
      expect(await categoryDao.countTransactionsUsing('groceries'), 2);
    });
  });
}
