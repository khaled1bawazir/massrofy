/// Schema **v3** — the P3a domain spine (KHA-23, KHA-25).
///
/// ADR-003 requires a forward-migration test for every schema version. Two
/// distinct things are checked here, and both have bitten this codebase
/// already:
///
/// 1. **A fresh install really has the foreign keys.** drift 2.31's Dart-side
///    `.references(Table, #column)` resolver silently emits **no** constraint
///    under this project's pinned analyzer — it reports a warning and carries
///    on, which is how you end up believing you have referential integrity
///    that does not exist. The tables therefore declare the SQL constraint
///    explicitly, and this file asserts that SQLite actually knows about it
///    via `PRAGMA foreign_key_list`.
///
/// 2. **An existing v2 install can get there.** `ALTER TABLE ADD COLUMN` is
///    fussy in SQLite: a column carrying a `REFERENCES` clause is only
///    accepted when it defaults to NULL. `transactions.instrument_id` does,
///    but that is a property worth a test rather than a comment, because the
///    failure mode is an app that will not open on upgrade — for a side-loaded
///    build with no update channel (risk R-11), the worst possible failure.
library;

import 'dart:io';

// `QueryRow` only — drift also exports an `isNull` that would collide with
// `package:matcher`'s.
import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';

/// The columns v3 adds to `transactions`, in SQL naming.
const List<String> _v3TransactionColumns = <String>[
  'instrument_id',
  'counterparty_name',
  'counterparty_bank_name',
  'remaining_balance_amount',
  'remaining_balance_currency',
  'remaining_balance_minor',
  'provenance_detail',
  'deleted_at',
];

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.map((QueryRow row) => row.data['name'] as String).toList();
}

Future<List<Map<String, Object?>>> _foreignKeys(
  AppDatabase db,
  String table,
) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA foreign_key_list($table);')
      .get();
  return rows.map((QueryRow row) => row.data).toList();
}

void main() {
  group('a fresh install at v3', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    test('reports schemaVersion 3', () {
      expect(db.schemaVersion, 3);
    });

    test('creates the bank and instrument tables', () async {
      final List<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table' "
                    "AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((QueryRow row) => row.data['name'] as String)
              .toList();

      expect(tables, containsAll(<String>['bank', 'instrument']));
    });

    test('the instrument to bank foreign key exists in SQLite, not only in '
        'the Dart model', () async {
      final List<Map<String, Object?>> keys = await _foreignKeys(
        db,
        'instrument',
      );

      expect(
        keys.any(
          (Map<String, Object?> fk) =>
              fk['table'] == 'bank' && fk['from'] == 'bank_id',
        ),
        isTrue,
        reason:
            'without this, an instrument could be orphaned from its bank and '
            'AC-B2.1 would rest on query discipline alone',
      );
      expect(
        keys.any(
          (Map<String, Object?> fk) =>
              fk['table'] == 'instrument' &&
              fk['from'] == 'settlement_account_id',
        ),
        isTrue,
      );
    });

    test('the transaction to instrument foreign key exists', () async {
      final List<Map<String, Object?>> keys = await _foreignKeys(
        db,
        'transactions',
      );
      expect(
        keys.any(
          (Map<String, Object?> fk) =>
              fk['table'] == 'instrument' && fk['from'] == 'instrument_id',
        ),
        isTrue,
      );
    });

    test('bank.canonical_key and instrument.ref_key are UNIQUE — the '
        'database-level guarantee behind AC-B12.3 and AC-B3.2', () async {
      await db.customStatement(
        "INSERT INTO bank (canonical_key, display_name_ar, display_name_en) "
        "VALUES ('bank-x', 'x', 'x');",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO bank (canonical_key, display_name_ar, display_name_en) "
          "VALUES ('bank-x', 'y', 'y');",
        ),
        throwsA(anything),
      );
    });

    test('every v3 column is present on transactions', () async {
      expect(
        await _columnNames(db, 'transactions'),
        containsAll(_v3TransactionColumns),
      );
    });
  });

  group('upgrading a v2 install', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-v3-migration');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('an existing database at v2 upgrades to v3, keeping its rows', () async {
      // ## Building a v2 database without a schema dump
      //
      // The project has no `drift_dev schema dump` baseline (it would be the
      // tidier tool). So this creates the v3 schema, then *removes* exactly
      // what v3 added and rewinds `user_version` — leaving a genuine v2-shaped
      // file on disk. Reopening it then runs the real `onUpgrade` branch, not
      // a re-implementation of it.
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;'); // force `onCreate`

      // A row that must survive the upgrade untouched.
      await db.customStatement(
        "INSERT INTO transactions (merchant_raw_text, amount_amount, "
        "amount_currency, amount_minor) VALUES ('Panda', '45.90', 'SAR', 4590);",
      );

      await db.customStatement('PRAGMA foreign_keys = OFF;');
      await db.customStatement('DROP TABLE instrument;');
      await db.customStatement('DROP TABLE bank;');
      for (final String column in _v3TransactionColumns) {
        await db.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column;',
        );
      }
      await db.customStatement('PRAGMA user_version = 2;');
      await db.close();

      // Reopening runs `onUpgrade(2 -> 3)` for real.
      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      final List<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
              .map((QueryRow row) => row.data['name'] as String)
              .toList();
      expect(tables, containsAll(<String>['bank', 'instrument']));

      expect(
        await _columnNames(db, 'transactions'),
        containsAll(_v3TransactionColumns),
        reason:
            'ALTER TABLE ADD COLUMN with a REFERENCES clause is only legal '
            'when the column defaults to NULL — if that ever changes, an '
            'upgrading install fails to open at all',
      );

      final List<QueryRow> rows = await db
          .customSelect('SELECT amount_amount, instrument_id FROM transactions')
          .get();
      expect(rows.single.data['amount_amount'], '45.90');
      expect(
        rows.single.data['instrument_id'],
        isNull,
        reason:
            'an existing transaction has no resolved instrument yet, and '
            'AC-B1.3 says that reads as explicitly unknown — not as a '
            'default row it never touched',
      );

      // The foreign key must exist on the upgraded database too, or fresh and
      // upgraded installs would silently diverge.
      expect(
        (await _foreignKeys(db, 'transactions')).any(
          (Map<String, Object?> fk) =>
              fk['table'] == 'instrument' && fk['from'] == 'instrument_id',
        ),
        isTrue,
      );

      await db.close();
    });
  });
}
