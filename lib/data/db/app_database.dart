import 'package:drift/drift.dart';

import 'tables/app_settings_table.dart';
import 'tables/audit_entry_table.dart';
import 'tables/ingest_watermark_table.dart';
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
  @override
  int get schemaVersion => 2;

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
