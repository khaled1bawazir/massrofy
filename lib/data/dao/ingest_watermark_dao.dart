import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables/ingest_watermark_table.dart';

part 'ingest_watermark_dao.g.dart';

/// Reads and advances ADR-006's ingestion watermark.
///
/// ## Every mutating method here takes an optional transaction context
///
/// Not for convenience — for correctness. ADR-006 requires the watermark to
/// advance **in the same database transaction as the writes it produced**.
/// If this DAO opened its own transaction, the ledger write and the watermark
/// advance would be two commits, and a process death between them would
/// either skip messages forever (watermark first) or reprocess them
/// (watermark last). Drift makes "join the caller's transaction" the default
/// when a DAO method is invoked *inside* a `transaction()` block on the same
/// database instance, which is exactly how `IngestionPipeline` calls it.
@DriftAccessor(tables: [IngestWatermarks])
class IngestWatermarkDao extends DatabaseAccessor<AppDatabase>
    with _$IngestWatermarkDaoMixin {
  IngestWatermarkDao(super.attachedDatabase);

  /// The single watermark row, creating it if a database predating the
  /// migration somehow lacks one.
  ///
  /// Returning a default rather than throwing is deliberate: an ingestion run
  /// that cannot read the watermark should behave like a run starting from
  /// zero — it will re-read everything, dedup will suppress what it has
  /// already seen (ADR-017 D1), and the user loses nothing. Throwing here
  /// would stop ingestion entirely, which is the worse failure.
  Future<IngestWatermarkRow> current() async {
    final IngestWatermarkRow? row =
        await (select(ingestWatermarks)..where(
              (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
            ))
            .getSingleOrNull();
    if (row != null) {
      return row;
    }
    await into(ingestWatermarks).insert(
      const IngestWatermarksCompanion(),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .getSingle();
  }

  /// Emits the watermark on every change — the Drift stream that drives the
  /// import-progress UI (AC-A3.2) without any polling.
  Stream<IngestWatermarkRow> watch() {
    return (select(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .watchSingle();
  }

  /// Moves the incremental watermark forward.
  ///
  /// **Monotonic by construction**: the `WHERE` clause refuses to move it
  /// backwards. That matters because two ingestion runs can genuinely
  /// overlap — the broadcast-triggered expedited worker and the 15-minute
  /// periodic sweep can both be in flight — and the slower one finishing last
  /// must not rewind the faster one's progress, which would cause the same
  /// messages to be re-read on every subsequent sweep forever.
  Future<void> advanceTo({
    required int smsProviderId,
    required DateTime smsDate,
  }) async {
    await customUpdate(
      'UPDATE ingest_watermark SET last_processed_sms_provider_id = ?1, '
      'last_processed_sms_date = ?2 '
      'WHERE id = ?3 AND last_processed_sms_provider_id <= ?1',
      variables: <Variable<Object>>[
        Variable<int>(smsProviderId),
        Variable<DateTime>(smsDate),
        Variable<int>(ingestWatermarkSingletonId),
      ],
      updates: <TableInfo<Table, Object>>{ingestWatermarks},
    );
  }

  /// **KHA-157 (C) — the one-time seed.** Plants the incremental watermark at
  /// the inbox's high-water mark, so "incremental" starts meaning *new* rather
  /// than *everything the phone has ever received*.
  ///
  /// ## Why this delegates to [advanceTo] instead of writing its own UPDATE
  ///
  /// KHA-157 (B) makes `last_processed_sms_date IS NULL` the discriminator for
  /// "never seeded", and that only holds while **every** writer sets both
  /// columns together. One writer is easier to keep honest than two: this
  /// method is a name and a doc comment over [advanceTo], so there is exactly
  /// one statement in the app that can move either column, and it is monotonic.
  ///
  /// The monotonic `WHERE` also makes a double seed harmless. Two sweeps can
  /// genuinely overlap (the expedited worker and the periodic sweep), so both
  /// can read a null date and both can call this; the higher id wins and the
  /// lower one is a no-op, which is exactly what should happen.
  ///
  /// ## The caller owns the guard, deliberately
  ///
  /// There is no `WHERE last_processed_sms_date IS NULL` here. The decision
  /// *whether* to seed belongs with the read of the high-water mark, because
  /// the two must happen in that order — read the mark, then write it, never
  /// re-read after writing. See `IngestionPipeline.runIncremental`, which is
  /// this method's only caller.
  ///
  /// Takes two scalars rather than the `InboxHighWaterMark` the caller holds,
  /// so that `data/` never imports `features/` — architecture §3's dependency
  /// direction is one-way, and `features/ingestion` already imports this file.
  Future<void> seedTo({required int smsProviderId, required DateTime smsDate}) {
    return advanceTo(smsProviderId: smsProviderId, smsDate: smsDate);
  }

  /// Records the start of a historical import (US-A3).
  ///
  /// [fromDate] is frozen here rather than recomputed on each resume, so an
  /// import running across midnight on the 1st of a month does not silently
  /// move its own lower bound.
  Future<void> beginImport({
    required DateTime fromDate,
    required int totalCandidates,
    required int startCursor,
  }) async {
    await (update(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .write(
          IngestWatermarksCompanion(
            importState: const Value<String>(importStateRunning),
            importFromDate: Value<DateTime>(fromDate),
            importTotalCandidates: Value<int>(totalCandidates),
            importProcessedCount: const Value<int>(0),
            importCursor: Value<int>(startCursor),
          ),
        );
  }

  /// Saves import progress. Called after **each chunk**, not at the end, so
  /// that a kill at any point loses at most one chunk of work (AC-A3.3).
  Future<void> recordImportProgress({
    required int cursor,
    required int processedCount,
  }) async {
    await (update(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .write(
          IngestWatermarksCompanion(
            importCursor: Value<int>(cursor),
            importProcessedCount: Value<int>(processedCount),
          ),
        );
  }

  /// Marks the import **finished, for good**.
  ///
  /// ## Why this writes `completed` and not `idle`
  ///
  /// It used to write `idle` + a null cursor — which is byte-for-byte the
  /// state a brand-new database is in. `HistoricalImporter.runOrResume()` reads
  /// exactly that pair to decide "nothing has ever run here, start a fresh
  /// import", so a finished import was indistinguishable from one that had
  /// never started. Since the foreground sweep calls `runOrResume()` on every
  /// app open, the entire calendar-month backfill was re-read, re-sanitised,
  /// re-HMACed and re-queried every single time the user opened the app. It
  /// produced no duplicate rows — ADR-017 D1 saw to that — so it was invisible
  /// except as battery, latency and a diagnostic log full of self-inflicted
  /// `duplicate_suppressed` events.
  ///
  /// The lesson is general enough to be worth stating: **a state machine needs
  /// a terminal state that is distinct from its initial state.** Encoding
  /// "done" as "back to the beginning" is a loop, not a completion.
  ///
  /// The cursor is still cleared, because it is meaningless once the walk is
  /// over; [importStateCompleted] is now the thing that carries the meaning.
  Future<void> completeImport() async {
    await (update(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .write(
          const IngestWatermarksCompanion(
            importState: Value<String>(importStateCompleted),
            importCursor: Value<int?>(null),
          ),
        );
  }

  /// Marks the import paused — used when the app is backgrounded or the
  /// process is about to be torn down. `paused` (rather than `idle`) is what
  /// tells the next run "there is unfinished work, resume it".
  Future<void> pauseImport() async {
    await (update(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .write(
          const IngestWatermarksCompanion(
            importState: Value<String>(importStatePaused),
          ),
        );
  }
}

/// The `importState` vocabulary (architecture §4.2 `IngestWatermark`), as
/// constants rather than a Dart enum because the value is persisted as text
/// and must survive a schema round-trip unchanged.
///
/// The historical import is a **one-shot backfill**, so its state machine is:
///
/// ```
///   idle ──beginImport──► running ──completeImport──► completed  (terminal)
///     ▲                      │  ▲                          │
///     │                      │  └──────runOrResume─────────┘  (no-op)
///  (fresh DB)          pauseImport
///                            ▼
///                         paused ──runOrResume──► running …
/// ```
///
/// `idle` means **never started**; `completed` means **finished, do not run
/// again**. Those are two different things and conflating them is precisely
/// the bug [IngestWatermarkDao.completeImport] documents. `paused` and
/// `running` both mean "unfinished work, resume from the cursor" — the
/// distinction between them is only for a progress UI, not for control flow.
const String importStateIdle = 'idle';
const String importStateRunning = 'running';
const String importStatePaused = 'paused';

/// The terminal state. Nothing transitions out of it: the backfill covers a
/// fixed window (the current calendar month at first run) and ongoing messages
/// are the incremental watermark's job, not the importer's.
///
/// Note for anyone reading a database created before this constant existed: a
/// finished import was recorded there as `idle`, which this code now reads as
/// "never started". Such a database re-runs the backfill exactly once more and
/// then settles into `completed`. That costs one extra walk and cannot create
/// duplicates (ADR-017 D1), so it is not worth a migration.
const String importStateCompleted = 'completed';
