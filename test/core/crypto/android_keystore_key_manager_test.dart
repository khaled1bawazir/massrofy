import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/android_keystore_key_manager.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';

/// These tests exercise the **Dart-side contract**
/// `AndroidKeystoreKeyManager` implements — method names, argument shapes,
/// and exception mapping — against a fake `MethodChannel` handler standing
/// in for `android/.../KeystoreChannel.kt`.
///
/// ## Read this before adding a test here and considering the job done
/// (KHA-75)
/// A fake `MethodChannel` handler **never crosses the Dart→Java codec
/// boundary**. It hands the Dart value straight back, so a `Uint8List` and a
/// plain `List<int>` are indistinguishable in this file. On the real Kotlin
/// side they are not: `StandardMessageCodec` decodes the former as `byte[]`
/// and the latter as `java.util.List<Integer>`. KHA-75 was precisely that
/// mismatch — every production wrap/unwrap threw
/// `ClassCastException: byte[] cannot be cast to java.util.List`, on every
/// Android device, while this file stayed green because its tests passed
/// plain lists.
///
/// The `'sends bytes as a Uint8List'` tests below pin the encoding these
/// tests *can* meaningfully assert. The genuine end-to-end coverage lives in
/// `integration_test/keystore_channel_test.dart`, which invokes the real
/// channel on a real device. Neither is sufficient alone.
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

  group('KHA-75 — byte arguments must cross the channel as a Uint8List, '
      'because KeystoreChannel.kt decodes them as a Kotlin ByteArray', () {
    test('wrapWithKeystoreKek normalises a plain List<int> to a Uint8List '
        'before sending it', () async {
      late MethodCall received;
      mockHandler((MethodCall call) async {
        received = call;
        return <String, Object?>{
          'ciphertext': <int>[1],
          'nonce': <int>[2],
        };
      });

      // A caller passing the interface's declared `List<int>` — the shape
      // that used to encode as a Java list and get read correctly, while
      // production's `Uint8List` did not. Both must now arrive identically.
      await manager.wrapWithKeystoreKek(<int>[9, 9, 9]);

      expect(
        received.arguments['keyBytes'],
        isA<Uint8List>(),
        reason:
            'a plain List<int> encodes as java.util.List<Integer> on the '
            'Kotlin side; only a Uint8List encodes as the byte[] that '
            'KeystoreChannel.byteArrayArg is written against',
      );
      expect(received.arguments['keyBytes'], <int>[9, 9, 9]);
    });

    test(
      'unwrapWithKeystoreKek sends ciphertext and nonce as Uint8List',
      () async {
        late MethodCall received;
        mockHandler((MethodCall call) async {
          received = call;
          return <int>[7];
        });

        await manager.unwrapWithKeystoreKek(
          WrappedKey(
            ciphertext: Uint8List.fromList(<int>[1, 2]),
            nonce: Uint8List.fromList(<int>[3, 4]),
          ),
        );

        expect(received.arguments['ciphertext'], isA<Uint8List>());
        expect(received.arguments['nonce'], isA<Uint8List>());
      },
    );
  });

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

  group('KHA-75 — every other platform error becomes a typed '
      'KeystoreOperationException, so AppLockController can tell a platform '
      'fault apart from a wrong credential (it previously could not, and '
      'reported both as "Authentication failed")', () {
    // Each KeystoreChannel.kt error code, and the kind it must map to.
    const Map<String, KeystoreFailureKind> cases =
        <String, KeystoreFailureKind>{
          'invalid_argument': KeystoreFailureKind.invalidArgument,
          'user_not_authenticated': KeystoreFailureKind.userNotAuthenticated,
          'keystore_error': KeystoreFailureKind.platform,
          'something_we_never_send': KeystoreFailureKind.unknown,
        };

    for (final MapEntry<String, KeystoreFailureKind> entry in cases.entries) {
      test('"${entry.key}" maps to ${entry.value}', () async {
        mockHandler((MethodCall call) async {
          throw PlatformException(code: entry.key);
        });

        final WrappedKey wrapped = WrappedKey(
          ciphertext: Uint8List.fromList(<int>[1]),
          nonce: Uint8List.fromList(<int>[2]),
        );
        await expectLater(
          manager.unwrapWithKeystoreKek(wrapped),
          throwsA(
            isA<KeystoreOperationException>()
                .having((e) => e.kind, 'kind', entry.value)
                .having((e) => e.code, 'code', entry.key),
          ),
        );
      });
    }

    test('wrapWithKeystoreKek maps platform errors too — the first-run path '
        'that KHA-75 actually broke goes through wrap, not unwrap', () async {
      mockHandler((MethodCall call) async {
        throw PlatformException(code: 'invalid_argument');
      });

      await expectLater(
        manager.wrapWithKeystoreKek(<int>[1, 2, 3]),
        throwsA(
          isA<KeystoreOperationException>().having(
            (e) => e.kind,
            'kind',
            KeystoreFailureKind.invalidArgument,
          ),
        ),
      );
    });
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
