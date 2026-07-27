import 'package:local_auth/local_auth.dart';

/// A thin seam over `package:local_auth`'s `LocalAuthentication`, so
/// `AppLockController` can be unit-tested without a real fingerprint
/// sensor or device credential prompt — a fake [BiometricGate] simply
/// returns `true`/`false` for each test case.
abstract interface class BiometricGate {
  /// Shows the platform biometric/device-credential prompt with [reason]
  /// as the rationale text, and returns whether authentication succeeded.
  Future<bool> authenticate({required String reason});
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

  @override
  Future<bool> authenticate({required String reason}) {
    return _localAuth.authenticate(
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
  }
}
