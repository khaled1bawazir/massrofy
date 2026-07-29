/// Schema **v4** — what a period total needs in order to mean something
/// (KHA-27, KHA-28, KHA-29, KHA-70).
///
/// ADR-003 requires a forward-migration test for every schema version. v4 adds
/// no tables and no foreign keys, so this file is shorter than its v3
/// counterpart — but it asserts one thing that file could not:
///
/// > **the migration adds no data.**
///
/// Every v4 column is left NULL (or, for `conversion_pending`, false) on rows
/// that already exist. That is not laziness: a backfilled `fx_rate_date` would
/// be provenance invented for a figure nobody recorded provenance for, which
/// is the exact defect KHA-70 was raised about, one level deeper. The test
/// below writes a v3-shaped row, upgrades, and insists it comes back
/// **unknown** rather than plausible.
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';
import 'schema_v5_migration_test.dart' show v5TransactionColumns;
import 'schema_v7_migration_test.dart' show rewindPastV7;

/// The columns v4 adds to `transactions`, in SQL naming.
///
/// Exported (rather than private) because `schema_v3_migration_test.dart`
/// needs to strip them when it rewinds a database to v2 — one list, so the
/// two files cannot disagree about what v4 is.
const List<String> v4TransactionColumns = <String>[
  'fx_rate_date',
  'fx_rate_source',
  'conversion_pending',
  'internal_transfer_group_id',
  'internal_transfer_state',
];

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.map((QueryRow row) => row.data['name'] as String).toList();
}

void main() {
  group('a fresh install at v4', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    test('reports a schema version of at least 4', () {
      // No longer an exact number. `schema_v5_migration_test.dart` is now the
      // one place the *current* version is pinned; this file's job is to
      // assert that v4's own additions survive, which stays true at every
      // later version. Pinning an exact number in every migration file means
      // each new schema version breaks every older test for no reason.
      expect(db.schemaVersion, greaterThanOrEqualTo(4));
    });

    test('every v4 column is present on transactions', () async {
      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v4TransactionColumns),
      );
    });
  });

  group('upgrading a v3 install', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-v4-migration');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('an existing database at v3 upgrades to v4, keeping its rows and '
        'adding no invented FX provenance', () async {
      // Same technique as the v3 test: build the current schema, remove
      // exactly what v4 added, rewind `user_version`, and reopen so the real
      // `onUpgrade(3 -> 4)` branch runs rather than a re-implementation of it.
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      // A foreign-currency transaction written by a v3 build: it has an
      // `fx_rate` and no way to say when that rate applied. This row is the
      // whole reason KHA-70 exists.
      await db.customStatement(
        "INSERT INTO transactions (merchant_raw_text, amount_amount, "
        "amount_currency, amount_minor, fx_rate) "
        "VALUES ('NORTHWIND SOFTWARE', '120', 'USD', 12000, '3.7510');",
      );

      // Everything v4 *and later* added has to come off. Leaving v5's columns
      // in place while claiming `user_version = 3` would make the v4→v5
      // branch fail on "duplicate column name" — the migration would be
      // re-adding a column the rewind did not remove. Same reasoning as
      // `schema_v3_migration_test.dart`'s own rewind list.
      //
      // v7's tables and columns come off through `rewindPastV7`, which also
      // sets `user_version`, so this file never needs to know what v7 added.
      for (final String column in <String>[
        ...v4TransactionColumns,
        ...v5TransactionColumns,
      ]) {
        await db.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column;',
        );
      }
      await rewindPastV7(db, toVersion: 3);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v4TransactionColumns),
      );

      final Map<String, Object?> row =
          (await db
                  .customSelect(
                    'SELECT amount_amount, amount_currency, fx_rate, fx_rate_date, '
                    'fx_rate_source, conversion_pending, internal_transfer_state '
                    'FROM transactions',
                  )
                  .get())
              .single
              .data;

      // The pre-existing values survive untouched.
      expect(row['amount_amount'], '120');
      expect(row['amount_currency'], 'USD');
      expect(row['fx_rate'], '3.7510');

      // …and the new ones are explicitly unknown, not plausibly filled in.
      expect(
        row['fx_rate_date'],
        isNull,
        reason:
            'a backfilled rate date would be a fabricated fact — the v3 build '
            'that wrote this row never knew one (KHA-70)',
      );
      expect(row['fx_rate_source'], isNull);
      expect(
        row['internal_transfer_state'],
        isNull,
        reason:
            'NULL means "nobody has ruled on this", which lets the read-time '
            'detector classify historic transfers on the same evidence as new '
            'ones. A backfilled state would freeze today\'s detector output '
            'into the database where a later improvement could not correct it',
      );

      // `conversion_pending` defaults to false. SQLite has no boolean type;
      // drift stores it as 0/1, and the assertion is written against the
      // storage form on purpose — a `false` that arrived as NULL would read
      // the same through the Dart mapper and hide the difference.
      expect(row['conversion_pending'], 0);

      await db.close();
    });
  });
}
