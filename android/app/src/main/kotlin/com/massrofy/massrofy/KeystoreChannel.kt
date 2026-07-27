package com.massrofy.massrofy

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * ADR-004's Keystore-wrapped-key operations, backing
 * `lib/core/crypto/android_keystore_key_manager.dart` over the
 * "massrofy/keystore_channel" MethodChannel.
 *
 * Generates (once) an AES-256-GCM key inside the Android Keystore aliased
 * "massrofy.dbkek", requiring the device to have been recently authenticated
 * via biometric or device credential before the key can be used to wrap or
 * unwrap anything. This is what makes the app lock cryptographic (ADR-005)
 * rather than a UI-only gate: failing or skipping authentication means this
 * key operation itself throws, so the DB Master Key is never recovered and
 * the encrypted database physically cannot be opened -- regardless of
 * whatever the Flutter UI does or doesn't show.
 *
 * NOTE on test coverage, stated honestly: this class has not been exercised
 * by an automated instrumented test in this PR -- doing so needs a real
 * Android device/emulator with Keystore + biometric hardware, which the
 * environment this PR was built in does not have. The Dart-side contract
 * this channel implements (method names, argument/result shapes, exception
 * mapping) is unit-tested against a fake MethodChannel handler; see
 * `test/core/crypto/android_keystore_key_manager_test.dart`. That test
 * cannot and does not exercise this Kotlin file.
 */
class KeystoreChannel : MethodChannel.MethodCallHandler {

    companion object {
        private const val KEY_ALIAS = "massrofy.dbkek"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128
    }

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "wrapWithKeystoreKek" -> {
                    val keyBytes = intListArg(call, "keyBytes")
                    val (ciphertext, nonce) = wrap(keyBytes)
                    result.success(
                        mapOf(
                            "ciphertext" to ciphertext.map { it.toInt() and 0xFF },
                            "nonce" to nonce.map { it.toInt() and 0xFF }
                        )
                    )
                }
                "unwrapWithKeystoreKek" -> {
                    val ciphertext = intListArg(call, "ciphertext")
                    val nonce = intListArg(call, "nonce")
                    val raw = unwrap(ciphertext, nonce)
                    result.success(raw.map { it.toInt() and 0xFF })
                }
                "deleteKeystoreKek" -> {
                    deleteKey()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // ADR-004's documented recovery trigger: the caller
            // (DbMasterKeyStore, via AndroidKeystoreKeyManager) is expected
            // to catch this on the Dart side, fall back to the Passphrase
            // KEK / recovery secret, and re-provision a fresh Keystore KEK.
            result.error("key_permanently_invalidated", e.message, null)
        } catch (e: Exception) {
            result.error("keystore_error", e.message, null)
        }
    }

    private fun intListArg(call: MethodCall, name: String): ByteArray {
        val list = call.argument<List<Int>>(name)
            ?: throw IllegalArgumentException("$name is required")
        return ByteArray(list.size) { i -> list[i].toByte() }
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)

        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE
        )
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)

        // ADR-004: enrolling a new fingerprint forces one recovery-secret
        // entry -- the secure default we choose deliberately. The insecure
        // alternative (false) would let anyone who can add a biometric to
        // the device silently inherit access to the database key.
        builder.setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+: require BIOMETRIC_STRONG or DEVICE_CREDENTIAL
            // authentication, with a 0-second validity window -- every
            // single use of this key demands a fresh authentication. This
            // is the OS-enforced half of ADR-005's "cryptographic, not
            // navigation-gated" app lock.
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
            )
        } else {
            // Below API 30 there is no composite biometric|device-credential
            // authenticator-type parameter for a Keystore key; the closest
            // available control is a short validity duration so a stale
            // authentication can't be reused indefinitely. This is a
            // documented ADR-005 interpretation for older platforms -- see
            // the PR description for the full explanation.
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(5)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun wrap(plaintext: ByteArray): Pair<ByteArray, ByteArray> {
        val key = getOrCreateKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(plaintext)
        return Pair(ciphertext, cipher.iv)
    }

    private fun unwrap(ciphertext: ByteArray, nonce: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        val key = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw IllegalStateException("massrofy.dbkek does not exist yet -- wrap before unwrap")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, nonce)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(ciphertext)
    }

    private fun deleteKey() {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }
}
