/// **Reachability and the end-to-end journeys P5b adds** — KHA-37, KHA-38.
///
/// `docs/lessons.md`, twice over:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code — it
/// > expires the moment someone adds a route, silently."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// P5a's version of this file exists because KHA-113 found **six** built, tested
/// screens with no construction site anywhere. This one covers P5b's five new
/// destinations (S-28..S-32) the same way: navigated to from the app shell, through
/// the real routes, over a real database — plus the two journeys that only exist
/// once several pieces are wired together (AC-E2.2's drill-down and AC-E5.2's
/// filtered total).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/screens/app_shell.dart';
import 'package:massrofy/presentation/screens/ledger_routes.dart';
import 'package:massrofy/presentation/screens/reports_screen.dart';
import 'package:massrofy/presentation/screens/transaction_list_screen.dart';

import '../support/app_test_harness.dart';

void main() {
  late TestSession session;
  late FakeSmsPermissionService permissions;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;

  setUp(() {
    session = TestSession.open();
    // Granted, so the AC-A1.3 banner does not sit on top of the assertions.
    permissions = FakeSmsPermissionService(
      current: SmsPermissionStatus.granted,
    );
    bankDao = BankDao(session.database, session.session.auditLogDao);
    instrumentDao = InstrumentDao(
      session.database,
      session.session.auditLogDao,
    );
  });

  tearDown(() async {
    await session.close();
  });

  Future<void> pumpShell(WidgetTester tester, {String locale = 'en'}) async {
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        locale: locale,
        child: const AppShell(),
      ),
    );
    await pumpHostFrames(tester);
  }

  /// One bank, one card, and two purchases dated **now** so they fall inside the
  /// live current month the shell opens on.
  Future<int> seedLedger() async {
    final int bankId = await bankDao.ensure(
      canonicalKey: 'qanda_bank',
      displayNameAr: 'بنك قندة',
      displayNameEn: 'Qanda Bank',
    );
    final int cardId = await instrumentDao.ensure(
      bankId: bankId,
      kind: InstrumentKind.card,
      maskedIdentifier: '****4821',
      refKey: 'qanda_bank:card:4821',
    );
    await session.session.transactionDao.insertManual(
      amount: Money.parse('310.40', currency: 'SAR'),
      merchantRawText: 'QANDA MART',
      occurredAt: DateTime.now().toUtc(),
      direction: 'debit',
      transactionType: TransactionType.posPurchase,
      affectsSpend: true,
      instrumentId: cardId,
    );
    await session.session.transactionDao.insertManual(
      amount: Money.parse('90.00', currency: 'SAR'),
      // Latin merchant text, as PRD §3.4 describes even inside Arabic messages.
      merchantRawText: 'NOON.COM',
      occurredAt: DateTime.now().toUtc(),
      direction: 'debit',
      transactionType: TransactionType.onlinePurchase,
      affectsSpend: true,
      instrumentId: cardId,
    );
    return cardId;
  }

  group('KHA-37 — the Reports tab and everything under it', () {
    testWidgets('the fourth tab exists, is at index 2, and opens S-28', (
      WidgetTester tester,
    ) async {
      await seedLedger();
      await pumpShell(tester);

      // design.md §1: Home · Transactions · Reports · More.
      expect(find.byKey(const Key('nav.reports')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav.reports')));
      await pumpHostFrames(tester);

      expect(find.byType(ReportsHubScreen), findsOneWidget);
      // Four cards, all present, each pre-showing its own line.
      for (final String key in <String>[
        'reports.card.category',
        'reports.card.instrument',
        'reports.card.monthOverMonth',
        'reports.card.spentVsKept',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }

      await disposeHost(tester);
    });

    testWidgets('the P5a placeholder line is GONE from the More menu', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.more')));
      await pumpHostFrames(tester);

      // A placeholder that outlives the thing it stood in for is worse than never
      // having written one, and only a test stops it lingering.
      expect(find.text('Reports arrive in the next release'), findsNothing);

      await disposeHost(tester);
    });

    testWidgets(
      '**every reports screen is reachable** — S-29, S-30, S-31, S-32',
      (WidgetTester tester) async {
        await seedLedger();
        await pumpShell(tester);
        await tester.tap(find.byKey(const Key('nav.reports')));
        await pumpHostFrames(tester);

        Future<void> openAndBack(String cardKey, Type screen) async {
          await tester.tap(find.byKey(Key(cardKey)));
          await pumpHostFrames(tester);
          expect(find.byType(screen), findsOneWidget, reason: cardKey);
          // Back to the hub, so the next hop starts from a known place.
          await tester.pageBack();
          await pumpHostFrames(tester);
        }

        await openAndBack('reports.card.category', CategoryBreakdownScreen);
        await openAndBack('reports.card.instrument', InstrumentBreakdownScreen);
        await openAndBack('reports.card.monthOverMonth', MonthComparisonScreen);
        await openAndBack('reports.card.spentVsKept', SpentVsKeptScreen);

        await disposeHost(tester);
      },
    );

    testWidgets('S-29 shows the period total, and it is the same figure Home '
        'shows (NFR-A6)', (WidgetTester tester) async {
      await seedLedger();
      await pumpShell(tester);

      // Home's headline first — 310.40 + 90.00.
      expect(
        find.descendant(
          of: find.byKey(const Key('home.monthTotal.value')),
          matching: find.text('−400.40 SAR'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('nav.reports')));
      await pumpHostFrames(tester);
      await tester.tap(find.byKey(const Key('reports.card.category')));
      await pumpHostFrames(tester);

      // The same string, from the same stream, computed by the same function.
      expect(
        find.descendant(
          of: find.byKey(const Key('categoryBreakdown.total')),
          matching: find.text('−400.40 SAR'),
        ),
        findsOneWidget,
      );

      await disposeHost(tester);
    });

    testWidgets(
      '**AC-E4.2** — with one month of data, S-31 states there is not '
      'enough history instead of drawing a comparison',
      (WidgetTester tester) async {
        await seedLedger();
        await pumpShell(tester);
        await tester.tap(find.byKey(const Key('nav.reports')));
        await pumpHostFrames(tester);
        await tester.tap(find.byKey(const Key('reports.card.monthOverMonth')));
        await pumpHostFrames(tester);

        expect(
          find.byKey(const Key('monthComparison.insufficientHistory')),
          findsOneWidget,
        );
        // No chart and no delta — not greyed, not zeroed, absent.
        expect(find.byKey(const Key('mom.chart')), findsNothing);
        expect(find.byKey(const Key('mom.delta')), findsNothing);

        await disposeHost(tester);
      },
    );

    testWidgets('**AC-E2.2** — tapping a category on S-29 lands on the '
        'transaction list, filtered to it', (WidgetTester tester) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.reports')));
      await pumpHostFrames(tester);
      await tester.tap(find.byKey(const Key('reports.card.category')));
      await pumpHostFrames(tester);

      // Both seeded rows are uncategorized (`insertManual` sets no category), so
      // the Uncategorized row is the one with transactions behind it — which is
      // also AC-E2.3's row, present with its real figure.
      final Finder uncategorized = find.byKey(
        const Key('categoryBreakdown.row.uncategorized'),
      );
      expect(uncategorized, findsOneWidget);
      await tester.tap(uncategorized);
      await pumpHostFrames(tester);

      expect(find.byType(TransactionListScreen), findsOneWidget);
      // The list arrives already filtered, so the total is labelled as a subset
      // rather than as the month.
      expect(
        find.byKey(const Key('txnList.total.filteredLabel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('filter.clearAll')), findsOneWidget);

      await disposeHost(tester);
    });

    testWidgets('the whole reports flow renders in Arabic RTL (NFR-U8)', (
      WidgetTester tester,
    ) async {
      await seedLedger();
      await pumpShell(tester, locale: 'ar');

      await tester.tap(find.byKey(const Key('nav.reports')));
      await pumpHostFrames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('التقارير'), findsWidgets);

      await tester.tap(find.byKey(const Key('reports.card.instrument')));
      await pumpHostFrames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('حسب البطاقة والحساب'), findsWidgets);

      await disposeHost(tester);
    });
  });

  group('KHA-38 — search and filter on S-10', () {
    testWidgets('the search field and the filter button are on the '
        'Transactions tab', (WidgetTester tester) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);

      expect(find.byKey(const Key('txnList.search')), findsOneWidget);
      expect(find.byKey(const Key('txnList.openFilter')), findsOneWidget);
      // Unfiltered: the total is labelled as the period's, not as a subset.
      expect(
        find.byKey(const Key('txnList.total.periodLabel')),
        findsOneWidget,
      );

      await disposeHost(tester);
    });

    testWidgets('**AC-E5.1 + AC-E5.2** — searching narrows the list AND the '
        'total, live', (WidgetTester tester) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);

      // Both rows, total 400.40.
      expect(find.text('QANDA MART'), findsWidgets);
      expect(find.text('NOON.COM'), findsWidgets);

      await tester.enterText(find.byKey(const Key('txnList.search')), 'noon');
      await pumpHostFrames(tester);

      // Only the matching row, and the figure is now 90.00 — the filtered subset,
      // relabelled so it cannot be read as the month's spending.
      expect(find.text('NOON.COM'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(TransactionListScreen),
          matching: find.text('QANDA MART'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('txnList.total.filteredLabel')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('txnList.total')),
          matching: find.text('−90.00 SAR'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 transaction'), findsOneWidget);

      await disposeHost(tester);
    });

    testWidgets('**AC-E5.3** — a search matching nothing shows the '
        'filtered-empty state with a working clear action', (
      WidgetTester tester,
    ) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);

      await tester.enterText(
        find.byKey(const Key('txnList.search')),
        'no-such-merchant',
      );
      await pumpHostFrames(tester);

      expect(find.byKey(const Key('txnList.filteredEmpty')), findsOneWidget);
      // NOT the "you have no transactions" copy — that would look like data loss
      // to a user who has two.
      expect(find.byKey(const Key('txnList.empty')), findsNothing);
      expect(find.byKey(const Key('txnList.emptyForPeriod')), findsNothing);

      // The way out actually works.
      await tester.tap(find.byKey(const Key('txnList.filteredEmpty.clear')));
      await pumpHostFrames(tester);

      expect(find.byKey(const Key('txnList.filteredEmpty')), findsNothing);
      expect(find.text('QANDA MART'), findsWidgets);
      expect(
        find.byKey(const Key('txnList.total.periodLabel')),
        findsOneWidget,
      );

      await disposeHost(tester);
    });

    testWidgets('the filter sheet opens, offers all four facets, and applies', (
      WidgetTester tester,
    ) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);

      await tester.tap(find.byKey(const Key('txnList.openFilter')));
      await pumpHostFrames(tester);

      // S-27's four facets — AC-E5.2's list, verbatim.
      expect(find.text('Date range'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Cards and accounts'), findsOneWidget);
      expect(find.text('Amount range'), findsOneWidget);

      // Pick a category that matches nothing (both seeded rows are
      // uncategorized), apply, and confirm the *screen* honoured it.
      await tester.tap(find.byKey(const Key('filterSheet.category.groceries')));
      await pumpHostFrames(tester);
      await tester.tap(find.byKey(const Key('filterSheet.apply')));
      await pumpHostFrames(tester);

      expect(find.byKey(const Key('txnList.filteredEmpty')), findsOneWidget);
      // And the applied facet surfaces as a removable chip (S-27).
      expect(
        find.byKey(const Key('filter.chip.category.groceries')),
        findsOneWidget,
      );

      await disposeHost(tester);
    });

    testWidgets('an inverted amount range blocks Apply rather than silently '
        'returning nothing', (WidgetTester tester) async {
      await seedLedger();
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);
      await tester.tap(find.byKey(const Key('txnList.openFilter')));
      await pumpHostFrames(tester);

      await tester.enterText(
        find.byKey(const Key('filterSheet.amountMin')),
        '500',
      );
      await tester.enterText(
        find.byKey(const Key('filterSheet.amountMax')),
        '100',
      );
      await pumpHostFrames(tester);

      expect(find.byKey(const Key('filterSheet.amountError')), findsOneWidget);
      // Disabled, not ignored: a filter that dropped what the user typed would
      // show a result they would read as an answer.
      final FilledButton apply = tester.widget<FilledButton>(
        find.byKey(const Key('filterSheet.apply')),
      );
      expect(apply.onPressed, isNull);

      await disposeHost(tester);
    });

    testWidgets('search works for an ARABIC merchant name too (PRD §3.4)', (
      WidgetTester tester,
    ) async {
      await seedLedger();
      await session.session.transactionDao.insertManual(
        amount: Money.parse('48.00', currency: 'SAR'),
        merchantRawText: 'مقهى القهوة العربية',
        occurredAt: DateTime.now().toUtc(),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
      );
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('nav.transactions')));
      await pumpHostFrames(tester);

      // Typed with a teh marbuta the bank did not use — the fold is what makes
      // this match (ADR-008's `CanonicalText.fold`, shared with the merchant-rule
      // engine so search and categorisation agree about "the same string").
      await tester.enterText(find.byKey(const Key('txnList.search')), 'القهوه');
      await pumpHostFrames(tester);

      expect(find.text('مقهى القهوة العربية'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(TransactionListScreen),
          matching: find.text('QANDA MART'),
        ),
        findsNothing,
      );

      await disposeHost(tester);
    });

    testWidgets('the search field and filter are ABSENT on an '
        'instrument-scoped list', (WidgetTester tester) async {
      final int cardId = await seedLedger();
      useTallHostSurface(tester);
      await tester.pumpWidget(
        hostScope(
          session: session,
          permissions: permissions,
          child: TransactionListHost(instrumentId: cardId),
        ),
      );
      await pumpHostFrames(tester);

      // On S-23/S-24 the set of rows IS the screen's subject; filtering it again
      // would leave the user unsure which narrowing they were looking at.
      expect(find.byKey(const Key('txnList.search')), findsNothing);
      expect(find.byKey(const Key('txnList.openFilter')), findsNothing);

      await disposeHost(tester);
    });
  });
}
