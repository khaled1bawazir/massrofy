import 'package:drift/drift.dart';

/// **P1 scope note — read this before extending this table.**
///
/// This is a deliberately minimal placeholder, not the final `Transaction`
/// entity. `docs/architecture.md` §4.2 defines the full schema (bank/
/// instrument linkage, provenance, categorisation confidence, FX, dedup
/// keys, soft-delete lifecycle, etc.) as **P3 — Domain model** work; P2
/// (SMS ingestion/parsing) hasn't landed yet either. This table exists in
/// P1 **only** to give the append-only audit-trail infrastructure
/// (ADR-010) a genuine mutation path to prove itself against, per the P1
/// build-plan done-check: *"any transaction mutation writes an immutable
/// history entry with actor, timestamp, before and after."* P3 will
/// **extend** this table (adding columns/tables), not discard it.
///
/// The SQL table is named `transactions` (plural) rather than the singular
/// domain word, specifically to avoid any ambiguity with SQLite's own
/// `TRANSACTION` keyword (used in `BEGIN TRANSACTION`) — a defensive choice,
/// not a hint that the underlying concept is anything other than "one
/// transaction record" (`docs/architecture.md`'s `Transaction` entity).
@DataClassName('TransactionRow')
class Transactions extends Table {
  @override
  String get tableName => 'transactions';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get merchantRawText => text().nullable()();

  // --- ADR-002 money triple: every stored amount is TEXT (authoritative,
  // exact decimal string) + TEXT (currency) + INTEGER (non-authoritative,
  // indexing-only minor units). No monetary total is ever produced by
  // summing `amountMinor` in SQL — see `.github/scripts/check_money_type_ban.sh`
  // and ADR-002's non-negotiable rule.
  TextColumn get amountAmount => text()();
  TextColumn get amountCurrency => text()();
  IntColumn get amountMinor => integer()();

  /// Nullable, no FK target yet (the `Category` table is P4 work) —
  /// intentionally loose in this P1-minimal table.
  TextColumn get categoryId => text().nullable()();

  /// Soft delete (US-B8) — hidden from normal lists/totals but retained and
  /// restorable. Only "erase everything" (ADR-011, P8) is a true hard
  /// delete.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
