import 'package:drift/drift.dart';

/// **`Instrument`** — `docs/architecture.md` §4.2; US-B2/B3/B13/B14/B15.
///
/// One row per account or card the app has ever seen mentioned, under the bank
/// that issued it. Three properties of this table carry acceptance criteria:
///
/// 1. **[kind] comes from the matched rule, never from a guess** (AC-B13.1/2).
///    PRD §3.4 observed the *same bank* printing a bare account number for a
///    transfer and a masked card number plus a network for a purchase. Digit
///    length does not distinguish them; the rule's declared `kind` does.
///    Conflating the two would merge "money sitting in my account" with
///    "credit card spend", which is exactly what US-B13 exists to prevent.
///
/// 2. **[refKey] — not [friendlyName] and not [maskedIdentifier] — is the
///    match key** (AC-B3.2). Renaming a card to "Blue Visa" must not cause the
///    next SMS carrying `****4821` to create a second instrument. Since the
///    rename touches only [friendlyName], and matching is on [refKey], that
///    failure is not merely avoided — it is unrepresentable.
///
/// 3. **[maskedIdentifier] is masked at the source** (NFR-S2). There is no
///    column here able to hold a full PAN, and `InstrumentMask.maskLast4` in
///    `lib/features/parsing/field_transforms.dart` is the only producer of the
///    value that lands in it.
@DataClassName('InstrumentRow')
class Instruments extends Table {
  @override
  String get tableName => 'instrument';

  IntColumn get id => integer().autoIncrement()();

  /// The owning bank. A real foreign key, and `PRAGMA foreign_keys = ON` is
  /// set on every connection (see `AppDatabase.migration.beforeOpen`), so an
  /// instrument can never be orphaned from its bank — which is what makes
  /// "drilling into a bank shows only its own instruments" (AC-B2.1) a
  /// structural fact rather than a query convention.
  ///
  /// **Why `customConstraint` and not `.references(Banks, #id)`:** drift
  /// 2.31's Dart-side reference resolver does not recognise the class
  /// argument under this project's pinned analyzer (it reports *"This
  /// parameter should be a simple class name"* and then emits **no** foreign
  /// key at all — a constraint you believe you have and do not). Writing the
  /// SQL constraint explicitly produces the real `REFERENCES` clause in the
  /// generated `CREATE TABLE`, which is verified by a migration test. Note
  /// that a column-level custom constraint replaces the generated one, so
  /// `NOT NULL` has to be stated here too.
  IntColumn get bankId =>
      integer().customConstraint('NOT NULL REFERENCES bank(id)')();

  /// `account` | `card`. See point 1 in the class doc comment.
  TextColumn get kind => text()();

  /// The storable, already-masked identifier, e.g. `****4821`. Before the user
  /// renames an instrument this is also its *label* (AC-B15.2), which is why
  /// it is required rather than nullable: an auto-created instrument with no
  /// identifier would be unidentifiable in the UI.
  TextColumn get maskedIdentifier => text()();

  /// The normalised match key — `<bank>:<kind>:<digits>`. `UNIQUE`, so a
  /// duplicate instrument cannot exist even if two ingestion paths raced.
  TextColumn get refKey => text().unique()();

  /// `visa` | `mada` | `mastercard`, or null when the message did not say.
  /// Null means **unknown**, never "no network" (AC-B1.3's rule applied to
  /// instruments).
  TextColumn get network => text().nullable()();

  /// `credit` | `debit` | `prepaid`, or null when unstated.
  TextColumn get cardType => text().nullable()();

  /// The user's own name for this instrument (US-B3). Null until they rename
  /// it, at which point [maskedIdentifier] steps down from label to detail.
  TextColumn get friendlyName => text().nullable()();

  /// The currency this instrument transacts in, when observed. Informational;
  /// no total is ever computed from it (totals are computed from the
  /// transactions' own currencies — ADR-009 forbids assuming).
  TextColumn get currencyCode => text().nullable()();

  /// **US-B14 — the card → settlement account link.**
  ///
  /// A self-reference: a card points at the account that settles it. Null
  /// means **"not linked"**, and AC-B14.3 is explicit that null is displayed
  /// as unlinked and never inferred — a guess here would tell the user their
  /// money flows somewhere it does not.
  IntColumn get settlementAccountId =>
      integer().nullable().customConstraint('REFERENCES instrument(id)')();

  /// `sms_repayment` | `user`, or null when unlinked. AC-B14.1 makes a card
  /// repayment message — which names both the card and the debiting account —
  /// the only *automatic* source of this link.
  TextColumn get linkSource => text().nullable()();

  /// When the link was observed, so a later contradicting message can be
  /// judged newer or older rather than simply overwriting.
  DateTimeColumn get linkObservedAt => dateTime().nullable()();

  /// Hidden from pickers and lists but retained, so its historic transactions
  /// keep their instrument context (there is no hard delete outside
  /// erase-all — ADR-011).
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// `raw_message.id` of the message that first mentioned this instrument
  /// (US-B15, NFR-A1). Null for a user-created instrument.
  IntColumn get firstSeenMessageId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
