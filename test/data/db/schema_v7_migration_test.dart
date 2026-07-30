/// Schema **v7** — the categorization spine (KHA-30, KHA-31).
///
/// ADR-003 requires a forward-migration test from an empty install for every
/// schema version. v7 is the largest migration since v3: four new tables, four
/// new columns on `transactions`, and one new trigger.
///
/// Three things this file pins that the column list alone would not:
///
///  1. **The v6 gap is deliberate.** `docs/build-plan.md` reserved v6 for
///     P3b-3 in case its merge/undo fixes needed a schema change; they did
///     not. The migration branch is `from < 7`, so a v5 install upgrades
///     directly, and this file asserts that path works rather than leaving the
///     skipped number to look like an accident.
///  2. **The migration invents nothing.** No category is seeded here, no
///     merchant is derived from `merchant_raw_text`, and no historical row is
///     categorised. A migration that ran the matcher over a user's history
///     would be an unattended bulk categorization with no audit trail — the
///     exact operation AC-D4.4 says must be the user's explicit choice.
///  3. **The category-delete guard is real SQL, not a convention.** AC-C3.3
///     says *"no transaction may be left pointing at a category that no longer
///     exists"*, and the last group here proves the database refuses the
///     delete even when the statement comes from outside the DAO.
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';
import 'schema_v8_migration_test.dart' show rewindPastV8;

/// The columns v7 adds to `transactions`, in SQL naming.
///
/// Exported (rather than private) because the v3/v4/v5 migration tests need to
/// strip them when they rewind a database to an older `user_version` — one
/// list, so no two files can disagree about what v7 is.
const List<String> v7TransactionColumns = <String>[
  'category_source',
  'category_confidence',
  'category_rule_id',
  'merchant_id',
];

/// The tables v7 adds, in drop order (children before parents).
const List<String> v7Tables = <String>[
  'merchant_rule',
  'merchant_alias',
  'merchant',
  'category',
];

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.map((QueryRow row) => row.data['name'] as String).toList();
}

Future<bool> _tableExists(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';",
      )
      .get();
  return rows.isNotEmpty;
}

/// Rewinds a current-schema database to [toVersion] by removing everything v7
/// added. Mirrors the technique the older migration tests use: the real
/// `onUpgrade` branch then runs, rather than a re-implementation of it.
Future<void> rewindPastV7(AppDatabase db, {required int toVersion}) async {
  // Everything v8 added comes off first (KHA-146). A database rewound to v5
  // must not still carry a v8 column, or the real `onUpgrade` would try to ADD
  // one that already exists and the test would fail for a reason unrelated to
  // the migration under test. Chained this way rather than duplicated so there
  // stays exactly one statement of what each version added.
  await rewindPastV8(db, toVersion: toVersion);
  for (final String column in v7TransactionColumns) {
    await db.customStatement('ALTER TABLE transactions DROP COLUMN $column;');
  }
  for (final String table in v7Tables) {
    await db.customStatement('DROP TABLE IF EXISTS $table;');
  }
  await db.customStatement('PRAGMA user_version = $toVersion;');
}

