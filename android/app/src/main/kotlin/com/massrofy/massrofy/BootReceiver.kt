package com.massrofy.massrofy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * ADR-006 Layer 2's other half: **re-arm the periodic sweep after a reboot**.
 *
 * Android clears all scheduled work when the device restarts. Without this,
 * the 15-minute self-healing sweep would stop after the first reboot and stay
 * stopped until the user next opened the app — quietly converting the
 * product's worst case from "up to 15 minutes late" into "whenever you happen
 * to open it", which is precisely the failure mode NFR-R1 exists to prevent
 * and the one a user would never think to report as a bug.
 *
 * WorkManager does re-schedule its own persisted `PeriodicWorkRequest`s after
 * boot via its internal `RescheduleReceiver`, so this is belt-and-braces. It
 * is kept because the failure it guards against is silent and because
 * `enqueueUniquePeriodicWork(..., KEEP, ...)` is idempotent — calling it when
 * WorkManager already restored the job costs nothing.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            // Sent to an app after it is updated. The same reasoning applies:
            // an APK update (the only update channel a side-loaded build has —
            // risk R-11) must not silently disarm ingestion.
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        IngestScheduler.ensurePeriodicSweep(context)
    }
}
