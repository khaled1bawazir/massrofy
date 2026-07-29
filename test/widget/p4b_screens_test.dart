/// **Widget tests for P4b's categorization surfaces** — KHA-32, KHA-33,
/// KHA-34, KHA-97.
///
/// | Surface | Acceptance criteria |
/// |---|---|
/// | S-12/S-13 Category picker + scope strip | AC-C2.2, AC-C2.3, AC-D5.1, AC-D5.3, AC-C3.2 |
/// | S-14 Category management | AC-C3.1, AC-C3.4, and the *Uncategorized* protection |
/// | S-15 Reassignment dialog | **AC-C3.3** — the delete blocks until a decision exists |
/// | S-16/S-17 Learned rules | AC-D4.1, AC-D4.2, AC-D4.3, **AC-D4.4** |
/// | S-18 low-confidence tab | AC-C4.1, and KHA-32's confidence display |
/// | S-11 header chip + provenance | KHA-31's *"why is this categorized this way"* |
///
/// Following the existing suites' rules: **both locales**, and every dense
/// screen at a **2.0 text scale** (NFR-U3, NFR-U8). Every screen's
/// design.md §3.4 states — loading, empty, error, locked, populated — are
/// asserted, because a screen that renders four of five is a screen with one
/// unhandled state a user will eventually reach.
///
/// NFR-M3: every merchant string here is synthetic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/dao/category_dao.dart'
    show CategoryDeleteDecision, ReassignTo, SetToUncategorized;
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/category_correction.dart';
import 'package:massrofy/features/categorization/learned_rules.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/presentation/screens/category_management_screen.dart';
import 'package:massrofy/presentation/screens/learned_rules_screen.dart';
import 'package:massrofy/presentation/screens/needs_review_screen.dart';
import 'package:massrofy/presentation/screens/transaction_detail_screen.dart';
import 'package:massrofy/presentation/widgets/category_picker_sheet.dart';
import 'package:massrofy/presentation/widgets/category_widgets.dart';

import 'p3_screens_test.dart' show useTallSurface, wrap;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final CategoryResolver seedResolver = CategoryResolver.defaults();

Category seedCategory(String id) =>
    DefaultCategories.seed.firstWhere((Category c) => c.id == id);

List<CategoryListItem> categoryItems({
  int groceriesCount = 18,
  int uncategorizedCount = 4,
}) => <CategoryListItem>[
  CategoryListItem(
    category: seedCategory('groceries'),
    transactionCount: groceriesCount,
  ),
  CategoryListItem(category: seedCategory('dining'), transactionCount: 34),
  CategoryListItem(
    category: seedCategory(CategoryIds.uncategorized),
    transactionCount: uncategorizedCount,
  ),
  CategoryListItem(
    category: seedCategory('salary_income'),
    transactionCount: 1,
  ),
];

LearnedRule rule({
  int id = 1,
  String merchant = 'QANDA Foods',
  String categoryId = 'groceries',
  String source = 'user',
  int appliedCount = 12,
}) => LearnedRule(
  ruleId: id,
  merchantId: id * 10,
  merchantName: merchant,
  merchantKey: merchant.toUpperCase(),
  categoryId: categoryId,
  source: source,
  appliedCount: appliedCount,
  updatedAt: DateTime.utc(2026, 7, 20),
);

FlaggedTransactionItem categoryFlagged({
  int id = 501,
  String reason = CategoryReviewReason.unknownMerchant,
}) => FlaggedTransactionItem(
  transactionId: id,
  amount: '89.00',
  currencyCode: 'SAR',
  merchantRawText: 'QANDA MART 0042',
  occurredAt: DateTime.utc(2026, 7, 15, 10, 5),
  reviewReason: reason,
);

LedgerTransaction purchase({int id = 1, bool deleted = false}) =>
    LedgerTransaction(
      id: id,
      amount: Money.parse('152.75', currency: 'SAR'),
      direction: 'debit',
      transactionType: TransactionType.posPurchase,
      affectsSpend: true,
      occurredAt: DateTime.utc(2026, 7, 15, 10),
      merchantRawText: 'QANDA MART',
      isDeleted: deleted,
    );

