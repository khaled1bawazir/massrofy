import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/security/app_lock_controller.dart';
import '../../features/security/app_lock_state.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// S-09 — App Lock Gate (`docs/mockups/lock-gate.html`).
///
/// ## What this screen is, structurally (a note for readers new to Flutter)
/// This is a `ConsumerWidget` — the Riverpod-flavoured version of
/// `StatelessWidget` that also gets a `WidgetRef` in `build()`, so it can
/// `ref.watch(appLockControllerProvider)` and rebuild automatically
/// whenever [AppLockController]'s state changes (locked → authenticating →
/// unlocked, etc.) — no manual `setState` bookkeeping needed here at all;
/// the *controller* owns the state, this widget only renders it.
///
/// **Why nothing "underneath" this screen ever renders pre-success
/// (AC-F1.2):** the app's root widget (`app.dart`) shows *either* this
/// screen *or* the real app content, chosen by
/// `appLockControllerProvider`'s `isUnlocked` — there is no shared
/// widget tree where financial data could be built off-screen and merely
/// hidden behind this one. Nothing to unmask, because nothing behind it was
/// ever built.
class LockGateScreen extends ConsumerStatefulWidget {
  /// Source of "now" for the locked-out countdown, injectable purely as a
  /// **test seam** (KHA-75). Production always uses the real clock.
  ///
  /// Why it has to exist: `flutter_test` advances a *fake async* clock when
  /// you `tester.pump(duration)`, which fires `Timer`s — but it does not
  /// move `DateTime.now()`, which stays on the real wall clock. Without this
  /// seam a widget test could prove the ticker fires and still not prove the
  /// displayed countdown ever changes, which is exactly the defect being
  /// fixed. A one-field function seam is a much smaller price than a test
  /// that sleeps for real seconds (slow, and flaky on a loaded CI runner).
  final DateTime Function() clock;

  const LockGateScreen({super.key, this.clock = DateTime.now});

  @override
  ConsumerState<LockGateScreen> createState() => _LockGateScreenState();
}

