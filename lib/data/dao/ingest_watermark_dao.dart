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

  /// Marks the import finished. The cursor is cleared so a later re-run
  /// starts fresh rather than resuming a completed walk.
  Future<void> completeImport() async {
    await (update(ingestWatermarks)..where(
          (IngestWatermarks t) => t.id.equals(ingestWatermarkSingletonId),
        ))
        .write(
          const IngestWatermarksCompanion(
            importState: Value<String>(importStateIdle),
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
const String importStateIdle = 'idle';
const String importStateRunning = 'running';
const String importStatePaused = 'paused';
