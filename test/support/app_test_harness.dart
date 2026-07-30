/// A harness for tests that exercise the app's **hosts** rather than its
/// screens — P5a (KHA-113, KHA-114).
///
/// ## Why this exists
///
/// Almost every widget test in this suite renders a pure screen over plain
/// values, which needs no harness at all. But the three P5a defects were all
/// *wiring* defects — a screen that existed and was never constructed, a
/// construction site that omitted three callbacks — and a test that renders the
/// screen directly cannot see any of them. Catching that class of bug means
/// pumping the real `Consumer` host with the real providers behind it, over a
/// real (if plain, in-memory) database.
///
/// Everything the harness fakes is a **platform channel**: the lock controller
/// (Keystore + biometrics) and the SMS permission service. The database, the
/// DAOs, the categorization service and every stream over them are the real
/// implementations, because those are exactly what the wiring has to reach.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/app_settings_dao.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/sms_broadcast_signal.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/providers/app_providers.dart';
import 'package:massrofy/presentation/providers/ingestion_providers.dart';

import 'plain_test_database.dart';

/// Reports a fixed lock state without touching real biometrics or the
/// Keystore — the same pattern `lock_gate_screen_test.dart` uses.
class FakeAppLockController extends AppLockController {
  final AppLockState initialState;

  FakeAppLockController([
    this.initialState = const AppLockState(status: AppLockStatus.unlocked),
  ]);

  @override
  AppLockState build() => initialState;
}

/// A scriptable [SmsPermissionService].
///
/// Records every call, so a test can assert the thing KHA-113 was actually
/// about: **that `request()` is called at all**, and only after the rationale
/// screen has been shown.
class FakeSmsPermissionService implements SmsPermissionService {
  /// What `status()` reports.
  SmsPermissionStatus current;

  /// What `request()` resolves to. Defaults to whatever [current] is, so a
  /// test that only cares about "was it asked" needs to script nothing.
  SmsPermissionStatus? requestResult;

  int requestCalls = 0;
  int openSettingsCalls = 0;

  FakeSmsPermissionService({
    this.current = SmsPermissionStatus.denied,
    this.requestResult,
  });

  @override
  Future<SmsPermissionStatus> status() async => current;

  @override
  Future<SmsPermissionStatus> request() async {
    requestCalls++;
    current = requestResult ?? current;
    return current;
  }

  @override
  Future<void> openAppSettings() async => openSettingsCalls++;

  @override
  Future<void> registerBackgroundEntrypoint(int callbackHandle) async {}

  @override
  Future<void> requestImmediateSweep() async {}
}

/// A hand-driven [SmsBroadcastSignal] — **KHA-122**.
///
/// The Kotlin side raises the real signal from a `BroadcastReceiver`, which no
/// widget test has. This lets a test say "an SMS just arrived" and then assert
/// what the app did about it, which is the only way to cover the defect: the
/// screen-level symptom was a *missing trigger*, and no test that renders a
/// screen over fixed values can see one of those.
class FakeSmsBroadcastSignal implements SmsBroadcastSignal {
  // Broadcast, not single-subscription: the provider may resubscribe after a
  // rebuild, and a single-subscription controller would throw on the second
  // listen rather than reporting the behaviour under test.
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get incoming => _controller.stream;

  /// Delivers one *"an SMS arrived"* marker.
  void emit() => _controller.add(null);

  Future<void> close() => _controller.close();
}

/// A real, plain in-memory [UnlockedDatabaseSession] plus its database.
///
/// The caller owns closing it — `addTearDown(session.close)`.
class TestSession {
  final AppDatabase database;
  final UnlockedDatabaseSession session;

  TestSession(this.database, this.session);

  static TestSession open() {
    final AppDatabase db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      // A fixed key: the audit chain's correctness is `audit_log_dao_test`'s
      // subject, not this harness's, and a deterministic key keeps failures
      // reproducible.
      auditChainKey: List<int>.generate(32, (int i) => i),
    );
    return TestSession(
      db,
      UnlockedDatabaseSession(
        database: db,
        auditLogDao: auditLogDao,
        transactionDao: TransactionDao(db, auditLogDao),
        rawMessageDao: RawMessageDao(db),
        appSettingsDao: AppSettingsDao(db),
      ),
    );
  }

  Future<void> close() => database.close();
}

