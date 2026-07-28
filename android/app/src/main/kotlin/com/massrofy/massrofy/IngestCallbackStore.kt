package com.massrofy.massrofy

import android.content.Context
import android.content.SharedPreferences

/**
 * Persists the raw handle of the Dart function [IngestWorker] should execute
 * when it starts a headless FlutterEngine.
 *
 * ## Why this is in plain SharedPreferences and that is fine
 *
 * Everything else this app persists goes through `flutter_secure_storage` or
 * the SQLCipher database. This does not, and the distinction is worth being
 * explicit about because "we put it in plain prefs" is normally a smell:
 *
 * The stored value is a **`Long` produced by
 * `PluginUtilities.getCallbackHandle`** — an offset into the app's own
 * compiled Dart snapshot. It is not a secret, not a key, not derived from
 * user data, and it is worthless to any other app: it only means anything to
 * *this* APK's snapshot, and it changes on every rebuild. Encrypting it would
 * add a Keystore unwrap to the start of every background wake — on the
 * critical path of ADR-006's 1–3 second latency target — to protect a number
 * that is already recoverable by anyone who can read the APK.
 *
 * **It must not be encrypted with the DB Master Key in particular**, because
 * that key requires user authentication (ADR-004), and the entire point of
 * this value is to be readable while the app is locked.
 */
object IngestCallbackStore {

    private const val PREFS = "massrofy.ingest.callback"
    private const val KEY_HANDLE = "dart_entrypoint_handle"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun writeHandle(context: Context, handle: Long) {
        prefs(context).edit().putLong(KEY_HANDLE, handle).apply()
    }

    /** Null when Dart has never run on this device since install. */
    fun readHandle(context: Context): Long? {
        val stored = prefs(context).getLong(KEY_HANDLE, -1L)
        return if (stored == -1L) null else stored
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_HANDLE).apply()
    }
}
