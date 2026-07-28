import 'package:drift/drift.dart';

/// ADR-006's **watermark** — the single most important row in the ingestion
/// design, and the reason the whole thing is self-healing.
///
/// ## What the watermark buys us
///
/// ADR-006 rejected two obvious designs before landing here:
///
///  - *Receiver parses inline* — a broadcast receiver has roughly a 10-second
///    budget, and can be killed mid-write.
///  - *Receiver hands the SMS body to WorkManager as input `Data`* —
///    WorkManager persists that in its **own unencrypted SQLite database**,
///    which would put plaintext bank SMS in a store we do not control the
///    encryption of.
///
/// The chosen design: **the broadcast carries no content at all.** It is a
/// bare "something arrived" signal. The worker then re-reads
/// `content://sms/inbox WHERE date > watermark`. Three properties follow, and
/// all three matter:
///
/// 1. **No PII transits any store we don't encrypt.** The only place a
///    message body ever lands is the SQLCipher database.
/// 2. **It is idempotent and resumable.** Re-running the same sweep produces
///    the same result. That is what makes AC-A3.3 ("an interrupted import
///    resumes without creating duplicates") true by construction rather than
///    by careful bookkeeping.
/// 3. **A missed broadcast self-heals.** If the OEM battery manager eats the
///    broadcast (risk R-1), the next wake — the 15-minute periodic sweep, or
///    simply the user opening the app — picks up *everything* since the
///    watermark. Nothing is lost; it arrives later. That is exactly the
///    bounded degradation ADR-006's latency table promises.
///
/// ## The atomicity rule, which is not optional
///
/// > *"advances the watermark **in the same database transaction** as the
/// > writes it produced"* — ADR-006 Layer 1, step 3.
///
/// If the watermark advanced first and the process died, the messages between
/// the old and new watermark would be skipped **forever** and the user would
/// never know. If it advanced last, in its own transaction, a crash would
/// re-process messages — harmless, because dedup catches them (ADR-017 D1),
/// but the first ordering is unrecoverable. Doing both in one transaction
/// makes the question moot. See `IngestWatermarkDao` and
/// `IngestionPipeline`.
///
/// ## Single row, by construction
///
/// `id` is fixed at [IngestWatermarks.singletonId] with a CHECK constraint,
/// so a second watermark row cannot exist. Two watermarks would mean two
/// answers to "where did we get to", and the lower one would silently win on
/// whichever code path read it first.
/// The only permitted primary-key value of the watermark row.
///
/// Declared as a top-level constant rather than a `static` member of
/// [IngestWatermarks] on purpose: Drift's generated code *extends* the table
/// class, and an unqualified reference to an inherited static member is a
/// Dart error. Keeping it out here also means SQL string literals and Dart
/// code share one source of truth for the value.
const int ingestWatermarkSingletonId = 1;

@DataClassName('IngestWatermarkRow')
class IngestWatermarks extends Table {
  @override
  String get tableName => 'ingest_watermark';

  /// Fixed at [ingestWatermarkSingletonId] and enforced by the CHECK
  /// constraint in [customConstraints] — two watermark rows would mean two
  /// answers to "where did we get to", and whichever one a given code path
  /// read first would silently win.
  IntColumn get id =>
      integer().withDefault(const Constant(ingestWatermarkSingletonId))();

  /// The `_id` of the newest SMS provider row processed. Used together with
  /// [lastProcessedSmsDate] because neither alone is sufficient: two messages
  /// can share a `date` to the millisecond (a multi-part SMS, or a carrier
  /// burst), and `_id` is monotonic but is reset when the user's SMS database
  /// is restored from a backup.
  IntColumn get lastProcessedSmsProviderId =>
      integer().withDefault(const Constant(0))();

  /// The `date` of the newest processed message. Stored, like every instant
  /// in this schema, in UTC.
  DateTimeColumn get lastProcessedSmsDate => dateTime().nullable()();

  /// `idle` | `running` | `paused` | `completed` — the historical import's
  /// state machine (architecture §4.2 `IngestWatermark`). The constants live
  /// in `IngestWatermarkDao`; the transition diagram is there too.
  ///
  /// `completed` is a **terminal** state and is deliberately not the same
  /// value as the initial `idle`. Reusing `idle` to mean "finished" made a
  /// completed import indistinguishable from one that had never started, so
  /// every app foreground re-ran the whole month's backfill. See
  /// `IngestWatermarkDao.completeImport`.
  ///
  /// Persisted rather than held in memory precisely because AC-A3.3 requires
  /// the import to survive the app being closed or the device restarting. An
  /// in-memory flag would report `idle` after a crash and silently restart
  /// the whole import from scratch.
  TextColumn get importState => text().withDefault(const Constant('idle'))();

  /// How far the historical import has walked **backwards** through the
  /// inbox: the oldest provider `_id` it has already handled. Resuming means
  /// continuing from here rather than from the top.
  IntColumn get importCursor => integer().nullable()();

  /// The lower bound of the historical import — **the start of the current
  /// calendar month in `Asia/Riyadh`** (AC-A3.1, OQ-11 resolved: not full
  /// history).
  ///
  /// Frozen at the moment the import starts rather than recomputed on each
  /// resume, so an import that spans midnight on the 1st does not silently
  /// change its own goalposts halfway through.
  DateTimeColumn get importFromDate => dateTime().nullable()();

  /// Progress reporting for the S-05 onboarding screen (AC-A3.2). Counts, not
  /// content — nothing here is sensitive.
  IntColumn get importTotalCandidates => integer().nullable()();
  IntColumn get importProcessedCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  /// The singleton guarantee, expressed at the SQL layer so it holds against
  /// **any** writer — including a future code path, a migration, or a bug in
  /// this DAO — rather than only against the DAO's public API shape. This is
  /// the same defence-in-depth reasoning ADR-010 applies to the append-only
  /// audit triggers.
  @override
  List<String> get customConstraints => <String>[
    'CHECK (id = $ingestWatermarkSingletonId)',
  ];
}
