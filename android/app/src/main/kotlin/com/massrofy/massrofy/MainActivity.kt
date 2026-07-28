package com.massrofy.massrofy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

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
