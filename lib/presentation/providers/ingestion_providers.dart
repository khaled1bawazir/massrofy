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

import '../../core/crypto/domain_separated_key.dart';
import '../../core/time/clock.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/sms/android_sms_source.dart';
import '../../features/ingestion/background_entrypoint.dart';
import '../../features/ingestion/content_hmac.dart';
import '../../features/ingestion/historical_importer.dart';
import '../../features/ingestion/ingestion_pipeline.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ingestion/sms_broadcast_signal.dart';
import '../../features/ingestion/sms_permission_service.dart';
import '../../features/ingestion/sms_source.dart';
import '../../features/ledger/ledger_entity_resolver.dart';
import '../../features/parsing/message_parser.dart';
import '../../features/parsing/partial_extraction.dart';
import '../../features/parsing/rule_pack.dart';
import '../../features/parsing/rule_pack_loader.dart';
import '../../features/parsing/rule_pack_message_parser.dart';
import 'app_providers.dart';
import 'categorization_providers.dart';
import 'ledger_providers.dart';

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

/// **KHA-122** — the Kotlin → Dart *"an SMS just arrived"* signal.
///
/// Overridden in tests, like every other platform boundary in this file.
final Provider<SmsBroadcastSignal> smsBroadcastSignalProvider =
    Provider<SmsBroadcastSignal>((Ref ref) => AndroidSmsBroadcastSignal());

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

      // P3a (KHA-23): the ingestion pipeline's link to the domain model.
      // Without this the pipeline still runs and still records every
      // transaction — it simply leaves the instrument explicitly unknown —
      // which is why the parameter is nullable. Wiring it here is what makes
      // "a bank and card appear the first time an SMS mentions them"
      // (US-B15) a property of the shipped app rather than of a test.
      final LedgerEntityResolver? resolver = await ref.watch(
        ledgerEntityResolverProvider.future,
      );

      // P4a (KHA-31): the learning loop's automatic half. Wiring it here is
      // what makes AC-D2.1 — "a new message from that same utility arrives
      // ALREADY categorized, with no user action" — a property of the shipped
      // app rather than of a test. Nullable for the same reason as the
      // resolver above: without it every transaction is simply uncategorized.
      final CategorizeWrittenTransaction? categorizer = await ref.watch(
        ingestionCategorizerProvider.future,
      );

      return IngestionPipeline(
        database: session.database,
        smsSource: ref.watch(smsSourceProvider),
        parser: parser,
        rawMessageDao: session.rawMessageDao,
        transactionDao: session.transactionDao,
        watermarkDao: IngestWatermarkDao(session.database),
        logger: ref.watch(safeLoggerProvider),
        // ADR-017 D1's HMAC key. Derived from the Keystore-held audit chain
        // key rather than provisioning a second secret from scratch: one
        // root secret, still one lifecycle/rotation story, but a distinct,
        // domain-separated subkey per protocol (KHA-21 / B5) so the audit
        // chain's HMAC and this one can never authenticate for each other.
        // See `domain_separated_key.dart` and `content_hmac.dart`.
        contentHmacKey: DomainSeparatedKey.derive(
          rootKey: session.auditLogDao.auditChainKey,
          label: ContentHmac.keyDerivationLabel,
        ),
        entityResolver: resolver,
        categorizer: categorizer,
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

/// **KHA-122 / AC-A1.1 — the trigger that makes the foreground sweep prompt.**
///
/// > *"…a corresponding transaction appears in the transaction list within
/// > single-digit seconds and without any user action — **including when the app
/// > simply stays open and is never backgrounded and resumed.**"*
///
/// Subscribes to the Kotlin broadcast signal and invalidates
/// [foregroundSweepProvider] on every marker. `app.dart` keeps this provider
/// alive while the app is unlocked; nothing reads its value.
///
/// ## Why the invalidation happens *here* rather than in a widget listener
///
/// A `ref.listen` in `app.dart` would have to decide "is this a new signal?" by
/// comparing the emitted value with the previous one, and that comparison is
/// wrong in one real case: when this provider is rebuilt (a resume invalidates
/// `smsPermissionStatusProvider`, which this watches), its sequence restarts, so
/// a fresh signal can emit a value equal to the last one it emitted before the
/// rebuild and be read as "nothing changed". Dropping an SMS trigger is the
/// exact failure the issue is about. Doing the invalidation at the point the
/// event actually arrives has no such comparison to get wrong.
///
/// ## The two gates, and why each is the honest answer rather than a guard
///
///  - **No unlocked session → no subscription.** ADR-005 makes the lock
///    cryptographic; while locked there is no database to write to, so there is
///    nothing a prompt sweep could do. That case is governed by AC-A1.4 /
///    NFR-R1's "visible at next unlock" clause and is deliberately unchanged.
///  - **No SMS permission → no subscription.** `foregroundSweepProvider`
///    already returns early without permission (AC-A1.3's revoked banner is the
///    user-visible half); subscribing would only schedule work that returns
///    immediately.
///
/// ## What it cannot do, by construction
///
/// It cannot ingest, parse, dedup or advance the watermark, because it does none
/// of those things — it invalidates the one provider that does, so the immediate
/// sweep and the resume sweep are *literally the same code*. That is what makes
/// product-owner's condition on KHA-122 (*"the immediate sweep must go through
/// the same dedup and watermark path as the resume sweep"*) structural rather
/// than a promise. `test/features/ingestion/immediate_sweep_race_test.dart`
/// pins the overlap case: exactly one transaction, whichever order they land in.
final StreamProvider<int> foregroundSmsSignalProvider = StreamProvider<int>((
  Ref ref,
) async* {
  final UnlockedDatabaseSession? session = await ref.watch(
    unlockedDatabaseSessionProvider.future,
  );
  if (session == null) {
    return;
  }
  final SmsPermissionStatus permission = await ref.watch(
    smsPermissionStatusProvider.future,
  );
  if (!permission.allowsIngestion) {
    return;
  }

  int received = 0;
  await for (final void _ in ref.watch(smsBroadcastSignalProvider).incoming) {
    received += 1;
    // The whole point of the file. Re-runs `runIncremental()` — same
    // watermark, same ADR-017 D1 dedup, same single writer.
    ref.invalidate(foregroundSweepProvider);
    // Emitted so the count is observable from a test and from a future
    // diagnostics panel. Deliberately a count and never the message: this
    // stream is one channel hop away from an SMS body and must stay
    // content-free (NFR-S4).
    yield received;
  }
});

/// **S-05 — the historical import's live progress** (KHA-113, AC-A3.2).
///
/// A Drift stream over the watermark row, which is the only place the import
/// records where it has got to (`historical_importer.dart` writes it after
/// every chunk, precisely so the import survives being killed mid-run). That
/// makes progress a *derived* fact rather than something the screen has to be
/// pushed: a background chunk that lands while the app is closed still moves
/// the bar the next time anyone looks.
final StreamProvider<ImportProgress> importProgressProvider =
    StreamProvider<ImportProgress>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield ImportProgress.idle;
        return;
      }
      final IngestWatermarkDao dao = IngestWatermarkDao(session.database);
      yield* dao.watch().map(
        (IngestWatermarkRow row) => ImportProgress(
          state: row.importState,
          processed: row.importProcessedCount,
          // Null while the importer is still counting candidates, which the
          // screen renders as an indeterminate bar rather than a fake
          // percentage.
          totalCandidates: row.importTotalCandidates,
          fromDateUtc: row.importFromDate,
        ),
      );
    });