/// A `ProviderScope` with everything a host test needs overridden, wrapping
/// [child] in a fully localised `MaterialApp`.
///
/// Returns the widget rather than a `List<Override>` for a mundane reason worth
/// stating so nobody "tidies" it back: `flutter_riverpod` does not export the
/// `Override` type, so a helper cannot name it in a return signature. Inside a
/// literal the parameter's context infers it, which is why the list below has
/// no explicit element type while the rest of this codebase does.
///
/// [clock] pins the ambient "now" — see the parameter's own note below.
Widget hostScope({
  required TestSession session,
  required SmsPermissionService permissions,
  required Widget child,
  AppLockState lockState = const AppLockState(status: AppLockStatus.unlocked),
  String locale = 'en',
  double textScale = 1.0,
  SmsBroadcastSignal? smsSignal,

  /// **KHA-161** — the wall clock, which is a device dependency like any other.
  ///
  /// Everything else this harness overrides is a platform channel; the clock is
  /// the one ambient input it left real. That is fine for a test whose subject
  /// has no calendar arithmetic in it, and a latent time bomb for one whose
  /// subject does: several of this product's rules are *defined* against the
  /// Riyadh month boundary (AC-A3.1, AC-E1.4), so a test with hard-dated
  /// fixtures and a live clock passes until the month it was written in ends.
  ///
  /// **Pass a [FixedClock] from any host test whose fixtures carry absolute
  /// dates.** Left `null` the real [SystemClock] stays in place, so no existing
  /// caller changes behaviour — this is opt-in on purpose rather than a
  /// harness-wide default, because a shared default instant would silently
  /// re-date fixtures in files nobody was looking at.
  Clock? clock,
}) => ProviderScope(
  overrides: [
    // A conditional element inside a collection literal (`if (x) value,`) —
    // Dart's way of building a list with an optional entry, and the reason the
    // override is simply absent rather than present-but-neutral when no clock
    // is supplied.
    if (clock != null) clockProvider.overrideWithValue(clock),
    appLockControllerProvider.overrideWith(
      () => FakeAppLockController(lockState),
    ),
    unlockedDatabaseSessionProvider.overrideWith(
      (Ref ref) async => lockState.isUnlocked ? session.session : null,
    ),
    smsPermissionServiceProvider.overrideWithValue(permissions),
    // **KHA-122.** Overridden unconditionally, even though most host tests never
    // build `foregroundSmsSignalProvider`: the real implementation opens an
    // `EventChannel` on a platform that does not exist in `flutter test`, and a
    // harness that leaves one platform boundary un-faked is a harness that fails
    // mysteriously the first time some screen happens to reach it. The default is
    // a signal that never fires, which is the correct neutral behaviour for a
    // test that is not about ingestion.
    smsBroadcastSignalProvider.overrideWithValue(
      smsSignal ?? FakeSmsBroadcastSignal(),
    ),
  ],
  child: wrapHost(child, locale: locale, textScale: textScale),
);

/// A `MaterialApp` with both locales wired, matching `app.dart`'s own setup so
/// a host test exercises the same localisation path the real app does.
Widget wrapHost(Widget child, {String locale = 'en', double textScale = 1.0}) =>
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
      builder: (BuildContext context, Widget? navigator) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: navigator!,
      ),
      home: child,
    );

/// Advances futures, streams and route transitions **without** waiting for the
/// tree to go quiet.
///
/// `tester.pumpAndSettle()` is the reflex here and it is the wrong tool for
/// these screens: they render `CircularProgressIndicator`s, which animate
/// forever by design, so "settled" never arrives and the test hangs until
/// `pumpAndSettle`'s ten-minute timeout. Pumping a fixed number of small frames
/// resolves every microtask and every route transition (~300 ms) while
/// tolerating an indicator that is still spinning somewhere on screen.
Future<void> pumpHostFrames(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Tears the widget tree down and lets Drift's stream-cleanup timers fire.
///
/// **Call this as the last line of any host test**, or the test fails with
/// *"A Timer is still pending even after the widget tree was disposed"* even
/// though every assertion passed.
///
/// Why: cancelling a Drift query stream schedules a zero-duration cleanup timer
/// (`StreamQueryStore.markAsClosed`) — the same behaviour
/// `categorization_providers.dart` documents as its reason for holding a single
/// subscription for a provider's whole lifetime. The binding disposes the tree
/// and then immediately asserts that no timers are pending, so the flush has to
/// happen inside the test body. `addTearDown` is too late: it runs after
/// `_verifyInvariants`.
Future<void> disposeHost(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

/// Gives a host test a tall surface.
///
/// These screens are scrolling lists, and a `ListView` builds lazily: on the
/// default 800x600 test window a control near the bottom is never constructed,
/// so a finder for it fails for a reason that has nothing to do with the
/// behaviour under test.
void useTallHostSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
