/// Riverpod wiring for SMS ingestion (ADR-006) and parsing (ADR-007).
///
/// ## Why this is a separate file from `app_providers.dart`
///
/// `app_providers.dart` wires the P1 foundation: keys, the lock controller,
/// the encrypted database session. Everything here depends on that session
/// existing, and nothing there depends on anything here. Keeping the two
/// apart makes the direction of that dependency obvious at a glance, and
/// stops the foundation file growing into the app's one big DI dumping
/// ground.
///
/// ## The point of wiring this up at all in P2
///
/// The P1 code review made a sharp observation that applies here too: a
/// component with **no production call site** is library code, not shipped
/// behaviour, and it is easy to convince yourself otherwise because the tests
/// are green. `openEncryptedConnection` had zero callers outside tests until
/// `unlockedDatabaseSessionProvider` was written for exactly that reason.
///
/// So these providers exist to make the ingestion pipeline genuinely
/// reachable from the running app: the moment the user unlocks,
/// [foregroundSweepProvider] runs the same pipeline the background worker
/// would, over the real device inbox.
library;

import 'dart:async' show unawaited;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time/clock.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../../data/sms/android_sms_source.dart';
import '../../features/ingestion/background_entrypoint.dart';
import '../../features/ingestion/historical_importer.dart';
import '../../features/ingestion/ingestion_pipeline.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ingestion/sms_permission_service.dart';
import '../../features/ingestion/sms_source.dart';
import '../../features/parsing/message_parser.dart';
import '../../features/parsing/rule_pack.dart';
import '../../features/parsing/rule_pack_loader.dart';
import '../../features/parsing/rule_pack_message_parser.dart';
import 'app_providers.dart';

/// Path of the bundled rule pack asset (ADR-007 "Bundled" source).
const String bundledRulePackAsset = 'assets/rule_packs/sa-core.json';

final Provider<Clock> clockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
);

final Provider<SmsPermissionService> smsPermissionServiceProvider =
    Provider<SmsPermissionService>((Ref ref) => AndroidSmsPermissionService());

final Provider<SmsSource> smsSourceProvider = Provider<SmsSource>(
  (Ref ref) => AndroidSmsSource(),
);

/// The user's current SMS permission state (AC-A1.2, AC-A1.3).
///
/// Deliberately a `FutureProvider` that is re-read on foreground rather than
/// a value cached at startup: **Android 11+ can revoke this permission on its
/// own** if the app goes unused for a few months (ADR-006). A cached "granted"
/// would leave the app cheerfully showing an empty transaction list while
/// nothing was being ingested — precisely the unexplained empty state
/// AC-A1.2 forbids.
final FutureProvider<SmsPermissionStatus> smsPermissionStatusProvider =
    FutureProvider<SmsPermissionStatus>(
      (Ref ref) => ref.watch(smsPermissionServiceProvider).status(),
    );

/// The active rule packs (ADR-007).
///
/// Bundled only, for now. Imported packs — the answer to risk R-11, where a
/// parser fix ships as data rather than as an APK the user must side-load —
/// slot in as additional entries in this list, **after** the bundled pack so
/// first-match-wins keeps bundled rules authoritative unless the user
/// deliberately replaces them.
final FutureProvider<List<RulePack>> activeRulePacksProvider =
    FutureProvider<List<RulePack>>((Ref ref) async {
      final String json = await rootBundle.loadString(bundledRulePackAsset);
      return <RulePack>[RulePackLoader.parse(json)];
    });

final FutureProvider<MessageParser> messageParserProvider =
    FutureProvider<MessageParser>((Ref ref) async {
      final List<RulePack> packs = await ref.watch(
        activeRulePacksProvider.future,
      );
      return RulePackMessageParser(packs: packs);
    });

/// The pipeline, bound to the **unlocked** database session.
///
/// Returns `null` while the app is locked. That is not a placeholder — it is
/// the honest expression of ADR-005's guarantee: with no unwrapped DB Master
/// Key there is no database to write to, so there is no pipeline. See
/// `ingestion_pipeline.dart`'s "the locked-database problem" note.
final FutureProvider<IngestionPipeline?> ingestionPipelineProvider =
    FutureProvider<IngestionPipeline?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        return null;
      }

      final MessageParser parser = await ref.watch(
        messageParserProvider.future,
      );

      return IngestionPipeline(
        database: session.database,
        smsSource: ref.watch(smsSourceProvider),
        parser: parser,
        rawMessageDao: session.rawMessageDao,
        transactionDao: session.transactionDao,
        watermarkDao: IngestWatermarkDao(session.database),
        logger: ref.watch(safeLoggerProvider),
        // ADR-017 D1's HMAC key. Reusing the Keystore-held audit chain key
        // rather than provisioning a second secret: one key, two uses, versus
        // a second key with its own lifecycle, rotation story and failure
        // modes to get wrong. See `content_hmac.dart`.
        contentHmacKey: session.auditLogDao.auditChainKey,
      );
    });

