/// A source-level guard on the Kotlin half of KHA-122's fix.
///
/// ## Why a source test, and what it is and is not worth
///
/// Same reasoning as `main_activity_host_test.dart`, which guards
/// `MainActivity`'s superclass: the behaviour depends on Kotlin that no Dart
/// test can execute. Raising the signal needs a real `SMS_RECEIVED` broadcast
/// from a real telephony stack, and the `EventChannel` needs a real engine
/// attached to a real Activity. Neither exists in `flutter test`, and the
/// ADR-003 emulator job does not deliver SMS.
///
/// What *can* be checked mechanically is the **shape of the wiring**, and that
/// is worth checking because the whole defect was a missing wire. Every
/// assertion below corresponds to one deletion that would silently restore
/// KHA-122:
///
/// | Deleted | Symptom on a device |
/// |---|---|
/// | `SmsForegroundBridge.signalSmsReceived()` in `SmsReceiver` | back to the original bug: nothing tells the foreground isolate anything |
/// | `SmsForegroundBridge.attach(...)` in `MainActivity` | the Dart stream never receives, so the signal is emitted into nothing |
/// | the channel name agreeing on both sides | as above, silently |
///
/// All three fail green today; after this file they fail red. The Dart-side
/// behaviour is covered properly by
/// `test/features/ingestion/immediate_sweep_wiring_test.dart`, which pumps the
/// real providers — this file only covers the seam that Dart cannot reach.
///
/// **Manual verification is still required** after any change here, and it is
/// QA's retest for KHA-122: with the app open and idle on Home, `adb emu sms
/// send` a rule-pack-matching message and watch the total move without
/// backgrounding the app.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ingestion/sms_broadcast_signal.dart';

const String _kotlinDir = 'android/app/src/main/kotlin/com/massrofy/massrofy';
const String _bridgePath = '$_kotlinDir/SmsForegroundBridge.kt';
const String _receiverPath = '$_kotlinDir/SmsReceiver.kt';
const String _mainActivityPath = '$_kotlinDir/MainActivity.kt';

String _read(String path) {
  final File file = File(path);
  // Guard the guard: a moved file must fail loudly rather than assert nothing
  // about an empty string.
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'expected to find $path. If it moved, update this test — do not delete '
        'it: it is the only automated check that the KHA-122 signal is wired at '
        'all.',
  );
  return file.readAsStringSync();
}

/// [source] with its comments removed.
///
/// Needed because these files explain the traps they avoid **by naming them**:
/// `SmsReceiver`'s own doc comment says *"note the total absence of
/// `Telephony.Sms.Intents.getMessagesFromIntent(intent)`"*. A naive
/// `contains` over the raw text would therefore fail on the very file whose
/// comment proves the author understood the rule — a test that punishes good
/// documentation. Stripping comments first asserts the property against the
/// *code*, which is what the property is about.
String _codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((String line) {
      final int comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

void main() {
  group('KHA-122 — the Kotlin -> Dart SMS signal is wired', () {
    test('SmsReceiver raises the signal as well as enqueuing the (no-op) '
        'background job', () {
      final String source = _read(_receiverPath);
      expect(
        source,
        contains('SmsForegroundBridge.signalSmsReceived()'),
        reason:
            'without this call nothing tells the foreground isolate an SMS has '
            'arrived, and AC-A1.1 fails again for the app-open-and-idle case: '
            'the WorkManager enqueue on the line above routes into '
            'runBackgroundIngestion(), which ADR-018 decision 1 makes an '
            'unconditional no-op.',
      );
      // The enqueue must stay too. It is the wake path for a dead process, and
      // deleting it would remove ADR-006 Layer 1 rather than fix anything.
      expect(
        source,
        contains('IngestScheduler.enqueueExpeditedSweep(context)'),
      );
    });

    test('SmsReceiver still reads nothing out of the intent (the security '
        'property the signal must not weaken)', () {
      final String source = _codeOnly(_read(_receiverPath));
      expect(
        source.contains('getMessagesFromIntent'),
        isFalse,
        reason:
            'the receiver must never touch the message body — ADR-006 chose a '
            'content-free wake precisely so a plaintext bank SMS can never '
            'reach a store this app does not encrypt. The KHA-122 signal is a '
            'bare marker for the same reason.',
      );
    });

    test('MainActivity attaches the bridge to the UI engine', () {
      final String source = _read(_mainActivityPath);
      expect(
        source,
        contains('SmsForegroundBridge.attach('),
        reason:
            'the EventChannel has to be installed on an engine for the Dart '
            'stream to receive anything. Attached only here, i.e. only on the '
            'engine that holds the unwrapped DB Master Key (ADR-005).',
      );
      expect(
        source,
        contains('SmsForegroundBridge.detach()'),
        reason:
            'a sink belonging to a destroyed engine would outlive the engine '
            'and throw on the next SMS',
      );
    });

    test('the channel name is the same string on both sides', () {
      // A mismatch here is the most plausible silent failure in the whole
      // change: both halves compile, the signal is emitted, and nothing ever
      // receives it.
      expect(
        _read(_bridgePath),
        contains('const val CHANNEL = "$smsEventChannelName"'),
        reason:
            'Kotlin and Dart must agree on the channel name. Dart\'s is '
            'smsEventChannelName in lib/features/ingestion/'
            'sms_broadcast_signal.dart.',
      );
    });

    test('the event payload is the same string on both sides', () {
      expect(
        _read(_bridgePath),
        contains('EVENT_SMS_RECEIVED = "$smsReceivedEvent"'),
        reason:
            'the Dart stream filters on this exact value, so a rename on one '
            'side alone would drop every signal while both halves still ran',
      );
    });

    test('the bridge carries no message content', () {
      final String source = _codeOnly(_read(_bridgePath));
      for (final String forbidden in <String>[
        'getMessagesFromIntent',
        'Telephony.Sms.BODY',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              'found "$forbidden" in $_bridgePath. This channel exists to say '
              '"something arrived", never what arrived (NFR-S1, NFR-S4).',
        );
      }
    });
  });
}
