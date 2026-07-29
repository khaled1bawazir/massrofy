/// **AC-C1.3 — the category-sum invariant**, asserted after each of the four
/// category operations KHA-30's done check names.
///
/// > *A test asserts the category-sum invariant holds after each of: create,
/// > rename, delete-with-reassign, delete-with-uncategorize. No orphaned
/// > category reference is reachable.*
///
/// `docs/build-plan.md` is explicit that this is *"a reconciliation guarantee,
/// not a display detail"*, and that P3b-1 made the underlying sum
/// currency-aware. So the fixtures here are deliberately awkward: two
/// currencies, a refund that must *reduce* spend, an internal transfer that
/// must be excluded from both sides, an unconverted foreign purchase that must
/// be left out of the base figure on both sides, and an uncategorized
/// transaction that must be *in* the sum.
///
/// A version of this test using only same-currency debits would pass against
/// almost any implementation. This one fails if the parts and the whole are
/// computed by two different sets of rules.
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
import 'package:massrofy/features/categorization/category_breakdown.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 13);

final PeriodRange july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

void main() {
  late AppDatabase db;
  late CategoryDao categoryDao;
  late TransactionDao transactionDao;
  late CategorizationService service;

  setUp(() async {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
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

  Future<int> spend(
    String amount, {
    String currency = 'SAR',
    String? categoryId,
    String direction = 'debit',
    String transactionType = 'pos_purchase',
    bool affectsSpend = true,
    int day = 15,
    String? convertedAmount,
  }) async {
    // Written through the SMS path rather than the manual one because that is
    // the only writer that accepts the bank's own converted amount, and this
    // fixture set needs both a converted and an unconverted foreign row.
    final int id = await transactionDao.insertFromParsedSms(
      amount: Money.parse(amount, currency: currency),
      convertedAmount: convertedAmount == null
          ? null
          : Money.parse(convertedAmount, currency: 'SAR'),
      conversionPending: currency != 'SAR' && convertedAmount == null,
      merchantRawText: 'SYNTHETIC MERCHANT $day',
      occurredAt: DateTime.utc(2026, 7, day, 12),
      direction: direction,
      transactionType: transactionType,
      affectsSpend: affectsSpend,
      sourceMessageId: day,
      rulePackId: 'test-pack',
      rulePackVersion: '1.0.0',
      ruleId: 'test-rule',
    );
    if (categoryId != null) {
      await transactionDao.setUserCategory(id: id, categoryId: categoryId);
    }
    return id;
  }

  /// Builds the breakdown the way a screen would.
  Future<CategoryBreakdown> breakdown() async => CategoryBreakdown.of(
    toLedgerTransactions(await transactionDao.all()),
    period: july2026,
    resolver: await service.resolver(),
  );

  /// The invariant itself, plus the independent cross-check that the parts
  /// really do add up to the same figure `LedgerTotals` produces on its own.
  Future<void> expectInvariantHolds(String after) async {
    final CategoryBreakdown result = await breakdown();
    expect(
      result.reconciles,
      isTrue,
      reason:
          'AC-C1.3 broken after $after: the category slices no longer sum to '
          'the period total',
    );

    final PeriodTotals independent = LedgerTotals.spend(
      toLedgerTransactions(await transactionDao.all()),
      period: july2026,
    );
    expect(
      result.total.base,
      independent.base,
      reason:
          'after $after the breakdown\'s own total drifted from the period '
          'figure every other screen shows',
    );
  }

  /// The awkward fixture set described in the library comment.
  Future<void> seedLedger() async {
    await spend('100.00', categoryId: 'groceries');
    await spend('50.00', categoryId: 'groceries', day: 16);
    await spend('80.00', categoryId: 'dining', day: 17);
    // Uncategorized — the row AC-C1.3 exists to keep in the sum.
    await spend('25.00', day: 18);
    // A refund reduces spend (US-B7). If the parts and the whole applied the
    // sign differently, this is the row that would expose it.
    await spend(
      '30.00',
      categoryId: 'groceries',
      direction: 'credit',
      transactionType: 'refund',
      day: 19,
    );
    // An internal transfer: excluded from spend on both sides (AC-B11.1).
    await spend(
      '500.00',
      categoryId: 'internal_transfer',
      transactionType: 'transfer_out',
      affectsSpend: false,
      day: 20,
    );
    // Foreign currency WITH the bank's own conversion — in the base total.
    await spend(
      '20.00',
      currency: 'USD',
      convertedAmount: '75.00',
      categoryId: 'shopping_retail',
      day: 21,
    );
    // Foreign currency with NO conversion — out of the base total on both
    // sides, and counted on the "not converted" line (ADR-009 case 4).
    await spend('10.00', currency: 'EUR', categoryId: 'dining', day: 22);
    // Outside the period entirely.
    await spend('999.00', categoryId: 'groceries', day: 5);
  }

  group('AC-C1.3 — the sum of all category totals equals the period total', () {
    setUp(seedLedger);

    test('holds on the seeded ledger, before any category operation', () async {
      await expectInvariantHolds('seeding');
    });

    test('Uncategorized is IN the breakdown, not omitted from it', () async {
      final CategoryBreakdown result = await breakdown();
      expect(
        result.categories.any(
          (CategoryTotal slice) => slice.category.isUncategorized,
        ),
        isTrue,
      );
      expect(result.uncategorizedCount, 1);
    });

    test('the unconverted transaction is excluded from BOTH sides, and said '
        'so on both', () async {
      final CategoryBreakdown result = await breakdown();
      expect(result.total.isIncomplete, isTrue);
      final CategoryTotal dining = result.categories.firstWhere(
        (CategoryTotal slice) => slice.category.id == 'dining',
      );
      expect(
        dining.totals.isIncomplete,
        isTrue,
        reason:
            'a category slice must never look more certain than the total it '
            'came from',
      );
      // …and the invariant still holds precisely because both sides left it
      // out.
      expect(result.reconciles, isTrue);
    });

    test('holds after CREATE (AC-C3.1)', () async {
      await categoryDao.createCustom(
        name: 'Kids',
        iconToken: 'child_care',
        groupKey: CategoryGroup.spending.key,
      );
      await expectInvariantHolds('create');
    });

    test('holds after RENAME (AC-C3.4)', () async {
      await categoryDao.rename(id: 'groceries', newName: 'Food shopping');
      await expectInvariantHolds('rename');
    });

    test('holds after DELETE-WITH-REASSIGN (AC-C3.3)', () async {
      final CategoryBreakdown before = await breakdown();
      final Money? groceriesBefore = before.categories
          .firstWhere((CategoryTotal s) => s.category.id == 'groceries')
          .totals
          .base;
      final Money? diningBefore = before.categories
          .firstWhere((CategoryTotal s) => s.category.id == 'dining')
          .totals
          .base;

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const ReassignTo('dining'),
      );
      await expectInvariantHolds('delete-with-reassign');

      // Stronger than "it still adds up": the money genuinely moved from one
      // slice to the other rather than being dropped and the total being
      // recomputed to match.
      final CategoryBreakdown after = await breakdown();
      expect(
        after.categories.any((CategoryTotal s) => s.category.id == 'groceries'),
        isFalse,
      );
      final Money? diningAfter = after.categories
          .firstWhere((CategoryTotal s) => s.category.id == 'dining')
          .totals
          .base;
      expect(diningAfter, diningBefore! + groceriesBefore!);
    });

    test('holds after DELETE-WITH-UNCATEGORIZE (AC-C3.3)', () async {
      final CategoryBreakdown before = await breakdown();
      final Money? groceriesBefore = before.categories
          .firstWhere((CategoryTotal s) => s.category.id == 'groceries')
          .totals
          .base;
      final Money? uncategorizedBefore = before.categories
          .firstWhere((CategoryTotal s) => s.category.isUncategorized)
          .totals
          .base;

      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const SetToUncategorized(),
      );
      await expectInvariantHolds('delete-with-uncategorize');

      final CategoryBreakdown after = await breakdown();
      final Money? uncategorizedAfter = after.categories
          .firstWhere((CategoryTotal s) => s.category.isUncategorized)
          .totals
          .base;
      expect(
        uncategorizedAfter,
        uncategorizedBefore! + groceriesBefore!,
        reason:
            'this is the operation a design that excluded Uncategorized from '
            'the breakdown would silently fail, while looking correct on the '
            'other three',
      );
    });

    test('holds after all four operations in sequence', () async {
      await categoryDao.createCustom(
        name: 'Kids',
        iconToken: 'child_care',
        groupKey: CategoryGroup.spending.key,
      );
      await categoryDao.rename(id: 'dining', newName: 'Eating out');
      await categoryDao.deleteCategory(
        id: 'groceries',
        decision: const ReassignTo('dining'),
      );
      await categoryDao.deleteCategory(
        id: 'shopping_retail',
        decision: const SetToUncategorized(),
      );
      await expectInvariantHolds('create + rename + both deletes');
    });

    test('a soft-deleted transaction leaves both sides at once', () async {
      // US-B8: a deleted transaction is out of every total. If it left the
      // slices but not the whole (or the reverse), this fails.
      final int id = await spend('40.00', categoryId: 'dining', day: 23);
      await expectInvariantHolds('adding a row');
      await transactionDao.softDelete(id: id, actor: 'user');
      await expectInvariantHolds('soft delete');
    });

    test('an unresolvable category id still lands in the sum, in the '
        'Uncategorized slice', () async {
      // Only reachable by editing the database outside the app — the delete
      // path repoints first. The point is the *degradation*: the figure stays
      // right and only the label falls back.
      final int id = await spend('60.00', day: 24);
      await db.customStatement(
        "UPDATE transactions SET category_id = 'ghost' WHERE id = ?;",
        <Object?>[id],
      );

      final CategoryBreakdown result = await breakdown();
      expect(result.reconciles, isTrue);
      expect(result.uncategorizedCount, 2);
    });
  });

  group('an empty ledger', () {
    test(
      'reconciles trivially rather than dividing by zero somewhere',
      () async {
        final CategoryBreakdown result = await breakdown();
        expect(result.categories, isEmpty);
        expect(result.total.base, isNull);
        expect(result.reconciles, isTrue);
      },
    );
  });
}
