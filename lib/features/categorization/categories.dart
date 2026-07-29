/// **The category model and the default starter list** — KHA-30, US-C1,
/// US-C3, AC-C1.1, AC-C3.1-4.
///
/// ## The list below is a transcription, not a design
///
/// `docs/build-plan.md` is unusually blunt about this, and it is repeated here
/// because this is the file where someone would be tempted:
///
/// > **Seed that list. Do not invent one, and do not "improve" it in code.**
///
/// Every row in [DefaultCategories.seed] comes from `docs/design.md` **§4**
/// (which resolved open question OQ-18): ten spending categories including the
/// system *Uncategorized*, then three money-movement categories. The Arabic
/// and English names, the Material Symbols icon token, and the ordering are
/// copied from that table verbatim.
/// `test/features/categorization/default_categories_test.dart` pins the shape
/// so a well-meaning edit here fails a test instead of silently changing what
/// the user was shown at onboarding.
///
/// ## "Uncategorized" is load-bearing, not a placeholder
///
/// AC-C1.1: *"every transaction shows either a specific category or an
/// explicit Uncategorized — never a blank"*. That is a guarantee about the
/// data model, so *Uncategorized* is:
///
///  - always present ([CategoryIds.uncategorized] is a compile-time constant,
///    so code can resolve the fallback with no query and no null case),
///  - `isProtected`, so it cannot be renamed or deleted (design §4),
///  - and the target of [CategoryResolver.resolve] for a null category id,
///    for an id that no longer resolves, and for a transaction written before
///    P4a existed.
///
/// ## A note for readers new to Dart
///
/// `final class` means "you may use it but not subclass it". These are value
/// types — a [Category] describes a category; it has no behaviour of its own
/// and nothing derives from it. The `abstract final class` namespaces
/// ([CategoryIds], [DefaultCategories]) hold only constants and static
/// functions.
library;

import '../../data/dao/category_fields.dart';

/// The stored-column vocabulary, re-exposed so feature code has one import.
/// Defined in `data/` because the DAO enforces AC-D3.1 against it and
/// architecture §3 forbids `data → features` — see that file's own note.
export '../../data/dao/category_fields.dart'
    show
        CategoryReviewReason,
        StoredCategorySource,
        categoryReviewReasons,
        uncategorizedCategoryId;

/// Design §4's two buckets. This is a behavioural distinction, not a heading.
enum CategoryGroup {
  /// Competes for budget share and appears in category-breakdown reports.
  spending('spending'),

  /// Income, transfers and withdrawals: captured and shown (US-B10/C15) but
  /// excluded from "spend" totals, and it cannot carry a budget
  /// (US-B11/G1).
  moneyMovement('money_movement');

  const CategoryGroup(this.key);

  /// The value stored in `category.group_key`. Kept explicit rather than
  /// relying on `name`, so renaming the Dart constant can never silently
  /// change what is in the database.
  final String key;

  /// Parses a stored value, defaulting to [spending].
  ///
  /// Defaulting rather than throwing is the safe direction here: an unknown
  /// group would otherwise make a category unreadable, and a category that
  /// cannot be read is a transaction that cannot show its category — AC-C1.1's
  /// exact failure. A category wrongly treated as spending is visible and
  /// fixable; one that crashes the picker is not.
  static CategoryGroup fromKey(String? value) => switch (value) {
    'money_movement' => CategoryGroup.moneyMovement,
    _ => CategoryGroup.spending,
  };
}

/// Ids that code is allowed to know by name.
///
/// Only the fallback is here. Every other category — including the twelve
/// other seeds — is data the user may rename, archive or delete, so nothing in
/// the app may branch on its id.
abstract final class CategoryIds {
  /// Design §4 row 10. The one id that must exist for AC-C1.1 to hold.
  ///
  /// Aliases the data layer's constant rather than repeating the literal: the
  /// DAO normalises this exact string to NULL on every write, so two
  /// definitions that could drift apart would be two definitions of what
  /// "uncategorized" is stored as.
  static const String uncategorized = uncategorizedCategoryId;
}

/// A category, as the rest of the app sees it.
final class Category {
  /// Stable across renames (AC-C3.4) — this is what
  /// `transactions.category_id` holds.
  final String id;

  /// Semantic key; equal to [id] for the seeded rows.
  final String key;

  final String nameAr;
  final String nameEn;

