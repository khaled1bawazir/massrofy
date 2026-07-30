/// SMS runtime permissions — the state machine behind design.md's S-02
/// (rationale), S-04 (denied / limited mode) and the AC-A1.3 revoked banner.
///
/// ## Why "denied" and "permanently denied" must not be collapsed
///
/// They demand completely different UI, and getting it wrong produces the
/// single most frustrating bug class in Android apps:
///
///  - **`denied`** — the OS dialog will still appear. The right affordance is
///    a "Grant SMS access" button that actually opens it.
///  - **`permanentlyDenied`** — Android silently no-ops the request. A
///    "Grant" button here does *nothing at all*, with no error and no dialog.
///    The only honest offer is a deep link into system Settings, which is
///    exactly what the approved S-04 mockup shows ("فتح إعدادات النظام" /
///    "Open system settings").
///
/// The Kotlin side owns this determination, because Android's own
/// `shouldShowRequestPermissionRationale` cannot distinguish "permanently
/// denied" from "never asked" — see `SmsChannel.kt`.
///
/// ## AC-A1.3: revoked mid-life
///
/// Two things must both be true when access is lost after having been
/// granted: the app **warns that ingestion has stopped**, and it states that
/// **previously captured data is still intact**. The second half is not
/// reassurance copy — a user who sees "SMS access lost" with no further
/// information reasonably fears their history is gone, and the natural
/// reaction to that fear is to reinstall, which would actually destroy it.
///
/// Android 11+ can also revoke permissions automatically for an app that has
/// been unused for a few months (ADR-006), so this is a state a perfectly
/// well-behaved user reaches without doing anything.
library;

import 'package:flutter/services.dart';

import '../../data/sms/android_sms_source.dart' show smsMethodChannelName;

/// The three states the UI must distinguish. See the library doc comment.
enum SmsPermissionStatus {
  granted,
  denied,
  permanentlyDenied;

  /// Whether ingestion can run at all. Used to decide between the normal
  /// dashboard and S-04's limited mode.
  bool get allowsIngestion => this == SmsPermissionStatus.granted;
}

abstract interface class SmsPermissionService {
  Future<SmsPermissionStatus> status();

  /// Shows the OS dialog and resolves with the resulting status.
  ///
  /// **Must only be called after the user has seen the rationale screen**
  /// (S-02, design flag D-9). Android gives an app effectively one good shot
  /// at this prompt; firing it cold, before explaining why a spending tracker
  /// wants to read SMS, is how a user reflexively denies and the app becomes
  /// permanently useless to them.
  Future<SmsPermissionStatus> request();

  /// Deep-links into this app's system settings page — the only workable
  /// action once the status is [SmsPermissionStatus.permanentlyDenied].
  Future<void> openAppSettings();

  /// Registers the Dart entrypoint the background worker calls, and arms
  /// ADR-006's Layer-2 periodic sweep.
  Future<void> registerBackgroundEntrypoint(int callbackHandle);

  /// Enqueues an expedited **background** sweep (ADR-006 Layer 2's
  /// WorkManager trigger).
  ///
  /// ## This is NOT the fix for KHA-122, and calling it would not be one
  ///
  /// KHA-122 named this method as the mechanism for AC-A1.1's app-open-and-idle
  /// case, on the reasonable evidence that it was declared, implemented over the
  /// channel, and had zero callers. Following the call through settles it:
  ///
  /// ```
  /// "requestImmediateSweep" -> IngestScheduler.enqueueExpeditedSweep(context)   // SmsChannel.kt
  ///                        -> IngestWorker -> runBackgroundIngestion()
  ///                        -> ADR-018 decision 1: an unconditional no-op
  /// ```
  ///
  /// A background isolate cannot unwrap the DB Master Key (ADR-005), so the job
  /// it schedules ingests nothing by design. Wiring this from Dart would spend a
  /// wake (against NFR-R7) and produce no transaction — and, worse, would look
  /// like the defect had been addressed.
  ///
  /// The direction is the real obstacle: closing AC-A1.1 needs **Kotlin → Dart**
  /// (tell the isolate that holds the key that there is something to sweep), and
  /// this is Dart → Kotlin. That signal is `SmsForegroundBridge` /
  /// `sms_broadcast_signal.dart`.
  ///
  /// It is kept rather than deleted because the *Kotlin* handler is real and
  /// used — `SmsReceiver` and `BootReceiver` both enqueue through
  /// `IngestScheduler` — so this is the Dart-side door onto a mechanism that
  /// exists, and it becomes useful the moment ADR-018 decision 1 is ever
  /// revisited. Until then it has no production caller **on purpose**, and this
  /// comment is the record of why, so the next reader does not re-derive
  /// KHA-122's wrong turn.
  Future<void> requestImmediateSweep();
}

final class AndroidSmsPermissionService implements SmsPermissionService {
  final MethodChannel _channel;

  AndroidSmsPermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(smsMethodChannelName);

  @override
  Future<SmsPermissionStatus> status() async {
    return _parse(await _invoke('permissionStatus'));
  }

  @override
  Future<SmsPermissionStatus> request() async {
    return _parse(await _invoke('requestPermissions'));
  }

  @override
  Future<void> openAppSettings() => _invoke('openAppSettings');

  @override
  Future<void> registerBackgroundEntrypoint(int callbackHandle) => _invoke(
    'registerBackgroundEntrypoint',
    <String, Object?>{'handle': callbackHandle},
  );

  @override
  Future<void> requestImmediateSweep() => _invoke('requestImmediateSweep');

  Future<String?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<String>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Unknown or absent values fall back to [SmsPermissionStatus.denied].
  ///
  /// Deliberately the *pessimistic* default. Defaulting to `granted` on an
  /// unrecognised value would make the app behave as though ingestion were
  /// working while nothing was actually being read — an empty transaction
  /// list with no explanation, which is precisely what AC-A1.2 forbids.
  SmsPermissionStatus _parse(String? raw) => switch (raw) {
    'granted' => SmsPermissionStatus.granted,
    'permanently_denied' => SmsPermissionStatus.permanentlyDenied,
    _ => SmsPermissionStatus.denied,
  };
}
