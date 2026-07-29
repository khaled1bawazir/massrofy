/// **The starter list is a transcription of `docs/design.md` §4** — KHA-30,
/// US-C3, OQ-18.
///
/// `docs/build-plan.md`: *"Seed that list. Do not invent one, and do not
/// 'improve' it in code."* This file is the mechanism that makes that
/// instruction enforceable rather than merely stated: it pins the count, the
/// grouping, the order, both names and the icon token of every row against the
/// design table. An edit here is only correct if `docs/design.md` §4 changed
/// first.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/categorization/categories.dart';

void main() {
  group('docs/design.md §4 — the default starting category list', () {
    test('has exactly 13 rows: 10 spending (incl. Uncategorized) + 3 money '
        'movement', () {
      expect(DefaultCategories.seed, hasLength(13));
      expect(
        DefaultCategories.seed
            .where((Category c) => c.group == CategoryGroup.spending)
            .length,
        10,
      );
      expect(
        DefaultCategories.seed
            .where((Category c) => c.group == CategoryGroup.moneyMovement)
            .length,
        3,
      );
    });

    test('matches design §4 row for row — English name, Arabic name, icon '
        'token and order', () {
      // Transcribed from the two tables in design.md §4, in their order. If
      // this list and the document ever disagree, the document is right.
      const List<List<String>> expected = <List<String>>[
        <String>['Groceries', 'البقالة', 'shopping_cart'],
        <String>['Dining & Cafés', 'مطاعم ومقاهي', 'restaurant'],
        <String>['Transport & Fuel', 'تنقل ووقود', 'directions_car'],
        <String>['Utilities & Bills', 'فواتير وخدمات', 'bolt'],
        <String>['Shopping & Retail', 'تسوق ومتاجر', 'shopping_bag'],
        <String>['Entertainment & Subscriptions', 'ترفيه واشتراكات', 'movie'],
        <String>['Health & Pharmacy', 'صحة وصيدليات', 'medical_services'],
        <String>['Loan & Installments', 'قروض وأقساط', 'account_balance'],
        <String>['Fees & Charges', 'رسوم وعمولات', 'receipt_long'],
        <String>['Uncategorized', 'غير مصنف', 'help_outline'],
        <String>['Salary & Income', 'راتب ودخل', 'payments'],
        <String>['Cash & ATM Withdrawal', 'سحب نقدي', 'local_atm'],
        <String>['Internal Transfer', 'تحويل داخلي', 'sync_alt'],
      ];

      expect(DefaultCategories.seed, hasLength(expected.length));
      for (int i = 0; i < expected.length; i++) {
        final Category actual = DefaultCategories.seed[i];
        expect(actual.nameEn, expected[i][0], reason: 'row ${i + 1} nameEn');
        expect(actual.nameAr, expected[i][1], reason: 'row ${i + 1} nameAr');
        expect(
          actual.iconToken,
          expected[i][2],
          reason: 'row ${i + 1} iconToken',
        );
        expect(
          actual.sortOrder,
          i + 1,
          reason:
              'design §4 numbers its rows 1-13 and that numbering is the '
              'seed order',
        );
      }
    });

    test('keeps Loan & Installments and Fees & Charges as their own '
        'categories (design §4 rationale, PRD §3.4)', () {
      // Design §4 is explicit that folding these into general spending
      // "would silently corrupt category-breakdown totals (AC-C1.3,
      // AC-E2.1)". Pinned so a future tidy-up has to argue with the document.
      expect(
        DefaultCategories.seed.map((Category c) => c.id),
        containsAll(<String>['loan_installments', 'fees_charges']),
      );
    });

    test('Uncategorized is present, protected, and the only protected row '
        '(AC-C1.1)', () {
      final List<Category> protectedRows = DefaultCategories.seed
          .where((Category c) => c.isProtected)
          .toList();
      expect(protectedRows, hasLength(1));
      expect(protectedRows.single.id, CategoryIds.uncategorized);
    });

    test('every seeded row is marked isSystem, and system does not mean '
        'uneditable', () {
      // Architecture §4.2 seeds the list as `isSystem = true` and calls it
      // "fully editable". The two flags answer different questions, and this
      // asserts they have not been conflated.
      expect(DefaultCategories.seed.every((Category c) => c.isSystem), isTrue);
      expect(
        DefaultCategories.seed.where((Category c) => !c.isProtected).length,
        12,
      );
    });

    test('ids and keys are unique', () {
      expect(
        DefaultCategories.seed.map((Category c) => c.id).toSet(),
        hasLength(13),
      );
      expect(
        DefaultCategories.seed.map((Category c) => c.key).toSet(),
        hasLength(13),
      );
    });

    test('names are unique in both languages — the seed itself must satisfy '
        'AC-C3.2', () {
      expect(
        DefaultCategories.seed.map((Category c) => c.nameEn).toSet(),
        hasLength(13),
      );
      expect(
        DefaultCategories.seed.map((Category c) => c.nameAr).toSet(),
        hasLength(13),
      );
    });

    test('only Uncategorized carries the reserved grey chart token '
        '(brand.md §2.5)', () {
      // brand.md fixes `chart-uncategorized` to grey "so 'Uncategorized'
      // always reads as unassigned, never as a themed category slice". Reusing
      // it for a real category would break that reading.
      final List<Category> grey = DefaultCategories.seed
          .where((Category c) => c.colorToken == 'chart-uncategorized')
          .toList();
      expect(grey, hasLength(1));
      expect(grey.single.id, CategoryIds.uncategorized);
    });
  });

  group('CategoryResolver — AC-C1.1, "never a blank"', () {
    final CategoryResolver resolver = CategoryResolver.defaults();

    test('a null category id resolves to Uncategorized', () {
      expect(resolver.resolve(null).id, CategoryIds.uncategorized);
    });

    test('an id that no longer exists resolves to Uncategorized rather than '
        'to nothing', () {
      // Unreachable through the app's own delete path (which repoints first),
      // but reachable by editing the database outside the app. The transaction
      // must stay visible and stay in its total; only the label degrades.
      expect(resolver.resolve('deleted_by_hand').id, CategoryIds.uncategorized);
    });

    test('the explicit Uncategorized id resolves to itself', () {
      expect(
        resolver.resolve(CategoryIds.uncategorized).id,
        CategoryIds.uncategorized,
      );
    });

    test('a real id resolves to that category', () {
      expect(resolver.resolve('groceries').nameEn, 'Groceries');
    });

    test('isKnown tells a writer apart from a renderer', () {
      // `resolve` never fails, which is right for rendering and wrong for
      // validating a write — so both exist.
      expect(resolver.isKnown('groceries'), isTrue);
      expect(resolver.isKnown('deleted_by_hand'), isFalse);
      expect(resolver.isKnown(null), isFalse);
    });

    test('a resolver built from a list with no Uncategorized still resolves '
        'to one', () {
      // The fallback of last resort: `DefaultCategories.uncategorized` is a
      // compile-time constant, so AC-C1.1 holds even before the seed is
      // written to the database.
      final CategoryResolver sparse = CategoryResolver(<Category>[
        DefaultCategories.seed.first,
      ]);
      expect(sparse.resolve(null).id, CategoryIds.uncategorized);
    });
  });
}
