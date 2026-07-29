/// Read/write access to the single-row `app_settings` table.
///
/// ## Why P5a needs this at all (KHA-113)
///
/// The onboarding gate has to tell three states apart, and they demand three
/// different screens:
///
/// | State | What the user sees |
/// |---|---|
/// | never asked for SMS access | **S-02** rationale, then the OS dialog (AC-A1.2) |
/// | asked, declined | **S-04** limited mode, manual entry offered |
/// | granted once, since revoked | the app, plus AC-A1.3's *"your data is intact"* banner |
///
/// The live permission status alone cannot distinguish the first from the
/// third — both read `denied` — and getting it wrong means re-running
/// onboarding at a user whose history is sitting right there. So the fact that
/// the question has been *asked* is persisted, in the `onboarding_complete`
/// column architecture §4.2 has carried since P1 with nothing writing to it.
///
/// ## Why this DAO is hand-written rather than generated
///
/// Every other DAO in this app is a Drift `@DriftAccessor` with a `.g.dart`
/// twin. This one is four statements over one row and needs no custom queries,
/// so it is written directly against the generated table accessor
/// (`database.appSettingsTable`) instead — which keeps the change to a single
/// new file and avoids re-running code generation over a 14,000-line
/// `app_database.g.dart` for a boolean.
///
/// ## Nothing here is audited, deliberately
///
/// NFR-A2 requires an audit entry for every mutation of *financial* data.
/// "The user has seen the permission rationale" is a UI preference, not a
/// ledger fact; recording it in the change history the user reads (US-F5)
/// would be noise in the one place that must stay readable.
library;

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The conventional primary key of the single settings row (the same
/// "always row 0" convention `IngestWatermark` uses).
const int appSettingsRowId = 0;

class AppSettingsDao {
  final AppDatabase database;

  const AppSettingsDao(this.database);

  /// The settings row, creating it with its column defaults on first read.
  ///
  /// `InsertMode.insertOrIgnore` rather than a read-then-write: two callers
  /// racing on first launch (the gate and a background sweep, say) would
  /// otherwise both see "absent" and the second insert would fail on the
  /// primary key.
  Future<AppSettingsRow> current() async {
    final AppSettingsRow? existing = await _selectRow().getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    await database
        .into(database.appSettingsTable)
        .insert(
          AppSettingsTableCompanion.insert(id: const Value(appSettingsRowId)),
          mode: InsertMode.insertOrIgnore,
        );
    return _selectRow().getSingle();
  }

  /// A live view of the row, so a screen re-renders when onboarding completes
  /// without anything having to invalidate a provider by hand.
  ///
  /// Yields `null` until the row exists. Callers treat that as "defaults",
  /// which is the truthful reading: an absent row means nothing has been
  /// configured yet.
  Stream<AppSettingsRow?> watch() => _selectRow().watchSingleOrNull();

  /// Records that the user has been through the SMS-permission decision,
  /// whichever way they answered.
  ///
  /// Set on **grant and on decline alike**. The flag means "we have asked",
  /// not "we succeeded" — a user who declined must land in S-04 limited mode
  /// on the next launch, not back at the rationale screen they already read.
  Future<void> markOnboardingComplete() async {
    // Guarantees the row exists before the update, since `update` over a
    // missing row writes nothing and reports success.
    await current();
    await (database.update(database.appSettingsTable)
          ..where(($AppSettingsTableTable t) => t.id.equals(appSettingsRowId)))
        .write(
          const AppSettingsTableCompanion(onboardingComplete: Value(true)),
        );
  }

  SimpleSelectStatement<$AppSettingsTableTable, AppSettingsRow> _selectRow() =>
      database.select(database.appSettingsTable)
        ..where(($AppSettingsTableTable t) => t.id.equals(appSettingsRowId));
}