void main() {
  group('a fresh install at v7', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    test('reports at least schemaVersion 7', () {
      // No longer an exact number — `schema_v8_migration_test.dart` is now the
      // one place the *current* version is pinned. Older migration files
      // deliberately assert `greaterThanOrEqualTo` so that adding a version
      // does not break every previous test for no reason.
      expect(db.schemaVersion, greaterThanOrEqualTo(7));
    });

    test('every v7 column is present on transactions', () async {
      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v7TransactionColumns),
      );
    });

    test('every v7 table is present', () async {
      for (final String table in v7Tables) {
        expect(await _tableExists(db, table), isTrue, reason: table);
      }
    });

    test('the schema seeds no categories — seeding is the service\'s job, in '
        'one place', () async {
      final int count =
          (await db.customSelect('SELECT COUNT(*) c FROM category;').get())
                  .single
                  .data['c']!
              as int;
      expect(
        count,
        0,
        reason:
            'design §4\'s list is written by CategorizationService.'
            'ensureDefaultsSeeded so fresh installs, upgrades and tests share '
            'one implementation. A migration that seeded separately would be a '
            'second copy of the design that could drift from the first',
      );
    });
  });

  group('upgrading a v5 install (the v6 gap is deliberate)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-v7-migration');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('an existing database at v5 upgrades straight to v7, keeping its rows '
        'and inventing no categorization', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      await db.customStatement(
        "INSERT INTO transactions (merchant_raw_text, amount_amount, "
        "amount_currency, amount_minor) "
        "VALUES ('PANDA STORE 1420', '152.75', 'SAR', 15275);",
      );

      await rewindPastV7(db, toVersion: 5);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v7TransactionColumns),
      );
      for (final String table in v7Tables) {
        expect(await _tableExists(db, table), isTrue, reason: table);
      }

      final Map<String, Object?> row =
          (await db
                  .customSelect(
                    'SELECT amount_amount, merchant_raw_text, category_id, '
                    'category_source, category_confidence, category_rule_id, '
                    'merchant_id FROM transactions',
                  )
                  .get())
              .single
              .data;

      expect(row['amount_amount'], '152.75');
      expect(row['merchant_raw_text'], 'PANDA STORE 1420');

      expect(
        row['category_source'],
        isNull,
        reason:
            'NULL means "no categorization decision has ever been recorded '
            'here". Writing \'none\' would claim the app looked at this row '
            'and declined, which it never did',
      );
      expect(row['category_confidence'], isNull);
      expect(row['category_rule_id'], isNull);
      expect(
        row['merchant_id'],
        isNull,
        reason:
            'deriving a merchant from merchant_raw_text during a migration '
            'would be an unattended bulk categorization with no audit trail — '
            'AC-D4.4 makes that the user\'s explicit choice, not a side effect '
            'of installing an update',
      );

      final int merchants =
          (await db.customSelect('SELECT COUNT(*) c FROM merchant;').get())
                  .single
                  .data['c']!
              as int;
      expect(merchants, 0);

      await db.close();
    });

    test('the v7 migration writes no audit_entry row of its own', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');
      await db.customStatement(
        "INSERT INTO transactions (amount_amount, amount_currency, "
        "amount_minor) VALUES ('10', 'SAR', 1000);",
      );

      await rewindPastV7(db, toVersion: 5);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      final int entries =
          (await db.customSelect('SELECT COUNT(*) c FROM audit_entry;').get())
                  .single
                  .data['c']!
              as int;
      expect(
        entries,
        0,
        reason:
            'a schema upgrade is not a change to the user\'s data and has no '
            'actor to attribute',
      );

      await db.close();
    });
  });

  group('AC-C3.3 — the category-delete guard is enforced by the database', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    Future<void> insertCategory(String id, {bool protected = false}) =>
        db.customStatement(
          "INSERT INTO category (id, key, name_ar, name_en, name_key_ar, "
          "name_key_en, icon_token, group_key, is_protected) VALUES "
          "('$id', '$id', '$id', '$id', '$id-ar', '$id-en', 'help_outline', "
          "'spending', ${protected ? 1 : 0});",
        );

    test('a category in use by a transaction cannot be deleted, even by raw '
        'SQL that never went near the DAO', () async {
      await insertCategory('groceries');
      await db.customStatement(
        "INSERT INTO transactions (amount_amount, amount_currency, "
        "amount_minor, category_id) VALUES ('10', 'SAR', 1000, 'groceries');",
      );

      await expectLater(
        db.customStatement("DELETE FROM category WHERE id = 'groceries';"),
        throwsA(anything),
      );

      final int remaining =
          (await db.customSelect('SELECT COUNT(*) c FROM category;').get())
                  .single
                  .data['c']!
              as int;
      expect(remaining, 1);
    });

    test(
      'a category in use by a merchant rule cannot be deleted either — a '
      'rule would re-create the dangling reference on the next message',
      () async {
        await insertCategory('dining');
        await db.customStatement(
          "INSERT INTO merchant (canonical_name, merchant_key) "
          "VALUES ('SYNTHETIC CAFE', 'SYNTHETIC CAFE');",
        );
        await db.customStatement(
          "INSERT INTO merchant_rule (merchant_id, category_id, source) "
          "VALUES (1, 'dining', 'user');",
        );

        await expectLater(
          db.customStatement("DELETE FROM category WHERE id = 'dining';"),
          throwsA(anything),
        );
      },
    );

    test('the protected category cannot be deleted even when nothing uses it '
        '(design §4: "always present")', () async {
      await insertCategory('uncategorized', protected: true);

      await expectLater(
        db.customStatement("DELETE FROM category WHERE id = 'uncategorized';"),
        throwsA(anything),
      );
    });

    test('an unused, unprotected category deletes normally — the guard blocks '
        'orphaning, not deleting', () async {
      await insertCategory('hobbies');

      await db.customStatement("DELETE FROM category WHERE id = 'hobbies';");

      final int remaining =
          (await db.customSelect('SELECT COUNT(*) c FROM category;').get())
                  .single
                  .data['c']!
              as int;
      expect(remaining, 0);
    });
  });
}
