import 'dart:typed_data';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/audit_chain_key_store.dart';
import 'package:massrofy/core/crypto/key_manager.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';

/// A fake [KeyManager] recording which [keyAlias] each call used — the
/// point of this test file is to prove [AuditChainKeyStore] always uses
/// its own alias (`massrofy.auditchain`), never the DB Master Key's
/// (`massrofy.dbkek`), so the two keys truly have independent lifecycles
/// (ADR-010: "a separate Keystore-held key").
class _FakeKeyManager implements KeyManager {
  final List<String> wrapAliasesUsed = <String>[];
  final List<String> unwrapAliasesUsed = <String>[];

  @override
  Future<WrappedKey> wrapWithKeystoreKek(
    List<int> secretBytes, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
    wrapAliasesUsed.add(keyAlias);
    return WrappedKey(
      ciphertext: Uint8List.fromList(
        secretBytes.map((int b) => b ^ 0xFF).toList(),
      ),
      nonce: Uint8List.fromList(<int>[0, 1, 2]),
    );
  }

  @override
  Future<List<int>> unwrapWithKeystoreKek(
    WrappedKey wrapped, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
    unwrapAliasesUsed.add(keyAlias);
    return wrapped.ciphertext.map((int b) => b ^ 0xFF).toList();
  }

  @override
  Future<void> deleteKeystoreKek({
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {}
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
  });

  test('hasExistingKey is false before anything is provisioned', () async {
    final AuditChainKeyStore store = AuditChainKeyStore(
      keyManager: _FakeKeyManager(),
    );
    expect(await store.hasExistingKey(), isFalse);
  });

  test(
    'provisionNewAuditChainKey generates a 32-byte key, marks the store as '
    'provisioned, and wraps it under the dedicated massrofy.auditchain '
    'alias — never massrofy.dbkek (ADR-010: a SEPARATE Keystore-held key)',
    () async {
      final _FakeKeyManager keyManager = _FakeKeyManager();
      final AuditChainKeyStore store = AuditChainKeyStore(
        keyManager: keyManager,
      );

      final Uint8List key = await store.provisionNewAuditChainKey();
      expect(key.length, 32);
      expect(await store.hasExistingKey(), isTrue);
      expect(keyManager.wrapAliasesUsed, <String>['massrofy.auditchain']);
    },
  );

  test('unlockAuditChainKey recovers the SAME key that was provisioned, via '
      'the same dedicated alias', () async {
    final _FakeKeyManager keyManager = _FakeKeyManager();
    final AuditChainKeyStore store = AuditChainKeyStore(keyManager: keyManager);

    final Uint8List provisioned = await store.provisionNewAuditChainKey();
    final Uint8List unlocked = await store.unlockAuditChainKey();

    expect(unlocked, provisioned);
    expect(keyManager.unwrapAliasesUsed, <String>['massrofy.auditchain']);
  });

  test(
    'unlockAuditChainKey before provisioning throws a clear StateError',
    () async {
      final AuditChainKeyStore store = AuditChainKeyStore(
        keyManager: _FakeKeyManager(),
      );
      expect(store.unlockAuditChainKey(), throwsA(isA<StateError>()));
    },
  );

  test(
    'two independently provisioned audit chain keys never collide (CSPRNG, '
    'item 12 — no injectable non-secure Random exists on this class either)',
    () async {
      final Uint8List keyA = await AuditChainKeyStore(
        keyManager: _FakeKeyManager(),
      ).provisionNewAuditChainKey();
      final Uint8List keyB = await AuditChainKeyStore(
        keyManager: _FakeKeyManager(),
      ).provisionNewAuditChainKey();
      expect(keyA, isNot(keyB));
    },
  );
}