class _LockGateScreenState extends ConsumerState<LockGateScreen> {
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    // Kick off authentication as soon as the gate first appears — matches
    // the mockup's "idle" state showing the biometric prompt immediately,
    // rather than waiting for an extra tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final AppLockState current = ref.read(appLockControllerProvider);
      if (current.status == AppLockStatus.locked ||
          current.status == AppLockStatus.sessionExpired) {
        ref.read(appLockControllerProvider.notifier).authenticate();
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  /// Starts/stops the once-a-second rebuild that makes the locked-out
  /// countdown actually count down (KHA-75, second defect).
  ///
  /// ## What was broken
  /// [_countdownTicker] existed, and `dispose()` cancelled it — but nothing
  /// ever *started* it. So [_subtitle] computed "Retry in 00:30" exactly
  /// once, at the moment the lockout began, and that text then sat frozen
  /// forever. Worse, the "use passcode" affordance is hidden while locked
  /// out, so once the (frozen) countdown appeared there was no control on
  /// screen at all: the only way out was to force-quit the app. That is
  /// what the human saw and reported as "the failure-attempt counter
  /// display seems broken".
  ///
  /// ## How this fixes it
  /// Called from `build`, which Riverpod re-runs on every state change.
  /// Creating/cancelling a `Timer` during build is safe (it mutates no
  /// widget state and schedules no synchronous rebuild); the *callback*
  /// then calls `setState` a second later, off the build phase, which is
  /// the normal way to drive a ticking clock. When the deadline passes the
  /// timer stops itself and one final rebuild re-enables the retry
  /// affordance — see [build]'s `stillCoolingDown`.
  void _syncCountdownTicker(AppLockState lockState) {
    final bool needsTicker =
        lockState.status == AppLockStatus.lockedOut &&
        _remaining(lockState) > Duration.zero;

    if (!needsTicker) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
      return;
    }
    if (_countdownTicker != null) return; // already ticking

    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      // Rebuild so [_subtitle] recomputes against a newer "now". The
      // rebuild itself calls this method again, which cancels the timer once
      // the deadline has passed.
      setState(() {});
    });
  }

  /// How much of the ADR-005 cooldown is left, floored at zero. `null`
  /// [AppLockState.lockedOutUntil] means "no deadline recorded", which is
  /// treated as already elapsed rather than as an infinite lockout — never
  /// strand the user because a field was missing.
  Duration _remaining(AppLockState lockState) {
    final DateTime? until = lockState.lockedOutUntil;
    if (until == null) return Duration.zero;
    final Duration remaining = until.difference(widget.clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final AppLockState lockState = ref.watch(appLockControllerProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);

    _syncCountdownTicker(lockState);

    // Only *while the cooldown is genuinely still running* is the retry
    // affordance suppressed. Once it elapses the button comes back, even
    // though the controller's status is still `lockedOut` — the controller
    // leaves that status in place until the next attempt is actually made
    // (see `AppLockController.authenticate`, which re-checks the deadline
    // and proceeds normally once it has passed).
    final bool stillCoolingDown =
        lockState.status == AppLockStatus.lockedOut &&
        _remaining(lockState) > Duration.zero;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Wordmark(title: l10n.appTitle),
                const SizedBox(height: 60),
                if (lockState.status == AppLockStatus.sessionExpired)
                  _SessionExpiredBanner(
                    text: l10n.lockGateSessionExpiredBanner,
                  ),
                if (lockState.status == AppLockStatus.failed)
                  _ErrorBanner(text: l10n.lockGateAuthFailed),
                _BiometricCircle(
                  failed: lockState.status == AppLockStatus.failed,
                  // The clock icon belongs to the *waiting* state only. Once
                  // the cooldown is spent the screen is functionally the
                  // mockup's idle state again, so it goes back to the
                  // fingerprint icon alongside the restored retry link.
                  lockedOut: stillCoolingDown,
                ),
                const SizedBox(height: 24),
                Text(
                  _headline(lockState, l10n, stillCoolingDown),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle(lockState, l10n),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                if (!stillCoolingDown)
                  TextButton(
                    onPressed: () => ref
                        .read(appLockControllerProvider.notifier)
                        .authenticate(),
                    child: Text(
                      l10n.lockGateUsePasscode,
                      style: const TextStyle(
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                      ),
                      semanticsLabel: l10n.lockGateUsePasscode,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [stillCoolingDown] is passed in rather than recomputed so the headline,
  /// the icon, the subtitle and the retry link all flip on the *same*
  /// evaluation of the deadline within one build — otherwise a build that
  /// straddles the expiry instant could render "Too many attempts" above a
  /// working retry button, which reads as a bug even though it is only a
  /// race between four separate `DateTime` reads.
  String _headline(
    AppLockState state,
    AppLocalizations l10n,
    bool stillCoolingDown,
  ) {
    switch (state.status) {
      case AppLockStatus.lockedOut:
        // Cooldown spent: the controller keeps `lockedOut` until the next
        // attempt is actually made, but from the user's point of view this
        // is the ordinary idle gate again, so say so.
        return stillCoolingDown
            ? l10n.lockGateTooManyAttempts
            : l10n.lockGateUnlockToView;
      case AppLockStatus.sessionExpired:
        return l10n.lockGateContinueUnlock;
      case AppLockStatus.locked:
      case AppLockStatus.authenticating:
      case AppLockStatus.failed:
      case AppLockStatus.unlocked:
        return l10n.lockGateUnlockToView;
    }
  }

  String _subtitle(AppLockState state, AppLocalizations l10n) {
    if (state.status == AppLockStatus.lockedOut) {
      // Rounded UP, not truncated. With `inSeconds` (which truncates), the
      // last fractional second of a cooldown would read "00:00" while the
      // retry affordance was still correctly hidden — the countdown and the
      // button would briefly disagree, which is exactly the kind of "is it
      // broken or just slow?" moment this screen must not create. Ceiling
      // means "00:01" until the deadline genuinely passes, and both the
      // text and the button then flip together.
      final int seconds = (_remaining(state).inMilliseconds / 1000).ceil();
      // Cooldown elapsed: drop the (now meaningless) "retry in 00:00" and
      // show the ordinary prompt hint again, matching the retry affordance
      // that `build`'s `stillCoolingDown` has just restored.
      if (seconds <= 0) return l10n.lockGateBiometricHint;
      final String mm = (seconds ~/ 60).toString().padLeft(2, '0');
      final String ss = (seconds % 60).toString().padLeft(2, '0');
      return l10n.lockGateRetryIn('$mm:$ss');
    }
    return l10n.lockGateBiometricHint;
  }
}

class _Wordmark extends StatelessWidget {
  final String title;
  const _Wordmark({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _BiometricCircle extends StatelessWidget {
  final bool failed;
  final bool lockedOut;
  const _BiometricCircle({required this.failed, required this.lockedOut});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).lockGateUnlockButtonSemanticLabel,
      button: true,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: failed
                ? AppColors.error
                : Colors.white.withValues(alpha: 0.35),
            width: 3,
          ),
        ),
        child: Icon(
          lockedOut ? Icons.lock_clock_outlined : Icons.fingerprint,
          color: Colors.white,
          size: 56,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.25),
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _SessionExpiredBanner extends StatelessWidget {
  final String text;
  const _SessionExpiredBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.infoTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.schedule_outlined, color: AppColors.info, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.info, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
