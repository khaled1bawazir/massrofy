import 'package:flutter/services.dart';

import 'key_manager.dart';
import 'wrapped_key.dart';

/// [KeyManager] backed by the real Android Keystore, via a `MethodChannel`
/// to `android/app/src/main/kotlin/.../KeystoreChannel.kt`.
///
/// ## Why a platform channel, and what it actually buys us (ADR-004/005)
/// Android Keystore-held keys — the kind that can require
/// `setUserAuthenticationRequired(true)` and survive with hardware/TEE
/// backing — are not reachable from pure Dart; there is no `dart:` or pub
/// package that talks to `android.security.keystore.KeyGenParameterSpec`.
/// [KeystoreChannel.kt] is real, hand-written Kotlin implementing AES-256-GCM
/// key generation and wrap/unwrap against that API (alias `massrofy.dbkek`
/// for the DB Master Key, `massrofy.auditchain` for ADR-010's audit chain
/// key — see [keyAlias] below) — see that file's doc comment for the two
/// deliberate, documented departures from ADR-004's literal text in this P1
/// slice: a time-bound (not per-operation) authentication window, and
/// `setInvalidatedByBiometricEnrollment(false)` until a real recovery path
/// exists.
///
/// **Test-coverage note (rewritten by KHA-75 — the previous wording was
/// technically true and still let a total, ship-blocking defect through).**
/// `test/core/crypto/android_keystore_key_manager_test.dart` covers this
/// class against a *fake* `MethodChannel` handler. A fake handler never
/// crosses the Dart→Java codec boundary: it hands the Dart value straight
/// back, so `Uint8List` looks identical to `List<int>` on both ends. The
/// Kotlin side, however, decodes those two as `byte[]` and
/// `java.util.List<Integer>` respectively, and KHA-75 was precisely that
/// mismatch — every real wrap/unwrap threw `ClassCastException` while
/// every Dart test stayed green. The fix is threefold and all three parts
/// matter: [_asWireBytes] pins one encoding here,
/// `KeystoreChannel.byteArrayArg` accepts it there, and
/// `integration_test/keystore_channel_test.dart` runs the *real* channel on
/// a real device so the wire format is genuinely asserted.
class AndroidKeystoreKeyManager implements KeyManager {
  static const MethodChannel _channel = MethodChannel(
    'massrofy/keystore_channel',
  );

  /// Injectable for tests — production code should use the default.
  final MethodChannel channel;

  const AndroidKeystoreKeyManager({MethodChannel? channel})
    : channel = channel ?? _channel;

  /// Normalises whatever byte container a caller passed into the ONE wire
  /// representation `KeystoreChannel.kt` expects (KHA-75).
  ///
  /// Flutter's `StandardMessageCodec` encodes a `Uint8List` as a typed-data
  /// buffer (decoded on the Kotlin side as `byte[]`) but a plain `List<int>`
  /// as a list (decoded as `java.util.List<Integer>`) — two different wire
  /// shapes for the same idea. Leaving the choice to each call site is what
  /// caused KHA-75: production always passed `Uint8List` while the only
  /// tests passed plain lists, so the two halves of the channel disagreed
  /// and nothing caught it. Converting here means there is exactly one
  /// possible encoding on the wire no matter who calls, and the Kotlin side
  /// only has to be right about one of them.
  ///
  /// `Uint8List.fromList` is a no-op-ish copy when the input already is one;
  /// these are 32-byte keys, so the copy is irrelevant next to the
  /// correctness guarantee.
  static Uint8List _asWireBytes(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// Translates `KeystoreChannel.kt`'s error codes into the typed
  /// exceptions the `features/` layer catches — see
  /// [KeystoreOperationException] for why this mapping lives here rather
  /// than leaking `PlatformException` upward.
  static Never _throwMapped(PlatformException e) {
    if (e.code == 'key_permanently_invalidated') {
      throw const KeystoreKeyInvalidatedException();
    }
    throw KeystoreOperationException(
      code: e.code,
      kind: switch (e.code) {
        'invalid_argument' => KeystoreFailureKind.invalidArgument,
        'user_not_authenticated' => KeystoreFailureKind.userNotAuthenticated,
        'keystore_error' => KeystoreFailureKind.platform,
        _ => KeystoreFailureKind.unknown,
      },
    );
  }

  @override
  Future<WrappedKey> wrapWithKeystoreKek(
    List<int> secretBytes, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
    try {
      final Map<Object?, Object?>? result = await channel
          .invokeMapMethod<Object?, Object?>(
            'wrapWithKeystoreKek',
            <String, Object?>{
              'keyBytes': _asWireBytes(secretBytes),
              'keyAlias': keyAlias,
            },
          );
      if (result == null) {
        throw const KeystoreOperationException(
          kind: KeystoreFailureKind.unknown,
          code: 'null_result',
        );
      }
      return WrappedKey(
        ciphertext: Uint8List.fromList(
          (result['ciphertext']! as List<Object?>).cast<int>(),
        ),
        nonce: Uint8List.fromList(
          (result['nonce']! as List<Object?>).cast<int>(),
        ),
      );
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<List<int>> unwrapWithKeystoreKek(
    WrappedKey wrapped, {
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
    try {
      final List<Object?>? result = await channel
          .invokeListMethod<Object?>('unwrapWithKeystoreKek', <String, Object?>{
            'ciphertext': _asWireBytes(wrapped.ciphertext),
            'nonce': _asWireBytes(wrapped.nonce),
            'keyAlias': keyAlias,
          });
      if (result == null) {
        throw const KeystoreOperationException(
          kind: KeystoreFailureKind.unknown,
          code: 'null_result',
        );
      }
      return result.cast<int>();
    } on PlatformException catch (e) {
      _throwMapped(e);
    }
  }

  @override
  Future<void> deleteKeystoreKek({
    String keyAlias = kDbMasterKeyKeystoreAlias,
  }) async {
    await channel.invokeMethod<void>('deleteKeystoreKek', <String, Object?>{
      'keyAlias': keyAlias,
    });
  }
}
