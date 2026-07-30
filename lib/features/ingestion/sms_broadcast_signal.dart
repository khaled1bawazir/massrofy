/// **KHA-122 — the Dart half of the immediate foreground sweep.**
///
/// > AC-A1.1 — *"…a corresponding transaction appears in the transaction list
/// > within single-digit seconds and without any user action — **including when
/// > the app simply stays open and is never backgrounded and resumed.**"*
///
/// ---
///
/// ## The gap this closes, in three facts
///
/// 1. **ADR-018 decision 1**: ADR-006's background isolate is a ratified no-op.
///    ADR-005 makes the app lock cryptographic, so a background isolate cannot
///    unwrap the DB Master Key and therefore cannot write. That decision stands
///    and this file does not reopen it.
/// 2. **The foreground sweep is the only writer** — `foregroundSweepProvider`.
/// 3. **Nothing re-armed it while the app just stayed open.** `app.dart`
///    invalidated it on `AppLifecycleState.resumed` and on the unlock
///    transition; an app sitting idle on Home hits neither.
///
/// So an SMS arriving during a live session waited for the next
/// background/foreground cycle. Nothing was lost — the watermark was intact and
/// the transaction appeared on the next resume — but the screen meanwhile said
/// `0.00 SAR` / *"No transactions recorded yet this month"*, which is a
/// confident, affirmative, wrong claim. That is the trust failure the
/// product-owner's decision on KHA-122 cites, not merely a latency one.
///
/// ## What this adds: a signal, not a second ingestion path
///
/// This is deliberately the thinnest possible thing. It carries **no message
/// content** (a bare marker crosses the channel), it performs **no ingestion**,
/// and it makes **no decisions**. All it does is let something in the UI isolate
/// know that re-reading the inbox is now worthwhile. The read, the parse, the
/// dedup and the watermark advance are all done by the *same*
/// `IngestionPipeline.runIncremental()` the resume sweep already calls — see
/// `foregroundSmsSignalProvider` in `presentation/providers/ingestion_providers.dart`,
/// which is the only consumer.
///
/// That "same path" property is the requirement, not an implementation detail.
/// Product-owner's scope note is explicit: *"a prompt sweep that races the
/// resume sweep and double-counts a transaction (AC-A5.1) or advances the
/// watermark past an unwritten message is strictly worse than the current
/// delay."* Because there is exactly one writer and it is reached through
/// exactly one method, the ADR-017 D1 dedup guarantees that protect a
/// re-delivered SMS protect an overlapping sweep too:
///
///  - `raw_message.sms_provider_id` is `UNIQUE` — the same inbox row cannot be
///    written twice;
///  - `raw_message.content_hmac` is `UNIQUE` — identical content cannot be
///    written twice even under a new provider id;
///  - `IngestWatermarkDao.advanceTo` is monotonic **in SQL**, so two overlapping
///    sweeps cannot rewind each other.
///
/// `test/features/ingestion/immediate_sweep_race_test.dart` asserts exactly one
/// transaction results when an immediate sweep and a resume sweep overlap.
///
/// ## Why this is not `SmsPermissionService.requestImmediateSweep()`
///
/// KHA-122 names that method as the mechanism, and it was the obvious candidate:
/// declared on the interface, implemented over the platform channel, zero
/// callers. It cannot do the job, and the reason is worth recording so nobody
/// wires it and believes the defect fixed:
///
/// ```
/// "requestImmediateSweep" -> IngestScheduler.enqueueExpeditedSweep(context)   // SmsChannel.kt
/// ```
///
/// It enqueues a WorkManager job, i.e. it routes into `IngestWorker` →
/// `runBackgroundIngestion()` → the ADR-018 **no-op**. Calling it from Dart
/// would add a wake (against NFR-R7) and ingest nothing. The direction of the
/// call is the problem: the fix needs Kotlin → Dart, and that method is
/// Dart → Kotlin. See its own doc comment, which now says so at the source.
library;

import 'package:flutter/services.dart';

/// The `EventChannel` name. Mirrors `SmsForegroundBridge.CHANNEL` in Kotlin.
const String smsEventChannelName = 'massrofy/sms_events';

/// The single event the Kotlin side emits. Compared explicitly rather than
/// accepting anything, so a future second event on this channel cannot silently
/// be read as "an SMS arrived".
const String smsReceivedEvent = 'sms_received';

/// A stream of *"an SMS just arrived"* markers.
///
/// An interface rather than a concrete class for the reason every platform
/// boundary in this codebase is one: a widget/provider test must be able to
/// deliver the signal without an Android runtime. `FakeSmsBroadcastSignal` in
/// `test/support/app_test_harness.dart` is the test double.
abstract interface class SmsBroadcastSignal {
  /// Emits once per matching broadcast the Kotlin side saw while a foregrounded
  /// engine was attached.
  ///
  /// Deliberately `Stream<void>`: the events carry nothing, and a stream of a
  /// richer type would invite someone to put the message body on it.
  Stream<void> get incoming;
}

/// The real implementation, over the `EventChannel` [MainActivity] installs.
final class AndroidSmsBroadcastSignal implements SmsBroadcastSignal {
  final EventChannel _channel;

  AndroidSmsBroadcastSignal({EventChannel? channel})
    : _channel = channel ?? const EventChannel(smsEventChannelName);

  @override
  Stream<void> get incoming => _channel
      .receiveBroadcastStream()
      // Only our own marker. `receiveBroadcastStream` is `Stream<dynamic>`, and
      // filtering on the exact string means an unexpected payload is ignored
      // rather than treated as a trigger.
      .where((Object? event) => event == smsReceivedEvent)
      .map<void>((Object? _) {})
      // A platform error must not kill the subscription: the app degrades to
      // the pre-KHA-122 behaviour (swept on next resume) rather than losing the
      // trigger for the rest of the session. Nothing is logged — NFR-S4 keeps
      // this layer out of writing diagnostics on an SMS-adjacent path, and the
      // failure is not actionable by the user.
      .handleError((Object _) {});
}
