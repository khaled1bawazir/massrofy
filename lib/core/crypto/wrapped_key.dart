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
