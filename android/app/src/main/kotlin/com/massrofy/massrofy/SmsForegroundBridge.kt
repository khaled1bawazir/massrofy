package com.massrofy.massrofy

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * **KHA-122 — the missing trigger wire.** Tells the *foreground* Dart isolate
 * that an SMS just arrived, so it can run the sweep itself.
 *
 * ## Why this object has to exist at all
 *
 * ADR-006 Layer 1 wakes a background isolate on `SMS_RECEIVED`, and **ADR-018
 * decision 1** makes that isolate a deliberate no-op: the DB Master Key is
 * unwrapped only behind a user-authenticated Keystore key (ADR-005), so a
 * background isolate cannot open the database — not sometimes, never. The only
 * writer is therefore Layer 2's foreground sweep, and before this file the only
 * thing that re-armed it was `AppLifecycleState.resumed`. An app left open and
 * idle on Home never resumed, so a matching SMS sat unprocessed until the user
 * backgrounded and reopened the app — which is exactly the AC-A1.1 gap QA found
 * on a device during the P5a walk.
 *
 * The UI isolate *does* hold the key. So the fix is not to make the background
 * isolate more capable (product-owner ruled that explicitly out of scope, and
 * ADR-018's trade still stands); it is to let the foreground isolate know there
 * is something to sweep.
 *
 * ## Why an [EventChannel] and not a second `BroadcastReceiver`
 *
 * Kotlin → Dart is a *stream* of "something arrived" signals with no payload, so
 * `EventChannel` is the idiomatic shape (a `MethodChannel` would need Dart to
 * host a call handler for a message that is not a call).
 *
 * The signal is raised from the **existing manifest-registered** [SmsReceiver],
 * not from a second receiver registered at runtime. That matters for **NFR-R7
 * (battery)**: the broadcast this app receives is unchanged, the number of
 * process wakes is unchanged, and this object adds exactly one method call on a
 * thread that was already running. Registering a second receiver for the same
 * action would have delivered the same broadcast twice into one process for no
 * gain.
 *
 * ## What happens when nobody is listening — and why that is the correct answer
 *
 * [sink] is null whenever there is no attached, foregrounded Flutter engine:
 * the app is not running, or the engine has been detached. Then
 * [signalSmsReceived] is a no-op and behaviour falls straight back to what
 * shipped before — the message is picked up by the next foreground/post-unlock
 * sweep, from the watermark, with nothing lost. That is **AC-A1.4 / NFR-R1's
 * "visible at next unlock"** clause, untouched by this change.
 *
 * Note this object is deliberately **not** aware of the app lock. It signals; it
 * does not decide. Whether a sweep may actually run is a question about the
 * decryption key, and Dart is the only side that can answer it — see
 * `sms_broadcast_signal.dart` and `foregroundSmsSignalProvider`, which gate on
 * the unlocked session before invalidating anything.
 *
 * ## Thread safety
 *
 * `BroadcastReceiver.onReceive` runs on the process main thread, which is also
 * Flutter's platform thread, so the common path could call [sink] directly.
 * [signalSmsReceived] posts to the main looper anyway rather than relying on
 * that: an `EventSink` touched from any other thread is undefined behaviour in
 * the Flutter embedder, and `SmsReceiver` is not the only conceivable caller
 * this object could acquire. Posting when already on the main thread costs one
 * message queue hop.
 */
object SmsForegroundBridge {

    /** The Dart-visible channel name. Mirrored by `sms_broadcast_signal.dart`. */
    const val CHANNEL = "massrofy/sms_events"

    /**
     * The one signal this channel ever emits. A bare marker: the Dart side
     * re-reads `content://sms/inbox` from the watermark, exactly as the resume
     * sweep does, so there is nothing to carry — and carrying a body would
     * recreate the very leak `SmsReceiver`'s doc comment explains it avoids.
     */
    private const val EVENT_SMS_RECEIVED = "sms_received"

    /**
     * Set while a Flutter engine is attached and listening; null otherwise.
     *
     * `@Volatile` because it is written from the platform thread (attach/detach
     * via the stream handler) and read on the same thread from
     * [signalSmsReceived] — but a receiver in a different component could in
     * principle be dispatched before that write is visible, and a stale
     * non-null sink would throw rather than degrade.
     */
    @Volatile
    private var sink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Installs the channel on [messenger]. Called once per engine, from
     * [MainActivity.configureFlutterEngine].
     *
     * Only the UI engine calls this. The background engine
     * (`IngestWorker` → `runBackgroundIngestion`) never does, which is what
     * keeps "the sweep runs where the key is" true by construction rather than
     * by a runtime check.
     */
    fun attach(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            },
        )
    }

    /**
     * Drops the current listener.
     *
     * Called from [MainActivity.onDestroy] so a destroyed engine's sink is not
     * held past its life. `onCancel` normally covers this; this is the belt to
     * those braces, because a leaked sink would throw on the next SMS rather
     * than quietly do nothing.
     */
    fun detach() {
        sink = null
    }

    /**
     * Raises the signal, if anything is listening.
     *
     * Swallows any embedder error: this is a *latency optimisation* on a path
     * that is already correct without it (the next sweep picks the message up
     * from the watermark). Letting an exception escape would propagate into
     * `SmsReceiver.onReceive`, where an uncaught throw is an ANR-adjacent crash
     * on the main thread — a strictly worse outcome than a message arriving a
     * few minutes late.
     */
    fun signalSmsReceived() {
        mainHandler.post {
            try {
                sink?.success(EVENT_SMS_RECEIVED)
            } catch (_: RuntimeException) {
                // Engine detached between the null check and the send.
            }
        }
    }
}
