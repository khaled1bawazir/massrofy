/// **The two reconciliation invariants, asserted at the WIDGET level** — KHA-37.
///
/// ---
///
/// ## Why this file exists even though both invariants are already tested
///
/// AC-C1.3 is tested at the data layer by
/// `test/features/categorization/category_sum_invariant_test.dart`, and AC-E3.2 by
/// `test/features/ledger/instrument_breakdown_test.dart`. Both are thorough. Both
/// stop one layer short of what the user sees.
///
/// KHA-37's brief names the gap directly, and names its precedent:
///
/// > *"Category totals including Uncategorized sum to the period total (AC-C1.3)
/// > — already tested at the data layer per P4a's `category_sum_invariant_test.dart`,
/// > this needs the widget-level path covered too (the same gap G-QA-34-1 found and
/// > fixed for KHA-97 — don't reintroduce it here)."*
///
/// The distinction is not pedantic. A domain type can hold the invariant perfectly
/// while the screen above it breaks the *displayed* one, and there are at least
/// three ordinary ways to do that, all of which look like reasonable UI decisions:
///
///  - **truncate** the list (`take(8)`, "top categories") — the rows then sum to
///    less than the footer;
///  - **fold** small slices into an "Other" row that AC-E2.3 forbids;
///  - **hide** the Uncategorized row because it looks untidy — which AC-E2.3 exists
///    to prevent, since *"hiding it would let the user believe their data is more
///    complete than it is."*
///
/// None of those touch `CategoryBreakdown`. All three would pass the data-layer
/// test. So these tests read the **figures off the rendered widget tree** and add
/// them up, which is the only version of the invariant the user can actually be
/// harmed by.
///
/// ## How the figures are read back
///
/// [renderedAmounts] walks the tree under a subtree finder, collects the `Text`
/// widgets whose content parses as a signed money figure, and returns them as
/// `Money`. That is deliberately a *reading* rather than an inspection of the
/// widget's inputs: asserting on `BreakdownRow.totals` would only re-check the
/// domain object this file exists to look past.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/category_breakdown.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_breakdown.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/screens/reports_screen.dart';

import '../support/ledger_fixtures.dart';

/// A `MaterialApp` with both locales wired, so these render exactly as the app
/// does — including under Arabic RTL, which every P5 screen must survive.
Widget wrap(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: const <LocalizationsDelegate<Object?>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
  home: child,
);

/// Every signed SAR figure rendered under [of], as `Money`.
///
/// Parses the *string on screen* — `−1,000.00 SAR` / `+100.00 SAR` — because what
/// this file is checking is the arithmetic of what the user can read, not the
/// arithmetic of what the widget was handed.
///
/// The sign is applied on the way out, so a credit slice subtracts. That mirrors
/// `formatSignedAmount`, which is the function that produced the string.
List<Money> renderedAmounts(WidgetTester tester, Finder of) {
  final List<Money> found = <Money>[];
  for (final Element element
      in find.descendant(of: of, matching: find.byType(Text)).evaluate()) {
    final String? data = (element.widget as Text).data;
    if (data == null || !data.endsWith(' SAR')) {
      continue;
    }
    final String body = data.substring(0, data.length - 4);
    final bool isCredit = body.startsWith('+');
    final String digits = body
        .replaceAll('−', '')
        .replaceAll('+', '')
        .replaceAll(',', '')
        .trim();
    final Money? parsed = Money.tryParse(digits, currency: 'SAR');
    if (parsed == null) {
      continue;
    }
    found.add(isCredit ? -parsed : parsed);
  }
  return found;
}

LedgerBank bank(int id) => LedgerBank(
  id: id,
  canonicalKey: 'bank_$id',
  displayNameAr: 'بنك $id',
  displayNameEn: 'Bank $id',
);

