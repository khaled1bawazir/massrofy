/// Schema **v8** — `raw_message.partial_extraction` (KHA-146).
///
/// ADR-003 requires a forward-migration test from an empty install for every
/// schema version. v8 is the smallest migration in the sequence — one nullable
/// column — but two of its properties are worth pinning rather than assuming:
///
///  1. **A v7 install upgrades in place and keeps its review queue.** The
///     column arrives; every existing row keeps its text, its classification
///     and its unparsed diagnostics, and gets `NULL` for the new column.
///  2. **NULL is not a gap to be filled later.** The migration deliberately
///     does not re-run the rule pack over stored bodies to backfill. Today's
///     pack re-reading messages ingested under an older one would let a row's
///     stored `unparsed_reason` and its derived partial extraction describe two
///     different readings of the same message. NULL means "this row predates
///     the feature", which is true, and the completion form falls back to the
///     blank behaviour those rows have today.
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';

/// The column v8 adds, in SQL naming.
const String v8RawMessageColumn = 'partial_extraction';

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.map((QueryRow row) => row.data['name'] as String).toList();
}

/// Rewinds a current-schema database to [toVersion] by removing what v8 added.
///
/// Exported because `schema_v7_migration_test.dart` calls it first inside its
/// own `rewindPastV7` — a database rewound to v5 must not still be carrying a
/// v8 column, or the real `onUpgrade` would try to `ADD COLUMN` one that is
/// already there and fail for a reason that has nothing to do with the
/// migration under test.
Future<void> rewindPastV8(AppDatabase db, {required int toVersion}) async {
  await db.customStatement(
    'ALTER TABLE raw_message DROP COLUMN $v8RawMessageColumn;',
  );
  await db.customStatement('PRAGMA user_version = $toVersion;');
}

void main() {
  group('a fresh install at v8', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    test('reports schemaVersion 8', () {
      expect(db.schemaVersion, 8);
    });

    test('raw_message carries the partial_extraction column', () async {
      expect(
        await _columnNames(db, 'raw_message'),
        contains(v8RawMessageColumn),
      );
    });

    test('a row inserted without it stores NULL — the column is genuinely '
        'optional, which is what every non-partial outcome needs', () async {
      await db.customStatement(
        "INSERT INTO raw_message (sender, received_at, content_hmac, "
        "classification) VALUES ('SYNTHBANK', 0, 'hmac-1', "
        "'financial_unparsed');",
      );

      final Map<String, Object?> row =
          (await db
                  .customSelect('SELECT $v8RawMessageColumn FROM raw_message;')
                  .get())
              .single
              .data;
      expect(row[v8RawMessageColumn], isNull);
    });
  });

  group('upgrading a v7 install', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-v8-migration');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('an existing v7 database gains the column, keeps its queued message, '
        'and backfills nothing', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      // A review-queue row shaped exactly like one the pre-KHA-146 build
      // wrote: sanitised text, a reason, a rule id, and no partial extraction
      // because the column did not exist. NFR-M3 — the body is fabricated.
      await db.customStatement(
        "INSERT INTO raw_message (sender, received_at, sanitized_body, "
        "content_hmac, bank_id, classification, unparsed_reason, "
        "unparsed_rule_id) VALUES ('SYNTHBANK', 1700000000000, "
        "'SYNTHBANK: purchase 152.75 SAR at SAMPLE MARKET 7.', 'hmac-legacy', "
        "'synthbank', 'financial_unparsed', 'required_field_missing', "
        "'synthbank.pos');",
      );

      await rewindPastV8(db, toVersion: 7);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      expect(
        await _columnNames(db, 'raw_message'),
        contains(v8RawMessageColumn),
      );

      final Map<String, Object?> row =
          (await db
                  .customSelect(
                    'SELECT sanitized_body, classification, unparsed_reason, '
                    'unparsed_rule_id, $v8RawMessageColumn FROM raw_message;',
                  )
                  .get())
              .single
              .data;

      expect(
        row['sanitized_body'],
        'SYNTHBANK: purchase 152.75 SAR at SAMPLE MARKET 7.',
        reason:
            'AC-A4.1 — the text a user completes the transaction from must '
            'survive the upgrade untouched',
      );
      expect(row['classification'], 'financial_unparsed');
      expect(row['unparsed_reason'], 'required_field_missing');
      expect(row['unparsed_rule_id'], 'synthbank.pos');
      expect(
        row[v8RawMessageColumn],
        isNull,
        reason:
            'NULL means "this row predates the feature". Re-running the '
            'current rule pack over a body ingested under an older one during '
            'a migration would let unparsed_reason and the derived extraction '
            'describe two different readings of the same message',
      );

      await db.close();
    });

    test('the v8 migration writes no audit_entry row of its own', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');
      await db.customStatement(
        "INSERT INTO raw_message (sender, received_at, content_hmac, "
        "classification) VALUES ('SYNTHBANK', 0, 'hmac-2', 'ignored_otp');",
      );

      await rewindPastV8(db, toVersion: 7);
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
}
