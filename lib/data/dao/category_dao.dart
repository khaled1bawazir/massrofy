import 'package:drift/drift.dart';

import '../../core/text/canonical_text.dart';
import '../db/app_database.dart';
import '../db/tables/category_table.dart';
import '../db/tables/merchant_table.dart';
import '../db/tables/transaction_table.dart';
import 'audit_log_dao.dart';

part 'category_dao.g.dart';

/// Reads and writes the `category` table — KHA-30, US-C1/US-C3.
///
/// ## What this DAO refuses to let a caller do
///
/// Three things, and each one is an acceptance criterion that would otherwise
/// depend on every future call site remembering it:
///
///  1. **Create a category whose name already exists** (AC-C3.2). Checked here
///     against the *folded* name (`CanonicalText.fold`), so `Groceries`,
///     `groceries` and `  GROCERIES ` are one name, and backed by two `UNIQUE`
///     indexes in the schema in case a caller ever finds another way in.
///  2. **Delete a category without saying where its transactions go**
///     (AC-C3.3). [deleteCategory] takes a required [CategoryDeleteDecision]; there is
///     no overload that omits it, and the database's own
///     `category_no_delete_while_in_use` trigger aborts the statement if the
///     repointing did not happen.
///  3. **Rename or delete the protected *Uncategorized* row** (design §4).
///
/// ## Renaming does not touch a single transaction (AC-C3.4)
///
/// *"Renaming a category updates all historical transactions and preserves
/// their history."* It does — by not touching them. `transactions.category_id`
/// holds the category's **id**, and [rename] changes only the name columns, so
/// every historical transaction shows the new name immediately and its own
/// audit history is untouched because nothing about it changed. An
/// implementation that rewrote transactions on rename would produce thousands
/// of audit entries recording a change that did not happen to them.
@DriftAccessor(tables: [Categories, Transactions, MerchantRules])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  final AuditLogDao auditLogDao;

  CategoryDao(super.attachedDatabase, this.auditLogDao);

  /// Inserts one seeded category if it is not already there.
  ///
  /// `InsertMode.insertOrIgnore` rather than read-then-write: seeding runs on
  /// every unlocked session (it is the cheapest way to guarantee the row
  /// AC-C1.1 depends on exists), and an idempotent statement is both faster
  /// and immune to two isolates racing — the UI isolate and the background
  /// ingestion isolate can both open this database (ADR-006).
  ///
  /// **No audit entry, deliberately.** ADR-010's trail records changes to the
  /// *user's* data and names the actor responsible. Installing the app's own
  /// shipped starter list is not a change to anything that existed and has no
  /// actor to name; writing "the app created 13 categories" on every install
  /// would add noise to a history whose value is that everything in it
  /// matters. Every subsequent edit to a seeded category — rename, delete —
  /// *is* audited, because that is a user changing something.
  ///
  /// Takes primitives rather than a domain `Category` on purpose: `data/` must
  /// not import `features/` (architecture §3's dependency rule), so the
  /// feature layer unpacks its own type here.
  Future<void> ensureSeedRow({
    required String id,
    required String key,
    required String nameAr,
    required String nameEn,
    required String iconToken,
    String? colorToken,
    required String groupKey,
    required bool isProtected,
    required int sortOrder,
    DateTime? now,
  }) async {
    final DateTime timestamp = now ?? DateTime.now();
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: id,
        key: key,
        nameAr: nameAr,
        nameEn: nameEn,
        nameKeyAr: CanonicalText.fold(nameAr),
        nameKeyEn: CanonicalText.fold(nameEn),
        iconToken: iconToken,
        colorToken: Value<String?>(colorToken),
        groupKey: groupKey,
        isSystem: const Value<bool>(true),
        isProtected: Value<bool>(isProtected),
        sortOrder: Value<int>(sortOrder),
        createdAt: Value<DateTime>(timestamp),
        updatedAt: Value<DateTime>(timestamp),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Creates a user-defined category (AC-C3.1), or returns `null` when its
  /// name duplicates an existing one (AC-C3.2).
  ///
  /// ## Why the single name is written into both language columns
  ///
  /// The user types one name (design §6.5's inline "+ New category" row has
  /// one field). We do not translate it — inventing an Arabic name for an
  /// English word the user chose would put words in their mouth, and a
  /// machine translation of "Kids" is not a category name anyone asked for.
  /// So both `name_ar` and `name_en` hold what they typed, and the app renders
  /// the same string in either locale.
  ///
  /// A useful consequence: because both folded-name columns are `UNIQUE`, a
  /// custom category called "Groceries" collides with the seed's English name
  /// *and* one called "البقالة" collides with the seed's Arabic name. One
  /// column could only have caught one of those.
  ///
  /// Returns null rather than throwing because a duplicate name is a normal
  /// user mistake with a normal UI response (AC-C3.2's "rejected with a
  /// message"), not an exceptional condition.
  Future<CategoryRow?> createCustom({
    required String name,
    required String iconToken,
    String? colorToken,
    required String groupKey,
    String actor = 'user',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    final String trimmed = name.trim();
    final String nameKey = CanonicalText.fold(trimmed);

    return transaction<CategoryRow?>(() async {
      if (trimmed.isEmpty || await _nameIsTaken(nameKey)) {
        return null;
      }

      // `custom_` prefix + the creation instant: unique without a UUID
      // dependency, and self-describing in a database browser. The row's
      // identity never changes afterwards, which is what makes AC-C3.4's
      // "renaming preserves history" free.
      final String id =
          'custom_${timestamp.toUtc().microsecondsSinceEpoch}_'
          '${nameKey.hashCode.toUnsigned(16)}';

      final int nextSortOrder =
          (await _maxSortOrder(groupKey) ?? _seedSortOrderCeiling) + 1;

      await into(categories).insert(
        CategoriesCompanion.insert(
          id: id,
          key: id,
          nameAr: trimmed,
          nameEn: trimmed,
          nameKeyAr: nameKey,
          nameKeyEn: nameKey,
          iconToken: iconToken,
          colorToken: Value<String?>(colorToken),
          groupKey: groupKey,
          isSystem: const Value<bool>(false),
          sortOrder: Value<int>(nextSortOrder),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'category',
        entityId: id,
        action: 'create',
        actor: actor,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(field: 'name', from: null, to: trimmed),
          AuditFieldChange(field: 'group', from: null, to: groupKey),
        ],
      );

      return byId(id);
    });
  }

  /// Renames a category (AC-C3.4). Returns the updated row, or `null` when the
  /// new name duplicates another category's.
  ///
  /// Throws [ProtectedCategoryError] for *Uncategorized* — design §4 states it
  /// "cannot be deleted or renamed", and AC-C1.1's fallback stops being
  /// recognisable if it can be renamed to something else.
  ///
  /// Not a transaction-touching operation: see the class comment.
  Future<CategoryRow?> rename({
    required String id,
    required String newName,
    String actor = 'user',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    final String trimmed = newName.trim();
    final String nameKey = CanonicalText.fold(trimmed);

    return transaction<CategoryRow?>(() async {
      final CategoryRow? existing = await byId(id);
      if (existing == null) {
        return null;
      }
      if (existing.isProtected) {
        throw ProtectedCategoryError(id, operation: 'renamed');
      }
      if (trimmed.isEmpty || await _nameIsTaken(nameKey, exceptId: id)) {
        return null;
      }

      await (update(
        categories,
      )..where((Categories t) => t.id.equals(id))).write(
        CategoriesCompanion(
          nameAr: Value<String>(trimmed),
          nameEn: Value<String>(trimmed),
          nameKeyAr: Value<String>(nameKey),
          nameKeyEn: Value<String>(nameKey),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'category',
        entityId: id,
        action: 'update',
        actor: actor,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          // Both prior names are recorded because a seeded category has two
          // and they differ; "from: البقالة" alone would read as though the
          // English name had been invented at rename time.
          AuditFieldChange(field: 'nameAr', from: existing.nameAr, to: trimmed),
          AuditFieldChange(field: 'nameEn', from: existing.nameEn, to: trimmed),
        ],
      );

      return byId(id);
    });
  }

  /// Deletes a category after moving everything that pointed at it —
  /// **AC-C3.3**.
  ///
  /// ## The order of operations is the acceptance criterion
  ///
  /// *"Deleting a category that is in use REQUIRES a decision on what happens
  /// to its transactions … No transaction may be left pointing at a category
  /// that no longer exists."*
  ///
  /// So, inside **one** database transaction:
  ///
  ///  1. every transaction (including soft-deleted ones — a restore must not
  ///     resurrect a dangling reference) is repointed per [decision];
  ///  2. every merchant rule naming this category is repointed the same way,
  ///     because a rule pointing at a deleted category would re-create the
  ///     dangling reference on the very next matching message;
  ///  3. one audit entry per repointed transaction is appended (NFR-A2: a
  ///     transaction's category changed, so its history has to say so and by
  ///     whose action);
  ///  4. only then is the row deleted.
  ///
  /// If step 1 or 2 missed anything, step 4 aborts: the
  /// `category_no_delete_while_in_use` trigger raises and the whole
  /// transaction rolls back. There is no ordering of these steps that leaves
  /// an orphan committed.
  ///
  /// Throws [ProtectedCategoryError] for *Uncategorized*, and
  /// [ArgumentError] when a reassign target does not exist or is the category
  /// being deleted.
  /// (Named `deleteCategory` rather than `delete` because
  /// `DatabaseAccessor.delete(table)` is drift's own statement builder — which
  /// this method calls twice below. Shadowing it would not merely be confusing;
  /// it would not compile.)
  Future<CategoryDeleteOutcome> deleteCategory({
    required String id,
    required CategoryDeleteDecision decision,
    String actor = 'user',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();

    return transaction<CategoryDeleteOutcome>(() async {
      final CategoryRow? existing = await byId(id);
      if (existing == null) {
        return const CategoryDeleteOutcome(
          deleted: false,
          transactionsMoved: 0,
          rulesMoved: 0,
        );
      }
      if (existing.isProtected) {
        throw ProtectedCategoryError(id, operation: 'deleted');
      }

      // `null` here is the stored form of Uncategorized — see the note on
      // `transactions.category_id`. Both branches of the decision therefore
      // produce one write path, not two.
      final String? replacementId = switch (decision) {
        ReassignTo(:final String categoryId) => categoryId,
        SetToUncategorized() => null,
      };

      if (replacementId != null) {
        if (replacementId == id) {
          throw ArgumentError.value(
            replacementId,
            'decision',
            'cannot reassign a category to itself',
          );
        }
        if (await byId(replacementId) == null) {
          throw ArgumentError.value(
            replacementId,
            'decision',
            'reassignment target does not exist',
          );
        }
      }

      final List<TransactionRow> affected = await (select(
        transactions,
      )..where((Transactions t) => t.categoryId.equals(id))).get();

      for (final TransactionRow row in affected) {
        await (update(
          transactions,
        )..where((Transactions t) => t.id.equals(row.id))).write(
          TransactionsCompanion(
            categoryId: Value<String?>(replacementId),
            updatedAt: Value<DateTime>(timestamp),
          ),
        );
        await auditLogDao.append(
          entityType: 'transaction',
          entityId: row.id.toString(),
          action: 'categorize',
          actor: actor,
          actorDetail: 'category_deleted:$id',
          changedAt: timestamp,
          fieldChanges: <AuditFieldChange>[
            AuditFieldChange(
              field: 'categoryId',
              from: row.categoryId,
              to: replacementId,
            ),
          ],
        );
      }

      // Every learned rule naming this category, read *before* it is changed
      // so each audit entry can state a genuine before/after (NFR-A2) rather
      // than a claim about a value nobody looked at.
      final List<MerchantRuleRow> affectedRules = await (select(
        merchantRules,
      )..where((MerchantRules t) => t.categoryId.equals(id))).get();

      if (replacementId == null) {
        // A rule cannot point at "nothing" — its whole content is a category —
        // so a rule naming a category the user deleted without a replacement
        // is deleted with it. The alternative (pointing it at Uncategorized)
        // would keep firing a rule that teaches the app nothing, and the user
        // would have to find and remove it by hand.
        await (delete(
          merchantRules,
        )..where((MerchantRules t) => t.categoryId.equals(id))).go();
      } else {
        await (update(
          merchantRules,
        )..where((MerchantRules t) => t.categoryId.equals(id))).write(
          MerchantRulesCompanion(
            categoryId: Value<String>(replacementId),
            updatedAt: Value<DateTime>(timestamp),
          ),
        );
      }

      // A learned rule is something a *person* taught the app, so destroying
      // or repointing one is exactly the kind of change NFR-A2 exists to keep
      // explicable — "why did my utility bills stop being categorised?" has to
      // have an answer. One entry per rule, matching the per-transaction
      // treatment above.
      for (final MerchantRuleRow rule in affectedRules) {
        await auditLogDao.append(
          entityType: 'merchant_rule',
          entityId: rule.id.toString(),
          action: replacementId == null ? 'delete' : 'update',
          actor: actor,
          actorDetail: 'category_deleted:$id',
          changedAt: timestamp,
          fieldChanges: <AuditFieldChange>[
            AuditFieldChange(
              field: 'categoryId',
              from: rule.categoryId,
              to: replacementId,
            ),
          ],
        );
      }
      final int rulesMoved = affectedRules.length;

      await (delete(categories)..where((Categories t) => t.id.equals(id))).go();

      await auditLogDao.append(
        entityType: 'category',
        entityId: id,
        action: 'delete',
        actor: actor,
        actorDetail: replacementId == null
            ? 'uncategorized'
            : 'reassigned_to:$replacementId',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(field: 'nameEn', from: existing.nameEn, to: null),
          AuditFieldChange(
            field: 'transactionsMoved',
            from: null,
            to: affected.length.toString(),
          ),
        ],
      );

      return CategoryDeleteOutcome(
        deleted: true,
        transactionsMoved: affected.length,
        rulesMoved: rulesMoved,
      );
    });
  }

  Future<CategoryRow?> byId(String id) => (select(
    categories,
  )..where((Categories t) => t.id.equals(id))).getSingleOrNull();

  /// Every category, in design §4's order. Archived rows are included —
  /// filtering them is a picker's decision, and a *breakdown* must still be
  /// able to name the category an old transaction points at.
  Future<List<CategoryRow>> all() =>
      (select(categories)..orderBy(<OrderClauseGenerator<Categories>>[
            (Categories t) => OrderingTerm.asc(t.sortOrder),
            (Categories t) => OrderingTerm.asc(t.id),
          ]))
          .get();

  /// The same list as a stream, so a category created in one screen appears in
  /// every picker without a manual refresh (architecture §7.5, AC-C3.1's
  /// "available in every picker").
  Stream<List<CategoryRow>> watchAll() =>
      (select(categories)..orderBy(<OrderClauseGenerator<Categories>>[
            (Categories t) => OrderingTerm.asc(t.sortOrder),
            (Categories t) => OrderingTerm.asc(t.id),
          ]))
          .watch();

  /// How many transactions point at [id] — what S-15's reassignment dialog
  /// shows ("This category has 12 transactions").
  ///
  /// Counts soft-deleted rows too: they can be restored (AC-B8.2), and a
  /// restored transaction pointing at a deleted category is exactly the
  /// orphan AC-C3.3 forbids.
  Future<int> countTransactionsUsing(String id) async {
    final List<TransactionRow> rows = await (select(
      transactions,
    )..where((Transactions t) => t.categoryId.equals(id))).get();
    return rows.length;
  }

  Future<bool> _nameIsTaken(String nameKey, {String? exceptId}) async {
    final List<CategoryRow> matches =
        await (select(categories)..where(
              (Categories t) =>
                  t.nameKeyAr.equals(nameKey) | t.nameKeyEn.equals(nameKey),
            ))
            .get();
    return matches.any((CategoryRow row) => row.id != exceptId);
  }

  /// The highest [Categories.sortOrder] currently used in [groupKey], or null
  /// when the group is empty.
  Future<int?> _maxSortOrder(String groupKey) async {
    final List<CategoryRow> rows =
        await (select(categories)
              ..where((Categories t) => t.groupKey.equals(groupKey))
              ..orderBy(<OrderClauseGenerator<Categories>>[
                (Categories t) => OrderingTerm.desc(t.sortOrder),
              ])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.first.sortOrder;
  }

  /// Design §4's list is numbered 1-13, so a custom category created before
  /// the seed exists still sorts after it.
  static const int _seedSortOrderCeiling = 13;
}

/// What happens to the transactions of a category being deleted — AC-C3.3's
/// *"REQUIRES a decision"*, expressed as a type.
///
/// A sealed class rather than a nullable `String replacementId`, because
/// "reassign to Uncategorized" and "the caller forgot to say" would then be
/// the same value. Here, a caller that has not decided cannot construct the
/// argument at all, and the `switch` in [CategoryDao.deleteCategory] is exhaustive
/// because the type is sealed — a third option would fail to compile until it
/// is handled.
sealed class CategoryDeleteDecision {
  const CategoryDeleteDecision();
}

/// Move this category's transactions to another category.
final class ReassignTo extends CategoryDeleteDecision {
  final String categoryId;
  const ReassignTo(this.categoryId);
}

/// Move this category's transactions to *Uncategorized* (stored as null).
final class SetToUncategorized extends CategoryDeleteDecision {
  const SetToUncategorized();
}

/// What a delete actually did — the numbers a confirmation toast reports.
final class CategoryDeleteOutcome {
  final bool deleted;
  final int transactionsMoved;
  final int rulesMoved;

  const CategoryDeleteOutcome({
    required this.deleted,
    required this.transactionsMoved,
    required this.rulesMoved,
  });
}

/// Thrown when a caller tries to rename or delete *Uncategorized*.
///
/// An error rather than a `false` return: AC-C1.1's fallback existing is an
/// invariant of the data model, so a caller attempting to remove it has a bug,
/// not a user with a bad input. The UI never offers the action (design §S-14
/// greys it out), so this can only fire from code.
final class ProtectedCategoryError extends StateError {
  /// [operation] is the past participle, e.g. `renamed` / `deleted`, so the
  /// message reads as a sentence.
  ProtectedCategoryError(String categoryId, {required String operation})
    : super(
        'category "$categoryId" is protected and cannot be $operation — '
        'see docs/design.md §4',
      );
}
