package com.massrofy.massrofy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * ADR-006 **Layer 3** — the opt-in escalation for hostile OEMs. **Off by
 * default.**
 *
 * ## What this is for, and why it is not on by default
 *
 * Layer 1 (the wake-only broadcast) is delivered even when the app process is
 * not running — normally. But Xiaomi, Huawei, Oppo, vivo and Samsung all ship
 * autostart/battery managers that will happily stop delivering broadcasts to
 * an app the user has not opened recently. That is risk R-1, and ADR-006 is
 * honest that it *cannot be fully solved, only bounded*.
 *
 * A foreground service keeps the process resident, which restores 1–3 second
 * latency on those devices. It costs battery, which NFR-R7 says must stay
 * reasonable. So it is a **user choice**, offered in Settings alongside the
 * standard battery-optimisation prompt, not a default the user pays for
 * without being asked.
 *
 * ## Why `specialUse` and not `dataSync`
 *
 * ADR-006 spells this out: Android 15 imposes runtime **caps** on `dataSync`
 * foreground services, which makes them unsuitable for something meant to run
 * continuously. `specialUse` normally invites Play policy review — which does
 * not apply here, because this app is side-loaded and architecturally cannot
 * be published to Play anyway (it depends on `RECEIVE_SMS`/`READ_SMS`; see
 * H-12 in the ADR).
 *
 * ## The notification is a feature, not a nuisance
 *
 * Android requires a visible, non-dismissible notification for a foreground
 * service, and that is the right outcome here: an app that keeps itself alive
 * to read your SMS **should** be visible while it does so. The text is
 * deliberately about *watching*, and it carries no amount, merchant, or
 * identifier — NFR-S4 applies to a notification exactly as it does to a log
 * line, and arguably more so, since a lock-screen notification is readable
 * without unlocking the phone.
 */
class ForegroundIngestService : Service() {

    companion object {
        private const val CHANNEL_ID = "massrofy.ingest.monitor"
        private const val NOTIFICATION_ID = 7302

        fun start(context: Context) {
            val intent = Intent(context, ForegroundIngestService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ForegroundIngestService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // The service does no work itself. Its ONLY job is to keep the
        // process resident so the Layer-1 broadcast keeps being delivered;
        // the actual ingestion still runs through the same WorkManager path
        // as every other trigger. One pipeline, four triggers — so a bug
        // cannot exist on the rare path and not the common one.
        IngestScheduler.enqueueExpeditedSweep(applicationContext)

        // START_STICKY: if the system kills us for memory, restart. That is
        // the entire point of the user having opted in.
        return START_STICKY
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SMS monitoring",
            // LOW: no sound, no heads-up. It is a persistent status line, not
            // an alert — the user opted into it and does not need reminding.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while Massrofy is watching for bank SMS."
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Massrofy is watching for bank messages")
            // No amount. No merchant. No card identifier. A foreground-service
            // notification is visible on the lock screen, i.e. WITHOUT the
            // app lock (ADR-005) having been satisfied — so anything shown
            // here bypasses the app's entire access-control model.
            .setContentText("Tap to turn this off in Settings.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
}
