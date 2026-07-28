/// The Dart side of ADR-006 Layer 1, step 2: the function
/// `IngestWorker.kt` starts inside a headless FlutterEngine.
///
/// ```
/// SmsReceiver (wake only) ─► WorkManager ─► IngestWorker (Kotlin)
///                                              │ starts a FlutterEngine with
///                                              ▼ no Activity and no UI
///                                       massrofyIngestEntrypoint()   ← here
/// ```
///
/// ## `@pragma('vm:entry-point')` is not optional
///
/// In a release build, Dart's tree-shaker removes any top-level function with
/// no visible caller. Nothing in Dart calls [massrofyIngestEntrypoint] — the
/// caller is Kotlin, via a numeric handle — so without this annotation the
/// function is present in debug, absent in release, and background ingestion
/// silently stops working **in exactly the build the user runs**. This is the
/// single most common way a headless-Flutter feature ships broken.
///
/// ## The honest limitation: the database may be locked
///
/// ADR-005 makes the app lock **cryptographic**, not navigational: the DB
/// Master Key is unwrapped through a Keystore key created with
/// `setUserAuthenticationRequired(true)`. A background isolate has no user
/// present, so it **cannot** unwrap that key and therefore cannot open the
/// database. That is the security property working exactly as designed, not a
/// defect to engineer around.
///
/// ADR-006 does not address this interaction — it assumes the worker can
/// write. This implementation takes the only option that loses nothing:
///
/// > **If the database cannot be opened, do nothing and do not advance the
/// > watermark.**
///
/// The messages stay queued in the SMS provider, which is their durable home
/// regardless, and the next run that *can* open the database — the foreground
/// sweep after the user unlocks — picks up everything since the watermark.
/// Correctness is fully preserved (NFR-A7); the cost is latency, and only
/// while the app is locked.
///
/// The alternatives all weaken something the architecture chose deliberately:
/// a second, auth-free Keystore key for a staging queue erodes ADR-004's
/// "access control is cryptographic"; a plaintext staging file contradicts
/// NFR-S1. Both are the solution-architect's call, and this phase's PR raises
/// it as an ADR gap rather than resolving it unilaterally in a code file.
library;

import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// Must match `IngestWorker.CHANNEL` in Kotlin.
const String ingestBackgroundChannelName = 'massrofy/ingest_background';

/// Resolves [massrofyIngestEntrypoint] to the integer handle Kotlin stores
/// and later uses to start it. Called once, from app startup.
///
/// Returns `null` if the handle cannot be resolved — which in practice means
/// the `vm:entry-point` annotation was removed. Callers should treat that as
/// "background ingestion is unavailable" and fall back to foreground sweeps
/// rather than crashing.
int? resolveIngestEntrypointHandle() {
  final CallbackHandle? handle = PluginUtilities.getCallbackHandle(
    massrofyIngestEntrypoint,
  );
  return handle?.toRawHandle();
}

/// Runs one ingestion sweep in a background isolate. **Never called from Dart.**
@pragma('vm:entry-point')
void massrofyIngestEntrypoint() {
  // Required before any platform channel can be used on a background isolate:
  // it wires up the message dispatcher that `MethodChannel` sends over.
  WidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(ingestBackgroundChannelName);

  channel.setMethodCallHandler((MethodCall call) async {
    if (call.method != 'runIngestion') {
      return null;
    }
    final bool succeeded = await runBackgroundIngestion();
    await channel.invokeMethod<void>('ingestionComplete', succeeded);
    return null;
  });

  // Handshake, rather than starting work immediately: the engine's channel
  // must be listening on the Kotlin side before Dart sends anything, or the
  // first message is dropped and the worker waits out its whole timeout for a
  // completion signal that already happened.
  channel.invokeMethod<void>('ingestionReady');
}

/// The body of a background run.
///
/// Returns `true` when the worker should report success, `false` when it
/// should retry.
///
/// **A locked database returns `true`, not `false`.** Retrying would burn
/// WorkManager's backoff budget on a condition that cannot resolve without a
/// human unlocking the phone — and nothing is lost by waiting, because the
/// watermark has not moved. Reporting failure here would be technically
/// accurate and practically wrong.
Future<bool> runBackgroundIngestion() async {
  // ## Why this is a documented stub rather than a wired-up pipeline
  //
  // Everything it would call already exists and is tested:
  // `IngestionPipeline.runIncremental()` (this directory),
  // `AndroidSmsSource` (`data/sms/`), `RulePackMessageParser`
  // (`features/parsing/`). What is missing is not code — it is a **decision**:
  // how a background isolate is supposed to obtain the DB Master Key when
  // ADR-004 deliberately made that key require user authentication.
  //
  // Composing the pipeline here today would mean either (a) it throws on
  // every real background wake, which is a worse outcome than an honest
  // no-op, or (b) inventing an auth-free key path — a security decision that
  // belongs to the solution-architect and to an ADR amendment, not to this
  // file.
  //
  // So the wiring stops at a clearly-labelled boundary, the ADR gap is raised
  // explicitly in this phase's PR, and **the product is still correct in the
  // meantime**: the Layer-2 foreground sweep runs the identical pipeline the
  // moment the user opens the app, and the watermark guarantees it picks up
  // everything that arrived while the app was locked. What is lost is
  // latency, not data.
  return true;
}
