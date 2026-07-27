import 'wrapped_key.dart';

/// The key-hierarchy contract from `docs/architecture.md` ADR-004: **three
/// keys, two independent unwrapping paths**, so a device-bound Keystore key
/// never becomes a single point of unrecoverable failure (ADR-004 exists
/// specifically to close R-2, "backup key recovery").
///
///   DB Master Key (32B, CSPRNG, generated once on first run)
///        ▲                                  ▲
///        │ wrapped by                       │ wrapped by
///   Keystore KEK                       Passphrase KEK
///   (biometric/device-credential-      (derived from the user's
///    gated, this device only)           recovery secret — ADR-012 —
///                                        works on ANY device)
///
/// This interface only names the **Keystore** half — [wrapWithKeystoreKek]/
/// [unwrapWithKeystoreKek]. The **Passphrase** half lives in
/// `passphrase_key_deriver.dart` as a separate, narrower interface, because
/// (per the task scoping for this P1 slice) its concrete implementation is
/// a documented stub until Epic I (backup, P8) actually builds the
/// recovery-secret generation and confirmation flow — see that file's doc
/// comment.
abstract interface class KeyManager {
  /// Generates (on first call) or reuses an Android Keystore AES-256-GCM
  /// key aliased `massrofy.dbkek`, with:
  ///  - `setUserAuthenticationRequired(true)`
  ///  - `setInvalidatedByBiometricEnrollment(true)` (ADR-004: deliberately
  ///    accepted friction — enrolling a new fingerprint forces one
  ///    recovery-secret entry, which is the secure default; the insecure
  ///    alternative would let anyone who can add a biometric to the device
  ///    silently inherit access to the database key)
  ///
  /// and wraps [dbMasterKey] with it. This is real Android Keystore
  /// hardware/TEE-backed key material on-device (see
  /// `android/.../KeystoreChannel.kt`) — there is no Dart-side fallback for
  /// production use; this method is only meaningfully callable on Android.
  Future<WrappedKey> wrapWithKeystoreKek(List<int> dbMasterKey);

  /// Unwraps a [WrappedKey] previously produced by [wrapWithKeystoreKek].
  ///
  /// Throws [KeystoreKeyInvalidatedException] if the underlying Keystore
  /// key has been invalidated (new biometric enrolled, device credential
  /// changed/removed, or an OS-level restore onto different Keystore
  /// hardware) — ADR-004's documented recovery path is to catch this,
  /// prompt for the recovery secret, unwrap via the Passphrase KEK instead,
  /// generate a fresh Keystore KEK, and re-wrap. **This must never be
  /// treated as data loss by a caller.**
  ///
  /// ADR-005 cryptographic-enforcement note: on Android, this operation
  /// requires the Keystore to consider the device "recently authenticated"
  /// via biometric or device credential (the key's own
  /// `setUserAuthenticationRequired`/`setUserAuthenticationParameters`
  /// policy — see the Kotlin implementation for the exact API-level
  /// behaviour). If authentication was never performed, or failed, this
  /// call throws rather than returning key material — the database
  /// therefore cannot be opened without a real, OS-enforced authentication
  /// having occurred, not merely without the app's own UI having *shown* a
  /// lock screen.
  Future<List<int>> unwrapWithKeystoreKek(WrappedKey wrapped);

  /// Deletes the Keystore alias entirely — used by erase-all (ADR-011) and
  /// by the recovery flow just before generating a fresh Keystore KEK.
  Future<void> deleteKeystoreKek();
}
