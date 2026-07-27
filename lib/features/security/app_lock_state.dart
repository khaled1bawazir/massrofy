/// The states `docs/mockups/lock-gate.html` (S-09) enumerates, mapped 1:1
/// onto Dart so the widget layer can `switch` over them instead of
/// juggling booleans.
enum AppLockStatus {
  /// Cold launch, or resumed past the re-lock grace period — the biometric
  /// prompt has not been shown yet for this attempt.
  locked,

  /// The platform biometric/device-credential prompt is currently showing.
  authenticating,

  /// Authentication failed once (wrong finger, cancelled) — recoverable,
  /// the user can simply try again.
  failed,

  /// Too many consecutive failures — cooling down until [AppLockState.lockedOutUntil].
  lockedOut,

  /// Re-locked after being backgrounded past the grace period — shown with
  /// the "session ended in the background" banner (ADR-005 re-lock policy),
  /// distinct from a plain cold-launch [locked] so the copy can say so.
  sessionExpired,

  /// Authentication succeeded and the DB Master Key has been unwrapped —
  /// the rest of the app may render.
  unlocked,
}

/// Immutable state for [AppLockController] (`app_lock_controller.dart`).
class AppLockState {
  final AppLockStatus status;

  /// Only meaningful when [status] is [AppLockStatus.lockedOut].
  final DateTime? lockedOutUntil;

  const AppLockState({required this.status, this.lockedOutUntil});

  const AppLockState.locked() : this(status: AppLockStatus.locked);

  bool get isUnlocked => status == AppLockStatus.unlocked;
}
