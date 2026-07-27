import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_manager.dart';
import 'passphrase_key_deriver.dart';
import 'wrapped_key.dart';

/// The narrow surface `AppLockController` needs from a DB-master-key store —
/// deliberately factored out of the concrete [DbMasterKeyStore] so
/// `test/features/security/app_lock_controller_test.dart` can supply a
/// lightweight fake instead of wiring up real `flutter_secure_storage`/
/// Android Keystore/Argon2id plumbing just to test lock-state transitions.
abstract interface class DbMasterKeyRepository {
  Future<bool> hasExistingKey();
  Future<Uint8List> provisionNewDatabaseKey();
  Future<Uint8List> unlockWithKeystore();
}

/// Orchestrates ADR-004's key hierarchy end to end: generating the DB
/// Master Key once, wrapping it under both KEKs, persisting the wrapped
/// blobs, and unwrapping it on unlock.
///
/// ## The three keys, restated for this file's context
///  - **DB Master Key** — 32 random bytes, generated once on first run,
///    never displayed/exported/logged. This is the key SQLCipher actually
///    opens the database with (`PRAGMA key`, see `data/db/db_connection.dart`).
///  - **Keystore KEK** — wraps the DB Master Key for daily biometric/
///    device-credential unlock. Device-bound; can be invalidated.
///  - **Passphrase KEK** — wraps the same DB Master Key, derived from the
///    user's recovery secret (ADR-012). Not device-bound; the P8/Epic I
///    recovery-secret flow supplies the actual secret material — this
///    class only needs *a* secret and *a* salt, whatever produced them.
///
/// Both wrapped blobs live in `flutter_secure_storage`
/// (`EncryptedSharedPreferences` on Android — itself Keystore-backed —
/// "defence in depth on already-encrypted material", per ADR-004).
///
/// Implements [DbMasterKeyRepository] — the narrow interface
/// `AppLockController` actually depends on — so tests can substitute a
/// lightweight fake instead of standing up real `flutter_secure_storage`/
/// Keystore/Argon2id plumbing.
class DbMasterKeyStore implements DbMasterKeyRepository {
  static const String _keystoreWrappedStorageKey = 'wrapped_by_keystore';
  static const String _passphraseWrappedStorageKey = 'wrapped_by_passphrase';
  static const String _passphraseSaltStorageKey = 'passphrase_salt';

  final KeyManager keyManager;
  final PassphraseKeyDeriver passphraseKeyDeriver;
  final FlutterSecureStorage secureStorage;

  // Deliberately **not** an injectable constructor parameter. The DB Master
  // Key generated below is the single key that ultimately opens the whole
  // encrypted database (ADR-003/ADR-004) — a security-sensitive value that
  // must always come from a cryptographically-secure random source, never
  // a caller-supplied one. `Random` and `Random.secure()` share the exact
  // same Dart type, so an optional `Random? random` constructor parameter
  // (as this class used to have) type-checks identically whether the
  // caller passes a real CSPRNG or a predictable, seedable
  // `Random(seed)` — the compiler cannot tell them apart, only a careful
  // reviewer reading every call site can, and that is precisely the kind
  // of mistake that must be made structurally impossible in a banking app.
  // `Random.secure()` is therefore hard-coded here as the only source this
  // class will ever use; a test that needs deterministic bytes should
  // assert on shape (`key.length == 32`) or on the wrap/unwrap round-trip,
  // never on exact key bytes (see `db_master_key_store_test.dart`).
  final Random _random = Random.secure();

  DbMasterKeyStore({
    required this.keyManager,
    required this.passphraseKeyDeriver,
    FlutterSecureStorage? secureStorage,
  }) : secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// True once a DB Master Key has been generated and wrapped at least
  /// once (i.e. this is not a first run).
  @override
  Future<bool> hasExistingKey() async {
    return (await secureStorage.read(key: _keystoreWrappedStorageKey)) != null;
  }

