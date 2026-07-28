package com.massrofy.massrofy

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * ADR-006 Layer 1, step 2: run the Dart ingestion pipeline in a **background
 * FlutterEngine**, with no Activity and no UI.
 *
 * ```
 * SmsReceiver (wake only) ─► WorkManager ─► this ─► background FlutterEngine
 *                                                   └─► ingestionEntrypoint()
 *                                                       in lib/features/ingestion/
 *                                                       background_entrypoint.dart
 * ```
 *
 * The `workmanager` plugin implements this same pattern. ADR-006 explicitly
 * allows either it or a hand-rolled equivalent — *"the **contract** is what is
 * fixed, not the plugin choice"* — and this is hand-rolled so the app carries
 * one fewer third-party dependency with access to its ingestion path, which
 * for a no-network banking app is a dependency-review win worth ~120 lines.
 *
 * ## How Dart gets started from Kotlin
 *
 * Dart code normally runs because an Activity created a FlutterEngine. Here
 * there is no Activity. Instead:
 *
 * 1. On first launch, Dart registers a **callback handle** — an integer the
 *    Flutter engine can later resolve back to a top-level Dart function — via
 *    [IngestCallbackStore]. It survives process death because it is in
 *    SharedPreferences.
 * 2. This worker builds a fresh `FlutterEngine`, looks the handle up, and
 *    tells the engine to execute that function.
 * 3. Dart runs the pipeline and calls back `ingestionComplete` on the channel
 *    below, which resolves the deferred and lets `doWork` return.
 *
 * ## Two things that will look like bugs and are not
 *
 * **The engine is destroyed in a `finally`.** A leaked FlutterEngine keeps a
 * whole Dart VM isolate alive in a background process — battery cost against
 * NFR-R7, for a job that ran for two seconds.
 *
 * **A timeout returns `Result.retry()`, not `failure()`.** If the Dart side
 * hangs (a pathological regex in an imported rule pack is the realistic
 * cause), giving up permanently would mean those messages are never ingested.
 * Retrying costs a little battery; not retrying loses transactions, and
 * NFR-A7 does not permit that.
 */
class IngestWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    private companion object {
        const val TAG = "MassrofyIngest"
        const val CHANNEL = "massrofy/ingest_background"

        /**
         * Generous relative to the 1–3 second target, because the *first* run
         * after install also performs the historical import of the current
         * calendar month (US-A3) over a potentially large inbox.
         */
        const val TIMEOUT_MS = 9L * 60L * 1000L
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.Main) {
        val handle = IngestCallbackStore.readHandle(applicationContext)
        if (handle == null) {
            // Dart has never run, so there is nothing registered to call. This
            // is normal on a device where an SMS arrives before the user has
            // ever opened the app. Succeeding (rather than retrying forever)
            // is correct: the watermark has not moved, so the message is still
            // waiting, and the first foreground launch will sweep it up.
            Log.i(TAG, "No Dart entrypoint registered yet; deferring to next foreground sweep.")
            return@withContext Result.success()
        }

        val callback = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (callback == null) {
            Log.w(TAG, "Stored Dart callback handle no longer resolves; clearing it.")
            IngestCallbackStore.clear(applicationContext)
            return@withContext Result.success()
        }

        val engine = FlutterEngine(applicationContext)
        val finished = CompletableDeferred<Boolean>()

        try {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    // Dart signals it is ready to be told to run.
                    "ingestionReady" -> {
                        channel.invokeMethod("runIngestion", null)
                        result.success(null)
                    }
                    // Dart signals the run finished. The boolean says whether
                    // it succeeded; `false` becomes a retry.
                    "ingestionComplete" -> {
                        finished.complete(call.arguments as? Boolean ?: true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

            engine.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(
                    applicationContext.assets,
                    io.flutter.FlutterInjector.instance()
                        .flutterLoader()
                        .findAppBundlePath(),
                    callback,
                ),
            )

            val succeeded = withTimeoutOrNull(TIMEOUT_MS) { finished.await() }
            when (succeeded) {
                // Timed out. See the class doc comment for why this retries
                // rather than failing.
                null -> Result.retry()
                true -> Result.success()
                false -> Result.retry()
            }
        } catch (error: Exception) {
            // Deliberately logs the exception TYPE, never its message: an
            // exception surfacing from the ingestion isolate can carry SMS
            // text in its message, and logcat is world-readable to anyone
            // with adb (NFR-S4).
            Log.w(TAG, "Ingestion run failed: ${error.javaClass.simpleName}")
            Result.retry()
        } finally {
            engine.destroy()
        }
    }
}
