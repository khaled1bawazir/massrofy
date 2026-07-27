package com.massrofy.massrofy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
