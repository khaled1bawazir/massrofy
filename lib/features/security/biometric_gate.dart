import 'package:local_auth/local_auth.dart';

/// A thin seam over `package:local_auth`'s `LocalAuthentication`, so
/// `AppLockController` can be unit-tested without a real fingerprint
/// sensor or device credential prompt — a fake [BiometricGate] simply
/// returns `true`/`false` for each test case.
abstract interface class BiometricGate {
  /// Shows the platform biometric/device-credential prompt with [reason]
  /// as the rationale text.
  ///
  /// Returns `true` on success and `false` when the user *declined* — a
  /// wrong biometric they gave up on, or an explicit cancel. Those are the
  /// two outcomes ADR-005's failed-attempt counter should count.
  ///
  /// Throws [BiometricGateUnavailableException] when the prompt could not
  /// run at all (no UI host, hardware busy, nothing enrolled, OS-level
  /// biometric lockout). That is a device fault, not a failed attempt —
  /// see that class's doc comment.
  Future<bool> authenticate({required String reason});
}

/// The prompt could not be shown or completed for a reason that is **not**
/// the user failing/declining authentication (KHA-72's policy half,
/// implemented here because KHA-75 proved what happens without it).
///
/// `local_auth` 3.x signals *every* non-success outcome by throwing a
/// `LocalAuthException` — including plain user-cancel, but also
/// `uiUnavailable`, `deviceError`, `noCredentialsSet`,
/// `biometricHardwareTemporarilyUnavailable`, `biometricLockout`... The
/// call site cannot tell those apart without knowing about `local_auth`,
/// and `AppLockController` deliberately doesn't (architecture.md keeps the
/// `features/` layer plugin-agnostic). So [LocalAuthBiometricGate] does the
/// triage: cancel-like codes become a plain `false`, everything else
/// becomes this exception.
///
/// Why the distinction is load-bearing: burning one of the user's five
/// ADR-005 attempts — and eventually locking them out for minutes — because
/// *the device's own biometric stack* hiccuped punishes them for a fault
/// that is not theirs. KHA-75 is the proof: a bug entirely inside this app
/// made every unlock fail, and users hit the lockout in seconds.
class BiometricGateUnavailableException implements Exception {
  /// The underlying plugin's error-code *name* (e.g. `'uiUnavailable'`).
  /// Useful in a debugger and for KHA-72's future "authentication
  /// unavailable" UI; deliberately never interpolated into a log line —
  /// `AppLockController` logs a fixed `const` category instead (ADR-015).
  final String codeName;

  const BiometricGateUnavailableException(this.codeName);

  @override
  String toString() => 'BiometricGateUnavailableException($codeName)';
}

/// Real implementation, backed by `local_auth`.
///
/// **ADR-005 scope note (read before assuming this is the whole story):**
/// `local_auth` shows the platform `BiometricPrompt`
/// (`BIOMETRIC_STRONG | DEVICE_CREDENTIAL`, matching ADR-005) but — unlike
/// a hand-written native integration — it does not expose Android's
/// `BiometricPrompt.CryptoObject` binding, so this call is not *itself*
/// cryptographically tied to the specific Keystore key operation that
/// follows it. The cryptographic enforcement ADR-005 requires instead comes
/// from the Keystore key itself (`KeystoreChannel.kt`): it is generated
/// with `setUserAuthenticationRequired(true)` and (API 30+)
/// `setUserAuthenticationParameters(0, BIOMETRIC_STRONG | DEVICE_CREDENTIAL)`,
/// so the *operating system* refuses to use that key at all unless the
/// device was recently authenticated — independently of whatever this
/// Dart-level call does. `AppLockController` calls [authenticate] first as
/// application-level defence in depth (never even attempt the unwrap
/// without a successful prompt), and the Keystore key's own policy is the
/// enforcement that holds even if that application-level check were ever
/// buggy. Tightening this further to full `CryptoObject` binding would mean
/// replacing `local_auth` with a hand-written native `BiometricPrompt`
/// invocation — noted as a follow-up in the PR description, not attempted
/// in this P1 slice.
class LocalAuthBiometricGate implements BiometricGate {
  final LocalAuthentication _localAuth;

  LocalAuthBiometricGate({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  /// The `local_auth` codes that mean "the user chose not to continue".
  /// These are genuine, countable attempts (KHA-72 item 2 names
  /// `userCanceled` explicitly), so they come back as a plain `false` rather
  /// than as a [BiometricGateUnavailableException]. Everything else the
  /// plugin can throw describes a *device* problem.
  static const Set<LocalAuthExceptionCode> _declinedByUser =
      <LocalAuthExceptionCode>{
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.userRequestedFallback,
      };

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        // ADR-005: "allowed authenticators BIOMETRIC_STRONG |
        // DEVICE_CREDENTIAL" — biometricOnly:false is what permits the
        // device-credential (PIN/pattern/password) fallback local_auth offers
        // when biometrics aren't enrolled or fail repeatedly.
        biometricOnly: false,
        // Retries automatically on foregrounding instead of failing outright
        // if the OS stops an in-progress prompt while the app is backgrounded.
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      // Translate at the boundary so nothing above this file ever has to
      // import `package:local_auth` — see [BiometricGateUnavailableException].
      if (_declinedByUser.contains(e.code)) {
        return false;
      }
      throw BiometricGateUnavailableException(e.code.name);
    }
  }
}
