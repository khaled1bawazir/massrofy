import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/screens/lock_gate_screen.dart';

/// A fake [AppLockController] that renders a fixed [AppLockState] and never
/// touches real biometrics/Keystore — [LockGateScreen] calls
/// `authenticate()` from `initState`, which this fake turns into a no-op so
/// the widget test only exercises **rendering**, matching each state in
/// `docs/mockups/lock-gate.html` — not the real authentication flow (that
/// is `app_lock_controller_test.dart`'s job).
class _FakeAppLockController extends AppLockController {
  final AppLockState initialState;
  _FakeAppLockController(this.initialState);

  @override
  AppLockState build() => initialState;

  @override
  Future<void> authenticate() async {
    // no-op: widget tests only assert on the state this fake was seeded
    // with, they never drive a real authentication attempt.
  }
}

Widget _wrap(Widget child, AppLockState state) {
  return ProviderScope(
    overrides: [
      appLockControllerProvider.overrideWith(
        () => _FakeAppLockController(state),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
      home: child,
    ),
  );
}

void main() {
  testWidgets(
    'idle/locked state shows the unlock headline and biometric hint',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const LockGateScreen(), const AppLockState.locked()),
      );
      await tester.pump();

      expect(find.text('Unlock to view your data'), findsOneWidget);
      expect(find.text('Place your finger on the sensor'), findsOneWidget);
    },
  );

  testWidgets(
    'AC-F1.2 — nothing that looks like transaction data, a total, or a card '
    'identifier is ever rendered on the lock gate',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const LockGateScreen(), const AppLockState.locked()),
      );
      await tester.pump();

      // The screen exists to show *nothing* financial — assert the app's
      // wordmark and lock copy are present and nothing resembling an
      // amount/currency string appears anywhere in the tree.
      expect(find.textContaining('SAR'), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    },
  );

  testWidgets('failed state shows the generic error banner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LockGateScreen(),
        const AppLockState(status: AppLockStatus.failed),
      ),
    );
    await tester.pump();

    expect(find.text('Authentication failed. Try again.'), findsOneWidget);
  });

  testWidgets('locked-out state shows the too-many-attempts headline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LockGateScreen(),
        AppLockState(
          status: AppLockStatus.lockedOut,
          lockedOutUntil: DateTime.now().add(const Duration(seconds: 30)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Too many attempts'), findsOneWidget);
    // The "use passcode" retry link is intentionally hidden *while the
    // cooldown is still running* — see the countdown group below for what
    // happens once it elapses.
    expect(find.text('Use device passcode instead'), findsNothing);

    // The countdown ticker is now genuinely running; wind it down so the
    // test does not end with a pending periodic Timer.
    await tester.pumpAndSettle(const Duration(seconds: 31));
  });

  group('KHA-75 — the locked-out countdown actually counts down', () {
    // A clock the test moves by hand, kept in lock-step with the fake-async
    // clock that `tester.pump(duration)` advances. `DateTime.now()` is NOT
    // advanced by `pump`, so without this the countdown text could never
    // change in a widget test no matter how correct the code is — see
    // `LockGateScreen.clock`'s doc comment.
    late DateTime fakeNow;
    DateTime clock() => fakeNow;

    /// Advances both clocks together by [seconds] one second at a time, so
    /// each `Timer.periodic` tick sees a correspondingly newer "now".
    Future<void> tick(WidgetTester tester, int seconds) async {
      for (int i = 0; i < seconds; i++) {
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    setUp(() => fakeNow = DateTime(2026, 7, 28, 12));

    testWidgets('the "retry in mm:ss" subtitle decrements once a second '
        '(it used to be computed once and then sit frozen forever, because '
        'the screen\'s Timer field was declared and disposed but never '
        'started)', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LockGateScreen(clock: clock),
          AppLockState(
            status: AppLockStatus.lockedOut,
            lockedOutUntil: fakeNow.add(const Duration(seconds: 30)),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('00:30'), findsOneWidget);

      await tick(tester, 3);

      expect(
        find.textContaining('00:30'),
        findsNothing,
        reason: 'the countdown must move on from its initial value',
      );
      expect(find.textContaining('00:27'), findsOneWidget);

      // Let the ticker stop itself so the test ends with no pending timers.
      await tick(tester, 28);
    });

    testWidgets('once the cooldown elapses the retry affordance comes back, '
        'so the user is not stranded on a dead screen until they '
        'force-quit the app', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LockGateScreen(clock: clock),
          AppLockState(
            status: AppLockStatus.lockedOut,
            lockedOutUntil: fakeNow.add(const Duration(seconds: 2)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Use device passcode instead'), findsNothing);

      await tick(tester, 3);

      expect(find.text('Use device passcode instead'), findsOneWidget);
      expect(
        find.textContaining('00:00'),
        findsNothing,
        reason: 'a spent countdown should not linger as "retry in 00:00"',
      );
      // The whole screen flips together — a "Too many attempts" headline
      // sitting above a working retry button reads as a bug.
      expect(find.text('Too many attempts'), findsNothing);
      expect(find.text('Unlock to view your data'), findsOneWidget);
    });

    testWidgets('a null lockedOutUntil is treated as already elapsed, never '
        'as an infinite lockout', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          LockGateScreen(clock: clock),
          const AppLockState(status: AppLockStatus.lockedOut),
        ),
      );
      await tester.pump();

      expect(find.text('Use device passcode instead'), findsOneWidget);
    });
  });

  testWidgets('session-expired state shows the background-session banner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LockGateScreen(),
        const AppLockState(status: AppLockStatus.sessionExpired),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(
        'Your session ended while the app was in the background',
      ),
      findsOneWidget,
    );
    expect(find.text('Unlock to continue'), findsOneWidget);
  });

  testWidgets('renders correctly under Arabic RTL locale (NFR-U8)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockControllerProvider.overrideWith(
            () => _FakeAppLockController(const AppLockState.locked()),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: <LocalizationsDelegate<Object?>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: <Locale>[Locale('ar'), Locale('en')],
          home: LockGateScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('افتح القفل لعرض بياناتك'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('افتح القفل لعرض بياناتك'))),
      TextDirection.rtl,
    );
  });
}
