import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao transactionDao;

  setUp(() {
    // Plain (non-encrypted) in-memory DB — see
    // test/support/plain_test_database.dart for why.
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    transactionDao = TransactionDao(db, auditLogDao);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'create() persists the transaction and writes a create audit entry',
    () async {
      final int id = await transactionDao.create(
        merchantRawText: 'Panda Foods',
        amount: Money.parse('45.00', currency: 'SAR'),
        actor: 'user',
      );

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.merchantRawText, 'Panda Foods');
      // package:decimal's canonical toString() trims trailing zeros — see
      // the note in money_test.dart; "45" and "45.00" are the same value.
      expect(row.amountAmount, '45');
      expect(row.amountCurrency, 'SAR');
      expect(row.isDeleted, isFalse);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        id.toString(),
      );
      expect(history, hasLength(1));
      expect(history.single.action, 'create');
      expect(history.single.actor, 'user');
    },
  );

  // P4a (KHA-30/31) replaced P1's `updateCategory` — which wrote `category_id`
  // alone — with two purpose-built methods, because a category id now travels
  // with three facts about how it got there. The US-F5 coverage the old test
  // provided is kept and extended below: the same before/after audit entry,
  // plus the provenance columns and the AC-D3.1 refusal that the old
  // single-method shape could not express.
  group('categorization writes (US-F5, AC-D2.2, AC-D3.1)', () {
    test('setUserCategory writes a before/after audit entry attributed to the '
        'user, and records the category as user-chosen', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('10.00', currency: 'SAR'),
        actor: 'user',
      );

      await transactionDao.setUserCategory(id: id, categoryId: 'groceries');
      await transactionDao.setUserCategory(id: id, categoryId: 'dining');

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.categoryId, 'dining');
      expect(row.categorySource, StoredCategorySource.user);
      expect(row.categoryConfidence, 1.0);
      expect(
        decodeUserEditedFields(row.userEditedFields),
        contains(TransactionField.categoryId),
        reason:
            'the app-wide "a person edited this" mechanism is what the '
            'enrichment merge already honours — AC-D3.1 reuses it rather than '
            'inventing a second protection flag',
      );

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        id.toString(),
      );
      // create + 2 categorizations == 3 entries, one per mutation.
      expect(history, hasLength(3));
      expect(history.last.action, 'categorize');
      expect(history.last.actor, 'user');
      final AuditFieldChange change = auditLogDao
          .decodeFieldChanges(history.last)
          .first;
      expect(change.field, TransactionField.categoryId);
      expect(change.from, 'groceries');
      expect(change.to, 'dining');
    });

    test('applyAutomaticCategory attributes the entry to the SYSTEM and names '
        'the rule that fired (AC-F5.2, NFR-A2)', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('10.00', currency: 'SAR'),
        actor: 'parser',
      );

      final bool written = await transactionDao.applyAutomaticCategory(
        id: id,
        categoryId: 'utilities_bills',
        confidence: 1.0,
        ruleId: 42,
        actorDetail: 'merchant_rule:42',
      );

      expect(written, isTrue);
      final TransactionRow row = await transactionDao.byId(id);
      expect(row.categoryId, 'utilities_bills');
      expect(row.categorySource, StoredCategorySource.rule);
      expect(row.categoryRuleId, 42);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        id.toString(),
      );
      expect(history.last.action, 'categorize');
      expect(history.last.actor, 'system_rule');
      expect(history.last.actorDetail, 'merchant_rule:42');
    });

    test('applyAutomaticCategory refuses to overwrite a user-set category and '
        'writes nothing at all (AC-D3.1)', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('10.00', currency: 'SAR'),
        actor: 'user',
      );
      await transactionDao.setUserCategory(id: id, categoryId: 'groceries');
      final int entriesBefore = (await auditLogDao.queryFor(
        'transaction',
        id.toString(),
      )).length;

      final bool written = await transactionDao.applyAutomaticCategory(
        id: id,
        categoryId: 'dining',
        confidence: 1.0,
        ruleId: 7,
        merchantId: 3,
        actorDetail: 'merchant_rule:7',
      );

      expect(written, isFalse);
      final TransactionRow row = await transactionDao.byId(id);
      expect(row.categoryId, 'groceries');
      expect(row.categorySource, StoredCategorySource.user);
      expect(
        row.merchantId,
        isNull,
        reason:
            'the refusal writes nothing — not even the merchant link — '
            'because any write here is what AC-D3.1 forbids',
      );
      expect(
        await auditLogDao.queryFor('transaction', id.toString()),
        hasLength(entriesBefore),
      );
    });

    test('choosing Uncategorized explicitly is stored as NULL and still '
        'protects the field (AC-C1.1 one representation)', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('10.00', currency: 'SAR'),
        actor: 'user',
      );

      await transactionDao.setUserCategory(
        id: id,
        categoryId: uncategorizedCategoryId,
      );

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.categoryId, isNull);
      expect(row.categorySource, StoredCategorySource.user);
      expect(
        await transactionDao.applyAutomaticCategory(
          id: id,
          categoryId: 'dining',
          confidence: 1.0,
          ruleId: 1,
          actorDetail: 'merchant_rule:1',
        ),
        isFalse,
        reason:
            'deliberately blanking a category is a decision, and the app must '
            'not quietly re-categorise something the user cleared',
      );
    });
  });

  group('Soft delete / restore (US-B8)', () {
    test(
      'softDelete hides the row logically and records the mutation',
      () async {
        final int id = await transactionDao.create(
          amount: Money.parse('20.00', currency: 'SAR'),
          actor: 'user',
        );

        await transactionDao.softDelete(id: id, actor: 'user');

        final TransactionRow row = await transactionDao.byId(id);
        expect(row.isDeleted, isTrue);

        final List<AuditEntryRow> history = await auditLogDao.queryFor(
          'transaction',
          id.toString(),
        );
        expect(history.last.action, 'delete');
      },
    );

    test('restore reverses a soft delete and records the mutation', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('20.00', currency: 'SAR'),
        actor: 'user',
      );
      await transactionDao.softDelete(id: id, actor: 'user');
      await transactionDao.restore(id: id, actor: 'user');

      final TransactionRow row = await transactionDao.byId(id);
      expect(row.isDeleted, isFalse);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        id.toString(),
      );
      expect(history.last.action, 'restore');
    });
  });

  group('_toMinorUnitsBestEffort respects the actual currency exponent (item 7 '
      '— previously hard-coded to 2 for every currency, which was silently '
      'wrong for 0- and 3-decimal currencies)', () {
    test('SAR (2-decimal, the common case) still derives correctly', () async {
      final int id = await transactionDao.create(
        amount: Money.parse('45.67', currency: 'SAR'),
        actor: 'user',
      );
      final TransactionRow row = await transactionDao.byId(id);
      expect(row.amountMinor, 4567);
    });

    test(
      'JPY (0-decimal) does not inflate the minor-units value 100x',
      () async {
        final int id = await transactionDao.create(
          amount: Money.parse('1500', currency: 'JPY'),
          actor: 'user',
        );
        final TransactionRow row = await transactionDao.byId(id);
        // Previously (hard-coded exponent=2) this would have produced
        // 150000 — a JPY amount has no fractional part at all.
        expect(row.amountMinor, 1500);
      },
    );

    test(
      'KWD (3-decimal) does not truncate the third fractional digit',
      () async {
        final int id = await transactionDao.create(
          amount: Money.parse('12.345', currency: 'KWD'),
          actor: 'user',
        );
        final TransactionRow row = await transactionDao.byId(id);
        // Previously (hard-coded exponent=2) this would have produced
        // 1234 (truncated to 2 decimals) instead of the correct 12345
        // (3 decimals — the fils, KWD's actual minor unit).
        expect(row.amountMinor, 12345);
      },
    );

    // ---------------------------------------------------------------------
    // KHA-79 — this test used to read "a negative KWD amount preserves its
    // sign correctly" and asserted `amountMinor == -1500`. It was green, and
    // it pinned **the opposite of the app's sign convention**: that
    // `create()` would accept, store and round-trip a negative magnitude.
    //
    // `lib/core/money/sign_convention.dart` is explicit that an amount is
    // always a non-negative magnitude and the sign lives in `direction`, and
    // P3b-1 guarded the two shipping write paths accordingly — but not
    // `create()`, which had no production caller. P3b-2 adds callers, so the
    // guard lands here, and this test now pins the rejection.
    //
    // Its real subject was always the KWD exponent, and that is covered
    // immediately above by "KWD (3-decimal) does not truncate the third
    // fractional digit" using a positive amount — so nothing is lost by
    // inverting it.
    // ---------------------------------------------------------------------
    test(
      'a negative KWD amount is REJECTED at the write boundary (KHA-79)',
      () {
        // `checkMovementAmount` throws synchronously, before the Future is
        // constructed, so `expectLater(future, throwsA(...))` would not catch
        // it. This form is required, not stylistic.
        expect(
          () => transactionDao.create(
            amount: Money.parse('-1.500', currency: 'KWD'),
            actor: 'user',
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  test('the ledger row and its audit entry are written atomically — an error '
      'mid-mutation leaves neither committed (NFR-R6)', () async {
    // setUserCategory() on a non-existent id: the SELECT ..getSingle()
    // throws before any write happens, so nothing should be recorded.
    await expectLater(
      transactionDao.setUserCategory(
        id: 999999,
        categoryId: 'groceries',
        actor: 'user',
      ),
      throwsA(anything),
    );
    expect(await auditLogDao.queryFor('transaction', '999999'), isEmpty);
  });
}
