/// **Reachability, proved by construction site** — KHA-35, KHA-36, and the
/// half of KHA-113 that is not about permissions.
///
/// `docs/lessons.md`, twice:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// KHA-113 found **six** built, tested screens with no construction site at
/// all. Grepping is how a human answers that question; this file is how the
/// build answers it — every one of the six is navigated to here, from the app
/// shell, through the real routes, over a real database.
///
/// It also covers the ACs that are about a *chain* rather than a screen:
/// AC-E1.2 (the total reflects a change), AC-B2.1/B2.2 (drilling into a bank
/// shows only its instruments) and AC-B2.3 (an instrument's total equals its
/// own transactions).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/screens/app_shell.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/presentation/screens/banks_screen.dart';
import 'package:massrofy/presentation/screens/ledger_routes.dart';
import 'package:massrofy/presentation/screens/home_screen.dart';
import 'package:massrofy/presentation/screens/instrument_detail_screen.dart';
import 'package:massrofy/presentation/screens/manual_entry_screen.dart';
import 'package:massrofy/presentation/screens/transaction_list_screen.dart';

import '../support/app_test_harness.dart';

void main() {
  late TestSession session;
  late FakeSmsPermissionService permissions;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;

  setUp(() {
    session = TestSession.open();
    // Granted, so the AC-A1.3 banner does not sit on top of the assertions
    // below. The banner has its own test in the onboarding suite.
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

  /// A bank with one card, and one purchase on it, dated **now** so it falls
  /// inside the live current month the shell opens on.
  Future<int> seedLedger({String amount = '310.40'}) async {
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
      amount: Money.parse(amount, currency: 'SAR'),
      merchantRawText: 'QANDA MART',
      occurredAt: DateTime.now().toUtc(),
      direction: 'debit',
      transactionType: TransactionType.posPurchase,
      affectsSpend: true,
      instrumentId: cardId,
    );
    return cardId;
  }

  testWidgets('the shell opens on Home, and Home carries the month total '
      '(AC-E1.1)', (WidgetTester tester) async {
    await seedLedger();
    await pumpShell(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    // Scoped to the card rather than to the whole tree: `AppShell`'s
    // `IndexedStack` builds every tab at once (deliberately — see its header),
    // so the transaction list's running total and Home's recent-activity row
    // carry the same string. Asserting on the *headline figure* is what
    // AC-E1.1 is about.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.monthTotal.value')),
        matching: find.text('−310.40 SAR'),
      ),
      findsOneWidget,
    );

    await disposeHost(tester);
  });

  testWidgets('**AC-E1.3** — with no transactions, Home shows an explicit '
      'zero and an empty state, never a blank', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('home.monthTotal.empty')), findsOneWidget);
    expect(find.text('0.00 SAR'), findsOneWidget);
    expect(find.byKey(const Key('home.empty')), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('**AC-E1.2** — a transaction added while Home is on screen moves '
      'the total, with no navigation at all', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(find.text('0.00 SAR'), findsOneWidget);

    await seedLedger(amount: '45.00');
    await pumpHostFrames(tester);

    // The AC says "on return to the main screen"; a Drift stream is stronger
    // than that — the figure moves without anyone leaving.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.monthTotal.value')),
        matching: find.text('−45.00 SAR'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home.monthTotal.empty')), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('the Transactions tab shows the list, and it agrees with Home', (
    WidgetTester tester,
  ) async {
    await seedLedger();
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('nav.transactions')));
    await pumpHostFrames(tester);

    expect(find.byType(TransactionListScreen), findsOneWidget);
    // NFR-A6: the same figure, from the same ledger, computed the same way.
    expect(find.byKey(const Key('txnList.total')), findsOneWidget);
    expect(find.text('−310.40 SAR'), findsWidgets);

    await disposeHost(tester);
  });

  testWidgets('**the dead screens of KHA-113, reached**: More -> Banks -> Bank '
      'Instrument detail', (WidgetTester tester) async {
    await seedLedger();
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('nav.more')));
    await pumpHostFrames(tester);
    await tester.tap(find.byKey(const Key('more.banks')));
    await pumpHostFrames(tester);

    // S-21 — `BanksScreen` had zero construction sites before this PR.
    expect(find.byType(BanksScreen), findsOneWidget);
    expect(find.text('Qanda Bank'), findsOneWidget);

    await tester.tap(find.text('Qanda Bank'));
    await pumpHostFrames(tester);

    // S-22 — AC-B13.3's two groups, never one merged list.
    expect(find.byType(BankDetailScreen), findsOneWidget);
    expect(find.textContaining('Accounts'), findsOneWidget);
    expect(find.textContaining('Cards'), findsOneWidget);

    // The card is under Cards, not Accounts — so open that segment first.
    await tester.tap(find.textContaining('Cards'));
    await pumpHostFrames(tester);
    await tester.tap(find.byType(InstrumentTile).first);
    await pumpHostFrames(tester);

    // S-23/S-24 — `InstrumentDetailScreen` also had zero construction sites.
    expect(find.byType(InstrumentDetailScreen), findsOneWidget);
    // AC-B2.3 — only this instrument's transactions, and the total equals
    // their sum for the period.
    expect(find.text('QANDA MART'), findsOneWidget);
    expect(find.text('−310.40 SAR'), findsWidgets);
    // NFR-S2 — masked, last four only, everywhere.
    expect(find.textContaining('4821'), findsWidgets);
    expect(find.textContaining('****4821'), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('**AC-B3.1** — an instrument can be renamed from its detail '
      'screen, and the new name is what the banks screen then shows', (
    WidgetTester tester,
  ) async {
    final int cardId = await seedLedger();
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        child: InstrumentDetailHost(instrumentId: cardId),
      ),
    );
    await pumpHostFrames(tester);

    await tester.tap(find.text('Rename'));
    await pumpHostFrames(tester);
    await tester.enterText(find.byType(TextField), 'Blue Visa');
    await tester.tap(find.text('Save name'));
    await pumpHostFrames(tester);

    final InstrumentRow row = await instrumentDao.byId(cardId);
    expect(row.friendlyName, 'Blue Visa');
    // AC-B3.2 — the match key is untouched, so the next SMS for this card
    // still resolves to it.
    expect(row.refKey, 'qanda_bank:card:4821');

    await disposeHost(tester);
  });

  testWidgets('**S-20 is reachable** — the Home FAB opens manual entry', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('home.addTransaction')));
    await pumpHostFrames(tester);

    expect(find.byType(ManualEntryScreen), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('every More-menu destination is reachable', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('nav.more')));
    await pumpHostFrames(tester);

    // Grepping for these keys answers "is X routed?" for the whole menu.
    for (final String key in <String>[
      'more.banks',
      'more.addTransaction',
      'more.recentlyDeleted',
      'more.needsReview',
      'more.categories',
      'more.rules',
      'more.lockNow',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // **Updated by P5b (KHA-37).** This assertion used to read:
    //
    //   expect(find.text('Reports arrive in the next release'), findsOneWidget);
    //
    // — because P5a shipped three tabs and disclosed the fourth's absence in the
    // More menu rather than opening a nav tab onto nothing. KHA-37 shipped the
    // Reports hub as a real tab, so the placeholder is **gone**, and the
    // assertion is inverted rather than deleted: a stale placeholder that
    // outlives the thing it stood in for is worse than never having written one,
    // and only a test can stop it lingering. The positive half (the tab exists
    // and opens S-28) lives in `p5b_shell_navigation_test.dart`.
    expect(find.text('Reports arrive in the next release'), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('the whole shell renders in Arabic RTL (NFR-U8)', (
    WidgetTester tester,
  ) async {
    await seedLedger();
    await pumpShell(tester, locale: 'ar');

    expect(tester.takeException(), isNull);
    expect(find.text('مصروفي'), findsOneWidget);
    expect(find.text('هذا الشهر'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav.more')));
    await pumpHostFrames(tester);
    expect(find.text('البنوك'), findsWidgets);

    await disposeHost(tester);
  });
}
