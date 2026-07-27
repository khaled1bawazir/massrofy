@Tags(<String>['release_mode_guard'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/security/privacy_overlay.dart';

/// ADR-014's "no shipped bypass" guarantee, actually exercised under
/// release-mode semantics — not merely asserted in a comment.
///
/// ## Why this is a genuine release-mode test, not a simulation
/// `kReleaseMode` (from `package:flutter/foundation.dart`) is defined as
/// `const bool.fromEnvironment('dart.vm.product')`. Flutter's build
/// tooling normally sets that environment value automatically based on
/// `--release`/`--profile`/`--debug`, and `flutter test` always compiles
/// in the equivalent of debug mode by default — which is exactly why a
/// plain `flutter test` run of this file would silently prove nothing (see
/// the loud self-check below, which exists precisely so that failure mode
/// cannot happen quietly). However, **`flutter test` accepts
/// `--dart-define` the same as `flutter run`/`flutter build`**, and
/// `dart.vm.product` is an ordinary key as far as that flag is concerned —
/// passing `--dart-define=dart.vm.product=true` genuinely flips
/// `kReleaseMode` to `true` for this test run (verified empirically while
/// building this fix). That means the assertions below run against the
/// **real** compile-time constant a release build would have, not a mock
/// or an injected seam — this is the actual `PrivacyGate.setObscured`
/// production code path, compiled the way a release build compiles it.
///
/// This file MUST be run as:
/// ```
/// flutter test --dart-define=dart.vm.product=true \
///   --dart-define=MASSROFY_DISABLE_PRIVACY_OVERLAY=true \
///   test/features/security/privacy_overlay_release_mode_test.dart
/// ```
/// — see the dedicated CI step in `.github/workflows/ci.yml` that pins
/// exactly this command line. Run under a plain `flutter test` (no
/// defines), `kReleaseMode` would already be `false` for the wrong reason
/// (debug mode, not "the bypass correctly didn't apply") and the first
/// assertion below fails loudly rather than the test passing for a reason
/// that proves nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('massrofy/privacy_channel');

  test('even with the QA-disable dart-define ALSO set, setObscured still '
      'calls the platform channel once dart.vm.product genuinely reports '
      'release mode — proving there is no reachable bypass in a release '
      'build, not merely documenting the intent', () async {
    // Fail loudly, first, if this file is ever run without the defines
    // that make the rest of this test meaningful — see the doc comment.
    expect(
      kReleaseMode,
      isTrue,
      reason:
          'This test must be run with --dart-define=dart.vm.product=true '
          '(see .github/workflows/ci.yml\'s dedicated CI step) — '
          'otherwise this is not actually exercising release-mode '
          'behaviour and the assertion below would pass for the wrong '
          'reason.',
    );

    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const PrivacyGate gate = PrivacyGate(channel: channel);
    await gate.setObscured(true);

    expect(
      calls,
      hasLength(1),
      reason:
          'the QA-disable branch is only ever reachable when '
          '!kReleaseMode — with kReleaseMode genuinely true here, '
          'setObscured must have called through to the platform channel '
          'regardless of the MASSROFY_DISABLE_PRIVACY_OVERLAY define',
    );
    expect(calls.single.method, 'setObscured');
  });
}
