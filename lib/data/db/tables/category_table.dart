import 'package:drift/drift.dart';

/// **`Category`** — `docs/architecture.md` §4.2, Epic C (US-C1, US-C3).
///
/// The 13-row starter list this table is seeded with comes from
/// `docs/design.md` **§4** and is transcribed, unaltered, into
/// `lib/features/categorization/categories.dart`. Architecture §4.2 is
/// explicit that the list *"is proposed by the designer … and is **not**
/// invented in code"*, so the seed data is a transcription with a test that
/// pins its shape, not an engineering choice.
///
/// ## Four properties here carry acceptance criteria
///
/// 1. **[id] is a stable TEXT id and renaming never touches it** (AC-C3.4).
///    `transactions.category_id` points at this column, so a rename is an
///    update to [nameAr]/[nameEn] alone and every historical transaction keeps
///    pointing at the same row. History is preserved because nothing about the
///    link changed.
///
/// 2. **[nameKeyAr] and [nameKeyEn] are separately `UNIQUE`** — this is how
///    AC-C3.2 ("duplicate names are rejected") is enforced by the *database*
///    rather than by a check the next caller might skip. They hold the
///    case- and orthography-folded form of the two names
///    (`CanonicalText.fold`), so `Groceries`, `groceries` and ` GROCERIES `
///    collide, as do `بقالة` and `بقاله`.
///
///    Both columns exist because a category has two names and a *user's*
///    custom category has one. `CategoryDao.create` writes the user's single
///    name into both language columns — see the note there — so a custom
///    category named "Groceries" collides with the seed's English name, and
///    one named "البقالة" collides with the seed's Arabic name. One constraint
///    could not catch both.
///
/// 3. **[isProtected] marks the row that can never be deleted or renamed.**
///    Exactly one row carries it: *Uncategorized*. Design §4 states it as
///    *"a system category: always present, cannot be deleted or renamed"*,
///    and AC-C1.1 depends on that literally — it is the fallback that makes
///    "every transaction shows a category, never a blank" a guarantee rather
///    than an aspiration. A guarantee whose only support was a UI that hides
///    a delete button would not survive the first new call site.
///
///    Note this is **not** [isSystem]. Architecture §4.2 seeds the whole
///    starter list as `isSystem = true` and calls it *"fully editable"*; the
///    other twelve seeds may be renamed, archived and deleted like any other.
///    Two flags because they answer two different questions: *"did the app
///    ship this?"* and *"may this be destroyed?"*.
///
/// 4. **No transaction may point at a category that does not exist**
///    (AC-C3.3). Enforced by a `BEFORE DELETE` trigger on this table — see
///    `AppDatabase._installCategoryGuardTrigger` for why a trigger rather than
///    the `FK RESTRICT` architecture §4.2 names, and why that is not a
///    weakening.
@DataClassName('CategoryRow')
class Categories extends Table {
  @override
  String get tableName => 'category';

  /// A stable, human-readable slug for the seeded rows (`groceries`,
  /// `uncategorized`, …) and a generated `custom_<n>_<millis>` id for
  /// user-created ones.
  ///
  /// TEXT rather than an autoincrementing integer because
  /// `transactions.category_id` has been TEXT since schema v1 and the seed ids
  /// have to be *knowable* — `CategoryIds.uncategorized` is referenced from
  /// code that must resolve the fallback category without a query.
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
  TextColumn get id => text()();

  /// The semantic key for a seeded category, e.g. `groceries`. Equal to [id]
  /// for seeds and kept as its own column so a future rule pack can name a
  /// category stably even if ids ever change shape.
  TextColumn get key => text().unique()();

  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();

  /// Folded match forms of the two names — the `UNIQUE` pair behind AC-C3.2.
  /// Never displayed (see `CanonicalText`).
  TextColumn get nameKeyAr => text().unique()();
  TextColumn get nameKeyEn => text().unique()();

  /// The Material Symbols identifier from design §4's table, e.g.
  /// `shopping_cart`. A token, not an asset path: `docs/brand.md` §5.1 keeps
  /// Flutter on bundled Material Symbols vector data.
  TextColumn get iconToken => text()();

  /// A `docs/brand.md` chart-palette token, e.g. `chart-teal`. Null means "let
  /// the theme choose", which is the honest state for a category the user
  /// created without picking a colour.
  TextColumn get colorToken => text().nullable()();

  /// `spending` | `money_movement` — design §4's two buckets.
  ///
  /// This is not cosmetic. A money-movement category is excluded from spend
  /// totals and cannot carry a budget (US-B10/B11, US-G1), so the group is a
  /// behavioural fact about the category that reporting reads.
  TextColumn get groupKey => text()();

  /// True for the 13 rows seeded from design §4. Fully editable regardless —
  /// see point 3 in the class comment.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  /// True for *Uncategorized* alone: may not be renamed, deleted or archived.
  BoolColumn get isProtected => boolean().withDefault(const Constant(false))();

  /// Hidden from pickers but retained, so historical transactions keep their
  /// category context. There is no hard delete outside erase-all (ADR-011) —
  /// except a category delete, which is a real delete *because* AC-C3.3 forces
  /// the user to say where its transactions go first.
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// Display order within [groupKey]; design §4's table is numbered 1-13 and
  /// that numbering is the seed order.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
