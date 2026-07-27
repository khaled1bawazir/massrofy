import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ADR-014: obscures the OS app-switcher (recents) snapshot without
/// shipping a bypass.
///
/// This talks to `android/.../PrivacyPlugin.kt` over the
/// `massrofy/privacy_channel` MethodChannel, which does the real work
/// (`setRecentsScreenshotEnabled`/`FLAG_SECURE`, branched by API level — see
/// that file). [PrivacyGate] itself only decides *when* to call it: on
/// `AppLifecycleState.inactive` (about to be backgrounded — obscure) and
/// `AppLifecycleState.resumed` (foregrounded again — un-obscure), which is
/// wired up by `PrivacyOverlayObserver` below.
///
/// **No shipped bypass (ADR-014).** [kMassrofyDisablePrivacyOverlayForQa] is
/// read from a `--dart-define` **and** gated behind `!kReleaseMode`, so the
/// Dart compiler tree-shakes the entire branch out of a release build —
/// there is no runtime toggle an end user (or an attacker) could ever
/// flip in a shipped APK. QA uses a debug build when it needs a
/// switcher-snapshot screenshot for evidence; foreground screenshots work
/// normally in every build configuration regardless.
class PrivacyGate {
  static const MethodChannel _channel = MethodChannel(
    'massrofy/privacy_channel',
  );

  final MethodChannel channel;

  const PrivacyGate({MethodChannel? channel}) : channel = channel ?? _channel;

  Future<void> setObscured(bool obscured) async {
    // QA escape hatch: exists ONLY in non-release builds. `kReleaseMode` is
    // a compile-time constant (`bool.fromEnvironment` under the hood), so
    // the Dart compiler proves this branch is dead code in a release build
    // and removes it entirely — there is no `if` left to bypass at runtime.
    if (!kReleaseMode && _qaDisableOverlay) {
      return;
    }
    await channel.invokeMethod<void>('setObscured', <String, Object?>{
      'obscured': obscured,
    });
  }
}

/// `--dart-define=MASSROFY_DISABLE_PRIVACY_OVERLAY=true` — read once as a
/// compile-time constant. Referencing this constant only inside a
/// `!kReleaseMode` branch (see [PrivacyGate.setObscured]) is what makes it
/// tree-shakeable; a `const bool.fromEnvironment` read directly inside
/// release code would NOT be safe to treat as absent, so the ordering here
/// matters and is deliberate.
const bool _qaDisableOverlay = bool.fromEnvironment(
  'MASSROFY_DISABLE_PRIVACY_OVERLAY',
);

/// Belt-and-braces Flutter-side scrim (ADR-014 measure 3): an opaque,
/// branded cover rendered over the whole app the instant the framework
/// reports `AppLifecycleState.inactive`, for the platforms/timings where
/// the native `FLAG_SECURE`/`setRecentsScreenshotEnabled` toggle isn't
/// guaranteed to land before the OS captures its snapshot. Removed again on
/// `resumed`.
class PrivacyScrim extends StatelessWidget {
  final bool visible;

  const PrivacyScrim({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return const ColoredBox(
      // Massrofy Navy (docs/brand.md `color.primary`) — a plain branded
      // scrim, never a blur-through of real content (AC-F1.2's "no
      // transaction data, totals, or card identifiers are visible" applies
      // just as much to a switcher preview as to the locked screen itself).
      color: Color(0xFF0B3D62),
      child: SizedBox.expand(),
    );
  }
}
