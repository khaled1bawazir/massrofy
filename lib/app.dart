import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async' show unawaited;

import 'features/security/app_lock_controller.dart';
import 'features/security/app_lock_state.dart';
import 'presentation/l10n/generated/app_localizations.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/ingestion_providers.dart';
import 'presentation/providers/ledger_providers.dart';
import 'presentation/screens/lock_gate_screen.dart';
import 'presentation/screens/onboarding_gate.dart';
import 'presentation/theme/app_theme.dart';

/// The app's root widget.
///
/// ## RTL/locale bootstrap (NFR-U8)
/// `supportedLocales` lists **Arabic first** — Arabic is this product's
/// primary, first-designed layout (`docs/design.md` §3.1), with English as
/// a fully-supported second locale. `locale` is left `null`, which tells
/// `MaterialApp` to resolve the locale from the OS via
/// `localeListResolutionCallback`'s default behaviour — i.e. the app
/// launches in Arabic (and therefore RTL, since `flutter_localizations`'
/// Arabic `GlobalMaterialLocalizations` reports `TextDirection.rtl`) on a
/// device set to Arabic, and in English/LTR otherwise, with no manual
/// `Directionality` override required anywhere: Flutter derives text
/// direction from the resolved `Locale` automatically for every widget that
/// asks `Directionality.of(context)`.
class MassrofyApp extends ConsumerWidget {
  const MassrofyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Forces the DI wiring in app_providers.dart to run once, at startup,
    // before anything reads `appLockControllerProvider`.
    ref.watch(appLockControllerConfiguratorProvider);

    return MaterialApp(
      title: 'Massrofy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      supportedLocales: const <Locale>[
        Locale('ar'), // primary — see class doc comment
        Locale('en'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppLockGateway(),
    );
  }
}

/// Chooses between [LockGateScreen] and [OnboardingGate] based on
/// [AppLockController]'s state, and wires the app-lifecycle observer that
/// re-locks on background (ADR-005) and obscures the app-switcher snapshot
/// (ADR-014).
///
/// ## Where the rest of the navigation lives
///
/// This gateway is still the app's only *root*: everything a user can reach
/// hangs off [OnboardingGate] → `AppShell`, which is what keeps ADR-005's
/// guarantee checkable — no screen exists above the lock gate.
///
/// The **navigation graph itself** lives in three files, and nowhere else.
/// `docs/lessons.md` records that *"'unreachable today' is a claim about
/// **navigation**, not about code"* and that a reachability question must be
/// answered *"by grepping for the construction site, never from the fact that
/// the widget exists in the tree."* These are the places to grep:
///
/// | File | Routes |
/// |---|---|
/// | `screens/app_shell.dart` | the `BottomNav` tabs and the More menu (S-40) |
/// | `screens/ledger_routes.dart` | S-10 list, S-21/22 banks, S-23/24 instruments, S-20 add/edit, S-05 import progress |
/// | `screens/categorization_routes.dart` | S-18 review inbox, S-14/15 categories, S-16/17 rules, S-11 detail, S-44 recently deleted, the S-12/13 correction sheet |
///
/// `screens/onboarding_gate.dart` constructs S-02/S-04 — the permission
/// journey. It is a *journey* rather than a destination, which is why it sits
/// above the shell instead of inside one of the route files.
///
/// Kept as its own tiny widget (rather than inlined into [MassrofyApp])
/// specifically so it can host a [WidgetsBindingObserver] with the
/// `State` object's own lifecycle — `MassrofyApp` itself has no reason to
/// be a `StatefulWidget` otherwise.
class _AppLockGateway extends ConsumerStatefulWidget {
  const _AppLockGateway();

  @override
  ConsumerState<_AppLockGateway> createState() => _AppLockGatewayState();
}

