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
 * ## Test coverage (updated by KHA-75 -- read this before trusting the
 * Dart-side tests alone)
 * `test/core/crypto/android_keystore_key_manager_test.dart` covers the
 * Dart-side contract (method names, argument/result shapes, exception
 * mapping) against a **fake** MethodChannel handler. That test is
 * structurally incapable of catching a whole class of bug in this file,
 * because a fake handler never crosses the Dart->Java codec boundary: it
 * sees Dart values on both ends. KHA-75 was exactly that bug -- see
 * [byteArrayArg]'s doc comment -- and it shipped with those tests green.
 * `integration_test/keystore_channel_test.dart` is the answer: it runs
 * inside the real app on a real Android device/emulator and invokes THIS
 * class over the real channel, so the wire encoding is genuinely exercised.
 * Run both; neither alone is sufficient.
 */
class KeystoreChannel : MethodChannel.MethodCallHandler {

    companion object {
        /// logcat tag for [logFailure] -- see that method for exactly what
        /// is and is not written to the platform log, and why.
        private const val LOG_TAG = "MassrofyKeystore"

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
                    val keyBytes = byteArrayArg(call, "keyBytes")
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
                    val ciphertext = byteArrayArg(call, "ciphertext")
                    val nonce = byteArrayArg(call, "nonce")
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
        } catch (e: IllegalArgumentException) {
            // KHA-75: an argument that could not be decoded at all is a
            // *programming* error in the Dart<->Kotlin contract, and it must
            // never again be reported with the same code as a genuine
            // Keystore/TEE failure -- conflating the two is precisely what
            // made KHA-75 look like an OEM secure-hardware incompatibility
            // for a whole review cycle. Distinct code, distinct log line.
            logFailure(call.method, e)
            result.error("invalid_argument", e.message, null)
        } catch (e: ClassCastException) {
            // Also an argument-decoding failure, and caught SEPARATELY from
            // the generic branch below on purpose. This is the literal
            // exception KHA-75 threw ("byte[] cannot be cast to
            // java.util.List"), and under the old code it fell into the
            // generic `keystore_error` bucket -- which is why the failure was
            // indistinguishable from a real Keystore fault, and why an
            // on-device regression test asserting "never invalid_argument"
            // would have been useless without this branch. Nothing in the
            // java.security/javax.crypto call graph below throws
            // ClassCastException, so reaching here means, unambiguously,
            // that the two halves of this channel disagree about a type.
            logFailure(call.method, e)
            result.error("invalid_argument", e.message, null)
        } catch (e: android.security.keystore.UserNotAuthenticatedException) {
            // The key exists but no biometric/device-credential
            // authentication has happened inside [AUTH_VALIDITY_SECONDS].
            // Its own code so the Dart side can tell "the OS refused the key
            // because auth went stale" apart from "the key or the platform
            // is broken" (KHA-75).
            logFailure(call.method, e)
            result.error("user_not_authenticated", e.message, null)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // ADR-004's documented recovery trigger: the caller
            // (DbMasterKeyStore, via AndroidKeystoreKeyManager) is expected
            // to catch this on the Dart side, fall back to the Passphrase
            // KEK / recovery secret, and re-provision a fresh Keystore KEK.
            logFailure(call.method, e)
            result.error("key_permanently_invalidated", e.message, null)
        } catch (e: Exception) {
            logFailure(call.method, e)
            result.error("keystore_error", e.message, null)
        }
    }

    /**
     * Emits ONE `adb logcat`-visible line per failed Keystore operation
     * (KHA-75).
     *
     * ## Why this exists and why it is safe (NFR-S2/NFR-S4)
     * Before this, every failure inside [onMethodCall] became an opaque
     * `PlatformException` on the Dart side, which `AppLockController` then
     * swallowed into a generic "Authentication failed" -- indistinguishable
     * from a wrong fingerprint. On a real device with no attached debugger
     * that left literally nothing to diagnose from, and cost two review
     * cycles (KHA-71, then KHA-75) chasing a phantom OEM/TEE incompatibility
     * that turned out to be a one-line argument-decoding bug.
     *
     * What is logged is deliberately only:
     *  - the channel method name (a fixed, compile-time vocabulary of three
     *    strings), and
     *  - the **exception class name** (framework-owned, e.g.
     *    `ClassCastException`, `UserNotAuthenticatedException`).
     *
     * What is deliberately NOT logged: the key alias, the exception
     * *message*, the stack trace, and above all any argument value. Key
     * material, ciphertext and nonces never reach this method, and the two
     * fields that are logged cannot carry user data by construction --
     * there is no code path that puts a value into either of them. That
     * combination is enough to identify the failing step immediately while
     * satisfying ADR-015's "no free text that could carry a value" rule.
     */
    private fun logFailure(method: String?, e: Exception) {
        android.util.Log.e(
            LOG_TAG,
            "keystore op failed: method=$method exception=${e.javaClass.simpleName}"
        )
    }

    /**
     * Reads a byte-array argument off a [MethodCall].
     *
     * ## Read this before changing the type here -- it is the KHA-75 bug
     * Flutter's `StandardMessageCodec` encodes Dart's **`Uint8List`** as a
     * dedicated typed-data buffer, which this (Kotlin) side of the channel
     * decodes as a Java **`byte[]`**. Only a *plain* `List<int>` is encoded
     * as a list and decoded as `java.util.List<Integer>`. These are two
     * different wire representations of "some bytes", and they are not
     * interchangeable.
     *
     * This method used to read `call.argument<List<Int>>(name)`
     * unconditionally. Every production call site passes a `Uint8List`
     * (`DbMasterKeyStore` generates the DB Master Key as one;
     * `WrappedKey.ciphertext`/`.nonce` are both `Uint8List`), so **every**
     * real wrap and unwrap threw
     * `ClassCastException: byte[] cannot be cast to java.util.List` -- on
     * every Android device, first run and every run after. The app could
     * never be unlocked by anybody. The Dart-side unit test did not catch it
     * because a fake `MethodChannel` handler sees the Dart value on both
     * ends (`Uint8List` in, `Uint8List` out); the `byte[]` vs `List<Integer>`
     * distinction only exists inside the *Java* decoder, so no amount of
     * Dart-only testing could have surfaced it. See
     * `integration_test/keystore_channel_test.dart` for the on-device test
     * that genuinely covers this now.
     *
     * Both encodings are accepted here on purpose. `Uint8List` is the one
     * `AndroidKeystoreKeyManager` now guarantees to send (it normalises
     * every caller's bytes before invoking), and the `List<Int>` branch is
     * kept so a future caller -- or a hand-written test harness -- that
     * sends a plain list still works instead of failing in this same
     * confusing way.
     */
    private fun byteArrayArg(call: MethodCall, name: String): ByteArray {
        return when (val raw = call.argument<Any>(name)) {
            null -> throw IllegalArgumentException("$name is required")
            is ByteArray -> raw
            is List<*> -> ByteArray(raw.size) { i ->
                val element = raw[i]
                if (element !is Number) {
                    throw IllegalArgumentException(
                        "$name must contain only numbers"
                    )
                }
                element.toByte()
            }
            else -> throw IllegalArgumentException(
                "$name must be a byte array or a list of ints, was " +
                    raw.javaClass.simpleName
            )
        }
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