  /// Material Symbols identifier from design §4, e.g. `shopping_cart`.
  final String iconToken;

  /// A `docs/brand.md` §2.5 chart-palette token, or null for "let the theme
  /// choose".
  final String? colorToken;

  final CategoryGroup group;

  /// True for the 13 rows seeded from design §4. **Editable regardless** —
  /// architecture §4.2 calls the seeded list "fully editable"; only
  /// [isProtected] restricts anything.
  final bool isSystem;

  /// True only for *Uncategorized*: cannot be renamed, deleted or archived.
  final bool isProtected;

  final bool isArchived;
  final int sortOrder;

  const Category({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.iconToken,
    required this.group,
    this.colorToken,
    this.isSystem = false,
    this.isProtected = false,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  /// True when this is the fallback category.
  bool get isUncategorized => id == CategoryIds.uncategorized;

  /// A category name is not sensitive (it is the app's own vocabulary, or a
  /// word the user chose for a *group* of spending), but the habit of terse
  /// `toString`s is kept — NFR-S4, ADR-015.
  @override
  String toString() => 'Category($id)';
}

/// The starter list from `docs/design.md` §4 — transcribed, not designed.
abstract final class DefaultCategories {
  /// The thirteen rows, in design §4's own order.
  ///
  /// Ten spending categories (numbered 1-10 in the design, *Uncategorized*
  /// last) then three money-movement categories (11-13). [Category.sortOrder]
  /// carries that numbering so a picker can render the design's order without
  /// depending on this list's iteration order.
  ///
  /// **Colour tokens** come from `docs/brand.md` §2.5's eight-slot categorical
  /// palette, assigned in order to the eight *spending* categories that appear
  /// in a chart. `Uncategorized` is pinned to `chart-uncategorized`, which
  /// brand.md fixes to grey *"so 'Uncategorized' always reads as unassigned,
  /// never as a themed category slice"*. Money-movement categories carry no
  /// chart colour because they never appear in a spend breakdown.
  static const List<Category> seed = <Category>[
    Category(
      id: 'groceries',
      key: 'groceries',
      nameAr: 'البقالة',
      nameEn: 'Groceries',
      iconToken: 'shopping_cart',
      colorToken: 'chart-navy',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 1,
    ),
    Category(
      id: 'dining',
      key: 'dining',
      nameAr: 'مطاعم ومقاهي',
      nameEn: 'Dining & Cafés',
      iconToken: 'restaurant',
      colorToken: 'chart-gold',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 2,
    ),
    Category(
      id: 'transport_fuel',
      key: 'transport_fuel',
      nameAr: 'تنقل ووقود',
      nameEn: 'Transport & Fuel',
      iconToken: 'directions_car',
      colorToken: 'chart-teal',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 3,
    ),
    Category(
      id: 'utilities_bills',
      key: 'utilities_bills',
      nameAr: 'فواتير وخدمات',
      nameEn: 'Utilities & Bills',
      iconToken: 'bolt',
      colorToken: 'chart-plum',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 4,
    ),
    Category(
      id: 'shopping_retail',
      key: 'shopping_retail',
      nameAr: 'تسوق ومتاجر',
      nameEn: 'Shopping & Retail',
      iconToken: 'shopping_bag',
      colorToken: 'chart-terracotta',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 5,
    ),
    Category(
      id: 'entertainment_subscriptions',
      key: 'entertainment_subscriptions',
      nameAr: 'ترفيه واشتراكات',
      nameEn: 'Entertainment & Subscriptions',
      iconToken: 'movie',
      colorToken: 'chart-slate',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 6,
    ),
    Category(
      id: 'health_pharmacy',
      key: 'health_pharmacy',
      nameAr: 'صحة وصيدليات',
      nameEn: 'Health & Pharmacy',
      iconToken: 'medical_services',
      colorToken: 'chart-olive',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 7,
    ),
    // Design §4 keeps these two as their own categories on purpose: PRD §3.4
    // shows loan-installment and standalone-fee messages are structurally and
    // semantically different from ordinary purchases, and *"lumping them in
    // would silently corrupt category-breakdown totals (AC-C1.3, AC-E2.1)"*.
    Category(
      id: 'loan_installments',
      key: 'loan_installments',
      nameAr: 'قروض وأقساط',
      nameEn: 'Loan & Installments',
      iconToken: 'account_balance',
      colorToken: 'chart-rose',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 8,
    ),
    Category(
      id: 'fees_charges',
      key: 'fees_charges',
      nameAr: 'رسوم وعمولات',
      nameEn: 'Fees & Charges',
      iconToken: 'receipt_long',
      // The ninth spending category and the palette has eight slots, so it
      // reuses the first. brand.md §2.5 allows reuse in order; what it forbids
      // is reusing `chart-uncategorized`, which stays reserved below.
      colorToken: 'chart-navy',
      group: CategoryGroup.spending,
      isSystem: true,
      sortOrder: 9,
    ),
    Category(
      id: CategoryIds.uncategorized,
      key: CategoryIds.uncategorized,
      nameAr: 'غير مصنف',
      nameEn: 'Uncategorized',
      iconToken: 'help_outline',
      colorToken: 'chart-uncategorized',
      group: CategoryGroup.spending,
      isSystem: true,
      // Design §4: "always present; cannot be deleted/renamed".
      isProtected: true,
      sortOrder: 10,
    ),
    Category(
      id: 'salary_income',
      key: 'salary_income',
      nameAr: 'راتب ودخل',
      nameEn: 'Salary & Income',
      iconToken: 'payments',
      group: CategoryGroup.moneyMovement,
      isSystem: true,
      sortOrder: 11,
    ),
    Category(
      id: 'cash_withdrawal',
      key: 'cash_withdrawal',
      nameAr: 'سحب نقدي',
      nameEn: 'Cash & ATM Withdrawal',
      iconToken: 'local_atm',
      group: CategoryGroup.moneyMovement,
      isSystem: true,
      sortOrder: 12,
    ),
    Category(
      id: 'internal_transfer',
      key: 'internal_transfer',
      nameAr: 'تحويل داخلي',
      nameEn: 'Internal Transfer',
      iconToken: 'sync_alt',
      group: CategoryGroup.moneyMovement,
      isSystem: true,
      sortOrder: 13,
    ),
  ];

  /// The fallback, available without a database read.
  ///
  /// Used by [CategoryResolver] so AC-C1.1 holds even in the window before the
  /// seed has been written, and in any code path that has a transaction but no
  /// loaded category list.
  static const Category uncategorized = Category(
    id: CategoryIds.uncategorized,
    key: CategoryIds.uncategorized,
    nameAr: 'غير مصنف',
    nameEn: 'Uncategorized',
    iconToken: 'help_outline',
    colorToken: 'chart-uncategorized',
    group: CategoryGroup.spending,
    isSystem: true,
    isProtected: true,
    sortOrder: 10,
  );
}

/// Turns a stored `category_id` into a [Category] that always exists.
///
/// **This is where AC-C1.1 is actually delivered.** Three inputs map to
/// *Uncategorized*, and they are three different facts that the user does not
/// need to be able to tell apart:
///
///  1. `null` — the app's single stored representation of "uncategorized"
///     (see `transaction_table.dart`'s note on the column);
///  2. an id that no longer resolves — impossible through the app's own delete
///     path, which repoints referencing rows first, but reachable if a
///     database were edited outside the app;
///  3. the literal [CategoryIds.uncategorized] — accepted so that a caller
///     that *does* hold the explicit id is not a special case.
///
/// None of the three ever yields null, and that is the point: there is no
/// blank state to render.
final class CategoryResolver {
  final Map<String, Category> _byId;

  CategoryResolver(Iterable<Category> categories)
    : _byId = <String, Category>{
        for (final Category category in categories) category.id: category,
      };

  /// A resolver over the compiled-in seed list — for callers with no database
  /// (tests, and any read that happens before the seed is written).
  factory CategoryResolver.defaults() =>
      CategoryResolver(DefaultCategories.seed);

  /// Never returns null. See the class comment.
  Category resolve(String? categoryId) {
    if (categoryId == null) {
      return _fallback;
    }
    return _byId[categoryId] ?? _fallback;
  }

  /// True when [categoryId] names a category this resolver knows about.
  /// Distinct from [resolve] because a *writer* does need to tell the three
  /// cases apart even though a *renderer* does not.
  bool isKnown(String? categoryId) =>
      categoryId != null && _byId.containsKey(categoryId);

  /// Every category this resolver knows, in the design's order.
  List<Category> get all =>
      _byId.values.toList()
        ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));

  Category get _fallback =>
      _byId[CategoryIds.uncategorized] ?? DefaultCategories.uncategorized;
}