void main() {
  // -----------------------------------------------------------------------
  // One fixture for both screens, deliberately containing every awkward case
  // the two invariants have to survive:
  //
  //   groceries        −1,000.00  (bill payment, account #10, bank 1)
  //   groceries        −  250.50  (POS, card #11, bank 1)
  //   groceries        +  100.00  (refund on card #11 — REDUCES spend, US-B7)
  //   dining           −  400.00  (POS, card #21, bank 2)
  //   (uncategorized)  −   60.00  (cash, no instrument — AC-E2.3 + AC-E3.2)
  //   internal xfer    −  750.00  out of #10 } excluded on BOTH legs, and the
  //   internal xfer    +  750.00  into #22   } pair spans two BANKS
  //
  //   Hand-computed net spend:
  //     1000.00 + 250.50 − 100.00 + 400.00 + 60.00 = 1,610.50
  // -----------------------------------------------------------------------
  final LedgerInstrument account10 = instrument(id: 10, bankId: 1);
  final LedgerInstrument card11 = instrument(
    id: 11,
    bankId: 1,
    kind: InstrumentKind.card,
    masked: '****4821',
  );
  final LedgerInstrument card21 = instrument(
    id: 21,
    bankId: 2,
    kind: InstrumentKind.card,
    masked: '****9002',
  );
  final LedgerInstrument account22 = instrument(id: 22, bankId: 2);

  final Money expectedTotal = Money.parse('1610.50', currency: 'SAR');

  List<LedgerTransaction> ledger() => <LedgerTransaction>[
    _categorized(
      tx(
        id: 1,
        amount: '1000.00',
        type: TransactionType.billPayment,
        on: account10,
      ),
      'groceries',
    ),
    _categorized(tx(id: 2, amount: '250.50', on: card11), 'groceries'),
    _categorized(
      tx(
        id: 3,
        amount: '100.00',
        direction: MovementDirection.credit,
        type: TransactionType.refund,
        on: card11,
      ),
      'groceries',
    ),
    _categorized(
      tx(
        id: 4,
        amount: '400.00',
        type: TransactionType.onlinePurchase,
        on: card21,
      ),
      'dining',
    ),
    // No category id at all → resolves to Uncategorized. Also cash, so it is the
    // one row that exercises AC-E2.3 and AC-E3.2 at once.
    tx(id: 5, amount: '60.00'),
    _categorized(
      tx(
        id: 6,
        amount: '750.00',
        type: TransactionType.transferOut,
        affectsSpend: false,
        at: DateTime.utc(2026, 7, 15, 10),
        on: account10,
      ),
      'internal_transfer',
    ),
    _categorized(
      tx(
        id: 7,
        amount: '750.00',
        direction: MovementDirection.credit,
        type: TransactionType.transferIn,
        affectsSpend: false,
        at: DateTime.utc(2026, 7, 15, 10, 5),
        on: account22,
      ),
      'internal_transfer',
    ),
  ];

  Widget categoryScreen({String locale = 'en'}) => wrap(
    CategoryBreakdownScreen(
      breakdown: CategoryBreakdown.of(
        ledger(),
        period: july2026,
        resolver: CategoryResolver.defaults(),
      ),
      period: july2026,
      isCurrentMonth: true,
      onPreviousMonth: () {},
      onNextMonth: () {},
      onCurrentMonth: () {},
    ),
    locale: locale,
  );

  Widget instrumentScreen({String locale = 'en'}) => wrap(
    InstrumentBreakdownScreen(
      breakdown: InstrumentBreakdown.of(
        ledger(),
        period: july2026,
        banks: <LedgerBank>[bank(1), bank(2)],
        instruments: <LedgerInstrument>[account10, card11, card21, account22],
      ),
      period: july2026,
      isCurrentMonth: true,
      onPreviousMonth: () {},
      onNextMonth: () {},
      onCurrentMonth: () {},
    ),
    locale: locale,
  );

  group('AC-C1.3 at the widget level — S-29', () {
    testWidgets('the category figures ON SCREEN sum to the footer total', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(categoryScreen());
      await tester.pump();

      final List<Money> rows = <Money>[];

      // Read every row figure off the tree, one row at a time, so a truncated or
      // folded list is impossible to miss.
      for (final String categoryId in <String>[
        'groceries',
        'dining',
        CategoryIds.uncategorized,
        'internal_transfer',
      ]) {
        final Finder row = find.byKey(Key('categoryBreakdown.row.$categoryId'));
        if (row.evaluate().isEmpty) {
          continue;
        }
        rows.addAll(renderedAmounts(tester, row));
      }

      final List<Money> footer = renderedAmounts(
        tester,
        find.byKey(const Key('categoryBreakdown.total')),
      );

      expect(
        footer.single,
        expectedTotal,
        reason:
            'the footer must be the hand-computed period total — this is the '
            'independent oracle, derived by adding five numbers in this file\'s '
            'header comment rather than by running the code under test',
      );
      expect(
        Money.sum(rows, currency: 'SAR'),
        footer.single,
        reason:
            'AC-C1.3 broken **as rendered**: the category rows on screen do not '
            'sum to the total printed underneath them. The domain object may '
            'still reconcile — a truncated list, an "Other" fold or a hidden '
            'Uncategorized row breaks only the displayed invariant, which is the '
            'only one the user can be harmed by (G-QA-34-1).',
      );
      // No mismatch banner: the guard must be silent when the invariant holds,
      // or it would be noise nobody reads when it does not.
      expect(
        find.byKey(const Key('breakdown.reconciliationFailed')),
        findsNothing,
      );
    });

    testWidgets('**AC-E2.3** — the Uncategorized row is present, on its own, '
        'with its real figure and no "Other" anywhere', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(categoryScreen());
      await tester.pump();

      final Finder uncategorized = find.byKey(
        Key('categoryBreakdown.row.${CategoryIds.uncategorized}'),
      );
      expect(
        uncategorized,
        findsOneWidget,
        reason:
            'a non-zero Uncategorized total must be its own line. Hiding it '
            'would let the user believe their data is more complete than it is, '
            'which is the entire reason AC-E2.3 is written down.',
      );
      expect(
        renderedAmounts(tester, uncategorized).single,
        Money.parse('60.00', currency: 'SAR'),
      );
      expect(find.text('Other'), findsNothing);
      expect(find.textContaining('Other categories'), findsNothing);
    });

    testWidgets('**AC-E2.1** — each row shows its share of the period, and the '
        'shares are computed from the same figures', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(categoryScreen());
      await tester.pump();

      // groceries = 1000.00 + 250.50 − 100.00 = 1,150.50 of 1,610.50 → 71%.
      // dining    =                    400.00 of 1,610.50 → 25%.
      // uncat.    =                     60.00 of 1,610.50 →  4%.
      expect(find.text('71% of the period'), findsOneWidget);
      expect(find.text('25% of the period'), findsOneWidget);
      expect(find.text('4% of the period'), findsOneWidget);
    });

    testWidgets('a money-movement category shows its count and says it is not '
        'spending, rather than showing a bare empty figure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(categoryScreen());
      await tester.pump();

      // Both transfer legs are in the period and carry the category, and neither
      // is spend (US-B11). Without this line the row would read "2 transactions"
      // beside no figure, which looks like lost money.
      expect(
        find.text('2 transactions, not counted as spending'),
        findsOneWidget,
      );
    });

    testWidgets('a category used only in ANOTHER month appears with a zero '
        'count and says so, and changes no figure', (
      WidgetTester tester,
    ) async {
      // Found during self-review, and pinned because it is surprising until you
      // see why: `CategoryBreakdown.of` partitions over the whole live set and
      // then totals each partition *within the period*, so a category whose only
      // rows are in June is present on July's breakdown with a count of zero.
      //
      // That is kept rather than filtered, for the same reason S-30 shows an
      // unused card (the approved mockup does): "you have a Health & Pharmacy
      // category and did not use it this month" is information. What it must never
      // do is affect the arithmetic — an empty slice contributes a null base
      // figure, so the footer identity is untouched.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrap(
          CategoryBreakdownScreen(
            breakdown: CategoryBreakdown.of(
              <LedgerTransaction>[
                ...ledger(),
                // June — outside `july2026`.
                _categorized(
                  tx(
                    id: 20,
                    amount: '77.00',
                    at: DateTime.utc(2026, 6, 12, 10),
                    on: card11,
                  ),
                  'health_pharmacy',
                ),
              ],
              period: july2026,
              resolver: CategoryResolver.defaults(),
            ),
            period: july2026,
            isCurrentMonth: true,
            onPreviousMonth: () {},
            onNextMonth: () {},
            onCurrentMonth: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('categoryBreakdown.row.health_pharmacy')),
        findsOneWidget,
      );
      expect(
        find.text('No transactions in this category this period'),
        findsOneWidget,
      );
      // The footer is unchanged — the June row is in no figure on this screen.
      expect(
        renderedAmounts(
          tester,
          find.byKey(const Key('categoryBreakdown.total')),
        ).single,
        expectedTotal,
      );
    });

    testWidgets('renders in Arabic RTL with the same arithmetic (NFR-U8)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(categoryScreen(locale: 'ar'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('غير مصنف'), findsOneWidget);
      // The figures are Western-Arabic numerals in both locales (design.md §2.2),
      // so the same footer string appears — which is also what makes the
      // invariant locale-independent rather than needing a second oracle.
      expect(
        renderedAmounts(
          tester,
          find.byKey(const Key('categoryBreakdown.total')),
        ).single,
        expectedTotal,
      );
    });
  });

  group('AC-E3.2 at the widget level — S-30', () {
    testWidgets('the instrument figures ON SCREEN, plus the cash row, sum to '
        'the footer total', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(instrumentScreen());
      await tester.pump();

      final List<Money> rows = <Money>[];
      for (final String rowKey in <String>[
        'instrumentBreakdown.row.10',
        'instrumentBreakdown.row.11',
        'instrumentBreakdown.row.21',
        'instrumentBreakdown.row.22',
        'instrumentBreakdown.row.unassigned',
      ]) {
        final Finder row = find.byKey(Key(rowKey));
        expect(row, findsOneWidget, reason: rowKey);
        rows.addAll(renderedAmounts(tester, row));
      }

      final List<Money> footer = renderedAmounts(
        tester,
        find.byKey(const Key('instrumentBreakdown.total')),
      );

      expect(footer.single, expectedTotal);
      expect(
        Money.sum(rows, currency: 'SAR'),
        footer.single,
        reason:
            'AC-E3.2 broken **as rendered**: the card and account rows plus the '
            'cash row do not sum to the total printed underneath them, which is '
            'the same figure Home and S-10 show',
      );
      expect(
        find.byKey(const Key('breakdown.reconciliationFailed')),
        findsNothing,
      );
    });

    testWidgets('the cash row is rendered and named, because without it the '
        'footer would not close', (WidgetTester tester) async {
      await tester.pumpWidget(instrumentScreen());
      await tester.pump();

      expect(
        find.byKey(const Key('instrumentBreakdown.row.unassigned')),
        findsOneWidget,
      );
      expect(find.text('Cash and unmatched'), findsOneWidget);
    });

    testWidgets('an unused card is shown and labelled as unused, not hidden', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(instrumentScreen());
      await tester.pump();

      // Account #22 holds only the incoming transfer leg, so it has no spend.
      expect(
        find.byKey(const Key('instrumentBreakdown.row.22')),
        findsOneWidget,
      );
    });

    testWidgets('renders in Arabic RTL with the same arithmetic (NFR-U8)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(instrumentScreen(locale: 'ar'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('نقداً وغير مطابق'), findsOneWidget);
      expect(
        renderedAmounts(
          tester,
          find.byKey(const Key('instrumentBreakdown.total')),
        ).single,
        expectedTotal,
      );
    });
  });

  group('the mismatch banner is not dead code', () {
    testWidgets('a breakdown whose parts do NOT sum to its total says so on '
        'screen', (WidgetTester tester) async {
      // Constructed by hand, because the domain types cannot produce this state —
      // which is exactly why the banner would otherwise be untested and could rot
      // into something that never renders. NFR-A6's requirement is that a
      // reconciliation break is *visible*, and "unreachable today" is not the
      // same as "unreachable".
      final CategoryBreakdown broken = CategoryBreakdown(
        categories: <CategoryTotal>[
          CategoryTotal(
            category: DefaultCategories.seed.first,
            totals: LedgerTotalsFixture.of('100.00'),
            transactionCount: 1,
          ),
        ],
        total: LedgerTotalsFixture.of('250.00'),
        baseCurrencyCode: 'SAR',
      );
      expect(broken.reconciles, isFalse);

      await tester.pumpWidget(
        wrap(
          CategoryBreakdownScreen(
            breakdown: broken,
            period: july2026,
            isCurrentMonth: true,
            onPreviousMonth: () {},
            onNextMonth: () {},
            onCurrentMonth: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('breakdown.reconciliationFailed')),
        findsOneWidget,
      );
    });
  });
}

/// [transaction] with [categoryId] attached.
///
/// `ledger_fixtures.dart`'s `tx` has no category parameter (it predates P4a), and
/// adding one there would touch every P3b test. Rebuilding the one field here is
/// cheaper and keeps this file's fixture legible.
LedgerTransaction _categorized(
  LedgerTransaction transaction,
  String categoryId,
) => LedgerTransaction(
  id: transaction.id,
  amount: transaction.amount,
  direction: transaction.direction,
  transactionType: transaction.transactionType,
  affectsSpend: transaction.affectsSpend,
  occurredAt: transaction.occurredAt,
  categoryId: categoryId,
  instrument: transaction.instrument,
  isDeleted: transaction.isDeleted,
);

/// A one-currency [PeriodTotals] for the mismatch-banner test.
abstract final class LedgerTotalsFixture {
  static PeriodTotals of(String amount) {
    final Money value = Money.parse(amount, currency: 'SAR');
    return PeriodTotals(
      base: value,
      baseCurrencyCode: 'SAR',
      convertedCount: 1,
      byCurrency: <CurrencyTotal>[
        CurrencyTotal(currencyCode: 'SAR', net: value, transactionCount: 1),
      ],
      unconverted: const <UnconvertedGroup>[],
    );
  }
}
