import 'package:drift/drift.dart';

import 'tables/app_settings_table.dart';
import 'tables/audit_entry_table.dart';
import 'tables/bank_table.dart';
import 'tables/ingest_watermark_table.dart';
import 'tables/instrument_table.dart';
import 'tables/raw_message_table.dart';
import 'tables/transaction_table.dart';

part 'app_database.g.dart';

/// Massrofy's single, whole-database-encrypted (ADR-003) local datastore.
///
/// For readers new to Drift: this class is mostly generated. The
/// `@DriftDatabase` annotation below, plus `part 'app_database.g.dart';`,
/// tells `build_runner` (via `drift_dev`) to generate a base class
/// `_$AppDatabase` containing typed table accessors (`auditEntries`,
/// `rawMessages`, ...), `Companion` classes for inserts/updates, and query
/// building helpers. You never edit the generated file by hand — run
/// `dart run build_runner build` after changing a table or this class.
///
/// **Note on DAOs (`lib/data/dao/`):** they are deliberately **not** listed
/// in a `daos: [...]` parameter here. Drift's `daos:` codegen assumes every
/// DAO's constructor takes only the database instance — but
/// `AuditLogDao` needs an `auditChainKey` and `TransactionDao` needs an
/// `AuditLogDao` collaborator (see those files), so this app constructs
/// its DAOs explicitly wherever they're needed (`app_providers.dart` in
/// production, directly in tests) instead of relying on a generated
/// getter that couldn't supply those extra arguments anyway.
@DriftDatabase(
  tables: [
    AuditEntries,
    RawMessages,
    Banks,
    Instruments,
    Transactions,
    AppSettingsTable,
    IngestWatermarks,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] is opened by `lib/data/db/db_connection.dart` in production
  /// (SQLCipher-keyed, pointing at the app's private storage) or directly
  /// by tests (an in-memory or temp-file SQLCipher-keyed connection) — this
  /// class itself has no opinion about *where* its bytes live, only about
  /// the schema and migrations within them.
  AppDatabase(super.executor);

  /// Bump this and add a branch in [migration] whenever a table changes.
  /// ADR-003 requires a forward-migration test from an empty install for
  /// every version — see `test/data/db/app_database_encryption_test.dart`.
  ///
  /// | Version | Phase | Change |
  /// |---|---|---|
  /// | 1 | P1 | audit, raw_message, minimal transactions, settings |
  /// | 2 | P2 | ingest watermark; SMS provenance, FX and dedup columns on transactions; unparsed diagnostics on raw_message |
  /// | 3 | P3a | `bank` + `instrument` tables (KHA-23); instrument FK, counterparty, remaining balance, provenance detail and `deleted_at` on transactions (KHA-25) |
  /// | 4 | P3b-1 | FX rate date/source/pending (KHA-27, KHA-70) and internal-transfer link + state (KHA-29) on transactions |
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _installAuditTriggers();
      await _seedIngestWatermark();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Stepwise, never a single "if from < to" catch-all. A user who skips
      // several app versions (entirely normal on a side-loaded build with no
      // update channel — risk R-11) must walk every step in order.
      if (from < 2) {
        await m.createTable(ingestWatermarks);
        await _seedIngestWatermark();

        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.convertedAmountAmount,
          transactions.convertedAmountCurrency,
          transactions.convertedAmountMinor,
          transactions.feeAmountAmount,
          transactions.feeAmountCurrency,
          transactions.feeAmountMinor,
          transactions.fxRate,
          transactions.occurredAt,
          transactions.timeSource,
          transactions.direction,
          transactions.transactionType,
          transactions.affectsSpend,
          transactions.referenceNumber,
          transactions.instrumentKind,
          transactions.instrumentMaskedRef,
          transactions.provenance,
          transactions.sourceMessageId,
          transactions.rulePackId,
          transactions.rulePackVersion,
          transactions.ruleId,
          transactions.needsReview,
          transactions.reviewReason,
          transactions.possibleDuplicateOfId,
        ]) {
          await m.addColumn(transactions, column);
        }

        await m.addColumn(rawMessages, rawMessages.unparsedReason);
        await m.addColumn(rawMessages, rawMessages.unparsedRuleId);
      }

      if (from < 3) {
        // P3a — the domain spine (KHA-23, KHA-25).
        //
        // Order matters and SQLite is unforgiving about it: `instrument`
        // references `bank`, and `transactions.instrument_id` references
        // `instrument`, so the parents must exist before the child that
        // points at them.
        await m.createTable(banks);
        await m.createTable(instruments);

        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.instrumentId,
          transactions.counterpartyName,
          transactions.counterpartyBankName,
          transactions.remainingBalanceAmount,
          transactions.remainingBalanceCurrency,
          transactions.remainingBalanceMinor,
          transactions.provenanceDetail,
          transactions.deletedAt,
        ]) {
          await m.addColumn(transactions, column);
        }
      }

      if (from < 4) {
        // P3b-1 — what a period total *means* (KHA-27, KHA-28, KHA-29,
        // KHA-70).
        //
        // Five columns, no data backfill, and the absence of a backfill is
        // the interesting part:
        //
        //  - `fx_rate_date` / `fx_rate_source` stay NULL on every existing
        //    row. That is the honest value: those rows were written by a
        //    build that never recorded a rate date, so we do not know one.
        //    Deriving `occurredAt` into them retroactively would invent
        //    provenance for figures nobody recorded provenance for — the
        //    opposite of what KHA-70 asked for.
        //  - `conversion_pending` defaults to false, which is right for every
        //    existing row: schema v3's only foreign-currency path came from
        //    the two online-purchase rules, both of which capture the bank's
        //    inline converted amount, so nothing already stored is pending.
        //    A v3 row that somehow lacked both is still handled correctly at
        //    read time, because `BaseCurrencyConverter` decides from the data
        //    it finds rather than from this flag.
        //  - `internal_transfer_*` stay NULL, meaning "nobody has ruled on
        //    this", which lets the read-time detector classify historic
        //    transfers on the same evidence as new ones. Backfilling a state
        //    here would freeze today's detector output into the database and
        //    make a later improvement unable to correct it.
        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.fxRateDate,
          transactions.fxRateSource,
          transactions.conversionPending,
          transactions.internalTransferGroupId,
          transactions.internalTransferState,
        ]) {
          await m.addColumn(transactions, column);
        }
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // ADR-003: enforce referential integrity on every connection, not
      // just at creation time (SQLite defaults foreign_keys OFF per
      // connection unless told otherwise).
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  /// Guarantees the singleton watermark row exists.
  ///
  /// Written as an INSERT OR IGNORE rather than a read-then-write so it is
  /// safe to call from both `onCreate` and `onUpgrade`, and so two concurrent
  /// openings (the UI isolate and the background ingestion isolate can both
  /// open the database — ADR-006) cannot race into two rows. The table's own
  /// CHECK constraint is the second line of defence.
  Future<void> _seedIngestWatermark() async {
    await customStatement(
      'INSERT OR IGNORE INTO ingest_watermark (id) VALUES '
      '($ingestWatermarkSingletonId);',
    );
  }

  /// ADR-010 layer 2: SQL triggers that make `audit_entry` append-only
  /// against *any* code path — present or future, including a bug in
  /// `AuditLogDao` itself — not just against the DAO's public API shape.
  Future<void> _installAuditTriggers() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS audit_no_update BEFORE UPDATE ON audit_entry
        BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS audit_no_delete BEFORE DELETE ON audit_entry
        BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
    ''');
  }
}
