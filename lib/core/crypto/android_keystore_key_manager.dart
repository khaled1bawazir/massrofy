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
/// key generation and wrap/unwrap against that API, exactly as ADR-004
/// specifies (alias `massrofy.dbkek`, `setInvalidatedByBiometricEnrollment(true)`).
///
/// **Test-coverage honesty note (see the PR description for the full
/// statement):** this class's Dart-side contract (method names, argument
/// shapes, exception mapping) is covered by
/// `test/core/crypto/android_keystore_key_manager_test.dart` against a
/// fake `MethodChannel` handler. The Kotlin implementation itself has not
/// been exercised by an automated instrumented test in this PR — doing so
/// needs a real Android device or emulator with Keystore/biometric hardware,
/// which this build environment does not have. That is a known gap, not a
/// claim of coverage that doesn't exist.
class AndroidKeystoreKeyManager implements KeyManager {
  static const MethodChannel _channel = MethodChannel(
    'massrofy/keystore_channel',
  );

  /// Injectable for tests — production code should use the default.
  final MethodChannel channel;

  const AndroidKeystoreKeyManager({MethodChannel? channel})
    : channel = channel ?? _channel;

  @override
  Future<WrappedKey> wrapWithKeystoreKek(List<int> dbMasterKey) async {
    final Map<Object?, Object?>? result = await channel
        .invokeMapMethod<Object?, Object?>(
          'wrapWithKeystoreKek',
          <String, Object?>{'keyBytes': dbMasterKey},
        );
    if (result == null) {
      throw PlatformException(
        code: 'null_result',
        message: 'KeystoreChannel.wrapWithKeystoreKek returned null',
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
  }

  @override
  Future<List<int>> unwrapWithKeystoreKek(WrappedKey wrapped) async {
    try {
      final List<Object?>? result = await channel.invokeListMethod<Object?>(
        'unwrapWithKeystoreKek',
        <String, Object?>{
          'ciphertext': wrapped.ciphertext,
          'nonce': wrapped.nonce,
        },
      );
      if (result == null) {
        throw PlatformException(
          code: 'null_result',
          message: 'KeystoreChannel.unwrapWithKeystoreKek returned null',
        );
      }
      return result.cast<int>();
    } on PlatformException catch (e) {
      if (e.code == 'key_permanently_invalidated') {
        throw const KeystoreKeyInvalidatedException();
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteKeystoreKek() async {
    await channel.invokeMethod<void>('deleteKeystoreKek');
  }
}