/// What S-05 renders. A value type rather than the raw row so the screen never
/// sees the ingestion cursor, which is an implementation detail it has no use
/// for and could not explain to a user.
final class ImportProgress {
  /// The watermark's own vocabulary: `idle` | `running` | `paused` | `done`.
  final String state;
  final int processed;
  final int? totalCandidates;

  /// AC-A3.1's lower bound — the start of the current calendar month. Used to
  /// count how many transactions the import has actually produced, which is
  /// the number the user cares about (the mockup shows it, not the message
  /// count).
  final DateTime? fromDateUtc;

  const ImportProgress({
    required this.state,
    required this.processed,
    required this.totalCandidates,
    required this.fromDateUtc,
  });

  static const ImportProgress idle = ImportProgress(
    state: importStateIdle,
    processed: 0,
    totalCandidates: null,
    fromDateUtc: null,
  );

  /// True while there is an import worth showing a progress screen for.
  /// `paused` counts: an import interrupted by a lock or a process death is
  /// still unfinished work, and hiding it would tell the user it had finished.
  ///
  /// `completed` deliberately does not — see [IngestWatermarkDao.completeImport]
  /// for why "done" is a distinct terminal state rather than a return to
  /// `idle`, and why conflating the two once made the app re-import the whole
  /// month on every launch.
  bool get isActive =>
      state == importStateRunning || state == importStatePaused;
}

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
              // KHA-146. `tryDecode` returns null for anything unreadable —
              // an older row written before schema v8, a row from a future
              // encoding, or a corrupted one — so a single bad row degrades
              // that one message to a blank form instead of throwing inside a
              // stream and emptying the whole review queue (NFR-A7 again: the
              // queue must survive its own contents).
              partialExtraction: PartialExtraction.tryDecode(
                row.partialExtraction as String?,
              ),
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
