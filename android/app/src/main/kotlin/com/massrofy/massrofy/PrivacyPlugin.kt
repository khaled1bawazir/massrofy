package com.massrofy.massrofy

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ADR-014: obscures the OS app-switcher (recents) snapshot without shipping
 * a foreground-screenshot bypass. Backs
 * `lib/features/security/privacy_overlay.dart` over the
 * "massrofy/privacy_channel" MethodChannel.
 *
 * - API 33+: `Activity.setRecentsScreenshotEnabled(false)` -- the precise,
 *   supported API for exactly this requirement; foreground screenshots
 *   still work normally, only the recents-list thumbnail is blanked.
 * - Below API 33: toggles `FLAG_SECURE` on/off, driven from the Dart side
 *   on `AppLifecycleState.inactive`/`resumed` (see `privacy_overlay.dart`),
 *   so the recents snapshot is blanked while the app is foregrounded and
 *   screenshots are otherwise still possible on that path too.
 *
 * There is no runtime toggle in a release build: the only caller of
 * "setObscured": false from Dart is the app resuming to the foreground, and
 * the debug-only escape hatch used by QA
 * (`MASSROFY_DISABLE_PRIVACY_OVERLAY`) lives entirely on the Dart side,
 * guarded by `kReleaseMode` so it is tree-shaken out of release builds --
 * this native class has no knowledge of that flag at all, by design
 * (ADR-014: "there is no shipped bypass").
 */
class PrivacyPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setObscured" -> {
                val obscured = call.argument<Boolean>("obscured") ?: true
                setObscured(obscured)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setObscured(obscured: Boolean) {
        if (Build.VERSION.SDK_INT >= 33) {
            activity.setRecentsScreenshotEnabled(!obscured)
        } else {
            if (obscured) {
                activity.window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE
                )
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }
}
