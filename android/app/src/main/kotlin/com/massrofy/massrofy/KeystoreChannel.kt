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
 * Generates (once per alias -- see [KEY_ALIAS_ARG] below) an AES-256-GCM key
 * inside the Android Keystore, requiring the device to have been recently
 * authenticated via biometric or device credential before the key can be
 * used to wrap or unwrap anything. This is what makes the app lock
 * cryptographic (ADR-005) rather than a UI-only gate: failing or skipping
 * authentication means this key operation itself throws, so the DB Master
 * Key is never recovered and the encrypted database physically cannot be
 * opened -- regardless of whatever the Flutter UI does or doesn't show.
 *
 * ## Which Keystore key gets wrapped/unwrapped: the `keyAlias` argument
 * Every method call carries a `keyAlias` string argument (see
 * [KEY_ALIAS_ARG]) naming *which* Keystore-held AES key to use --
 * `massrofy.dbkek` (the DB Master Key's KEK, ADR-004) and
 * `massrofy.auditchain` (the audit hash-chain's HMAC-seed key, ADR-010) are
 * two entirely separate Keystore entries with independent lifecycles, both
 * served by this one class rather than duplicating this file. See
 * `lib/core/crypto/key_manager.dart` and
 * `lib/core/crypto/audit_chain_key_store.dart` for the Dart-side callers.
 *
 * ## Authentication binding -- why `wrap`/`unwrap` call `cipher.init()`
 * directly, with no `BiometricPrompt.CryptoObject` (read this before
 * "fixing" it back to a per-op key)
 * Android Keystore keys created with `setUserAuthenticationRequired(true)`
 * come in two flavours, and they are **not interchangeable**:
 *  - **Auth-per-operation** (`setUserAuthenticationParameters(0, ...)`):
 *    the *very Cipher instance* used for the crypto operation must be
 *    wrapped in a `BiometricPrompt.CryptoObject` and unlocked by a
 *    biometric prompt shown for that specific instance. Calling
 *    `cipher.init()`/`doFinal()` directly, as this file does, throws
 *    `UserNotAuthenticatedException` on every single call with this
 *    policy -- this was a real, shipped defect on API 30+ that this
 *    comment (and the fix below) exists to correct.
 *  - **Time-bound** (`setUserAuthenticationParameters(timeoutSeconds, ...)`
 *    with `timeoutSeconds > 0`, or the legacy
 *    `setUserAuthenticationValidityDurationSeconds(timeoutSeconds)`): the
 *    key is usable, with an ordinary `cipher.init()`/`doFinal()` and no
 *    `CryptoObject`, for any operation performed within `timeoutSeconds` of
 *    *some* successful biometric/device-credential authentication recorded
 *    by the OS -- it does not need to be the same `Cipher` instance, or
 *    even the same authentication call, that unlocked it.
 *
 * ADR-005 names `androidx.biometric.BiometricPrompt` **via the `local_auth`
 * plugin** as the app-lock authentication mechanism -- a generic prompt
 * that has no way to hand this class a `CryptoObject` to bind a `Cipher`
 * to (`local_auth`'s Dart-facing `authenticate()` API is plugin-agnostic
 * and returns only a bool). Building and wiring a bespoke, hand-rolled
 * `BiometricPrompt`+`CryptoObject`+`FragmentActivity` bridge just for this
 * one Keystore call would be a materially larger, harder-to-verify change
 * than this app's actual authentication flow calls for, and ADR-005 does
 * not ask for it. The correct, ADR-005-consistent fix is therefore the
 * **time-bound** key policy: [AUTH_VALIDITY_SECONDS] applies uniformly on
 * every supported API level (previously API 30+ used `0`, i.e.
 * auth-per-operation, while pre-30 already used a positive duration --
 * that inconsistency was the actual bug). The accepted tradeoff, stated
 * plainly: for [AUTH_VALIDITY_SECONDS] after `local_auth`'s prompt
 * succeeds, *any* caller in this process (not cryptographically tied to
 * that specific prompt) could invoke `wrap`/`unwrap` -- a small, deliberate
 * relaxation, scoped to a single-user local device where the very next
 * thing the app does after that prompt succeeds is exactly this call.
 *
 * NOTE on test coverage, stated honestly: this class has not been exercised
 * by an automated instrumented test in this PR -- doing so needs a real
 * Android device/emulator with Keystore + biometric hardware, which the
 * environment this PR was built in does not have. The Dart-side contract
 * this channel implements (method names, argument/result shapes, exception
 * mapping) is unit-tested against a fake MethodChannel handler; see
 * `test/core/crypto/android_keystore_key_manager_test.dart`. That test
 * cannot and does not exercise this Kotlin file. See
 * `integration_test/db_encryption_test.dart` and the dedicated
 * `android-sqlcipher-integration-test` CI job for the genuine, on-device
 * coverage this PR adds alongside that honest gap.
 */
class KeystoreChannel : MethodChannel.MethodCallHandler {

    companion object {
        /// Argument name every method call carries, naming which Keystore
        /// alias to operate on -- see the class doc comment.
        private const val KEY_ALIAS_ARG = "keyAlias"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128

        /// How long a successful biometric/device-credential authentication
        /// keeps a Keystore key usable, on every supported API level -- see
        /// the class doc comment's "Authentication binding" section for why
        /// this must be a positive duration (never 0) given how this class
        /// actually invokes the Cipher (no CryptoObject).
        private const val AUTH_VALIDITY_SECONDS = 5
    }

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "wrapWithKeystoreKek" -> {
                    val keyAlias = stringArg(call, KEY_ALIAS_ARG)
                    val keyBytes = intListArg(call, "keyBytes")
                    val (ciphertext, nonce) = wrap(keyAlias, keyBytes)
                    result.success(
                        mapOf(
                            "ciphertext" to ciphertext.map { it.toInt() and 0xFF },
                            "nonce" to nonce.map { it.toInt() and 0xFF }
                        )
                    )
                }
                "unwrapWithKeystoreKek" -> {
                    val keyAlias = stringArg(call, KEY_ALIAS_ARG)
                    val ciphertext = intListArg(call, "ciphertext")
                    val nonce = intListArg(call, "nonce")
                    val raw = unwrap(keyAlias, ciphertext, nonce)
                    result.success(raw.map { it.toInt() and 0xFF })
                }
                "deleteKeystoreKek" -> {
                    val keyAlias = stringArg(call, KEY_ALIAS_ARG)
                    deleteKey(keyAlias)
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

    private fun stringArg(call: MethodCall, name: String): String {
        return call.argument<String>(name)
            ?: throw IllegalArgumentException("$name is required")
    }

    private fun getOrCreateKey(keyAlias: String): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)

        val existing = keyStore.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE
        )
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)

        // ADR-004 says the secure default is `true` here -- but that default
        // is *only* actually safe once a recovery path exists for the data
        // it would otherwise strand. As of this P1 slice,
        // `DbMasterKeyStore.unwrapWithRecoverySecret` is a documented
        // `UnimplementedError` stub (Epic I / P8 work) and no
        // passphrase-wrapped blob is ever written. Shipping `true` today
        // would mean: the first time this device's user re-enrolls a
        // fingerprint (or changes/removes their device credential), this
        // Keystore key is invalidated with **no way back** -- permanent,
        // total loss of the encrypted database and the audit trail for a
        // real user. A banking app must never trade convenience for
        // unrecoverable user data loss.
        //
        // So, deliberately, for this P1 slice: **false**. Re-enrolling a
        // biometric will NOT invalidate this key, and daily unlock keeps
        // working uninterrupted. The accepted tradeoff: someone who can add
        // a biometric to this unlocked device (i.e. someone who already has
        // physical access to an unlocked phone -- itself a broader
        // compromise than this key was ever designed to withstand alone)
        // would silently keep the ability to unlock the database via that
        // new biometric too, rather than being forced through a recovery
        // flow. This must flip back to `true` the moment
        // `unwrapWithRecoverySecret` is genuinely implemented against a
        // real passphrase-wrapped envelope (ADR-012) -- tracked as Epic I /
        // P8 follow-up work, not deferred silently.
        builder.setInvalidatedByBiometricEnrollment(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+: require BIOMETRIC_STRONG or DEVICE_CREDENTIAL
            // authentication within the last AUTH_VALIDITY_SECONDS seconds.
            // This is a **time-bound** key (positive duration), matching
            // how `wrap`/`unwrap` below actually invoke the Cipher (a plain
            // `cipher.init()`/`doFinal()`, no `BiometricPrompt.CryptoObject`
            // binding) -- see the class doc comment's "Authentication
            // binding" section for the full explanation of why `0` here
            // (auth-per-operation) was a shipped defect
            // (`UserNotAuthenticatedException` on every call) and why a
            // positive duration is the ADR-005-consistent fix, not a
            // workaround.
            builder.setUserAuthenticationParameters(
                AUTH_VALIDITY_SECONDS,
                KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
            )
        } else {
            // Below API 30 there is no composite biometric|device-credential
            // authenticator-type parameter for a Keystore key; the closest
            // available control is the same short validity duration used
            // above, via the legacy API -- so both branches now agree on
            // the same time-bound (not auth-per-operation) semantics.
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(AUTH_VALIDITY_SECONDS)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun wrap(keyAlias: String, plaintext: ByteArray): Pair<ByteArray, ByteArray> {
        val key = getOrCreateKey(keyAlias)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(plaintext)
        return Pair(ciphertext, cipher.iv)
    }

    private fun unwrap(keyAlias: String, ciphertext: ByteArray, nonce: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        val key = keyStore.getKey(keyAlias, null) as? SecretKey
            ?: throw IllegalStateException("$keyAlias does not exist yet -- wrap before unwrap")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, nonce)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(ciphertext)
    }

    private fun deleteKey(keyAlias: String) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        if (keyStore.containsAlias(keyAlias)) {
            keyStore.deleteEntry(keyAlias)
        }
    }
}
