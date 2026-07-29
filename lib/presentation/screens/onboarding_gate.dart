/// **KHA-113 — the journey that makes the product start working.**
///
/// Mockup: `docs/mockups/onboarding.html`. Screens S-02, S-04, S-05.
///
/// ---
///
/// ## The defect this closes
///
/// QA's first fresh-install walk found that Massrofy **never asks for SMS
/// permission**. `SmsPermissionRationaleScreen` had no route,
/// `SmsPermissionService.request()` had no caller anywhere in `lib/`, and the
/// app therefore sat on "no transactions" forever — the entire value
/// proposition inert, with the only route to a working app being a trip into
/// Android Settings the user has no reason to know about.
///
/// `SmsPermissionService.request()`'s own doc comment already said *"must only
/// be called after the user has seen the rationale screen"*. This file is the
/// caller that comment was written for.
///
/// ## Three states, three screens, and why they must not be collapsed
///
/// ```
///                       has the user been asked before?
///                     no                            yes
///                     │                              │
///        S-02 rationale (AC-A1.2)          permission granted?
///                     │                       yes        no
///          "Grant" ───┴─── "Not now"           │          │
///              │             │              the app    the app +
///     OS dialog (S-03)       │              (+ S-05    AC-A1.3
///        │         │         │              progress)  banner
///     granted    denied      │
///        │         │         │
///      the app   S-04 limited mode (AC-A1.2 / D-9)
/// ```
///
/// The two "no permission" leaves look identical to a naive check — both read
/// `denied` from the OS — and they demand opposite screens. Someone who has
/// never been asked needs the rationale; someone whose access Android revoked
/// after months of disuse (ADR-006) needs to be told **ingestion stopped and
/// their data is intact** (AC-A1.3), on top of the app, *not* an onboarding
/// flow that implies they are starting over. The `onboarding_complete` flag in
/// `app_settings` is what tells them apart — see `app_settings_dao.dart`.
///
/// ## Android gives you effectively one prompt
///
/// After a second denial the OS dialog stops appearing at all, silently and
/// permanently, and the only recovery is a Settings trip most people never
/// make. That is why S-02 exists at all (design flag D-9) and why this gate
/// never fires `request()` before it has been shown. It is also why the
/// rationale is shown **once per install** rather than on every launch: nagging
/// spends the one prompt.
///
/// ## The app is never a dead end (PRD D-9)
///
/// Every leaf reaches the app. Declining at S-02 goes to S-04, and S-04 offers
/// three ways forward — retry, open system settings, or continue into
/// Massrofy with manual entry as the path. A spending tracker that a user
/// cannot use because they said no to one permission has failed them twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../features/ingestion/sms_permission_service.dart';
import '../providers/app_providers.dart';
import '../providers/ingestion_providers.dart';
import 'app_shell.dart';
import 'ledger_routes.dart';
import 'sms_limited_mode_screen.dart';
import 'sms_permission_rationale_screen.dart';

/// Where in the onboarding journey the user is, *within this app session*.
///
/// Session state rather than persisted state, deliberately: what is durable is
/// only "have we asked" (the `onboarding_complete` column). Everything else
/// here is the shape of one conversation, and a conversation that resumed
/// mid-sentence after a process death would be stranger than one that starts
/// again.
enum _OnboardingStep {
  /// Deciding which screen to show — the settings row is still being read.
  deciding,

  /// S-02 is on screen.
  rationale,

  /// The OS dialog is up. Nothing of ours is interactive.
  requesting,

  /// S-04 is on screen.
  limitedMode,

  /// Done with onboarding; the app shell is showing.
  finished,
}

