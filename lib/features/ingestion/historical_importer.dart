/// The first-run historical import (US-A3, AC-A3.1–A3.3).
///
/// > *"transaction SMS already in the inbox **from the start of the current
/// > calendar month** onward are parsed into transactions"* — AC-A3.1, which
/// > resolved OQ-11. **Not** full history.
///
/// ## Why "resumable" is a correctness requirement, not a nicety
///
/// AC-A3.3: *"Given an initial import is interrupted (app closed, device
/// restart), when the app next runs, then the import resumes or restarts
/// **without creating duplicate transactions**."*
///
/// The device decides when this process dies, not us. On a first run over a
/// busy inbox the import is the longest-running thing the app does, so it is
/// the *most* likely thing to be killed — by the user swiping the app away,
/// by Doze, by an OEM memory manager. An import that could not resume would
/// restart from scratch every time and, on a device that kills it reliably,
/// would never finish at all.
///
/// Two mechanisms make resumption safe, and they are independent on purpose:
///
/// 1. **A persisted cursor** (`IngestWatermark.importCursor`), written after
///    **each chunk** rather than at the end. A kill loses at most one chunk.
/// 2. **Dedup** (ADR-017 D1), which is enforced by `UNIQUE` constraints in
///    the schema. Even if the cursor were lost entirely and the import
///    restarted from zero, no duplicate transaction could be created.
///
/// Mechanism 2 is what actually satisfies AC-A3.3; mechanism 1 is what makes
/// it finish in reasonable time. Relying on the cursor alone would be
/// hoping — relying on dedup alone would work but be needlessly slow.
///
/// ## Forwards, not backwards
///
/// The walk goes oldest-to-newest from the start of the month. That is what
/// makes the cursor meaningful across a restart: a backwards walk's cursor
/// would have to be reinterpreted every time new messages arrived at the top
/// of the inbox, which is exactly the situation during a long import.
///
/// The import deliberately does **not** advance the incremental watermark
/// (`processAll(advanceWatermark: false)`). The two cursors track different
/// things: one says "how far back have we looked", the other says "how far
/// forward have we got". Conflating them would let the import silently skip
/// messages that arrived while it was running.
library;

import '../../core/logging/log_event.dart';
import '../../core/logging/safe_logger.dart';
import '../../core/time/clock.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import 'ingestion_pipeline.dart';
import 'sms_source.dart';

const String _logImportStarted = 'ingestion.import_started';
const String _logImportResumed = 'ingestion.import_resumed';
const String _logImportCompleted = 'ingestion.import_completed';

final class HistoricalImporter {
  final SmsSource smsSource;
  final IngestionPipeline pipeline;
  final IngestWatermarkDao watermarkDao;
  final Clock clock;
  final SafeLogger logger;

  /// Messages per chunk.
  ///
  /// Small on purpose. Every chunk boundary is a progress save (AC-A3.3) and
  /// a yield point that lets the UI isolate breathe, which is what keeps the
  /// app responsive during the import (AC-A3.2, NFR-R3). A large chunk would
  /// import faster on a device that never gets killed and never finish on one
  /// that does.
  final int chunkSize;

  const HistoricalImporter({
    required this.smsSource,
    required this.pipeline,
    required this.watermarkDao,
    required this.clock,
    required this.logger,
    this.chunkSize = 50,
  });

  /// Runs, or resumes, the import.
  ///
  /// Safe to call repeatedly — on every app launch, if you like. If an import
  /// is already `running` this picks up where it left off; if it completed,
  /// it does nothing.
  ///
  /// [shouldContinue] is polled between chunks so the caller can stop the
  /// import cleanly when the app is backgrounded, leaving the state `paused`
  /// and the cursor saved rather than being killed mid-chunk.
  Future<IngestionRunResult> runOrResume({
    bool Function()? shouldContinue,
  }) async {
    final row = await watermarkDao.current();

    // Already finished, and not left paused mid-walk. Nothing to do.
    if (row.importState == importStateIdle && row.importCursor == null) {
      final DateTime from = RiyadhCalendar.startOfCurrentMonthUtc(
        clock.nowUtc(),
      );
      // A fresh start. `from` is frozen into the watermark row here rather
      // than recomputed on each resume, so an import that spans midnight on
      // the 1st of a month does not silently move its own lower bound
      // half-way through and skip the first days of the old month.
      final int total = await smsSource.countRange(from: from);
      await watermarkDao.beginImport(
        fromDate: from,
        totalCandidates: total,
        startCursor: 0,
      );
      logger.info(LogEvent(category: _logImportStarted, count: total));
      return _walk(from: from, cursor: 0, shouldContinue: shouldContinue);
    }

    // Resuming. Use the *stored* `importFromDate`, never a freshly computed
    // one, for the same reason.
    final DateTime from =
        row.importFromDate ??
        RiyadhCalendar.startOfCurrentMonthUtc(clock.nowUtc());
    final int cursor = row.importCursor ?? 0;
    logger.info(LogEvent(category: _logImportResumed, count: cursor));

    return _walk(from: from, cursor: cursor, shouldContinue: shouldContinue);
  }

  Future<IngestionRunResult> _walk({
    required DateTime from,
    required int cursor,
    bool Function()? shouldContinue,
  }) async {
    IngestionRunResult total = const IngestionRunResult();
    int position = cursor;
    int processed = 0;

    while (true) {
      if (shouldContinue != null && !shouldContinue()) {
        // Clean stop. `paused` (not `idle`) is what tells the next run there
        // is unfinished work to pick up.
        await watermarkDao.pauseImport();
        return total;
      }

      final List<RawSmsRecord> chunk = await smsSource.readRange(
        from: from,
        afterProviderId: position,
        limit: chunkSize,
      );
      if (chunk.isEmpty) {
        break;
      }

      final IngestionRunResult chunkResult = await pipeline.processAll(
        chunk,
        // See the library doc comment: the historical walk must not move the
        // incremental watermark.
        advanceWatermark: false,
      );

      total = _merge(total, chunkResult);
      position = chunk.last.providerId;
      processed += chunk.length;

      // Save AFTER the chunk's writes, never before. If the process dies
      // between the writes and this save, the chunk is simply re-read next
      // time and dedup suppresses it — harmless. The other order would skip
      // it permanently.
      await watermarkDao.recordImportProgress(
        cursor: position,
        processedCount: processed,
      );
    }

    await watermarkDao.completeImport();
    logger.info(LogEvent(category: _logImportCompleted, count: processed));
    return total;
  }

  IngestionRunResult _merge(IngestionRunResult a, IngestionRunResult b) =>
      IngestionRunResult(
        examined: a.examined + b.examined,
        transactionsWritten: a.transactionsWritten + b.transactionsWritten,
        flaggedAsPossibleDuplicate:
            a.flaggedAsPossibleDuplicate + b.flaggedAsPossibleDuplicate,
        suppressedAsExactDuplicate:
            a.suppressedAsExactDuplicate + b.suppressedAsExactDuplicate,
        routedToReviewQueue: a.routedToReviewQueue + b.routedToReviewQueue,
        ignoredAsNoise: a.ignoredAsNoise + b.ignoredAsNoise,
        discardedNonFinancialSender:
            a.discardedNonFinancialSender + b.discardedNonFinancialSender,
        failedWithError: a.failedWithError + b.failedWithError,
      );
}
