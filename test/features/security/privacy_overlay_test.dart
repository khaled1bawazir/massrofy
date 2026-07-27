import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/security/privacy_overlay.dart';

/// Ordinary (debug-mode) behaviour of [PrivacyGate] — every `flutter test`
/// run (including this one) compiles with `kReleaseMode == false` (see the
/// dedicated `privacy_overlay_release_mode_test.dart` for the test that
/// actually flips that constant), so the QA-disable flag is irrelevant
/// here: the `!kReleaseMode` guard on it plays no role in a normal debug
/// build/test run, since the flag itself defaults to `false` unless a
/// developer explicitly builds with
/// `--dart-define=MASSROFY_DISABLE_PRIVACY_OVERLAY=true`. This file proves
/// the channel is invoked at all in the everyday case; the release-mode
/// file proves the "no shipped bypass" guarantee ADR-014 actually depends
/// on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('massrofy/privacy_channel');
  final List<MethodCall> calls = <MethodCall>[];

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    mockHandler((MethodCall call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'setObscured(true) invokes the platform channel with obscured=true',
    () async {
      const PrivacyGate gate = PrivacyGate(channel: channel);
      await gate.setObscured(true);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setObscured');
      expect(calls.single.arguments['obscured'], isTrue);
    },
  );

  test(
    'setObscured(false) invokes the platform channel with obscured=false',
    () async {
      const PrivacyGate gate = PrivacyGate(channel: channel);
      await gate.setObscured(false);

      expect(calls, hasLength(1));
      expect(calls.single.arguments['obscured'], isFalse);
    },
  );
}
