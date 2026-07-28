// KHA-75's regression coverage: the ADR-004 Keystore channel, exercised
// over the REAL platform channel on a REAL Android device/emulator.
//
// ## Why this file has to exist (and why more Dart unit tests could not
// have prevented the bug it covers)
//
// `test/core/crypto/android_keystore_key_manager_test.dart` tests
// `AndroidKeystoreKeyManager` against a *fake* `MethodChannel` handler. A
// fake handler hands the Dart value straight back — it never crosses the
// Dart→Java codec boundary. On the real boundary, Flutter's
// `StandardMessageCodec` encodes a Dart `Uint8List` as a typed-data buffer
// that Kotlin decodes as `byte[]`, but a plain `List<int>` as a list that
// Kotlin decodes as `java.util.List<Integer>`. Those are different Java
// types, and `KeystoreChannel.kt` read every byte argument as the second one
// while every production caller sent the first.
//
// The result, verified on a stock Android 15 emulator with a PIN and a
// fingerprint enrolled:
//
//   E/MassrofyKeystore: java.lang.ClassCastException:
//       byte[] cannot be cast to java.util.List
//         at KeystoreChannel.intListArg(KeystoreChannel.kt:158)
//         at KeystoreChannel.onMethodCall(KeystoreChannel.kt:119)
//
// — thrown on *every* wrap and *every* unwrap, on every device, so the app
// lock could never be passed by anybody. `AppLockController`'s `catch (_)`
// then reported it to the user as "Authentication failed. Try again.",
// making a total platform bug look like a wrong fingerprint. It survived a
// full review cycle and was initially diagnosed as an OEM secure-hardware
// incompatibility.
//
// So: this file's job is to make sure the two halves of the channel still
// agree about the wire format. Everything else about the Keystore is
// secondary here.
//
// ## What this test asserts, and why it does not need an unlocked device
//
// The `massrofy.dbkek` key is created with
// `setUserAuthenticationRequired(true)`, so a *successful* wrap needs a
// device that (a) has a secure lock screen and (b) authenticated within the
// last few seconds. A CI emulator has neither, and arranging both would make
// this test a flaky race against a 5-second window.
//
// It does not need to. The bug being guarded against is an
// argument-*decoding* failure, which happens strictly BEFORE any Keystore
// work — so the assertion is about which failures are possible, not about
// success:
//
//   - `invalid_argument` (KeystoreFailureKind.invalidArgument) means the
//     Kotlin side could not read what Dart sent. That is KHA-75, and it must
//     never happen again. **This is the assertion.**
//   - Success, `user_not_authenticated`, or a plain `keystore_error` (e.g.
//     "Secure lock screen must be set up") all mean the arguments decoded
//     fine and the call reached real Keystore work. All are accepted here.
//
// On a device that *is* set up (a developer machine, or the human's phone),
// the same test additionally exercises a genuine round trip when the wrap
// succeeds — see the second test.
//
// Run via:
//   flutter test integration_test/keystore_channel_test.dart -d <deviceId>
// See the `android-sqlcipher-integration-test` job in
// `.github/workflows/ci.yml`, which runs every file in `integration_test/`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:massrofy/core/crypto/android_keystore_key_manager.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';

/// A Keystore alias used only by this test, so it can never disturb the real
/// `massrofy.dbkek` / `massrofy.auditchain` entries on a developer's device.
const String _testAlias = 'massrofy.test.kha75';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const AndroidKeystoreKeyManager keyManager = AndroidKeystoreKeyManager();

  // 32 bytes, generated the same way `DbMasterKeyStore` generates the real
  // DB Master Key: as a `Uint8List`. That type is the whole point of this
  // file — a `List<int>` here would not reproduce the original bug.
  final Uint8List secret = Uint8List.fromList(
    List<int>.generate(32, (int i) => i),
  );

  tearDown(() async {
    // Best-effort cleanup; a delete of a non-existent alias is a no-op in
    // `KeystoreChannel.deleteKey`, and a failure here must not fail the test.
    try {
      await keyManager.deleteKeystoreKek(keyAlias: _testAlias);
    } on Object {
      // ignored — see above
    }
  });

  testWidgets(
    'KHA-75 — a Uint8List argument is decodable by KeystoreChannel.kt, so a '
    'wrap never fails with invalid_argument',
    (WidgetTester tester) async {
      KeystoreOperationException? failure;
      try {
        await keyManager.wrapWithKeystoreKek(secret, keyAlias: _testAlias);
      } on KeystoreOperationException catch (e) {
        failure = e;
      } on KeystoreKeyInvalidatedException {
        // Also fine: it means the call reached real Keystore work.
      }

      expect(
        failure?.kind,
        isNot(KeystoreFailureKind.invalidArgument),
        reason:
            'invalid_argument means KeystoreChannel.kt could not decode the '
            'bytes Dart sent it — that is exactly KHA-75 (a Uint8List '
            'arriving as byte[] while the Kotlin side read java.util.List), '
            'and it broke the app lock on 100% of devices. Any OTHER outcome '
            '(success, user_not_authenticated, or a plain keystore_error such '
            'as "Secure lock screen must be set up") is acceptable here: all '
            'of those prove the arguments decoded and the call got as far as '
            'real Keystore work, which is what this test exists to prove.',
      );
    },
    skip: !Platform.isAndroid,
  );

  testWidgets(
    'KHA-75 — when the device is set up enough for the wrap to succeed, the '
    'unwrap round trip returns the original bytes',
    (WidgetTester tester) async {
      WrappedKey wrapped;
      try {
        wrapped = await keyManager.wrapWithKeystoreKek(
          secret,
          keyAlias: _testAlias,
        );
      } on KeystoreOperationException catch (e) {
        // Typically: no secure lock screen, or no authentication inside the
        // 5-second `AUTH_VALIDITY_SECONDS` window — neither of which a CI
        // emulator has. There is then nothing to round-trip, so this is
        // reported honestly as a skip rather than silently passing.
        //
        // `invalid_argument` is deliberately NOT skipped-over quietly: it is
        // the KHA-75 regression, and the previous test has already failed
        // hard on it. Naming it here keeps the two messages consistent
        // instead of blaming a missing lock screen for a decoding bug.
        markTestSkipped(
          e.kind == KeystoreFailureKind.invalidArgument
              ? 'skipped because the channel could not decode its arguments '
                    '(${e.code}) — see the failing KHA-75 test above; this '
                    'test could not have run regardless'
              : 'device cannot complete an auth-bound Keystore wrap '
                    '(${e.code}) — it needs a secure lock screen AND an '
                    'authentication within the last few seconds. The '
                    'decoding assertion in the previous test still ran.',
        );
        return;
      }

      // The wrapped blob must itself be well-formed: AES-GCM over 32 bytes
      // with a 128-bit tag is 48 bytes of ciphertext, and a 96-bit nonce.
      expect(wrapped.nonce, hasLength(12));
      expect(wrapped.ciphertext, hasLength(secret.length + 16));

      final List<int> unwrapped = await keyManager.unwrapWithKeystoreKek(
        wrapped,
        keyAlias: _testAlias,
      );
      expect(
        unwrapped,
        secret,
        reason:
            'the DB Master Key must survive a wrap/unwrap round trip byte for '
            'byte — anything else means the encrypted database could not be '
            'reopened on the next launch',
      );
    },
    skip: !Platform.isAndroid,
  );
}
