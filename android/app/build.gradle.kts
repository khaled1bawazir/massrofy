plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.massrofy.massrofy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.massrofy.massrofy"
        // ADR-004/ADR-005 need Android Keystore APIs that only exist from
        // API 26 (O) onward (KeyGenParameterSpec.Builder basics) with the
        // strongest binding (setUserAuthenticationParameters, biometric |
        // device-credential composite) available from API 30 (R) --
        // KeystoreChannel.kt branches on SDK_INT for that. 26 is a
        // reasonable modern floor for a banking-domain, side-loaded app
        // (Android 8.0+, still comfortably covers the vast majority of
        // real-world devices) and is set explicitly here rather than left
        // at Flutter's own (lower) default.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
