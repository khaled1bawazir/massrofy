package com.massrofy.massrofy

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Kotlin half of ADR-006's ingestion: reading `content://sms/inbox`,
 * handling the two runtime permissions, and arming the background layers.
 *
 * ## Read-only, in the strongest sense available on the platform
 *
 * This class calls `contentResolver.query`. It never calls `insert`,
 * `update`, or `delete`, and the app declares neither `SEND_SMS` nor
 * `WRITE_SMS`. CON-2 — *"the app is read-only with respect to money"* — has a
 * direct analogue here: Massrofy observes the user's SMS, it never touches
 * them. A user should be able to grant SMS access to a spending tracker
 * without wondering whether it might reply to their bank.
 *
 * ## The projection is minimal on purpose (NFR-P1)
 *
 * Four columns: `_id`, `address`, `body`, `date`. Not `person`, not `thread_id`,
 * not `service_center`. The SMS provider will happily return everything; data
 * minimisation means not asking. Bodies of non-financial messages are read
 * into memory for the microseconds it takes the Dart classifier to reject the
 * sender, and are then simply not persisted (NFR-P4).
 */
class SmsChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    /**
     * Set by [MainActivity] when the channel is attached, and only then. A
     * runtime permission dialog needs an Activity; the SMS *reads* do not,
     * which is why the read path takes a plain Context and works from the
     * background worker.
     */
    var activity: Activity? = null

    private var pendingPermissionResult: MethodChannel.Result? = null

    companion object {
        const val CHANNEL = "massrofy/sms_channel"
        const val PERMISSION_REQUEST_CODE = 7301

        /**
         * The exact two permissions ADR-006 requires, and no more.
         * `RECEIVE_SMS` gets the broadcast (Layer 1); `READ_SMS` gets the
         * content provider (the actual ingestion, and the historical import).
         * Both are needed — one without the other gives either a wake with
         * nothing to read, or a read that never wakes.
         */
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
        )

        private val INBOX: Uri = Telephony.Sms.Inbox.CONTENT_URI

        private val PROJECTION = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
        )
    }

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermissions" -> requestPermissions(result)
            "openAppSettings" -> {
                openAppSettings()
                result.success(null)
            }
            "registerBackgroundEntrypoint" -> {
                val handle = (call.argument<Any>("handle") as? Number)?.toLong()
                if (handle == null) {
                    result.error("bad_args", "handle is required", null)
                } else {
                    IngestCallbackStore.writeHandle(context, handle)
                    // Arm ADR-006 Layer 2 the moment we know Dart can be
                    // called back. Doing it here rather than at app start
                    // means the periodic sweep is never scheduled for a build
                    // that has no entrypoint to run.
                    IngestScheduler.ensurePeriodicSweep(context)
                    result.success(null)
                }
            }
            "requestImmediateSweep" -> {
                IngestScheduler.enqueueExpeditedSweep(context)
                result.success(null)
            }
            // ADR-006 Layer 3, driven from Settings (P5). Exposed now so the
            // mechanism is real rather than a promise in a document; the
            // toggle that calls it is a later phase's UI work.
            "setForegroundServiceEnabled" -> {
                if (call.argument<Boolean>("enabled") == true) {
                    ForegroundIngestService.start(context)
                } else {
                    ForegroundIngestService.stop(context)
                }
                result.success(null)
            }
            // KHA-157 (A). Ids and a timestamp only — this is the one read in
            // the app that is guaranteed to touch no message content at all.
            "highWaterMark" -> result.success(highWaterMark())
            "readSince" -> result.success(
                readSince(
                    afterId = (call.argument<Any>("afterId") as? Number)?.toLong() ?: 0L,
                    limit = call.argument<Int>("limit") ?: 100,
                ),
            )
            "readRange" -> result.success(
                readRange(
                    fromEpochMs = (call.argument<Any>("fromEpochMs") as? Number)?.toLong() ?: 0L,
                    afterId = (call.argument<Any>("afterId") as? Number)?.toLong() ?: 0L,
                    limit = call.argument<Int>("limit") ?: 50,
                ),
            )
            "countRange" -> result.success(
                countRange(
                    fromEpochMs = (call.argument<Any>("fromEpochMs") as? Number)?.toLong() ?: 0L,
                ),
            )
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Permissions (AC-A1.2, AC-A1.3)
    // -------------------------------------------------------------------------

    /**
     * Returns one of `granted` / `denied` / `permanently_denied`.
     *
     * The three-way distinction matters to the UI and is easy to collapse by
     * accident. `denied` means "ask again" — the OS dialog will still appear.
     * `permanently_denied` means the OS will silently no-op a request, so the
     * only honest thing the app can offer is a deep link to Settings
     * (design.md S-04). An app that keeps showing a "Grant permission" button
     * which visibly does nothing is worse than one that says "open Settings".
     *
     * ### Android's rationale flag is genuinely ambiguous before the first ask
     *
     * `shouldShowRequestPermissionRationale` returns `false` both when the
     * user has permanently denied *and* when they have never been asked. We
     * disambiguate with our own "have we asked yet" flag rather than guessing,
     * because guessing wrong on a first run would show the Settings deep link
     * to a user who has not yet seen a single permission dialog.
     */
    private fun permissionStatus(): String {
        val allGranted = SMS_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) return "granted"

        val currentActivity = activity ?: return "denied"
        if (!PermissionAskState.hasAsked(context)) return "denied"

        val canAskAgain = SMS_PERMISSIONS.any {
            ActivityCompat.shouldShowRequestPermissionRationale(currentActivity, it)
        }
        return if (canAskAgain) "denied" else "permanently_denied"
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no_activity", "Permission requests need a foreground activity", null)
            return
        }
        if (pendingPermissionResult != null) {
            // Two overlapping requests would leave one Dart Future hanging
            // forever, which in the UI shows up as a button that never
            // finishes loading.
            result.error("already_requesting", "A permission request is in flight", null)
            return
        }

        pendingPermissionResult = result
        PermissionAskState.markAsked(context)
        ActivityCompat.requestPermissions(
            currentActivity,
            SMS_PERMISSIONS,
            PERMISSION_REQUEST_CODE,
        )
    }

    /** Called by [MainActivity]'s `onRequestPermissionsResult`. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        if (granted) {
            // Arm Layer 2 immediately. Waiting for the next app launch would
            // leave a window where the user has granted access and nothing is
            // watching.
            IngestScheduler.ensurePeriodicSweep(context)
        }
        result.success(permissionStatus())
    }

    private fun openAppSettings() {
        val intent = Intent(
            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    // -------------------------------------------------------------------------
    // Reading the inbox
    // -------------------------------------------------------------------------

    /**
     * Messages with `_id > afterId`, **oldest first**.
     *
     * Oldest-first is required, not stylistic: the Dart pipeline advances the
     * watermark as it goes, so processing newest-first would let a high id
     * move the watermark past messages that were never processed — losing
     * them permanently, which NFR-A7 forbids.
     *
     * Keying on `_id` rather than `date`: two messages can share a `date` to
     * the millisecond (a multi-part message, or a carrier burst), and a
     * `date > watermark` query would then drop one of them.
     */
    private fun readSince(afterId: Long, limit: Int): List<Map<String, Any?>> {
        return query(
            selection = "${Telephony.Sms._ID} > ?",
            args = arrayOf(afterId.toString()),
            limit = limit,
        )
    }

    /**
     * The historical-import window (AC-A3.1): received at or after
     * [fromEpochMs], resuming after [afterId].
     */
    private fun readRange(fromEpochMs: Long, afterId: Long, limit: Int): List<Map<String, Any?>> {
        return query(
            selection = "${Telephony.Sms.DATE} >= ? AND ${Telephony.Sms._ID} > ?",
            args = arrayOf(fromEpochMs.toString(), afterId.toString()),
            limit = limit,
        )
    }

    /**
     * **KHA-157 (A) — the newest inbox row's `_id` and `date`, and nothing
     * else.**
     *
     * ## The projection is two columns, not four
     *
     * [PROJECTION] is deliberately not reused here. This query exists to
     * answer "where does the future start?", which needs no body and no
     * sender, and NFR-P1's data minimisation means not asking for what we do
     * not need — even for the microseconds it would live in memory. It is the
     * only inbox read in the app that cannot leak message content, because it
     * never requests any.
     *
     * ## Three return shapes, and the distinction that matters
     *
     * - `null` — **unreadable**: `SecurityException` (no `READ_SMS`, or an
     *   Android 11+ auto-revoke), or a null cursor from the provider.
     * - `mapOf("empty" to true)` — read fine, no rows.
     * - `mapOf("id" to Long, "date" to Long)` — the newest row.
     *
     * The Dart side must be able to tell the first from the second: seeding a
     * watermark while permission is denied would mark it seeded at 0 and then
     * sweep the entire device history the moment permission arrived. That is
     * the 424-item flood KHA-157 was filed for, so the ambiguity is removed
     * here rather than guessed at there.
     *
     * `LIMIT 1` on a `_id DESC` sort, so this is one row however large the
     * inbox is.
     */
    private fun highWaterMark(): Map<String, Any?>? {
        return try {
            context.contentResolver.query(
                INBOX,
                arrayOf(Telephony.Sms._ID, Telephony.Sms.DATE),
                null,
                null,
                "${Telephony.Sms._ID} DESC LIMIT 1",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return@use mapOf<String, Any?>("empty" to true)
                }
                mapOf<String, Any?>(
                    "id" to cursor.getLong(cursor.getColumnIndexOrThrow(Telephony.Sms._ID)),
                    "date" to cursor.getLong(cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)),
                )
            }
            // A null cursor means the provider refused the query. Falling
            // through to `null` here — rather than to "empty" — is the safe
            // direction: seed nothing, sweep nothing, retry next sweep.
        } catch (_: SecurityException) {
            null
        }
    }

    /** A count for the progress bar (AC-A3.2). Never content. */
    private fun countRange(fromEpochMs: Long): Int {
        return try {
            context.contentResolver.query(
                INBOX,
                arrayOf(Telephony.Sms._ID),
                "${Telephony.Sms.DATE} >= ?",
                arrayOf(fromEpochMs.toString()),
                null,
            )?.use { it.count } ?: 0
        } catch (_: SecurityException) {
            0
        }
    }

    private fun query(
        selection: String,
        args: Array<String>,
        limit: Int,
    ): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        try {
            context.contentResolver.query(
                INBOX,
                PROJECTION,
                selection,
                args,
                "${Telephony.Sms._ID} ASC LIMIT $limit",
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addressIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

                while (cursor.moveToNext()) {
                    rows.add(
                        mapOf(
                            "id" to cursor.getLong(idIndex),
                            "address" to (cursor.getString(addressIndex) ?: ""),
                            "body" to (cursor.getString(bodyIndex) ?: ""),
                            "date" to cursor.getLong(dateIndex),
                        ),
                    )
                }
            }
        } catch (_: SecurityException) {
            // Permission was revoked between the check and the read — a real
            // race on Android 11+, which can auto-reset permissions for an
            // unused app (ADR-006). Returning empty rather than throwing means
            // the run is a no-op, the watermark does not move, and the
            // foreground app shows the AC-A1.3 "ingestion has stopped" warning
            // rather than crashing a background worker.
            return emptyList()
        }
        return rows
    }
}

/**
 * Remembers whether the OS permission dialog has ever been shown.
 *
 * See [SmsChannel.permissionStatus] for why Android's own APIs cannot answer
 * this: `shouldShowRequestPermissionRationale` returns `false` both for
 * "never asked" and for "permanently denied", and those two states need
 * completely different UI.
 */
private object PermissionAskState {
    private const val PREFS = "massrofy.permissions"
    private const val KEY_ASKED = "sms_permission_asked"

    fun hasAsked(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ASKED, false)

    fun markAsked(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ASKED, true)
            .apply()
    }
}
