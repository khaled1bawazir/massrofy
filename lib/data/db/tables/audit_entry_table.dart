import 'package:drift/drift.dart';

/// ADR-010 — the append-only audit trail table.
///
/// Enforcement is three layers deep, and all three exist in this codebase:
///  1. **API shape** — `AuditLogDao` (see `lib/data/dao/audit_log_dao.dart`)
///     exposes only `append()` and `queryFor()`. There is no update/delete
///     method to call.
///  2. **SQL triggers** — `AppDatabase` installs `BEFORE UPDATE`/
///     `BEFORE DELETE` triggers on this table (see `app_database.dart`),
///     which `RAISE(ABORT, ...)` regardless of which code path attempted
///     the mutation — including a future bug in this very DAO.
///  3. **Tamper evidence** — `prevHash`/`entryHash` form an HMAC-SHA256
///     chain, so even a direct database edit (bypassing the app entirely)
///     is detectable via `AuditLogDao.verifyChainIntegrity()`.
///
/// **Honest enforcement boundary (ADR-010):** append-only is enforced
/// against the application and against any non-root actor on the device.
/// It is tamper-evident, not tamper-proof, against the device's own owner —
/// see the ADR for why a stronger claim would require a remote witness this
/// architecture deliberately does not have (ADR-001, CON-1).
@DataClassName('AuditEntryRow')
class AuditEntries extends Table {
  @override
  String get tableName => 'audit_entry';

  IntColumn get id => integer().autoIncrement()();

  /// Which kind of thing changed, e.g. `'transaction'`, `'instrument'`,
  /// `'bank'`. Kept as free text (not a foreign key) because the audit
  /// trail must be able to describe entities that no longer exist.
  TextColumn get entityType => text()();

  /// The id of the specific row that changed, stored as text so this table
  /// stays entity-agnostic regardless of each entity's own id type.
  TextColumn get entityId => text()();

  /// `'create' | 'update' | 'delete' | 'restore' | 'merge' | 'categorize' |
  /// 'rule_apply'` — validated by the DAO layer.
  TextColumn get action => text()();

  /// `'user' | 'system_rule' | 'parser' | 'importer'`.
  TextColumn get actor => text()();

  /// e.g. the `ruleId` that fired — satisfies "which rule applied"
  /// (AC-F5.2).
  TextColumn get actorDetail => text().nullable()();

  DateTimeColumn get changedAt => dateTime()();

  /// JSON-encoded `[{field, from, to}, ...]` — see `AuditFieldChange` in
  /// `lib/data/dao/audit_log_dao.dart` for the Dart-side shape.
  TextColumn get fieldChangesJson => text()();

  /// The previous entry's [entryHash], or the fixed genesis marker for the
  /// very first entry ever written.
  TextColumn get prevHash => text()();

  /// `HMAC-SHA256(auditChainKey, prevHash || canonicalJson(entry))`.
  TextColumn get entryHash => text()();
}
