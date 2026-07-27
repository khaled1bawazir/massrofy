import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/android_keystore_key_manager.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';

/// These tests exercise the **Dart-side contract**
/// `AndroidKeystoreKeyManager` implements — method names, argument shapes,
/// and exception mapping — against a fake `MethodChannel` handler standing
/// in for `android/.../KeystoreChannel.kt`. They deliberately do **not**
/// exercise real Android Keystore hardware, which this build environment
/// does not have; see that Kotlin file's doc comment for the honest
/// statement of what is and isn't covered by automated tests in this PR.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('massrofy/keystore_channel');
  late AndroidKeystoreKeyManager manager;

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    manager = const AndroidKeystoreKeyManager(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'wrapWithKeystoreKek sends keyBytes and decodes the wrapped result',
    () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <String, Object?>{
          'ciphertext': <int>[1, 2, 3],
          'nonce': <int>[4, 5, 6],
        };
      });

      final WrappedKey result = await manager.wrapWithKeystoreKek(<int>[
        9,
        9,
        9,
      ]);

      expect(received.method, 'wrapWithKeystoreKek');
      expect(received.arguments['keyBytes'], <int>[9, 9, 9]);
      expect(result.ciphertext, <int>[1, 2, 3]);
      expect(result.nonce, <int>[4, 5, 6]);
    },
  );

  test(
    'unwrapWithKeystoreKek sends ciphertext/nonce and decodes the raw key',
    () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <int>[7, 7, 7];
      });

      final WrappedKey wrapped = WrappedKey(
        ciphertext: Uint8List.fromList(<int>[1, 2]),
        nonce: Uint8List.fromList(<int>[3, 4]),
      );
      final List<int> raw = await manager.unwrapWithKeystoreKek(wrapped);

      expect(received.method, 'unwrapWithKeystoreKek');
      expect(received.arguments['ciphertext'], wrapped.ciphertext);
      expect(received.arguments['nonce'], wrapped.nonce);
      expect(raw, <int>[7, 7, 7]);
    },
  );

  test('a "key_permanently_invalidated" PlatformException maps to '
      'KeystoreKeyInvalidatedException (ADR-004 recovery trigger)', () async {
    mockHandler((MethodCall call) async {
      throw PlatformException(code: 'key_permanently_invalidated');
    });

    final WrappedKey wrapped = WrappedKey(
      ciphertext: Uint8List.fromList(<int>[1]),
      nonce: Uint8List.fromList(<int>[2]),
    );
    await expectLater(
      manager.unwrapWithKeystoreKek(wrapped),
      throwsA(isA<KeystoreKeyInvalidatedException>()),
    );
  });

  test('any other PlatformException is rethrown as-is', () async {
    mockHandler((MethodCall call) async {
      throw PlatformException(code: 'some_other_error');
    });

    final WrappedKey wrapped = WrappedKey(
      ciphertext: Uint8List.fromList(<int>[1]),
      nonce: Uint8List.fromList(<int>[2]),
    );
    await expectLater(
      manager.unwrapWithKeystoreKek(wrapped),
      throwsA(isA<PlatformException>()),
    );
  });

  test('deleteKeystoreKek invokes the channel method', () async {
    late MethodCall received;
    mockHandler((MethodCall call) async {
      received = call;
      return null;
    });

    await manager.deleteKeystoreKek();
    expect(received.method, 'deleteKeystoreKek');
  });

  group('keyAlias (item 4 — the same channel now backs both the DB Master '
      'Key KEK and ADR-010\'s separate audit-chain KEK)', () {
    test('wrapWithKeystoreKek defaults to the DB Master Key alias when none '
        'is given', () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <String, Object?>{
          'ciphertext': <int>[1],
          'nonce': <int>[2],
        };
      });

      await manager.wrapWithKeystoreKek(<int>[1, 2, 3]);
      expect(received.arguments['keyAlias'], 'massrofy.dbkek');
    });

    test('wrapWithKeystoreKek forwards an explicit keyAlias (e.g. the '
        'audit-chain alias)', () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <String, Object?>{
          'ciphertext': <int>[1],
          'nonce': <int>[2],
        };
      });

      await manager.wrapWithKeystoreKek(<int>[
        1,
        2,
        3,
      ], keyAlias: 'massrofy.auditchain');
      expect(received.arguments['keyAlias'], 'massrofy.auditchain');
    });

    test('unwrapWithKeystoreKek forwards an explicit keyAlias', () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <int>[9];
      });

      final WrappedKey wrapped = WrappedKey(
        ciphertext: Uint8List.fromList(<int>[1]),
        nonce: Uint8List.fromList(<int>[2]),
      );
      await manager.unwrapWithKeystoreKek(
        wrapped,
        keyAlias: 'massrofy.auditchain',
      );
      expect(received.arguments['keyAlias'], 'massrofy.auditchain');
    });

    test('deleteKeystoreKek forwards an explicit keyAlias', () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return null;
      });

      await manager.deleteKeystoreKek(keyAlias: 'massrofy.auditchain');
      expect(received.arguments['keyAlias'], 'massrofy.auditchain');
    });
  });
}
