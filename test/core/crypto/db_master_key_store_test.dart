import 'dart:typed_data';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/db_master_key_store.dart';
import 'package:massrofy/core/crypto/key_manager.dart';
import 'package:massrofy/core/crypto/passphrase_key_deriver.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';

/// A fake [KeyManager] that "wraps" by simply XOR-ing with a fixed pad —
/// not real cryptography, just enough round-trip behaviour to test
/// [DbMasterKeyStore]'s orchestration logic without an Android Keystore.
class _FakeKeyManager implements KeyManager {
  bool throwInvalidated = false;

  @override
  Future<WrappedKey> wrapWithKeystoreKek(
    List<int> secretBytes, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
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
    if (throwInvalidated) {
      throw const KeystoreKeyInvalidatedException();
    }
    return wrapped.ciphertext.map((int b) => b ^ 0xFF).toList();
  }

  @override
  Future<void> deleteKeystoreKek({
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {}
}

void main() {
  setUp(() {
    // Swaps the real platform channel for an in-memory fake, per
    // flutter_secure_storage's own documented testing helper.
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
  });

  test('hasExistingKey is false before anything is provisioned', () async {
    final DbMasterKeyStore store = DbMasterKeyStore(
      keyManager: _FakeKeyManager(),
      passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
    );
    expect(await store.hasExistingKey(), isFalse);
  });

  test(
    'provisionNewDatabaseKey generates a 32-byte key and marks the store as provisioned',
    () async {
      final DbMasterKeyStore store = DbMasterKeyStore(
        keyManager: _FakeKeyManager(),
        passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
      );

      final Uint8List key = await store.provisionNewDatabaseKey();
      expect(key.length, 32);
      expect(await store.hasExistingKey(), isTrue);
    },
  );

  test('unlockWithKeystore recovers the SAME key that was provisioned '
      '(the wrap/unwrap round-trip is what daily unlock depends on)', () async {
    final DbMasterKeyStore store = DbMasterKeyStore(
      keyManager: _FakeKeyManager(),
      passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
    );

    final Uint8List provisioned = await store.provisionNewDatabaseKey();
    final Uint8List unlocked = await store.unlockWithKeystore();

    expect(unlocked, provisioned);
  });

  test(
    'unlockWithKeystore before provisioning throws a clear StateError',
    () async {
      final DbMasterKeyStore store = DbMasterKeyStore(
        keyManager: _FakeKeyManager(),
        passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
      );
      expect(store.unlockWithKeystore(), throwsA(isA<StateError>()));
    },
  );

  test('a KeystoreKeyInvalidatedException from KeyManager propagates through '
      'unlockWithKeystore unchanged (ADR-004 recovery trigger)', () async {
    final _FakeKeyManager keyManager = _FakeKeyManager();
    final DbMasterKeyStore store = DbMasterKeyStore(
      keyManager: keyManager,
      passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
    );
    await store.provisionNewDatabaseKey();
    keyManager.throwInvalidated = true;
    expect(
      store.unlockWithKeystore(),
      throwsA(isA<KeystoreKeyInvalidatedException>()),
    );
  });

  test('provisionNewDatabaseKey never has an injectable, non-CSPRNG source '
      '(item 12) — two independently provisioned keys must not collide, '
      'which they would systematically if a predictable generator were ever '
      'reachable here', () async {
    final Uint8List keyA = await DbMasterKeyStore(
      keyManager: _FakeKeyManager(),
      passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
    ).provisionNewDatabaseKey();
    final Uint8List keyB = await DbMasterKeyStore(
      keyManager: _FakeKeyManager(),
      passphraseKeyDeriver: const Hkdf256PassphraseKeyDeriver(),
    ).provisionNewDatabaseKey();

    expect(keyA, isNot(keyB));
  });

  group('DbMasterKeyStore.bytesToHex / zeroize (ADR-005 memory hygiene)', () {
    test('bytesToHex produces lower-case, zero-padded hex', () {
      expect(DbMasterKeyStore.bytesToHex(<int>[0, 255, 16]), '00ff10');
    });

    test('zeroize overwrites every byte in place', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      DbMasterKeyStore.zeroize(bytes);
      expect(bytes, everyElement(0));
    });
  });
}
