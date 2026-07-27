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

/// The default Keystore alias — the DB Master Key's own KEK, exactly as
/// ADR-004 names it. Every method below accepts an explicit [keyAlias] so
/// the **same** Keystore-wrapping mechanism can also back ADR-010's
/// separate `auditChainKey` (alias `massrofy.auditchain`, see
/// `audit_chain_key_store.dart`) without a second, near-duplicate Kotlin
/// implementation — one generic "wrap/unwrap bytes under a named Keystore
/// AES-256-GCM key" primitive, reused for both purposes.
const String kDbMasterKeyKeystoreAlias = 'massrofy.dbkek';

abstract interface class KeyManager {
  /// Generates (on first call) or reuses an Android Keystore AES-256-GCM
  /// key aliased [keyAlias] (defaults to [kDbMasterKeyKeystoreAlias]), with:
  ///  - `setUserAuthenticationRequired(true)`
  ///  - a *time-bound* authentication window (see
  ///    `android/.../KeystoreChannel.kt`'s doc comment for exactly why it
  ///    must be time-bound rather than per-operation, given how this
  ///    interface's callers actually invoke it)
  ///  - `setInvalidatedByBiometricEnrollment(false)` **for this P1 slice,
  ///    deliberately** — ADR-004 names `true` as the eventual secure
  ///    default, but that default is only safe once a real recovery path
  ///    exists for the data it would otherwise strand, and
  ///    `DbMasterKeyStore.unwrapWithRecoverySecret` is still a documented
  ///    stub (Epic I / P8). Shipping `true` today would mean the first
  ///    biometric re-enrollment permanently destroys the encrypted
  ///    database with no way back — see the Kotlin implementation's doc
  ///    comment for the full tradeoff and the follow-up this defers.
  ///
  /// and wraps [secretBytes] with it. This is real Android Keystore
  /// hardware/TEE-backed key material on-device (see
  /// `android/.../KeystoreChannel.kt`) — there is no Dart-side fallback for
  /// production use; this method is only meaningfully callable on Android.
  ///
  /// [keyAlias] selects *which* Keystore-held AES key wraps [secretBytes] —
  /// each distinct alias is an entirely separate Keystore key with its own
  /// lifecycle (own invalidation, own deletion). Callers must pass the same
  /// [keyAlias] to the matching [unwrapWithKeystoreKek]/[deleteKeystoreKek]
  /// call that they used here.
  Future<WrappedKey> wrapWithKeystoreKek(
    List<int> secretBytes, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  });

  /// Unwraps a [WrappedKey] previously produced by [wrapWithKeystoreKek]
  /// under the same [keyAlias].
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
  Future<List<int>> unwrapWithKeystoreKek(
    WrappedKey wrapped, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  });

  /// Deletes the Keystore alias entirely — used by erase-all (ADR-011) and
  /// by the recovery flow just before generating a fresh Keystore KEK.
  Future<void> deleteKeystoreKek({String keyAlias = kDbMasterKeyKeystoreAlias});
}