/// Sits between the lock gate and [AppShell].
///
/// Renders the app directly for every user who has already been through
/// onboarding, which after the first launch is everyone — so this widget costs
/// one settings read and then gets out of the way.
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key});

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  _OnboardingStep _step = _OnboardingStep.deciding;

  /// The status the OS reported from the last `request()`, which is what S-04
  /// needs in order to choose between "Try again" and "Open system settings" —
  /// on `permanentlyDenied` Android silently no-ops the request, so a "Grant"
  /// button there would visibly do nothing at all.
  SmsPermissionStatus _status = SmsPermissionStatus.denied;

  /// True once the user has dismissed S-05, so the progress screen does not
  /// reappear on every rebuild while a long import keeps running.
  bool _importDismissed = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UnlockedDatabaseSession?> sessionAsync = ref.watch(
      unlockedDatabaseSessionProvider,
    );
    final AsyncValue<SmsPermissionStatus> permissionAsync = ref.watch(
      smsPermissionStatusProvider,
    );

    if (_step == _OnboardingStep.finished) {
      return _shellOrImportProgress();
    }

    // Both reads have to land before a decision can be made. Rendering the app
    // in the meantime and *then* replacing it with an onboarding screen would
    // flash the dashboard at a first-run user, which reads as a glitch.
    final UnlockedDatabaseSession? session = sessionAsync.value;
    final SmsPermissionStatus? permission = permissionAsync.value;
    if (sessionAsync.isLoading ||
        permissionAsync.isLoading ||
        session == null ||
        permission == null) {
      // A failed read of either falls through to the app rather than trapping
      // the user in a spinner: the worst case of guessing "already onboarded"
      // is a missing prompt, which the More menu can still recover; the worst
      // case of guessing the other way is re-running onboarding at someone who
      // has years of history.
      if (sessionAsync.hasError || permissionAsync.hasError) {
        return const AppShell();
      }
      return const _GateLoading();
    }

    return FutureBuilder<AppSettingsRow>(
      future: session.appSettingsDao.current(),
      builder: (BuildContext context, AsyncSnapshot<AppSettingsRow> snapshot) {
        if (!snapshot.hasData) {
          return snapshot.hasError ? const AppShell() : const _GateLoading();
        }
        final bool alreadyAsked = snapshot.data!.onboardingComplete;

        // The common case, and the only one after first launch: the question
        // has been settled, so this widget is a pass-through. A revoked
        // permission surfaces as AC-A1.3's banner on Home, not as a takeover.
        //
        // **Gated on `deciding`, and that is load-bearing.** The persisted flag
        // is written the moment the user answers — *including when they
        // decline* — so without this guard the very act of pressing "Not now"
        // would flip `alreadyAsked` to true and this branch would skip S-04
        // entirely, dropping the user into the app with no explanation of why
        // nothing is being ingested. That is exactly the unexplained empty
        // state AC-A1.2 forbids. Once a journey has started in this session,
        // the session's own step outranks a flag that journey just wrote.
        if (_step == _OnboardingStep.deciding &&
            (alreadyAsked || permission.allowsIngestion)) {
          return _shellOrImportProgress();
        }

        return switch (_step) {
          _OnboardingStep.rationale ||
          _OnboardingStep.deciding => SmsPermissionRationaleScreen(
            onGrantPressed: _requestPermission,
            onNotNowPressed: () => _finishOnboarding(
              nextStep: _OnboardingStep.limitedMode,
              status: SmsPermissionStatus.denied,
            ),
          ),
          // The OS dialog is on top of us. Keeping the rationale underneath
          // rather than swapping to a spinner means the dialog does not appear
          // over a screen the user has never seen.
          _OnboardingStep.requesting => SmsPermissionRationaleScreen(
            onGrantPressed: () {},
            onNotNowPressed: () {},
          ),
          _OnboardingStep.limitedMode => SmsLimitedModeScreen(
            status: _status,
            onRequestPermission: _requestPermission,
            onOpenSettings: () =>
                ref.read(smsPermissionServiceProvider).openAppSettings(),
            onAddManually: () {
              setState(() => _step = _OnboardingStep.finished);
              openManualEntry(context);
            },
            onContinue: () => setState(() => _step = _OnboardingStep.finished),
          ),
          _OnboardingStep.finished => _shellOrImportProgress(),
        };
      },
    );
  }

  /// **The call KHA-113 says nothing in `lib/` was making.**
  ///
  /// Fires the OS dialog and routes on the outcome: granted goes straight into
  /// the app (where the foreground sweep is already watching for an unlocked
  /// session), denied goes to S-04 rather than to an unexplained empty screen,
  /// which is precisely what AC-A1.2 forbids.
  ///
  /// `markOnboardingComplete` runs for **both** outcomes. The flag means "we
  /// have asked", not "we succeeded" — a user who declined must land in limited
  /// mode next launch, not back at a rationale screen they have already read.
  Future<void> _requestPermission() async {
    setState(() => _step = _OnboardingStep.requesting);
    final SmsPermissionStatus result = await ref
        .read(smsPermissionServiceProvider)
        .request();
    if (!mounted) {
      return;
    }
    await _finishOnboarding(
      nextStep: result.allowsIngestion
          ? _OnboardingStep.finished
          : _OnboardingStep.limitedMode,
      status: result,
    );
  }

  Future<void> _finishOnboarding({
    required _OnboardingStep nextStep,
    required SmsPermissionStatus status,
  }) async {
    final UnlockedDatabaseSession? session = await ref.read(
      unlockedDatabaseSessionProvider.future,
    );
    await session?.appSettingsDao.markOnboardingComplete();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _step = nextStep;
    });
    // Re-read the OS status so the ingestion pipeline and the AC-A1.3 banner
    // both see the new answer immediately, rather than on the next foreground.
    ref.invalidate(smsPermissionStatusProvider);
  }

  /// **S-05 (AC-A3.2)**, or the app.
  ///
  /// The progress screen is shown only while a historical import is genuinely
  /// running *and* the user has not dismissed it. Both conditions matter: a
  /// resumed import on the fifth launch must not hijack the app, and a user who
  /// pressed "continue in the background" must not have it come back.
  Widget _shellOrImportProgress() {
    final ImportProgress progress =
        ref.watch(importProgressProvider).value ?? ImportProgress.idle;
    if (progress.isActive && !_importDismissed) {
      return ImportProgressHost(
        onContinueInBackground: () => setState(() => _importDismissed = true),
      );
    }
    return const AppShell();
  }
}

/// A bare centred spinner. No app bar and no copy: this is on screen for one
/// database read, and anything more would flash text nobody can finish reading.
class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      key: Key('onboarding.loading'),
      child: CircularProgressIndicator(),
    ),
  );
}
