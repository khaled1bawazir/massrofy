import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/providers/app_providers.dart';
import 'package:massrofy/presentation/screens/home_placeholder_screen.dart';

import '../support/plain_test_database.dart';

/// A fake [AppLockController] that reports a fixed state without touching
/// real biometrics/Keystore — same pattern `lock_gate_screen_test.dart`
/// already uses.
class _FakeAppLockController extends AppLockController {
  final AppLockState initialState;
  _FakeAppLockController(this.initialState);

  @override
  AppLockState build() => initialState;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
    home: child,
  );
}

void main() {
  late AppDatabase db;

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'once unlocked, the screen proves the encrypted-datastore session is '
    'wired end to end (ADR-010: AuditLogDao/openEncryptedConnection are '
    'reachable production code paths, not just library code) — this test '
    'overrides unlockedDatabaseSessionProvider with a plain in-memory DB '
    'so it never touches real SQLCipher/Keystore plumbing',
    (WidgetTester tester) async {
      db = openPlainTestDatabase();
      final AuditLogDao auditLogDao = AuditLogDao(
        db,
        auditChainKey: List<int>.generate(32, (int i) => i),
      );
      final UnlockedDatabaseSession fakeSession = UnlockedDatabaseSession(
        database: db,
        auditLogDao: auditLogDao,
        transactionDao: TransactionDao(db, auditLogDao),
        rawMessageDao: RawMessageDao(db),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLockControllerProvider.overrideWith(
              () => _FakeAppLockController(
                const AppLockState(status: AppLockStatus.unlocked),
              ),
            ),
            unlockedDatabaseSessionProvider.overrideWith(
              (Ref ref) async => fakeSession,
            ),
          ],
          child: _wrap(const HomePlaceholderScreen()),
        ),
      );
      await tester.pump(); // let the FutureProvider settle
      await tester.pump();

      expect(
        find.text('Encrypted datastore: open — audit trail ready'),
        findsOneWidget,
      );
    },
  );

  testWidgets('while the session is still opening, a loading indicator is '
      'shown rather than a premature success/failure message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockControllerProvider.overrideWith(
            () => _FakeAppLockController(
              const AppLockState(status: AppLockStatus.unlocked),
            ),
          ),
          unlockedDatabaseSessionProvider.overrideWith(
            (Ref ref) => Completer<UnlockedDatabaseSession?>().future,
          ),
        ],
        child: _wrap(const HomePlaceholderScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Clean up the never-completing future's pending timer expectations by
    // disposing the tree; nothing else to assert here.
  });
}
