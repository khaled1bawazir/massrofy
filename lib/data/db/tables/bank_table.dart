import 'package:drift/drift.dart';

/// **`Bank`** — `docs/architecture.md` §4.2, US-B12, AC-B12.1/AC-B12.3.
///
/// ## The one idea that makes AC-B12.3 work
///
/// AC-B12.3: *"two SMS reference the same bank using different naming (e.g.
/// Arabic name in one message, an abbreviation in another) … they resolve to
/// the same bank entity, not two."*
///
/// The way this is achieved is deliberately boring: **identity is
/// [canonicalKey], never a display string.** The rule pack (ADR-007) already
/// assigns every bank a stable `bankId` such as `bank-aljazira`, and every
/// sender pattern, alias and display name for that bank hangs off it. So
/// "بنك الجزيرة" and "BAJ" are not two names to be reconciled after the fact —
/// they are two *inputs* that both resolve to one key before anything is
/// written.
///
/// The alternative — matching on the display text and merging duplicates
/// later — is how a spending tracker ends up showing the same bank twice with
/// half the transactions under each, and no total that is right.
///
/// ## For readers new to Drift
///
/// A `Table` subclass describes columns; `build_runner` generates the row
/// class named by `@DataClassName` (`BankRow` here) plus a `BanksCompanion`
/// used for inserts and updates. Nothing in this file is executed at runtime —
/// it is a schema description read by the generator.
@DataClassName('BankRow')
class Banks extends Table {
  @override
  String get tableName => 'bank';

  IntColumn get id => integer().autoIncrement()();

  /// The stable identity — the rule pack's `bankId`. **`UNIQUE`, and that
  /// uniqueness is the database-level guarantee behind AC-B12.3**: even if
  /// two ingestion runs raced, SQLite would reject the second insert rather
  /// than let a duplicate bank exist.
  TextColumn get canonicalKey => text().unique()();

  /// Display names, both scripts, from the pack. Stored (rather than looked
  /// up from the pack at render time) so a bank stays labelled correctly even
  /// if a later pack drops it — a bank that disappears from the UI because its
  /// rules were retired would take its transactions' context with it.
  TextColumn get displayNameAr => text()();
  TextColumn get displayNameEn => text()();

  /// The alias set observed for this bank, as a JSON array of strings. Used
  /// for name-based resolution (a message that names its bank in text rather
  /// than only in the sender id) and for manual add later (S-48/S-49).
  ///
  /// JSON in a `TEXT` column rather than a child table: aliases are read as a
  /// whole set, never queried individually, and a child table would add a join
  /// to every bank read for no query we actually make.
  TextColumn get aliasesJson => text().withDefault(const Constant('[]'))();

  /// `rule_pack` | `user`. A bank the user typed in by hand is a different
  /// fact from one the pack recognised, and the parser-health panel should
  /// never blame a rule for a bank no rule created.
  TextColumn get source => text().withDefault(const Constant('rule_pack'))();

  /// The `raw_message.id` that first mentioned this bank (US-B15 / NFR-A1).
  /// Nullable because a user-created bank has no originating message.
  IntColumn get firstSeenMessageId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
