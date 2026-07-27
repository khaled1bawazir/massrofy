import 'package:drift/drift.dart';

import '../../core/money/currency_exponents.dart';
import '../../core/money/money.dart';
import '../db/app_database.dart';
import '../db/tables/transaction_table.dart';
import 'audit_log_dao.dart';

part 'transaction_dao.g.dart';

/// A P1-minimal ledger DAO — see `lib/data/db/tables/transaction_table.dart`
/// for why this table is intentionally small. Its purpose in this phase is
/// to prove the audit-trail mechanism (ADR-010) against a genuine mutation
/// path: every method below that changes a row also writes an
/// [AuditLogDao.append] call **inside the same Drift `transaction()`
/// block**, so the ledger row and its audit entry can never drift apart —
/// either both are committed, or (on any error) neither is, which is what
/// NFR-R6 ("an app crash ... must not corrupt or lose already-recorded
/// transactions") requires of the write path.
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  final AuditLogDao auditLogDao;

  TransactionDao(super.attachedDatabase, this.auditLogDao);

  /// Creates a new transaction row and its matching `create` audit entry.
  Future<int> create({
    String? merchantRawText,
    required Money amount,
    String? categoryId,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          categoryId: Value<String?>(categoryId),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );
      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'create',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'amount',
            from: null,
            to: amount.toCanonicalString(),
          ),
          AuditFieldChange(
            field: 'currency',
            from: null,
            to: amount.currencyCode,
          ),
          if (merchantRawText != null)
            AuditFieldChange(
              field: 'merchantRawText',
              from: null,
              to: merchantRawText,
            ),
        ],
      );
      return id;
    });
  }

  /// Re-categorises an existing transaction, writing a before/after audit
  /// entry for the `categoryId` field (US-F5, AC-F5.1).
  Future<void> updateCategory({
    required int id,
    required String? newCategoryId,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          categoryId: Value<String?>(newCategoryId),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'update',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'categoryId',
            from: existing.categoryId,
            to: newCategoryId,
          ),
        ],
      );
    });
  }

  /// Soft-deletes a transaction (US-B8: hidden and restorable — only
  /// "erase everything", ADR-011/P8, is a true hard delete, AC-B8.3).
  Future<void> softDelete({
    required int id,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          isDeleted: const Value<bool>(true),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'delete',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'isDeleted',
            from: existing.isDeleted.toString(),
            to: 'true',
          ),
        ],
      );
    });
  }

  /// Restores a soft-deleted transaction (US-B8.2).
  Future<void> restore({
    required int id,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          isDeleted: const Value<bool>(false),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'restore',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: const <AuditFieldChange>[
          AuditFieldChange(field: 'isDeleted', from: 'true', to: 'false'),
        ],
      );
    });
  }

  Future<List<TransactionRow>> all() => select(transactions).get();

  Future<TransactionRow> byId(int id) => (select(
    transactions,
  )..where((Transactions t) => t.id.equals(id))).getSingle();

  /// Best-effort derivation of the non-authoritative `_minor` column
  /// (ADR-002) for indexing/range filters only — **never** used for
  /// arithmetic. Looks up the *actual* currency's minor-unit exponent via
  /// [minorUnitExponentFor] (`lib/core/money/currency_exponents.dart`) —
  /// previously this hard-coded a 2-decimal exponent for every currency,
  /// which silently produced a wrong (100x too large, then truncated)
  /// `_minor` value for 0-decimal currencies like JPY and a wrong (10x too
  /// small) value for 3-decimal currencies like KWD/BHD/JOD.
  int _toMinorUnitsBestEffort(Money amount) {
    final int exponent = minorUnitExponentFor(amount.currencyCode);
    final List<String> parts = amount.toCanonicalString().split('.');
    final String wholePart = parts[0];
    final String rawFractionPart = parts.length > 1 ? parts[1] : '';
    final String fractionPart = exponent == 0
        ? ''
        : rawFractionPart.padRight(exponent, '0').substring(0, exponent);
    final int sign = wholePart.startsWith('-') ? -1 : 1;
    final String digits = '${wholePart.replaceFirst('-', '')}$fractionPart';
    return sign * int.parse(digits);
  }
}
