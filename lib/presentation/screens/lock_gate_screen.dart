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
  const LockGateScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final AppLockState lockState = ref.watch(appLockControllerProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);

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
                  lockedOut: lockState.status == AppLockStatus.lockedOut,
                ),
                const SizedBox(height: 24),
                Text(
                  _headline(lockState, l10n),
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
                if (lockState.status != AppLockStatus.lockedOut)
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

  String _headline(AppLockState state, AppLocalizations l10n) {
    switch (state.status) {
      case AppLockStatus.lockedOut:
        return l10n.lockGateTooManyAttempts;
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
      final DateTime? until = state.lockedOutUntil;
      final Duration remaining = until == null
          ? Duration.zero
          : until.difference(DateTime.now());
      final int seconds = remaining.isNegative ? 0 : remaining.inSeconds;
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
