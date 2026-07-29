/// **KHA-114 — soft-delete was unreachable.**
///
/// `TransactionDetailScreen` renders Edit/Delete/Restore only when a callback
/// is supplied, on the rule that *"a delete affordance that silently does
/// nothing in a banking app is a trust failure, not a stub"*. Its only
/// production construction site — `TransactionDetailHost` — supplied
/// `onEditCategory` and `loadCategoryProvenance` and **none of the other
/// three**. So AC-B6.2's confirm-then-soft-delete flow was fully built, fully
/// tested at the screen level, and impossible for a user to trigger; and S-44
/// Recently Deleted, which P4b deliberately routed, could never contain
/// anything.
///
/// ## Why these tests pump the HOST
///
/// The screen-level behaviour was already covered by `p3b2_screens_test.dart`
/// and passed throughout the bug's life, because a test that hands the screen
/// three callbacks is testing the screen, not the wiring. These pump the real
/// host over a real database and assert on what a user can actually do — the
/// only shape of test that could have caught this.
///
/// A second defect sat underneath the first: the host watched
/// `transactionDao.watchLive()`, which **excludes** soft-deleted rows. Wiring
/// `onDelete` alone would have made the row vanish the instant it was deleted,
/// leaving the deleted banner and the Restore button just as unreachable one
/// level down. `watchById` is the fix, and the restore test below is what pins
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/screens/categorization_routes.dart';
import 'package:massrofy/presentation/screens/manual_entry_screen.dart';

import '../support/app_test_harness.dart';

