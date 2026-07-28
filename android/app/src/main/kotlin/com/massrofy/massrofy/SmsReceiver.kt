package com.massrofy.massrofy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * ADR-006 **Layer 1** — the primary path, target 1–3 seconds.
 *
 * ## This receiver deliberately reads NOTHING from the intent
 *
 * `SMS_RECEIVED` delivers the message body inside the intent. We ignore it,
 * entirely, and that is the whole design:
 *
 *  - **Nothing to hand off.** ADR-006 rejected passing the body to
 *    WorkManager as input `Data`, because WorkManager persists input data in
 *    *its own unencrypted SQLite database* in app storage. That would put a
 *    plaintext bank SMS in a store whose encryption we do not control —
 *    against NFR-S1's intent. The only way to be sure that never happens is
 *    to never have the body in the first place.
 *  - **Idempotent and self-healing.** The worker re-reads
 *    `content://sms/inbox WHERE date > watermark`, so a broadcast that is
 *    delayed, duplicated, or dropped entirely changes nothing about
 *    correctness. A dropped broadcast just means the message is picked up by
 *    the Layer-2 sweep instead. This is what bounds risk R-1 (OEM battery
 *    managers killing background receivers) instead of pretending it does
 *    not exist.
 *  - **It fits the budget.** A `BroadcastReceiver.onReceive` runs on the main
 *    thread with roughly a 10-second budget before the system considers the
 *    app unresponsive. Enqueuing one work request takes microseconds.
 *    Unwrapping a Keystore key, opening a SQLCipher database and running
 *    regex rules would not, and could be killed half-way (NFR-R6).
 *
 * `SMS_RECEIVED` is on Android's implicit-broadcast exemption list, which is
 * what makes manifest registration work at all while the process is not
 * running. It is also why this app cannot ever be published on Google Play
 * (`RECEIVE_SMS`/`READ_SMS` are restricted to default SMS handlers) — a
 * lock-in the ADR records deliberately as H-12, satisfied by side-loading.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        // Note the total absence of `Telephony.Sms.Intents.getMessagesFromIntent(intent)`.
        // If you are tempted to add it, read the class doc comment first — the
        // fact that this method cannot leak a message body is a security
        // property, not an oversight.
        IngestScheduler.enqueueExpeditedSweep(context)
    }
}
