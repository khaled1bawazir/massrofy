package com.massrofy.massrofy

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * The one place that decides *when* ingestion runs — ADR-006's three layers,
 * expressed as WorkManager requests.
 *
 * Centralised so the constants below exist once. A second copy of
 * `"massrofy.ingest"` somewhere else would silently create a second work
 * queue, and `ExistingWorkPolicy.KEEP` would then stop deduplicating anything.
 */
object IngestScheduler {

    /**
     * ADR-006 names this unique work explicitly. `KEEP` means a burst of five
     * SMS arriving together enqueues **one** sweep, not five — and one sweep
     * picks up all five anyway, because the worker reads everything past the
     * watermark rather than one message.
     */
    private const val UNIQUE_SWEEP_WORK = "massrofy.ingest"
    private const val UNIQUE_PERIODIC_WORK = "massrofy.ingest.periodic"

    /**
     * WorkManager's hard floor. Asking for less does not get you less; it
     * gets you 15 minutes and a false sense of latency. This is the number
     * behind the "up to 15 minutes" row in ADR-006's honest latency table.
     */
    private const val PERIODIC_INTERVAL_MINUTES = 15L

    /** ADR-006 Layer 1. Called by [SmsReceiver] on every inbound SMS. */
    fun enqueueExpeditedSweep(context: Context) {
        val request = OneTimeWorkRequestBuilder<IngestWorker>()
            // Expedited work runs promptly even in Doze — but the quota is
            // finite, and exhausting it would mean the request is *rejected*
            // rather than delayed. RUN_AS_NON_EXPEDITED_WORK_REQUEST demotes
            // it to a normal job instead of dropping it, which is the
            // difference between "this SMS shows up a bit later" and "this
            // SMS never shows up". ADR-006 specifies exactly this.
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_SWEEP_WORK,
            ExistingWorkPolicy.KEEP,
            request,
        )
    }

    /**
     * ADR-006 **Layer 2** — the self-healing sweep, and the reason the
     * product is correct even when Layer 1 is suppressed.
     *
     * > *"This guarantees AC-A1.4 unconditionally: if the broadcast never
     * > arrives, the message is still captured, just later. This layer is
     * > what makes the product correct even when R-1 bites."*
     *
     * `KEEP` rather than `UPDATE`: re-arming on every app launch must not
     * reset the interval timer, or a user who opens the app every ten minutes
     * would never let the periodic job fire at all.
     */
    fun ensurePeriodicSweep(context: Context) {
        val request = PeriodicWorkRequestBuilder<IngestWorker>(
            PERIODIC_INTERVAL_MINUTES,
            TimeUnit.MINUTES,
        ).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            UNIQUE_PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }
}
