import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_manager.dart';
import 'wrapped_key.dart';

/// The narrow surface production wiring (`app_providers.dart`) needs from
/// an audit-chain-key store — mirrors [DbMasterKeyRepository] in
/// `db_master_key_store.dart` on purpose (see that file's doc comment for
/// the pattern this deliberately repeats) so a test can supply a
/// lightweight fake instead of real `flutter_secure_storage`/Keystore
/// plumbing.
abstract interface class AuditChainKeyRepository {
  Future<bool> hasExistingKey();
  Future<Uint8List> provisionNewAuditChainKey();
  Future<Uint8List> unlockAuditChainKey();
}

/// Provisions and unwraps ADR-010's `auditChainKey` — the separate
/// Keystore-held key that seeds every audit-entry's HMAC-SHA256 tamper-
/// evidence chain (`AuditLogDao._computeHash`).
///
/// ## Why this class exists, and why it looks so much like [DbMasterKeyStore]
/// Before this change, `auditChainKey` had **no production source at all**:
/// every real call site either didn't exist yet, or a test constructed
/// `AuditLogDao` with a hard-coded `List<int>` it made up on the spot. This
/// class is what makes ADR-010's promise — *"`auditChainKey` is a separate
/// Keystore-held key"* — a real, reachable, production code path: a fresh
/// 32-byte CSPRNG value, generated once, wrapped by its **own** Keystore
/// alias (`massrofy.auditchain` — entirely separate from the DB Master
/// Key's `massrofy.dbkek`, so invalidating/deleting one never touches the
/// other), and persisted (wrapped, never raw) in `flutter_secure_storage`.
///
/// The shape deliberately mirrors [DbMasterKeyStore] — same "generate once,
/// wrap with a named Keystore alias, persist the wrapped blob, unwrap on
/// every unlock" pattern — reusing the *same* [KeyManager]/`KeystoreChannel`
/// machinery via the generic `keyAlias` parameter added to [KeyManager]
/// (see that file), rather than a second near-duplicate Kotlin
/// implementation. The two stores are still separate Dart classes (not one
/// generic "wrap any named secret" class) because that keeps each one's
/// doc comments talking about the *actual* key it manages — a small
/// readability trade this codebase already made once for
/// [DbMasterKeyStore] and repeats here for consistency.
class AuditChainKeyStore implements AuditChainKeyRepository {
  /// A distinct Keystore alias from the DB Master Key's `massrofy.dbkek` —
  /// see `lib/core/crypto/key_manager.dart`'s [kDbMasterKeyKeystoreAlias].
  static const String keystoreAlias = 'massrofy.auditchain';

  static const String _wrappedStorageKey = 'audit_chain_wrapped_by_keystore';

  final KeyManager keyManager;
  final FlutterSecureStorage secureStorage;

  // CSPRNG only, never injectable — see the identical reasoning on
  // `DbMasterKeyStore._random`, which this deliberately repeats: the value
  // generated below seeds a tamper-evidence hash chain for the whole audit
  // trail, so it must always come from a cryptographically-secure source,
  // never a caller-suppliable one that a test (or a future mistake) could
  // quietly swap for a predictable `Random(seed)`.
  final Random _random = Random.secure();

  AuditChainKeyStore({
    required this.keyManager,
    FlutterSecureStorage? secureStorage,
  }) : secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<bool> hasExistingKey() async {
    return (await secureStorage.read(key: _wrappedStorageKey)) != null;
  }

  /// First-run provisioning: generates a fresh 32-byte audit chain key,
  /// wraps it with the (separate) audit-chain Keystore KEK, and persists
  /// the wrapped blob. Returns the raw key bytes so the caller can pass
  /// them straight into `AuditLogDao(auditChainKey: ...)` for this session.
  @override
  Future<Uint8List> provisionNewAuditChainKey() async {
    final Uint8List rawKey = _generateRandomBytes(32);
    final WrappedKey wrapped = await keyManager.wrapWithKeystoreKek(
      rawKey,
      keyAlias: keystoreAlias,
    );
    await secureStorage.write(
      key: _wrappedStorageKey,
      value: jsonEncode(wrapped.toStorageMap()),
    );
    return rawKey;
  }

  /// Unwraps the previously-provisioned audit chain key — called on every
  /// unlock alongside [DbMasterKeyStore.unlockWithKeystore], so both keys
  /// become available together for the rest of that unlocked session (see
  /// `lib/presentation/providers/app_providers.dart`).
  @override
  Future<Uint8List> unlockAuditChainKey() async {
    final String? stored = await secureStorage.read(key: _wrappedStorageKey);
    if (stored == null) {
      throw StateError(
        'No Keystore-wrapped audit chain key exists yet — call '
        'provisionNewAuditChainKey() first.',
      );
    }
    final WrappedKey wrapped = WrappedKey.fromStorageMap(
      (jsonDecode(stored) as Map<String, Object?>).cast<String, String>(),
    );
    final List<int> rawKey = await keyManager.unwrapWithKeystoreKek(
      wrapped,
      keyAlias: keystoreAlias,
    );
    return Uint8List.fromList(rawKey);
  }

  Uint8List _generateRandomBytes(int length) {
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
