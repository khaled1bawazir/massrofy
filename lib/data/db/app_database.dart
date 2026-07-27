import 'package:drift/drift.dart';

import 'tables/app_settings_table.dart';
import 'tables/audit_entry_table.dart';
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
  tables: [AuditEntries, RawMessages, Transactions, AppSettingsTable],
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
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _installAuditTriggers();
    },
    beforeOpen: (OpeningDetails details) async {
      // ADR-003: enforce referential integrity on every connection, not
      // just at creation time (SQLite defaults foreign_keys OFF per
      // connection unless told otherwise).
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

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
