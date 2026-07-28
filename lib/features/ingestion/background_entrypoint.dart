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
  // ## This no-op is the ratified design (ADR-018), not a stub
  //
  // ADR-018 decision 1 names this function and this file directly: *"a no-op
  // ... This is the design, not a stub. It MUST NOT advance the watermark,
  // and it MUST report success to WorkManager rather than failure."* This
  // comment cites that ADR, replacing the earlier text that raised the
  // situation as an open ADR gap — the gap is closed (KHA-56, architecture
  // v1.1).
  //
  // **Why there is nothing to compose here.** ADR-005 unwraps the DB Master
  // Key through a Keystore key with `setUserAuthenticationRequired(true)` and
  // a 5-second authentication validity window. A background isolate has no
  // user present, so it can never unwrap that key. The pieces this function
  // would otherwise wire together all exist and are tested —
  // `IngestionPipeline.runIncremental()`, `AndroidSmsSource` (`data/sms/`),
  // `RulePackMessageParser` (`features/parsing/`) — but composing them here
  // would only produce a call that throws on every real background wake.
  // ADR-018 considered and rejected the alternatives (an auth-free "ingest
  // inbox" key, plaintext staging, widening the grace window, leaning on a
  // foreground service) in its options table; the short version is that each
  // creates a second, weaker copy of the user's financial data to buy latency
  // nobody is awake to observe.
  //
  // **This is unconditional, and deliberately so.** It does not test the lock
  // state and does not attempt to open the database. ADR-018 decision 1 is
  // phrased as "a no-op when the database cannot be opened"; returning
  // unconditionally is a superset of that and is safe for the same single
  // reason — **the watermark does not move**, so ADR-006's Layer-2 sweep
  // re-reads every message that arrived since it, the moment the app is next
  // opened. The consequence, stated plainly rather than buried: ADR-006
  // Layer 1 contributes zero ingestion in *every* case, not only while
  // locked. What ships from Layer 1 is the wake path.
  //
  // **Returning `true`, not `false`** — see this function's doc comment.
  //
  // **Not yet implemented from ADR-018:** decision 2's `ingest.skipped.locked`
  // diagnostic event (counts only, ADR-015) for the parser-health panel. It
  // is the evidence the human would need if H-13 is ever revisited. Flagged
  // here rather than silently omitted; it belongs with the diagnostics screen
  // phase, not this file.
  return true;
}
