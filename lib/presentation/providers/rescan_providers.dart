/// Riverpod wiring for KHA-133's "check my banks again" re-scan.
///
/// Kept out of `ingestion_providers.dart` deliberately: everything here is the
/// *user-triggered* recovery path, everything there is the automatic ingestion
/// path, and ADR-006's KHA-133 decision turns on that distinction (Q3 rejected
/// every automatic trigger). One file per direction makes it obvious at a
/// glance that nothing in the app calls the re-scan on its own — grep this
/// file's `RescanController.run` for callers and there is exactly one, a
/// button.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/log_event.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../../features/ingestion/ingestion_pipeline.dart';
import '../../features/ingestion/rescan_coordinator.dart';
import '../../features/ingestion/sms_permission_service.dart';
import '../../features/parsing/message_parser.dart';
import 'app_providers.dart';
import 'ingestion_providers.dart';

const String _logRescanFailed = 'ingestion.rescan_failed';

/// The coordinator, bound to the **unlocked** database session.
///
/// `null` while the app is locked, for the same reason
/// [ingestionPipelineProvider] is: ADR-005 makes the lock cryptographic, so
/// with no unwrapped DB Master Key there is no database, and therefore no
/// coordinator. That is the honest expression of the guarantee, not a
/// placeholder — and it is why the screen has a real locked state rather than
/// a spinner that never resolves.
final FutureProvider<RescanCoordinator?> rescanCoordinatorProvider =
    FutureProvider<RescanCoordinator?>((Ref ref) async {
      final IngestionPipeline? pipeline = await ref.watch(
        ingestionPipelineProvider.future,
      );
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (pipeline == null || session == null) {
        return null;
      }

      final MessageParser parser = await ref.watch(
        messageParserProvider.future,
      );

      return RescanCoordinator(
        smsSource: ref.watch(smsSourceProvider),
        pipeline: pipeline,
        watermarkDao: IngestWatermarkDao(session.database),
        parser: parser,
        auditLogDao: session.auditLogDao,
        clock: ref.watch(clockProvider),
        logger: ref.watch(safeLoggerProvider),
      );
    });

// ---------------------------------------------------------------------------
// Screen state
// ---------------------------------------------------------------------------

/// What the re-check screen is showing.
///
/// A sealed hierarchy rather than an `AsyncValue<RescanResult?>`, because the
/// states this screen must distinguish are not "loading / data / error":
/// **locked** and **permission revoked** are ordinary, expected, non-error
/// conditions with their own copy and their own next action, and squeezing
/// them into `AsyncError` would render them as "something went wrong" — which
/// is both untrue and unhelpful.
sealed class RescanState {
  const RescanState();
}

/// Nothing has been asked for yet. The button is enabled.
final class RescanIdle extends RescanState {
  const RescanIdle();
}

/// A walk is in progress. The button is disabled — see [RescanController.run]
/// for why that is a correctness measure, not just polish.
final class RescanRunning extends RescanState {
  const RescanRunning();
}

/// It finished. [result] carries every number the screen shows.
final class RescanSucceeded extends RescanState {
  final RescanResult result;
  const RescanSucceeded(this.result);
}

/// It could not run, or it threw. [reason] decides the copy.
final class RescanFailed extends RescanState {
  final RescanFailureReason reason;
  const RescanFailed(this.reason);
}

/// Why a re-check did not produce a result. Each has different copy and a
/// different thing the user can do about it.
enum RescanFailureReason {
  /// The app locked (or was never unlocked) between opening the screen and
  /// pressing the button. ADR-005: no key, no database.
  locked,

  /// `READ_SMS` is not granted. Android 11+ can auto-revoke it on an unused
  /// app, so this is a live state and not a theoretical one (AC-A1.3).
  permissionDenied,

  /// Something threw. The exception is deliberately not carried into the UI or
  /// the log — see [RescanController.run].
  unexpectedError,
}

/// Drives the one button.
///
/// The controller — rather than the screen calling the coordinator directly —
/// is what keeps the run alive across a rebuild, and what makes the
/// double-tap guard a single place rather than a `bool` in a `State`.
class RescanController extends Notifier<RescanState> {
  @override
  RescanState build() => const RescanIdle();

  /// Runs a full re-check. **The only caller is the button.**
  ///
  /// ## The re-entrancy guard is not cosmetic
  ///
  /// Two overlapping walks would not corrupt anything — dedup would suppress
  /// the second one's writes and neither touches a cursor — but they would
  /// each report a *share* of the recovered transactions, so the user would be
  /// told "3 new transactions" for a run that actually recovered 12. A number
  /// that is quietly wrong is precisely what PRD §1's "trusts the numbers"
  /// criterion cannot survive, so the second tap is dropped.
  Future<void> run() async {
    if (state is RescanRunning) {
      return;
    }
    state = const RescanRunning();

    try {
      // Checked before the coordinator is even built: with no `READ_SMS` there
      // is no inbox to re-read, and "nothing new found" would be a lie the
      // user has no way to see through.
      final SmsPermissionStatus permission = await ref.read(
        smsPermissionStatusProvider.future,
      );
      if (!permission.allowsIngestion) {
        state = const RescanFailed(RescanFailureReason.permissionDenied);
        return;
      }

      final RescanCoordinator? coordinator = await ref.read(
        rescanCoordinatorProvider.future,
      );
      if (coordinator == null) {
        state = const RescanFailed(RescanFailureReason.locked);
        return;
      }

      state = RescanSucceeded(await coordinator.recheckAllBanks());
    } catch (_) {
      // The error object is discarded rather than logged, for exactly the
      // reason `IngestionPipeline.processAll` discards its own: an exception
      // raised inside a parse routinely carries the offending SMS text in its
      // message, and this log line goes into a buffer the user may later share
      // (ADR-015, NFR-S4). The category alone says what failed.
      ref
          .read(safeLoggerProvider)
          .warning(const LogEvent(category: _logRescanFailed));
      state = const RescanFailed(RescanFailureReason.unexpectedError);
    }
  }

  // There is deliberately no `reset()`. "Check again" on the result card calls
  // [run] directly: it moves straight to [RescanRunning], which clears the
  // previous counts off the screen in the same frame. A separate clear step
  // would be one more tap for the same outcome, and a state the user could get
  // stuck in.
}

final NotifierProvider<RescanController, RescanState> rescanControllerProvider =
    NotifierProvider<RescanController, RescanState>(RescanController.new);
