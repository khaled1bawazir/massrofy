/// A source-level guard on the Activity that hosts the app lock's biometric
/// prompt (KHA-71).
///
/// ## Why a *source* test, and why it is worth having anyway
///
/// `local_auth` shows Android's `BiometricPrompt` inside a `DialogFragment`,
/// which can only be attached to an `androidx.fragment.app.FragmentActivity`.
/// Its Android implementation therefore checks the host Activity's type first
/// (`LocalAuthPlugin.java` -> `AuthResultCode.NOT_FRAGMENT_ACTIVITY`) and, if
/// the check fails, returns an error *without ever showing a dialog*. Because
/// `MainActivity` extended plain `FlutterActivity`, the app lock gate (S-09,
/// ADR-005) sat on "Unlock to view your data" forever on a real device and
/// nothing behind it was reachable — the whole app, blocked by one word in a
/// superclass name.
///
/// Nothing in CI caught that, and nothing in CI *can*: a biometric prompt
/// needs real hardware with an enrolled credential, so neither a widget test
/// (no Android at all) nor the ADR-003 emulator job (no biometric enrolment,
/// and it never drives the lock gate) exercises the path. The defect is
/// invisible right up until a human installs the APK on a phone.
///
/// What is left is to assert the *shape* of the code that the runtime
/// behaviour depends on. This test reads `MainActivity.kt` as text and fails
/// if the superclass is ever changed back. That is a weak check compared with
/// exercising a real prompt — it proves the declaration, not that
/// authentication works — but the failure it guards against is precisely a
/// one-token edit, which is exactly what a text check catches. A future
/// refactor that reverts it now fails a test with an explanation attached,
/// instead of shipping green and unusable.
///
/// Manual verification is still required after any change here: install the
/// debug APK on a device with a fingerprint/PIN enrolled and confirm the
/// native prompt appears on first run.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Path is relative to the package root, which is `flutter test`'s working
/// directory.
const String _mainActivityPath =
    'android/app/src/main/kotlin/com/massrofy/massrofy/MainActivity.kt';

void main() {
  group('MainActivity hosts local_auth correctly (KHA-71)', () {
    late String source;

    setUpAll(() {
      final File file = File(_mainActivityPath);
      // Guard the guard: if the file is ever moved, this test must fail
      // loudly rather than quietly assert nothing about an empty string.
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'expected to find $_mainActivityPath. If MainActivity moved, '
            'update this test — do not delete it: it is the only automated '
            'check that the biometric prompt can be shown at all.',
      );
      source = file.readAsStringSync();
    });

    test('extends FlutterFragmentActivity, which local_auth requires', () {
      expect(
        source,
        contains('class MainActivity : FlutterFragmentActivity()'),
        reason:
            'MainActivity must extend io.flutter.embedding.android.'
            'FlutterFragmentActivity. AndroidX Biometric hosts BiometricPrompt '
            'in a DialogFragment, so local_auth refuses to show any prompt '
            'unless the host Activity is a FragmentActivity (KHA-71). With a '
            'plain FlutterActivity the app lock gate (S-09) is unpassable on '
            'a real device and the entire app is unreachable.',
      );
    });

    test('imports FlutterFragmentActivity and does not extend or import the '
        'plain FlutterActivity', () {
      expect(
        source,
        contains('import io.flutter.embedding.android.FlutterFragmentActivity'),
        reason: 'the superclass must be imported from the Flutter embedding',
      );

      // Deliberately matched as *code* rather than as a bare word: the file's
      // own doc comment explains the bug and therefore names the wrong class
      // in prose several times. Only these two forms would actually change
      // the compiled superclass.
      for (final String forbidden in <String>[
        'import io.flutter.embedding.android.FlutterActivity',
        ': FlutterActivity(',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              'found "$forbidden" in $_mainActivityPath. The plain '
              'FlutterActivity cannot host a biometric prompt (KHA-71). If a '
              'second Activity that never authenticates is added later, '
              'narrow this assertion rather than deleting it.',
        );
      }
    });
  });
}