class _AppLockGatewayState extends ConsumerState<_AppLockGateway>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ADR-006: tell the Kotlin side which Dart function the background
    // WorkManager job should start, and arm the Layer-2 periodic sweep.
    //
    // Deferred to after the first frame because it crosses a platform
    // channel, and `initState` runs before the binding has finished wiring
    // one up. `unawaited` is correct rather than lazy: nothing on screen
    // depends on the result, and a failure here degrades to "foreground
    // sweeps only", which is a working app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        registerBackgroundIngestion(ref.read(smsPermissionServiceProvider)),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppLockController controller = ref.read(
      appLockControllerProvider.notifier,
    );
    final bool wasUnlocked = ref.read(appLockControllerProvider).isUnlocked;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // ADR-005 re-lock policy: default grace is 0 seconds (lock
        // immediately). A configurable grace period (0/15/30/60s) is a
        // Settings feature for a later phase; this P1 slice implements the
        // secure default.
        ref.read(privacyGateProvider).setObscured(true);
        if (wasUnlocked) {
          controller.lock();
        }
      case AppLifecycleState.resumed:
        ref.read(privacyGateProvider).setObscured(false);
        final AppLockStatus status = ref.read(appLockControllerProvider).status;
        if (status == AppLockStatus.locked) {
          controller.authenticate();
        }
        // ADR-006's permission auto-reset check: Android 11+ can revoke
        // RECEIVE_SMS/READ_SMS on its own if the app goes unused for months.
        // Re-reading on every foreground is what makes the AC-A1.3 warning
        // appear at all, instead of the app silently capturing nothing.
        ref.invalidate(smsPermissionStatusProvider);
        // ADR-006 Layer 2's foreground trigger. See `foregroundSweepProvider`
        // — this is currently the layer doing the real work on any wake where
        // the app was locked, and the watermark guarantees it picks up
        // everything since the last successful run.
        //
        // **Kept exactly as it was by KHA-122.** The new broadcast-driven
        // trigger (see the `unlocked` branch in `build`) covers the
        // app-stays-open case; this covers everything that arrived while the app
        // was away, when no engine was listening for a signal at all. They are
        // not redundant, and the dedup path makes the overlap safe.
        ref.invalidate(foregroundSweepProvider);
        // **AC-E1.4** — *"when the user opens the app on the 1st, the
        // current-month total resets to the new month."* A resume is the only
        // moment the app can notice the clock has crossed a month boundary
        // while it was in the background, and this is where a resume is
        // already being handled. A no-op unless the month genuinely turned
        // over AND the user has not paged back to an older month — see
        // `PeriodRangeNotifier.refreshIfTrackingCurrentMonth`, which owns that
        // distinction so this call site does not have to.
        ref.read(ledgerPeriodProvider.notifier).refreshIfTrackingCurrentMonth();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// **NFR-S3 — collapse the navigation stack the moment the app locks.**
  ///
  /// This widget is `MaterialApp.home`, i.e. the content of the **first** route
  /// in the Navigator. Every screen the user pushes — the banks list, an
  /// instrument's transactions, the review inbox — is drawn in an *opaque route
  /// above it*. So swapping this widget to [LockGateScreen] hides nothing on
  /// its own: the pushed screen keeps covering the gate.
  ///
  /// That was harmless while `HomePlaceholderScreen` was the only destination
  /// and nothing was pushed. P5a is the phase that makes it reachable, which is
  /// precisely the shape `docs/lessons.md` warns about — *"'unreachable today'
  /// is a claim about navigation, not about code — it expires the moment
  /// someone adds a route, silently."* This PR adds the routes, so it closes
  /// the hole in the same change.
  ///
  /// Two things already limit the blast radius and neither is sufficient alone:
  /// `privacyGateProvider` covers the app-switcher snapshot (ADR-014), and
  /// every provider yields empty while locked (ADR-005), so a pushed screen
  /// re-renders as its locked/empty state rather than showing figures. This
  /// makes the guarantee structural instead of emergent: after a lock there is
  /// nothing above the gate at all.
  void _collapseToLockGate() {
    // Deferred to after the frame: this runs from a provider listener, which
    // can fire mid-build, and mutating the Navigator during a build is illegal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((Route<Object?> route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fires on every lock, whichever path caused it — backgrounding, the
    // session expiring, or the More menu's "Lock now".
    ref.listen<AppLockState>(appLockControllerProvider, (
      AppLockState? previous,
      AppLockState next,
    ) {
      if ((previous?.isUnlocked ?? false) && !next.isUnlocked) {
        _collapseToLockGate();
      }
    });

    final bool unlocked = ref.watch(appLockControllerProvider).isUnlocked;

    if (unlocked) {
      // Watching (not reading) is what makes the sweep run on unlock as well
      // as on resume: the provider is rebuilt the moment the database session
      // becomes available, which is the first instant ingestion is possible
      // at all (ADR-005 — no unwrapped key means no database to write to).
      //
      // The AsyncValue itself is intentionally not rendered. The result of a
      // sweep reaches the UI through Drift streams on the ledger and the
      // review queue, not through this future — architecture §7.5's
      // "reactive, no polling".
      ref.watch(foregroundSweepProvider);

      // **KHA-122 / AC-A1.1 — the third trigger, and the one that was missing.**
      //
      // Until this line there were exactly two: this `watch` (fires on unlock)
      // and `didChangeAppLifecycleState`'s `invalidate` (fires on resume). An
      // app left open and idle on Home hits neither, so an SMS arriving during
      // a live session was not ingested until the user backgrounded and
      // reopened — while the screen said `0.00 SAR` and "All caught up". QA
      // found that on a device during the P5a walk.
      //
      // `foregroundSmsSignalProvider` invalidates `foregroundSweepProvider`
      // itself, so this is a **keep-alive**, not a read: the value is
      // deliberately unused. Watching is what holds the `EventChannel`
      // subscription open, and putting it inside the `unlocked` branch is what
      // ties the subscription's lifetime to the only state in which acting on
      // it is legal (ADR-005 — the UI isolate holds the key; ADR-018 D1 — no
      // background isolate does).
      //
      // The rebuild cost of an emission is one call to this `build`: the
      // returned `const OnboardingGate()` is a canonicalised constant, so
      // Flutter sees the identical widget instance and skips the subtree
      // entirely.
      ref.watch(foregroundSmsSignalProvider);
    }

    // **NFR-S3, and the one place it is enforced.** Every P5a screen is
    // constructed inside `OnboardingGate` → `AppShell` → the route files, all
    // of which hang off this single expression's `true` branch. Nothing the
    // user can reach is built in the `false` branch, so "every screen sits
    // behind the app lock" is checkable by reading one line rather than by
    // auditing thirty widgets.
    return unlocked ? const OnboardingGate() : const LockGateScreen();
  }
}
