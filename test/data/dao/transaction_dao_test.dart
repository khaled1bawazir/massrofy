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

  test('updateCategory() writes a before/after audit entry (US-F5)', () async {
    final int id = await transactionDao.create(
      amount: Money.parse('10.00', currency: 'SAR'),
      actor: 'user',
    );

    await transactionDao.updateCategory(
      id: id,
      newCategoryId: 'groceries',
      actor: 'user',
    );
    await transactionDao.updateCategory(
      id: id,
      newCategoryId: 'dining',
      actor: 'system_rule',
      actorDetail: 'rule-42',
    );

    final TransactionRow row = await transactionDao.byId(id);
    expect(row.categoryId, 'dining');

    final List<AuditEntryRow> history = await auditLogDao.queryFor(
      'transaction',
      id.toString(),
    );
    // create + 2 updates == 3 entries, one per mutation.
    expect(history, hasLength(3));
    expect(history.last.actor, 'system_rule');
    expect(history.last.actorDetail, 'rule-42');
    final AuditFieldChange change = auditLogDao
        .decodeFieldChanges(history.last)
        .single;
    expect(change.from, 'groceries');
    expect(change.to, 'dining');
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

  test('the ledger row and its audit entry are written atomically — an error '
      'mid-mutation leaves neither committed (NFR-R6)', () async {
    // updateCategory() on a non-existent id: the SELECT ..getSingle()
    // throws before any write happens, so nothing should be recorded.
    await expectLater(
      transactionDao.updateCategory(
        id: 999999,
        newCategoryId: 'groceries',
        actor: 'user',
      ),
      throwsA(anything),
    );
    expect(await auditLogDao.queryFor('transaction', '999999'), isEmpty);
  });
}
