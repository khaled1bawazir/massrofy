/// **KHA-113 — the app never asked for SMS permission.**
///
/// On a fresh install, `SmsPermissionRationaleScreen` had no route and
/// `SmsPermissionService.request()` had no caller anywhere in `lib/`, so the
/// product's entire value proposition never activated: the app sat on "no
/// transactions" forever and the only way to a working install was a trip into
/// Android Settings the user has no reason to know about.
///
/// ## What these tests are, that a screen test is not
///
/// Every screen involved here was **already built and already tested** before
/// KHA-113 was filed. The defect was in the *wiring*, and a test that renders
/// `SmsPermissionRationaleScreen` directly cannot see wiring at all — it would
/// have passed throughout the bug's life. So these pump the real
/// `OnboardingGate` with the real providers behind it and assert on what a
/// fresh install actually reaches.
///
/// The one thing faked is the platform: the lock controller (Keystore +
/// biometrics) and the SMS permission service. The database, the settings DAO
/// and every stream over them are real.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/presentation/screens/app_shell.dart';
import 'package:massrofy/presentation/screens/onboarding_gate.dart';
import 'package:massrofy/presentation/screens/sms_limited_mode_screen.dart';
import 'package:massrofy/presentation/screens/sms_permission_rationale_screen.dart';

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

  /// [relaunch] gives the gate a fresh `Key`, which forces Flutter to build a
  /// new `State` instead of reusing the existing one — i.e. it models an app
  /// **relaunch** rather than a rebuild. Without it, pumping the gate a second
  /// time in one test would carry the first journey's in-session step over,
  /// and the test would be asserting the wrong thing.
  Future<void> pumpGate(
    WidgetTester tester, {
    String locale = 'en',
    bool relaunch = false,
  }) async {
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        locale: locale,
        child: OnboardingGate(key: relaunch ? const Key('relaunch') : null),
      ),
    );
    // Two settles: the session future, then the settings read.
    await pumpHostFrames(tester);
  }

  testWidgets('**the defect** — a fresh install with no SMS permission lands '
      'on the S-02 rationale screen', (WidgetTester tester) async {
    permissions.current = SmsPermissionStatus.denied;

    await pumpGate(tester);

    expect(
      find.byType(SmsPermissionRationaleScreen),
      findsOneWidget,
      reason:
          'before KHA-113 this screen had no construction site anywhere in '
          'lib/ and a fresh install went straight to an empty dashboard',
    );
    expect(find.text('Why Massrofy needs SMS access'), findsOneWidget);
    // Nothing has been asked of the OS yet — the rationale comes FIRST
    // (design flag D-9), because Android gives an app effectively one prompt.
    expect(permissions.requestCalls, 0);

    await disposeHost(tester);
  });

  testWidgets('**the other half of the defect** — pressing Grant actually '
      'calls SmsPermissionService.request(), which nothing in lib/ did', (
    WidgetTester tester,
  ) async {
    permissions.current = SmsPermissionStatus.denied;
    permissions.requestResult = SmsPermissionStatus.granted;

    await pumpGate(tester);
    await tester.tap(find.text('Grant SMS access'));
    await pumpHostFrames(tester);

    expect(permissions.requestCalls, 1);
    // Granted → straight into the app.
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(SmsPermissionRationaleScreen), findsNothing);

    await disposeHost(tester);
  });

  testWidgets('a DENIED outcome lands on S-04 limited mode, never on an '
      'unexplained empty screen (AC-A1.2)', (WidgetTester tester) async {
    permissions.current = SmsPermissionStatus.denied;
    permissions.requestResult = SmsPermissionStatus.denied;

    await pumpGate(tester);
    await tester.tap(find.text('Grant SMS access'));
    await pumpHostFrames(tester);

    expect(permissions.requestCalls, 1);
    expect(find.byType(SmsLimitedModeScreen), findsOneWidget);
    // AC-A1.3's second half travels with the screen: the frightening sentence
    // never appears without the reassuring one.
    expect(
      find.textContaining('still intact'),
      findsOneWidget,
      reason:
          'a user who reads "SMS access stopped" with no further information '
          'reasonably reinstalls, which would actually destroy their history',
    );

    await disposeHost(tester);
  });

  testWidgets('"Not now" also reaches limited mode — declining is a route, '
      'not a dead end', (WidgetTester tester) async {
    await pumpGate(tester);
    await tester.tap(find.text('Not now'));
    await pumpHostFrames(tester);

    expect(find.byType(SmsLimitedModeScreen), findsOneWidget);
    // The OS dialog was never raised, which is the point of "Not now": it must
    // not spend the one prompt Android will show.
    expect(permissions.requestCalls, 0);

    await disposeHost(tester);
  });

  testWidgets('S-04 offers a way INTO the app — PRD D-9\'s "the app must '
      'remain usable"', (WidgetTester tester) async {
    await pumpGate(tester);
    await tester.tap(find.text('Not now'));
    await pumpHostFrames(tester);

    await tester.tap(find.byKey(const Key('smsLimited.continue')));
    await pumpHostFrames(tester);

    expect(find.byType(AppShell), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('a PERMANENTLY denied status offers system settings instead of '
      'a Grant button that Android would silently no-op', (
    WidgetTester tester,
  ) async {
    permissions.current = SmsPermissionStatus.denied;
    permissions.requestResult = SmsPermissionStatus.permanentlyDenied;

    await pumpGate(tester);
    await tester.tap(find.text('Grant SMS access'));
    await pumpHostFrames(tester);

    expect(find.text('Open system settings'), findsOneWidget);
    await tester.tap(find.text('Open system settings'));
    await pumpHostFrames(tester);
    expect(permissions.openSettingsCalls, 1);

    await disposeHost(tester);
  });

  testWidgets('**the flag is set on DECLINE too** — a second launch shows the '
      'app, not the rationale screen the user already read', (
    WidgetTester tester,
  ) async {
    await pumpGate(tester);
    await tester.tap(find.text('Not now'));
    await pumpHostFrames(tester);

    final AppSettingsRow settings = await session.session.appSettingsDao
        .current();
    expect(
      settings.onboardingComplete,
      isTrue,
      reason:
          'the flag means "we have asked", not "we succeeded" — see '
          'app_settings_dao.dart',
    );

    // A fresh gate over the same database, as a relaunch would be.
    await pumpGate(tester, relaunch: true);
    expect(find.byType(SmsPermissionRationaleScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);

    await disposeHost(tester);
  });

  testWidgets('a user who ALREADY has permission never sees onboarding at '
      'all', (WidgetTester tester) async {
    permissions.current = SmsPermissionStatus.granted;

    await pumpGate(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(SmsPermissionRationaleScreen), findsNothing);
    expect(permissions.requestCalls, 0);

    await disposeHost(tester);
  });

  testWidgets('**AC-A1.3** — permission revoked AFTER onboarding shows the '
      'app with a banner, not the onboarding flow again', (
    WidgetTester tester,
  ) async {
    // The state Android 11+ produces on its own for an app left unused for a
    // few months. It reads `denied` exactly like a fresh install, which is why
    // the persisted flag has to exist at all.
    await session.session.appSettingsDao.markOnboardingComplete();
    permissions.current = SmsPermissionStatus.denied;

    await pumpGate(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(SmsPermissionRationaleScreen), findsNothing);
    expect(
      find.byType(SmsAccessRevokedBanner),
      findsOneWidget,
      reason:
          'taking over the whole app would hide the very data the banner '
          'exists to say is still intact',
    );

    await disposeHost(tester);
  });

  testWidgets('the whole journey renders in Arabic RTL (NFR-U8)', (
    WidgetTester tester,
  ) async {
    await pumpGate(tester, locale: 'ar');
    expect(find.byType(SmsPermissionRationaleScreen), findsOneWidget);
    expect(find.text('لماذا يحتاج مصروفي إلى إذن الرسائل'), findsOneWidget);

    await tester.tap(find.text('ليس الآن'));
    await pumpHostFrames(tester);
    expect(find.byType(SmsLimitedModeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeHost(tester);
  });
}
