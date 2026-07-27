import 'package:drift/drift.dart';

/// A single-row settings table (architecture.md §4.2's `AppSettings`),
/// pared to the fields P1 actually needs: locale/currency defaults and the
/// app-lock re-lock grace period (ADR-005).
///
/// For readers new to Drift/SQL: "single row" is enforced by convention
/// here (always writing/reading `id = 0`), which is the same pattern
/// `docs/architecture.md` describes for `IngestWatermark`. A stricter
/// enforcement (a `CHECK (id = 0)` constraint) is a straightforward future
/// addition and isn't required for P1's scope.
@DataClassName('AppSettingsRow')
class AppSettingsTable extends Table {
  @override
  String get tableName => 'app_settings';

  IntColumn get id => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  TextColumn get baseCurrency => text().withDefault(const Constant('SAR'))();
  TextColumn get locale => text().withDefault(const Constant('ar'))();

  /// Seconds of grace after backgrounding before the app re-locks
  /// (ADR-005's re-lock policy). Default `0` — lock immediately.
  IntColumn get lockGraceSeconds => integer().withDefault(const Constant(0))();

  BoolColumn get onboardingComplete =>
      boolean().withDefault(const Constant(false))();
}
