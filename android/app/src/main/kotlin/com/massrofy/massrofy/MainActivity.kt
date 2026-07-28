package com.massrofy.massrofy

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's single Activity.
 *
 * ## Why `FlutterFragmentActivity` and not `FlutterActivity` (KHA-71)
 *
 * This superclass is **load-bearing for the app lock (ADR-005)**, not a
 * stylistic choice. `local_auth` — which backs
 * `lib/features/security/biometric_gate.dart`'s `LocalAuthBiometricGate` —
 * shows Android's `BiometricPrompt`, and AndroidX Biometric hosts that prompt
 * in a `DialogFragment`. A fragment needs a `FragmentManager`, which only an
 * `androidx.fragment.app.FragmentActivity` has. So `local_auth`'s Android
 * implementation begins with, literally:
 *
 * ```java
 * if (!(activity instanceof FragmentActivity)) {   // LocalAuthPlugin.java
 *   ... AuthResultCode.NOT_FRAGMENT_ACTIVITY ...   // -> never shows a prompt
 * }
 * ```
 *
 * With a plain `FlutterActivity` that branch is taken on **every** call: the
 * Dart side throws `LocalAuthException(uiUnavailable, "The current Activity
 * must be a FragmentActivity.")` and the native dialog is never shown at all.
 * Observed on a real device (Honor Magic V5) as the lock gate (S-09) sitting
 * on "Unlock to view your data" forever, with no prompt and no way past it —
 * i.e. 100% of the app unreachable. `FlutterFragmentActivity` is Flutter's
 * own drop-in replacement for exactly this case; it reads the same
 * `AndroidManifest` meta-data (`NormalTheme`, `SplashScreenDrawable`) and
 * honours the same `launchMode`/`configChanges`, so nothing else in the
 * manifest changes.
 *
 * `test/platform/main_activity_host_test.dart` asserts this superclass is
 * still `FlutterFragmentActivity`. It exists because no CI job can catch a
 * regression here behaviourally — a biometric prompt needs real hardware, and
 * a one-character edit back to `FlutterActivity` would otherwise ship a
 * completely unusable app with every check green.
 */
class MainActivity : FlutterFragmentActivity() {

    /**
     * Held as a field, unlike the other two channels, because Android
     * delivers permission results to the **Activity** (via
     * [onRequestPermissionsResult]) rather than to whoever asked. The channel
     * therefore has to be reachable from here to be told the answer.
     */
    private var smsChannel: SmsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ADR-004: Keystore-wrapped DB-master-key operations.
        KeystoreChannel().attach(
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "massrofy/keystore_channel"
            )
        )

        // ADR-014: app-switcher (recents) snapshot obscuring.
        PrivacyPlugin(this).attach(
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "massrofy/privacy_channel"
            )
        )

        // ADR-006: SMS permissions, inbox reads, and arming the background
        // ingestion layers.
        smsChannel = SmsChannel(applicationContext).also { channel ->
            channel.activity = this
            channel.attach(
                MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    SmsChannel.CHANNEL
                )
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        smsChannel?.onPermissionResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        // Drop the Activity reference so a rotation or a backgrounded
        // Activity cannot be leaked by the channel, which outlives it (it
        // holds the application context).
        smsChannel?.activity = null
        smsChannel = null
        super.onDestroy()
    }
}