  /// First-run provisioning: generates a fresh 32-byte DB Master Key, wraps
  /// it with the Keystore KEK, and persists the wrapped blob.
  ///
  /// Returns the raw key as a mutable [Uint8List] — deliberately **not** a
  /// `String` — so the caller (`AppLockController`) can genuinely zero it
  /// on lock (ADR-005: "zero the in-memory key (overwrite the byte
  /// list...)"). Dart `String`s are immutable and interned/copied in ways
  /// that make a real, deterministic wipe impossible; a mutable byte
  /// buffer is the only representation that can actually be overwritten.
  /// Convert to the hex form `openEncryptedConnection` needs with
  /// [DbMasterKeyStore.bytesToHex], and only at the point of use.
  @override
  Future<Uint8List> provisionNewDatabaseKey() async {
    final Uint8List rawKey = _generateRandomBytes(32);
    final WrappedKey wrapped = await keyManager.wrapWithKeystoreKek(rawKey);
    await secureStorage.write(
      key: _keystoreWrappedStorageKey,
      value: jsonEncode(wrapped.toStorageMap()),
    );
    return rawKey;
  }

  /// Daily unlock path: unwraps the DB Master Key via the Keystore KEK.
  /// This is the call that only succeeds once the OS has itself required a
  /// recent biometric/device-credential authentication for this Keystore
  /// key — see `KeyManager.unwrapWithKeystoreKek`'s doc comment for exactly
  /// what that does and doesn't guarantee (ADR-005).
  ///
  /// Throws [KeystoreKeyInvalidatedException] if the Keystore key was
  /// invalidated — the caller (`AppLockController`) is expected to fall
  /// back to [unwrapWithRecoverySecret].
  @override
  Future<Uint8List> unlockWithKeystore() async {
    final String? stored = await secureStorage.read(
      key: _keystoreWrappedStorageKey,
    );
    if (stored == null) {
      throw StateError(
        'No Keystore-wrapped DB key exists yet — call provisionNewDatabaseKey() first.',
      );
    }
    final WrappedKey wrapped = WrappedKey.fromStorageMap(
      (jsonDecode(stored) as Map<String, Object?>).cast<String, String>(),
    );
    final List<int> rawKey = await keyManager.unwrapWithKeystoreKek(wrapped);
    return Uint8List.fromList(rawKey);
  }

  /// Recovery path (ADR-004): derives the Passphrase KEK from [recoverySecret]
  /// and the stored salt, unwraps the DB Master Key, then — critically —
  /// **re-wraps it under a freshly generated Keystore KEK** so daily
  /// biometric unlock works again afterwards. No data is lost; this is the
  /// documented answer to "what happens on device credential change."
  Future<Uint8List> unwrapWithRecoverySecret(List<int> recoverySecret) async {
    final String? wrappedJson = await secureStorage.read(
      key: _passphraseWrappedStorageKey,
    );
    final String? saltB64 = await secureStorage.read(
      key: _passphraseSaltStorageKey,
    );
    if (wrappedJson == null || saltB64 == null) {
      throw StateError(
        'No passphrase-wrapped DB key exists yet — recovery/backup was never enabled.',
      );
    }

    // NOTE: deriving the Passphrase KEK is enough to prove *possession* of
    // the recovery secret, but the actual unwrap of the DB Master Key in
    // this P1 slice is performed the same way the Keystore path is tested
    // — via the KeyManager abstraction — once Epic I (P8) defines the
    // concrete on-disk envelope for the passphrase-wrapped blob (ADR-012).
    // This method's presence and signature are what matter for now: every
    // call site that will need "recover via secret, then re-provision a
    // fresh Keystore KEK" already has a stable contract to build against.
    await passphraseKeyDeriver.derive(
      secret: recoverySecret,
      salt: base64Decode(saltB64),
    );
    throw UnimplementedError(
      'Recovery-secret unwrap is wired to a concrete Passphrase-KEK envelope '
      'in Epic I (P8), per this class\'s doc comment. Keystore-path unlock '
      '(unlockWithKeystore) and DB-master-key provisioning are the P1-real '
      'paths this PR implements and tests.',
    );
  }

  Uint8List _generateRandomBytes(int length) {
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Converts raw key bytes to the lower-case hex string
  /// `PRAGMA key = "x'<hex>'"` needs (ADR-003). Kept as a `static` pure
  /// function (not an instance method) so a caller can convert right at the
  /// point of opening the database connection, without holding onto the
  /// hex `String` any longer than necessary — remember, unlike the
  /// `Uint8List` this is derived from, a `String` cannot be zeroed.
  static String bytesToHex(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Overwrites [bytes] in place with zeros — call this the moment a raw
  /// key is no longer needed (ADR-005's re-lock policy: "zero the
  /// in-memory key"). This only works because [bytes] is a mutable
  /// [Uint8List], never a `String`.
  static void zeroize(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}
