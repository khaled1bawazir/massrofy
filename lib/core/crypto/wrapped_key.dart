import 'dart:convert';
import 'dart:typed_data';

/// The result of wrapping (encrypting) a key with another key ("KEK" — key
/// encryption key), per ADR-004. This is what gets persisted (in
/// `flutter_secure_storage`) — the unwrapped key material itself is never
/// written to disk.
class WrappedKey {
  /// AES-256-GCM ciphertext of the wrapped key material.
  final Uint8List ciphertext;

  /// The 96-bit (12-byte) nonce used for this specific wrap operation. Per
  /// ADR-004/ADR-012 convention, a fresh random nonce is used every time a
  /// key is (re-)wrapped — nonces are never reused with the same KEK.
  final Uint8List nonce;

  const WrappedKey({required this.ciphertext, required this.nonce});

  /// Serialises to the JSON-safe map stored under one
  /// `flutter_secure_storage` entry (e.g. `wrapped_by_keystore`).
  Map<String, String> toStorageMap() => <String, String>{
    'ciphertext': base64Encode(ciphertext),
    'nonce': base64Encode(nonce),
  };

  factory WrappedKey.fromStorageMap(Map<String, String> map) => WrappedKey(
    ciphertext: base64Decode(map['ciphertext']!),
    nonce: base64Decode(map['nonce']!),
  );
}

/// Thrown when the Android Keystore key backing a [WrappedKey] has been
/// invalidated — new biometric enrolled, device credential changed or
/// removed, or the device was restored from an OS-level backup (ADR-004).
///
/// The caller's correct response (per ADR-004) is: prompt for the recovery
/// secret, unwrap via the Passphrase KEK instead, generate a **fresh**
/// Keystore KEK, and re-wrap — never treat this as data loss.
class KeystoreKeyInvalidatedException implements Exception {
  final String message;
  const KeystoreKeyInvalidatedException([
    this.message = 'Android Keystore key was invalidated',
  ]);

  @override
  String toString() => 'KeystoreKeyInvalidatedException: $message';
}

/// Why a Keystore wrap/unwrap failed, as a **closed set** the Dart layers
/// can `switch` over (KHA-75).
///
/// ## Why an enum and not just the raw platform error string
/// `AppLockController` has to log which step failed, and ADR-015 requires
/// every `LogEvent.category` to be a compile-time constant at the call site
/// — you may not interpolate a runtime string into it, precisely so a value
/// can never leak into a log line. A closed enum is what makes that possible:
/// the controller switches over these cases and passes a `const` category
/// for each. It also keeps `package:flutter/services.dart`'s
/// `PlatformException` out of the `features/` layer, which
/// `architecture.md`'s module boundaries deliberately keep Flutter-light.
enum KeystoreFailureKind {
  /// The Kotlin side could not even decode the arguments we sent it — a
  /// Dart<->Kotlin contract bug on our side, never anything the user did.
  /// **This is the KHA-75 failure**: every `Uint8List` argument was being
  /// read as a `java.util.List`, so every wrap and unwrap threw
  /// `ClassCastException` and the app could not be unlocked on any device.
  invalidArgument,

  /// The key exists and is fine, but the OS refused the operation because
  /// no biometric/device-credential authentication happened recently enough
  /// (`KeystoreChannel.AUTH_VALIDITY_SECONDS`). Retrying — i.e. showing the
  /// prompt again — is the correct response.
  userNotAuthenticated,

  /// Any other Keystore/TEE-level failure (hardware unavailable, provider
  /// error, an OEM Keystore quirk). Not a wrong credential.
  platform,

  /// The channel failed in a way that isn't one of our own error codes at
  /// all (missing plugin, malformed reply).
  unknown,
}

/// Raised when an Android Keystore operation fails for a reason that is
/// **not** "the user presented the wrong credential" (KHA-75).
///
/// Before this type existed, every one of these surfaced as a bare
/// `PlatformException` that `AppLockController` swallowed in a
/// `catch (_)`, showing the user the same "Authentication failed. Try
/// again." as a genuinely wrong fingerprint — and, worse, counting it
/// toward ADR-005's 5-strikes lockout, so a fault that was entirely the
/// app's own locked the user out. Both of those are fixed by giving this
/// class of failure a name the controller can catch specifically.
///
/// [KeystoreKeyInvalidatedException] stays separate: it is not a fault at
/// all, it is ADR-004's documented recovery trigger.
class KeystoreOperationException implements Exception {
  final KeystoreFailureKind kind;

  /// The platform error code as sent by `KeystoreChannel.kt` (one of
  /// `invalid_argument`, `user_not_authenticated`, `keystore_error`). Kept
  /// for debugging and for a future "authentication unavailable" UI
  /// (KHA-72); deliberately **never** written to a log by this app — see
  /// [KeystoreFailureKind]'s doc comment.
  final String code;

  const KeystoreOperationException({required this.kind, required this.code});

  @override
  String toString() => 'KeystoreOperationException($code)';
}