void main() {
  // =========================================================================
  group('S-12/S-13 — the category picker and the scope strip (KHA-33)', () {
    testWidgets('AC-C2.2 — tapping a category applies it in ONE tap from the '
        'open sheet, with no screen navigation', (WidgetTester tester) async {
      useTallSurface(tester);
      CategoryPickResult? result;

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                merchantName: 'QANDA Foods',
                autoConfirmDelay: Duration.zero,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      // Tap 1 — the chip (here, the button standing in for it).
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryPickerSheet), findsOneWidget);

      // Tap 2 — the category cell. With a zero auto-confirm the scope strip
      // resolves immediately, which is exactly the passive two-tap flow
      // design.md §6.4 describes.
      await tester.tap(find.byKey(const Key('categoryPicker.spending.dining')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.categoryId, 'dining');
      expect(
        result!.scope,
        CorrectionScope.thisAndFuture,
        reason: 'AC-D5.1 — the default trains the learning loop',
      );
      // Zero additional screens: the sheet is gone and nothing was pushed.
      expect(find.byType(CategoryPickerSheet), findsNothing);
    });

    testWidgets('AC-D5.1 — the optional third tap overrides the default to '
        '"just this transaction", and cancels the countdown', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      CategoryPickResult? result;

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                merchantName: 'QANDA Foods',
                // A long delay so the test is asserting the OVERRIDE, not
                // racing the timer.
                autoConfirmDelay: const Duration(seconds: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.spending.dining')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('categoryPicker.scopeStrip')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('categoryPicker.scopeOnly')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.scopeConfirm')));
      await tester.pumpAndSettle();

      expect(result!.scope, CorrectionScope.thisTransactionOnly);
    });

    testWidgets('AC-D5.3 — the scope strip states how many existing '
        'transactions "this and future" would fill in', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                merchantName: 'QANDA Foods',
                autoConfirmDelay: const Duration(seconds: 30),
                affectedCountFor: (String _) async => 11,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.spending.dining')));
      await tester.pumpAndSettle();

      expect(find.textContaining('11'), findsWidgets);
    });

    testWidgets('AC-C4.3 — confirming a category that already matches the '
        'merchant\'s rule skips the scope question entirely', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      CategoryPickResult? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                merchantName: 'QANDA Foods',
                existingRuleCategoryId: 'dining',
                autoConfirmDelay: const Duration(seconds: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.spending.dining')));
      await tester.pumpAndSettle();

      // No strip, no 30-second wait: the sheet closed on tap 2.
      expect(result, isNotNull);
      expect(find.byKey(const Key('categoryPicker.scopeStrip')), findsNothing);
    });

    testWidgets('the explicit Uncategorized choice never asks about scope, '
        'because it teaches nothing', (WidgetTester tester) async {
      useTallSurface(tester);
      CategoryPickResult? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                autoConfirmDelay: const Duration(seconds: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('categoryPicker.spending.uncategorized')),
      );
      await tester.pumpAndSettle();

      expect(result!.categoryId, CategoryIds.uncategorized);
      expect(result!.scope, CorrectionScope.thisTransactionOnly);
    });

    testWidgets('AC-C3.2 — the inline "+ New category" form names the '
        'duplicate-name problem and creates nothing', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int attempts = 0;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showCategoryPickerSheet(
                context: context,
                categories: DefaultCategories.seed,
                autoConfirmDelay: Duration.zero,
                onCreateCategory:
                    ({
                      required String name,
                      required String iconToken,
                      required CategoryGroup group,
                    }) async {
                      attempts++;
                      // The contract `CategoryDao.createCustom` has: null for
                      // a duplicate, not an exception.
                      return null;
                    },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.newCategory')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('categoryPicker.newCategoryName')),
        'Groceries',
      );
      await tester.tap(
        find.byKey(const Key('categoryPicker.newCategoryCreate')),
      );
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(
        find.text(
          'A category with this name already exists — choose another name',
        ),
        findsOneWidget,
        reason: 'AC-C3.2 names the problem, not a generic "invalid input"',
      );
      // Still on the form, nothing applied.
      expect(
        find.byKey(const Key('categoryPicker.newCategoryForm')),
        findsOneWidget,
      );
    });

    testWidgets('a successful inline creation applies the new category '
        'immediately ("create and use")', (WidgetTester tester) async {
      useTallSurface(tester);
      const Category invented = Category(
        id: 'work_meals',
        key: 'work_meals',
        nameAr: 'وجبات العمل',
        nameEn: 'Work meals',
        iconToken: 'restaurant',
        group: CategoryGroup.spending,
      );
      CategoryPickResult? result;

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await showCategoryPickerSheet(
                context: context,
                categories: <Category>[...DefaultCategories.seed, invented],
                autoConfirmDelay: Duration.zero,
                onCreateCategory:
                    ({
                      required String name,
                      required String iconToken,
                      required CategoryGroup group,
                    }) async => invented,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categoryPicker.newCategory')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('categoryPicker.newCategoryName')),
        'Work meals',
      );
      await tester.tap(
        find.byKey(const Key('categoryPicker.newCategoryCreate')),
      );
      await tester.pumpAndSettle();

      expect(result!.categoryId, 'work_meals');
    });

    testWidgets('design.md §3.4 Filtered-empty — a search matching nothing '
        'reads differently from an empty list', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          // A bare `Scaffold` stands in for the modal route: the sheet's text
          // field and ink responses need a `Material` ancestor, which
          // `showModalBottomSheet` supplies in production.
          const Scaffold(
            body: CategoryPickerSheet(
              categories: DefaultCategories.seed,
              autoConfirmDelay: Duration.zero,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('categoryPicker.search')),
        'zzzz-no-such-category',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('categoryPicker.noResults')), findsOneWidget);
    });

    testWidgets('search matches the Arabic name even in the English locale, '
        'because a bilingual user types whichever comes to mind', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          // A bare `Scaffold` stands in for the modal route: the sheet's text
          // field and ink responses need a `Material` ancestor, which
          // `showModalBottomSheet` supplies in production.
          const Scaffold(
            body: CategoryPickerSheet(
              categories: DefaultCategories.seed,
              autoConfirmDelay: Duration.zero,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('categoryPicker.search')),
        'البقالة',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('categoryPicker.noResults')), findsNothing);
      expect(
        find.byKey(const Key('categoryPicker.spending.groceries')),
        findsOneWidget,
      );
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale without '
        'overflowing (NFR-U3, NFR-U8)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: CategoryPickerSheet(
              categories: DefaultCategories.seed,
              merchantName: 'QANDA Foods',
              autoConfirmDelay: Duration.zero,
            ),
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('البقالة'), findsWidgets);
    });
  });

  // =========================================================================
  group('S-14/S-15 — category management (KHA-97)', () {
    testWidgets(
      'AC-C3.1 — every category is listed, in both design §4 groups',
      (WidgetTester tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(
          wrap(CategoryManagementScreen(items: categoryItems())),
        );

        expect(find.text('Groceries'), findsOneWidget);
        expect(find.text('Salary & Income'), findsOneWidget);
        expect(find.text('Spending'), findsOneWidget);
        expect(find.text('Money movement'), findsOneWidget);
        expect(find.text('18 transactions'), findsOneWidget);
      },
    );

    testWidgets('Uncategorized offers NO rename and NO delete affordance — '
        'absent, not disabled', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            onRename: (Category c, String n) async => true,
            onDelete: (Category c, CategoryDeleteDecision d) async {},
          ),
        ),
      );

      expect(
        find.byKey(const Key('categories.delete.groceries')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('categories.delete.uncategorized')),
        findsNothing,
        reason:
            'KHA-97: the screen must not offer the action in the first '
            'place — a greyed-out delete icon is still a delete icon',
      );
      expect(
        find.byKey(const Key('categories.rename.uncategorized')),
        findsNothing,
      );
      expect(find.textContaining('System category'), findsOneWidget);
    });

    testWidgets('**AC-C3.3** — deleting a category IN USE cannot complete '
        'until a target is chosen', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<CategoryDeleteDecision> decisions = <CategoryDeleteDecision>[];
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            onDelete: (Category c, CategoryDeleteDecision d) async =>
                decisions.add(d),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('categories.delete.groceries')));
      await tester.pumpAndSettle();

      // The dialog states the count. Scoped to the dialog, because the list row
      // behind it legitimately shows the same number.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('18 transactions'),
        ),
        findsOneWidget,
      );
      // …and Delete is DISABLED until a decision exists. This is the
      // acceptance criterion expressed as a property of the widget tree rather
      // than as a convention someone has to follow.
      final FilledButton confirm = tester.widget<FilledButton>(
        find.byKey(const Key('categories.deleteConfirm')),
      );
      expect(confirm.onPressed, isNull);
      await tester.tap(find.byKey(const Key('categories.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(decisions, isEmpty);
    });

    testWidgets('AC-C3.3 — choosing "reassign to another category" produces a '
        'ReassignTo decision', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<CategoryDeleteDecision> decisions = <CategoryDeleteDecision>[];
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            onDelete: (Category c, CategoryDeleteDecision d) async =>
                decisions.add(d),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('categories.delete.groceries')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('categories.reassignPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining & Cafés').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories.deleteConfirm')));
      await tester.pumpAndSettle();

      expect(decisions, hasLength(1));
      expect(decisions.single, isA<ReassignTo>());
      expect((decisions.single as ReassignTo).categoryId, 'dining');
    });

    testWidgets('choosing Uncategorized produces SetToUncategorized, not '
        'ReassignTo("uncategorized") — one stored representation', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<CategoryDeleteDecision> decisions = <CategoryDeleteDecision>[];
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            onDelete: (Category c, CategoryDeleteDecision d) async =>
                decisions.add(d),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('categories.delete.groceries')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories.reassignPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uncategorized').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories.deleteConfirm')));
      await tester.pumpAndSettle();

      expect(
        decisions.single,
        isA<SetToUncategorized>(),
        reason:
            'the DAO stores this state as NULL; two encodings of one fact is '
            'the ambiguity `normalizeStoredCategoryId` exists to prevent',
      );
    });

    testWidgets('an EMPTY category needs no decision and deletes in one '
        'confirmation', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<CategoryDeleteDecision> decisions = <CategoryDeleteDecision>[];
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(groceriesCount: 0),
            onDelete: (Category c, CategoryDeleteDecision d) async =>
                decisions.add(d),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('categories.delete.groceries')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('categories.reassignPicker')), findsNothing);
      await tester.tap(find.byKey(const Key('categories.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(decisions, hasLength(1));
    });

    testWidgets('dismissing the reassignment dialog deletes nothing', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<CategoryDeleteDecision> decisions = <CategoryDeleteDecision>[];
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            onDelete: (Category c, CategoryDeleteDecision d) async =>
                decisions.add(d),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('categories.delete.groceries')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('categories.deleteCancel')));
      await tester.pumpAndSettle();
      expect(decisions, isEmpty);
    });

    testWidgets('AC-C3.4 — a rename that collides shows AC-C3.2\'s message', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: categoryItems(),
            // False is `CategoryDao.rename` returning null: the folded name is
            // already taken.
            onRename: (Category c, String n) async => false,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('categories.rename.groceries')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('categories.renameField')),
        'Dining & Cafés',
      );
      await tester.tap(find.byKey(const Key('categories.renameSave')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('already exists'),
        findsOneWidget,
        reason:
            'the same problem deserves the same sentence as the create form',
      );
    });

    testWidgets(
      'design.md §3.4 — loading, empty, error and locked all render',
      (WidgetTester tester) async {
        useTallSurface(tester);

        await tester.pumpWidget(
          wrap(
            const CategoryManagementScreen(
              items: <CategoryListItem>[],
              isLoading: true,
            ),
          ),
        );
        expect(find.byKey(const Key('categories.loading')), findsOneWidget);

        await tester.pumpWidget(
          wrap(const CategoryManagementScreen(items: <CategoryListItem>[])),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('categories.empty')), findsOneWidget);

        await tester.pumpWidget(
          wrap(
            const CategoryManagementScreen(
              items: <CategoryListItem>[],
              errorMessage: 'Your categories could not be loaded.',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Your categories could not be loaded.'),
          findsOneWidget,
        );

        await tester.pumpWidget(
          wrap(
            const CategoryManagementScreen(
              items: <CategoryListItem>[],
              isLocked: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('categoryLockedState')), findsOneWidget);
      },
    );

    testWidgets('Arabic RTL at 2.0 text scale (NFR-U3, NFR-U8)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(items: categoryItems()),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('البقالة'), findsOneWidget);
    });
  });

  // =========================================================================
  group('S-16/S-17 — learned rules (KHA-34)', () {
    testWidgets('AC-D4.1 — every rule is listed with its merchant and its '
        'category', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[
              rule(),
              rule(
                id: 2,
                merchant: 'QANDB Books',
                categoryId: 'shopping_retail',
              ),
            ],
            resolver: seedResolver,
          ),
        ),
      );

      expect(find.textContaining('QANDA Foods'), findsOneWidget);
      expect(find.textContaining('Groceries'), findsOneWidget);
      expect(find.textContaining('QANDB Books'), findsOneWidget);
      expect(find.text('Applied to 12 transactions'), findsWidgets);
    });

    testWidgets('a SEED rule is visually distinguished from one the user '
        'taught (AC-D3.1\'s precedence made visible)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule(source: 'seed')],
            resolver: seedResolver,
          ),
        ),
      );
      expect(find.textContaining('Built in'), findsOneWidget);
    });

    testWidgets('**AC-D4.4** — the re-apply prompt names the count, and the '
        '"Yes" button is disabled until that count is known', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule()],
            resolver: seedResolver,
            categories: DefaultCategories.seed,
            onEditRule: (RuleEditRequest r) async => 0,
            onCountAffected: (LearnedRule r, String c) async => 7,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rules.edit.1')));
      await tester.pumpAndSettle();

      // Nothing has changed yet, so there is nothing to ask about and both
      // answer buttons are inert.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('rules.editReapply')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('rules.editPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining & Cafés').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('7 existing transactions'), findsOneWidget);
      expect(find.text('Yes, 7 transactions'), findsOneWidget);
    });

    testWidgets('AC-D4.4 — "going forward only" and "yes, re-apply" produce '
        'different requests', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<RuleEditRequest> requests = <RuleEditRequest>[];

      Widget screen() => wrap(
        LearnedRulesScreen(
          rules: <LearnedRule>[rule()],
          resolver: seedResolver,
          categories: DefaultCategories.seed,
          onEditRule: (RuleEditRequest r) async {
            requests.add(r);
            return r.reapplyToHistory ? 7 : 0;
          },
          onCountAffected: (LearnedRule r, String c) async => 7,
        ),
      );

      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const Key('rules.edit.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining & Cafés').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editForwardOnly')));
      await tester.pumpAndSettle();

      expect(requests.single.reapplyToHistory, isFalse);
      expect(requests.single.categoryId, 'dining');
      expect(
        find.textContaining('left as they are'),
        findsOneWidget,
        reason:
            'states the half the user chose NOT to do, so "nothing visibly '
            'happened" is explained rather than mysterious',
      );
    });

    testWidgets('AC-D4.4 — "yes, re-apply" reports how many transactions were '
        'rewritten', (WidgetTester tester) async {
      // A separate test rather than a second half of the one above: pumping a
      // fresh widget tree mid-test replaces the `ScaffoldMessenger`, so a
      // snackbar assertion after a re-pump measures the wrong tree.
      useTallSurface(tester);
      final List<RuleEditRequest> requests = <RuleEditRequest>[];
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule()],
            resolver: seedResolver,
            categories: DefaultCategories.seed,
            onEditRule: (RuleEditRequest r) async {
              requests.add(r);
              return 7;
            },
            onCountAffected: (LearnedRule r, String c) async => 7,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rules.edit.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining & Cafés').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editReapply')));
      await tester.pumpAndSettle();

      expect(requests.single.reapplyToHistory, isTrue);
      expect(
        find.textContaining('re-applied to 7 transactions'),
        findsOneWidget,
      );
    });

    testWidgets('KHA-104 — a refused edit says so, rather than reporting a '
        'success that did not happen', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule()],
            resolver: seedResolver,
            categories: DefaultCategories.seed,
            // Null is the refusal sentinel surfacing from
            // `MerchantDao.upsertRule` through `editRule`.
            onEditRule: (RuleEditRequest r) async => null,
            onCountAffected: (LearnedRule r, String c) async => 3,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rules.edit.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining & Cafés').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editReapply')));
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer available'), findsOneWidget);
    });

    testWidgets('S-17 never offers Uncategorized as a rule target', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule()],
            resolver: seedResolver,
            categories: DefaultCategories.seed,
            onEditRule: (RuleEditRequest r) async => 0,
            onCountAffected: (LearnedRule r, String c) async => 0,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rules.edit.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.editPicker')));
      await tester.pumpAndSettle();

      expect(
        find.text('Uncategorized'),
        findsNothing,
        reason:
            '"always file this merchant under I-do-not-know" is not a lesson '
            '— the service refuses it at the write boundary, and the screen '
            'must not let the user reach that refusal',
      );
    });

    testWidgets('AC-D4.3 — the delete confirmation states BOTH halves: future '
        'transactions stop following it, history keeps its categories', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<LearnedRule> deleted = <LearnedRule>[];
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[rule()],
            resolver: seedResolver,
            onDeleteRule: (LearnedRule r) async => deleted.add(r),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rules.delete.1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('arrive uncategorized'), findsOneWidget);
      expect(find.textContaining('keep their categories'), findsOneWidget);

      await tester.tap(find.byKey(const Key('rules.deleteCancel.1')));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty, reason: 'cancel deletes nothing');

      await tester.tap(find.byKey(const Key('rules.delete.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules.deleteConfirm.1')));
      await tester.pumpAndSettle();
      expect(deleted, hasLength(1));
    });

    testWidgets(
      'design.md §3.4 — loading, empty, error and locked all render',
      (WidgetTester tester) async {
        useTallSurface(tester);

        await tester.pumpWidget(
          wrap(
            LearnedRulesScreen(
              rules: const <LearnedRule>[],
              resolver: seedResolver,
              isLoading: true,
            ),
          ),
        );
        expect(find.byKey(const Key('rules.loading')), findsOneWidget);

        await tester.pumpWidget(
          wrap(
            LearnedRulesScreen(
              rules: const <LearnedRule>[],
              resolver: seedResolver,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rules.empty')), findsOneWidget);
        expect(
          find.textContaining('teaches a rule automatically'),
          findsOneWidget,
          reason: 'the empty state explains how rules come to exist',
        );

        await tester.pumpWidget(
          wrap(
            LearnedRulesScreen(
              rules: const <LearnedRule>[],
              resolver: seedResolver,
              errorMessage: 'Your learned rules could not be loaded.',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Your learned rules could not be loaded.'),
          findsOneWidget,
        );

        await tester.pumpWidget(
          wrap(
            LearnedRulesScreen(
              rules: const <LearnedRule>[],
              resolver: seedResolver,
              isLocked: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('categoryLockedState')), findsOneWidget);
      },
    );

    testWidgets('Arabic RTL at 2.0 text scale (NFR-U3, NFR-U8)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          LearnedRulesScreen(
            rules: <LearnedRule>[
              rule(),
              rule(id: 2, merchant: 'QANDB'),
            ],
            resolver: seedResolver,
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('القواعد المتعلمة'), findsOneWidget);
    });
  });

  // =========================================================================
  group('S-18 — the low-confidence tab gains categorization rows (KHA-32)', () {
    Widget inbox({
      List<FlaggedTransactionItem> flagged = const <FlaggedTransactionItem>[],
      Map<int, CategoryAssignment> assignments =
          const <int, CategoryAssignment>{},
      void Function(FlaggedTransactionItem)? onCategorize,
      String locale = 'en',
      double textScale = 1.0,
    }) => wrap(
      NeedsReviewScreen(
        unparsed: const <ReviewQueueItem>[],
        flagged: flagged,
        categoryAssignments: assignments,
        onFillInDetails: (_) {},
        onNotATransaction: (_) {},
        onOpenFlagged: (_) {},
        onCategorize: onCategorize,
      ),
      locale: locale,
      textScale: textScale,
    );

    testWidgets('**AC-C4.1** — a flagged row carries the needs-review '
        'indicator as an icon AND the literal words, never colour alone', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[categoryFlagged()],
          assignments: <int, CategoryAssignment>{
            501: CategoryAssignment(
              category: seedCategory(CategoryIds.uncategorized),
              band: ConfidenceBand.none,
              needsReview: true,
              reviewReason: CategoryReviewReason.unknownMerchant,
            ),
          },
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needsReviewBadge')), findsOneWidget);
      expect(find.text('Needs review'), findsWidgets);
      expect(find.byIcon(Icons.flag_outlined), findsWidgets);
    });

    testWidgets('KHA-32 — the confidence is shown in WORDS plus its figure', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[
            categoryFlagged(reason: CategoryReviewReason.lowConfidenceCategory),
          ],
          assignments: <int, CategoryAssignment>{
            501: CategoryAssignment(
              category: seedCategory(CategoryIds.uncategorized),
              band: ConfidenceBand.low,
              confidence: 0.62,
              needsReview: true,
              reviewReason: CategoryReviewReason.lowConfidenceCategory,
            ),
          },
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('confidenceIndicator')), findsOneWidget);
      expect(find.textContaining('Not sure'), findsOneWidget);
      expect(find.textContaining('62%'), findsOneWidget);
    });

    testWidgets('the three CategoryReviewReasons ask three different '
        'questions', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[
            categoryFlagged(
              id: 1,
              reason: CategoryReviewReason.unknownMerchant,
            ),
            categoryFlagged(
              id: 2,
              reason: CategoryReviewReason.noRuleForMerchant,
            ),
            categoryFlagged(
              id: 3,
              reason: CategoryReviewReason.lowConfidenceCategory,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Low confidence (3)'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('have not seen this merchant'),
        findsOneWidget,
      );
      expect(find.textContaining('nobody has said'), findsOneWidget);
      expect(find.textContaining('not sure enough'), findsOneWidget);
    });

    testWidgets('§6.1 — tapping the chip on a flagged row opens the '
        'correction flow', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<int> corrected = <int>[];
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[categoryFlagged()],
          assignments: <int, CategoryAssignment>{
            501: CategoryAssignment(
              category: seedCategory(CategoryIds.uncategorized),
              band: ConfidenceBand.none,
              needsReview: true,
              reviewReason: CategoryReviewReason.unknownMerchant,
            ),
          },
          onCategorize: (FlaggedTransactionItem item) =>
              corrected.add(item.transactionId),
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('needsReview.categoryChip.501')));
      await tester.pumpAndSettle();

      expect(corrected, <int>[501]);
    });

    testWidgets('a DUPLICATE flag still renders its own card, unchanged — the '
        'two kinds of flag are told apart by reviewReason', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[
            FlaggedTransactionItem(
              transactionId: 601,
              amount: '212.00',
              currencyCode: 'SAR',
              merchantRawText: 'QANDB Books',
              reviewReason: ReviewReason.possibleDuplicate,
              possibleDuplicateOfId: 602,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Possible duplicate'), findsWidgets);
      // …and none of the categorization chrome leaks onto it.
      expect(find.byKey(const Key('confidenceIndicator')), findsNothing);
    });

    testWidgets('Arabic RTL at 2.0 text scale (NFR-U3, NFR-U8)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        inbox(
          flagged: <FlaggedTransactionItem>[categoryFlagged()],
          assignments: <int, CategoryAssignment>{
            501: CategoryAssignment(
              category: seedCategory(CategoryIds.uncategorized),
              band: ConfidenceBand.low,
              confidence: 0.7,
              needsReview: true,
              reviewReason: CategoryReviewReason.lowConfidenceCategory,
            ),
          },
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  group('S-11 — the header chip and KHA-31\'s provenance', () {
    testWidgets('the category chip renders and opens the correction flow', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int taps = 0;
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: purchase(),
            categoryAssignment: CategoryAssignment(
              category: seedCategory('groceries'),
              band: ConfidenceBand.confident,
              confidence: 0.9,
            ),
            onEditCategory: () => taps++,
          ),
        ),
      );

      expect(find.byKey(const Key('txnDetail.categoryChip')), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.textContaining('Confident match'), findsOneWidget);

      await tester.tap(find.byKey(const Key('txnDetail.categoryChip')));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('a DELETED transaction\'s category is read-only', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int taps = 0;
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: purchase(deleted: true),
            categoryAssignment: CategoryAssignment(
              category: seedCategory('groceries'),
              band: ConfidenceBand.userChosen,
            ),
            onEditCategory: () => taps++,
          ),
        ),
      );
      await tester.tap(
        find.byKey(const Key('txnDetail.categoryChip')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        taps,
        0,
        reason:
            'correcting a deleted row would train the learning loop on a '
            'transaction the user has said should not exist',
      );
    });

    testWidgets('KHA-31 — "why this category?" loads on demand and shows the '
        'rule plus the audit trail', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: purchase(),
            categoryAssignment: CategoryAssignment(
              category: seedCategory('groceries'),
              band: ConfidenceBand.confident,
              confidence: 1.0,
            ),
            loadCategoryProvenance: () async => CategoryProvenance(
              transactionId: 1,
              source: StoredCategorySource.rule,
              categoryId: 'groceries',
              confidence: 1.0,
              rule: rule(),
              auditTrail: <CategoryAuditEntry>[
                CategoryAuditEntry(
                  changedAt: DateTime.utc(2026, 7, 15, 10),
                  actor: 'system_rule',
                  actorDetail: 'merchant_rule:1',
                  toCategoryId: 'groceries',
                ),
              ],
            ),
          ),
        ),
      );

      // Not loaded until asked — it is a second query for a rarely-asked
      // question.
      expect(find.byKey(const Key('txnDetail.provenancePanel')), findsNothing);
      await tester.tap(find.byKey(const Key('txnDetail.whyCategorized')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('txnDetail.provenancePanel')),
        findsOneWidget,
      );
      expect(find.textContaining('learned rule applied this'), findsOneWidget);
      expect(find.textContaining('QANDA Foods'), findsOneWidget);
      expect(find.textContaining('A learned rule'), findsWidgets);
    });

    testWidgets('KHA-31 — a rule that has since been deleted is stated as '
        'such, not as a dangling reference', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: purchase(),
            loadCategoryProvenance: () async => CategoryProvenance(
              transactionId: 1,
              source: StoredCategorySource.rule,
              categoryId: 'groceries',
              confidence: 1.0,
              auditTrail: const <CategoryAuditEntry>[],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('txnDetail.whyCategorized')));
      await tester.pumpAndSettle();
      expect(find.textContaining('has since been deleted'), findsOneWidget);
    });

    testWidgets('KHA-31 — the three other provenance answers are three '
        'different sentences', (WidgetTester tester) async {
      useTallSurface(tester);

      int generation = 0;
      Future<void> pumpWith(CategoryProvenance provenance) async {
        // A fresh key per pump, so Flutter builds a NEW State rather than
        // reusing the previous one — otherwise `_pending` is already set from
        // the last case and the "why?" affordance is gone before the tap.
        await tester.pumpWidget(
          wrap(
            TransactionDetailScreen(
              key: ValueKey<int>(generation++),
              transaction: purchase(),
              loadCategoryProvenance: () async => provenance,
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('txnDetail.whyCategorized')));
        await tester.pumpAndSettle();
      }

      await pumpWith(
        CategoryProvenance(
          transactionId: 1,
          source: StoredCategorySource.user,
          categoryId: 'groceries',
          auditTrail: const <CategoryAuditEntry>[],
        ),
      );
      expect(find.textContaining('You chose this'), findsOneWidget);

      await pumpWith(CategoryProvenance.unknown(1));
      expect(find.textContaining('could not decide'), findsOneWidget);

      await pumpWith(
        CategoryProvenance(
          transactionId: 1,
          source: 'default',
          categoryId: 'groceries',
          auditTrail: const <CategoryAuditEntry>[],
        ),
      );
      expect(
        find.textContaining('before the app started recording'),
        findsOneWidget,
      );
    });

    testWidgets('design.md §3.4 — the provenance panel has a loading and an '
        'error state, and the error never renders as an empty history', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: purchase(),
            loadCategoryProvenance: () async =>
                throw StateError('database unavailable'),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('txnDetail.whyCategorized')));
      await tester.pump();
      expect(
        find.byKey(const Key('txnDetail.provenanceLoading')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('txnDetail.provenanceError')),
        findsOneWidget,
      );
      expect(find.textContaining('No categorization history'), findsNothing);
    });

    testWidgets('a screen with no category information renders no chip at all '
        '— never an invented Uncategorized one', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(TransactionDetailScreen(transaction: purchase())),
      );
      expect(find.byKey(const Key('txnDetail.categoryChip')), findsNothing);
      expect(find.byKey(const Key('txnDetail.whyCategorized')), findsNothing);
    });
  });

  // =========================================================================
  group('the shared indicators (NFR-U4)', () {
    testWidgets('ConfidenceIndicator renders nothing at all for a category '
        'the USER chose', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: ConfidenceIndicator(
              band: ConfidenceBand.userChosen,
              confidence: 1.0,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('confidenceIndicator')), findsNothing);
      expect(
        find.textContaining('100%'),
        findsNothing,
        reason:
            'printing a confidence beside a category the user typed would be '
            'the app congratulating itself on a fact it did not establish',
      );
    });

    testWidgets('ConfidenceIndicator omits the figure when there is no '
        'meaningful one', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const Scaffold(body: ConfidenceIndicator(band: ConfidenceBand.none)),
        ),
      );
      expect(find.text('No match found'), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);
    });

    testWidgets('an unknown icon token falls back to a neutral label icon '
        'rather than throwing', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: CategoryChip(
              category: const Category(
                id: 'custom',
                key: 'custom',
                nameAr: 'مخصص',
                nameEn: 'Custom',
                iconToken: 'no_such_icon_token_from_the_future',
                group: CategoryGroup.spending,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
    });

    testWidgets('ConfidenceBand.of tells "you decided" apart from "we are '
        'sure"', (WidgetTester tester) async {
      // A pure function, asserted here beside the widget that renders it so
      // the banding rule and its presentation stay in one place.
      expect(
        ConfidenceBand.of(
          source: StoredCategorySource.user,
          confidence: 1.0,
          categoryId: 'groceries',
          autoApplyThreshold: 0.85,
        ),
        ConfidenceBand.userChosen,
      );
      expect(
        ConfidenceBand.of(
          source: StoredCategorySource.rule,
          confidence: 0.90,
          categoryId: 'groceries',
          autoApplyThreshold: 0.85,
        ),
        ConfidenceBand.confident,
      );
      expect(
        ConfidenceBand.of(
          source: StoredCategorySource.rule,
          confidence: 0.70,
          categoryId: 'groceries',
          autoApplyThreshold: 0.85,
        ),
        ConfidenceBand.low,
      );
      expect(
        ConfidenceBand.of(
          source: StoredCategorySource.none,
          confidence: 0.0,
          categoryId: null,
          autoApplyThreshold: 0.85,
        ),
        ConfidenceBand.none,
        reason: 'AC-D2.4 — no candidate at any tier',
      );
      expect(
        ConfidenceBand.of(
          source: StoredCategorySource.none,
          confidence: 0.62,
          categoryId: null,
          autoApplyThreshold: 0.85,
        ),
        ConfidenceBand.low,
        reason: 'a candidate matched but was refused — the app is asking',
      );
    });
  });
}