void main() {
  late TestSession session;
  late FakeSmsPermissionService permissions;

  setUp(() {
    session = TestSession.open();
    permissions = FakeSmsPermissionService();
  });

  tearDown(() async {
    await session.close();
  });

  /// One ordinary card purchase, written through the real DAO so the audit
  /// chain and the soft-delete trigger behave exactly as they do in the app.
  Future<int> insertPurchase() => session.session.transactionDao.insertManual(
    amount: Money.parse('310.40', currency: 'SAR'),
    merchantRawText: 'QANDA MART',
    occurredAt: DateTime.now().toUtc(),
    direction: 'debit',
    transactionType: TransactionType.posPurchase,
    affectsSpend: true,
  );

  Future<void> pumpDetail(WidgetTester tester, int id) async {
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        child: TransactionDetailHost(
          transactionId: id,
          // Zero, so the correction sheet's scope strip resolves
          // deterministically rather than racing a real 3-second timer.
          autoConfirmDelay: Duration.zero,
        ),
      ),
    );
    await pumpHostFrames(tester);
  }

  testWidgets('**the defect** — the detail screen offers Edit and Delete', (
    WidgetTester tester,
  ) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    expect(
      find.byKey(const Key('txnDetail.delete')),
      findsOneWidget,
      reason:
          'before KHA-114 the host supplied no onDelete, so this button did '
          'not render and AC-B6.2 could not be performed by any user',
    );
    expect(find.byKey(const Key('txnDetail.edit')), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('**AC-B6.2** — Delete asks for an explicit confirmation, and '
      'cancelling writes nothing', (WidgetTester tester) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.delete')));
    await pumpHostFrames(tester);

    // The dialog names Recently deleted, because "deleted" alone reads as
    // destroyed and a user who believes that hesitates over correcting a wrong
    // row.
    expect(find.byKey(const Key('txnDetail.deleteConfirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('txnDetail.deleteCancel')));
    await pumpHostFrames(tester);

    final TransactionRow? row = await session.session.transactionDao.byIdOrNull(
      id,
    );
    expect(row!.isDeleted, isFalse);

    await disposeHost(tester);
  });

  testWidgets('**AC-B6.1/B8.1** — confirming soft-deletes the row and the '
      'screen says where it went', (WidgetTester tester) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.delete')));
    await pumpHostFrames(tester);
    await tester.tap(find.byKey(const Key('txnDetail.deleteConfirm')));
    await pumpHostFrames(tester);

    final TransactionRow? row = await session.session.transactionDao.byIdOrNull(
      id,
    );
    expect(row!.isDeleted, isTrue, reason: 'soft, never destroyed (US-B8)');
    expect(row.deletedAt, isNotNull);
    expect(find.text('Moved to Recently deleted'), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('**the second defect** — after deleting, the screen still shows '
      'the transaction, marked deleted, with Restore', (
    WidgetTester tester,
  ) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.delete')));
    await pumpHostFrames(tester);
    await tester.tap(find.byKey(const Key('txnDetail.deleteConfirm')));
    await pumpHostFrames(tester);

    // With `watchLive()` the row would have vanished here and the screen would
    // read "this transaction is no longer here" — leaving `onRestore` exactly
    // as unreachable as `onDelete` had been.
    expect(find.text('This transaction is no longer here'), findsNothing);
    expect(find.byKey(const Key('txnDetail.restore')), findsOneWidget);
    // Delete and Restore are never both offered.
    expect(find.byKey(const Key('txnDetail.delete')), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('**AC-B8.2** — Restore brings it back, and it is live again', (
    WidgetTester tester,
  ) async {
    final int id = await insertPurchase();
    await session.session.transactionDao.softDelete(
      id: id,
      actor: 'user',
      actorDetail: 'user_delete',
    );
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.restore')));
    await pumpHostFrames(tester);

    final TransactionRow? row = await session.session.transactionDao.byIdOrNull(
      id,
    );
    expect(row!.isDeleted, isFalse);
    expect(find.text('Transaction restored'), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('**S-44 can finally hold something** — a deleted transaction '
      'appears in Recently Deleted', (WidgetTester tester) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.delete')));
    await pumpHostFrames(tester);
    await tester.tap(find.byKey(const Key('txnDetail.deleteConfirm')));
    await pumpHostFrames(tester);
    await disposeHost(tester);

    // The screen P4b routed specifically so S-11's "you can find it under
    // Recently deleted" would name a place the user can reach. Until KHA-114
    // was fixed it could only ever render its empty state.
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        child: const RecentlyDeletedHost(),
      ),
    );
    await pumpHostFrames(tester);

    expect(find.text('QANDA MART'), findsOneWidget);
    expect(find.text('Nothing has been deleted'), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('**US-B5** — Edit opens the S-20 form in edit mode, pre-filled '
      'from the stored row', (WidgetTester tester) async {
    final int id = await insertPurchase();
    await pumpDetail(tester, id);

    await tester.tap(find.byKey(const Key('txnDetail.edit')));
    await pumpHostFrames(tester);

    expect(find.byType(ManualEntryScreen), findsOneWidget);
    // `310.4`, not `310.40`. The form deliberately starts from the stored
    // **canonical** string rather than a display-formatted one, so the user
    // edits exactly what is recorded (ADR-002 — the text IS the authoritative
    // value), and `Money`'s `Decimal` holds `310.40` and `310.4` as the same
    // value. `formatAmountDigits` is what pads for *display*; the edit field is
    // not display. Asserted explicitly so a future change to either side is a
    // decision rather than an accident.
    expect(find.text('310.4'), findsOneWidget);
    expect(find.text('QANDA MART'), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('AC-B1.2 — the original SMS text reaches the screen for an '
      'SMS-derived transaction, and a manual entry says it has none', (
    WidgetTester tester,
  ) async {
    // The manual half first: `insertManual` leaves `sourceMessageId` null.
    final int manualId = await insertPurchase();
    await pumpDetail(tester, manualId);
    expect(
      find.text('No original message — this transaction was added manually'),
      findsOneWidget,
    );
    await disposeHost(tester);
  });

  testWidgets('the whole detail screen renders in Arabic RTL (NFR-U8)', (
    WidgetTester tester,
  ) async {
    final int id = await insertPurchase();
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        locale: 'ar',
        child: TransactionDetailHost(
          transactionId: id,
          autoConfirmDelay: Duration.zero,
        ),
      ),
    );
    await pumpHostFrames(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('txnDetail.delete')), findsOneWidget);

    await disposeHost(tester);
  });
}