final FutureProvider<HistoricalImporter?> historicalImporterProvider =
    FutureProvider<HistoricalImporter?>((Ref ref) async {
      final IngestionPipeline? pipeline = await ref.watch(
        ingestionPipelineProvider.future,
      );
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (pipeline == null || session == null) {
        return null;
      }

      return HistoricalImporter(
        smsSource: ref.watch(smsSourceProvider),
        pipeline: pipeline,
        watermarkDao: IngestWatermarkDao(session.database),
        clock: ref.watch(clockProvider),
        logger: ref.watch(safeLoggerProvider),
      );
    });

/// **ADR-006 Layer 2, the foreground trigger.**
///
/// > *"A `PeriodicWorkRequest` every 15 minutes, **plus a sweep on app
/// > foreground**, plus a `BOOT_COMPLETED` receiver…"*
///
/// This is the layer that makes the product correct even when Layer 1 is
/// suppressed by an OEM battery manager (risk R-1) — and, given the
/// locked-database limitation documented in `background_entrypoint.dart`, it
/// is currently the layer that does the actual work on every wake where the
/// app was locked. The watermark guarantees it picks up everything since the
/// last successful run, however long ago that was.
///
/// Runs the incremental sweep first, then resumes any unfinished historical
/// import. That order matters: new messages are what the user is waiting to
/// see, and a long import must not delay them.
final FutureProvider<IngestionRunResult?> foregroundSweepProvider =
    FutureProvider<IngestionRunResult?>((Ref ref) async {
      final IngestionPipeline? pipeline = await ref.watch(
        ingestionPipelineProvider.future,
      );
      if (pipeline == null) {
        return null;
      }

      final SmsPermissionStatus permission = await ref.watch(
        smsPermissionStatusProvider.future,
      );
      if (!permission.allowsIngestion) {
        // AC-A1.3: nothing to ingest, and the UI shows the revoked banner.
        // Returning rather than throwing keeps "no permission" an ordinary
        // state rather than an error the user has to interpret.
        return null;
      }

      final IngestionRunResult result = await pipeline.runIncremental();

      final HistoricalImporter? importer = await ref.watch(
        historicalImporterProvider.future,
      );
      // Fire-and-forget: the import is explicitly non-blocking (AC-A3.2,
      // NFR-R2) and reports progress through the watermark's own Drift
      // stream, so the caller has no reason to await it.
      if (importer != null) {
        unawaited(importer.runOrResume());
      }

      return result;
    });

/// The unparsed half of the Needs Review inbox (design.md S-18).
///
/// A Drift stream, so a background ingestion run that adds a review item
/// updates the badge and the list with no polling and no manual refresh
/// (architecture §7.5).
final StreamProvider<List<ReviewQueueItem>> reviewQueueProvider =
    StreamProvider<List<ReviewQueueItem>>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield const <ReviewQueueItem>[];
        return;
      }

      yield* session.rawMessageDao.watchReviewQueue().map(
        (List<dynamic> rows) => <ReviewQueueItem>[
          for (final dynamic row in rows)
            ReviewQueueItem(
              rawMessageId: row.id as int,
              // Non-null by construction: the query filters to
              // `financial_unparsed`, and that classification is only ever
              // written together with a body (see `IngestionPipeline`). The
              // `?? ''` is a belt to those braces rather than a real case.
              sanitizedBody: (row.sanitizedBody as String?) ?? '',
              sender: row.sender as String,
              receivedAt: row.receivedAt as DateTime,
              bankId: row.bankId as String?,
              unparsedReason: row.unparsedReason as String?,
              unparsedRuleId: row.unparsedRuleId as String?,
            ),
        ],
      );
    });

/// Registers the Dart entrypoint the background worker calls, and arms
/// ADR-006's Layer-2 periodic sweep. Called once at startup.
///
/// The handle must be registered **before** the first SMS arrives, or
/// `IngestWorker` finds nothing to call and defers to the next foreground
/// sweep (which is correct, but slower). Registering at startup rather than
/// after onboarding means a user who grants permission and immediately
/// receives an SMS is covered.
Future<void> registerBackgroundIngestion(SmsPermissionService service) async {
  final int? handle = resolveIngestEntrypointHandle();
  if (handle == null) {
    // Only reachable if the `@pragma('vm:entry-point')` annotation is
    // removed, in which case the tree-shaker dropped the function from the
    // release build. Failing silently here is right — the foreground sweep
    // still works — but it is worth knowing the shape of the failure.
    return;
  }
  await service.registerBackgroundEntrypoint(handle);
}
