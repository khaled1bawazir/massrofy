/// Schema **v5** — the mutation surface (KHA-26, KHA-64) — and the recorded
/// consequence of **KHA-69's decision**.
///
/// ADR-003 requires a forward-migration test for every schema version. v5 adds
/// three nullable columns and no tables, so the migration half of this file is
/// short. The second group is the interesting one.
///
/// ## The KHA-69 half
///
/// KHA-69 asked what to do about audit rows written *before* P3a's timestamp
/// fix: they hash over an untruncated timestamp that storage cannot keep, so
/// `verifyChainIntegrity()` reports tampering on intact history, permanently,
/// and — because the chain is sequential — the first bad entry poisons every
/// entry after it.
///
/// **The decision is option (a): no such rows exist anywhere, so there is
/// nothing to re-chain.** Recorded and dated in `docs/architecture.md` next to
/// ADR-010 and in the v5 migration branch in `app_database.dart`. The evidence
/// is that the database key is provisioned *behind* the app-lock gate
/// (ADR-005), KHA-75 established the lock had never once succeeded on real
/// hardware, and the first successful real-device unlock in this app's history
/// was on build `56e9cbaa` — which already contains the P3a fix.
///
/// A test cannot prove "no device holds such a row". What it *can* pin is the
/// consequence the decision commits us to, which is what the second group
/// does: **an ordinary upgrade must leave the chain verifiable.** If that ever
/// fails, the assumption behind option (a) has been broken somewhere and the
/// decision needs revisiting — which is the alarm this file exists to be.
library;

import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';
import 'schema_v7_migration_test.dart' show rewindPastV7;

/// The columns v5 adds to `transactions`, in SQL naming.
const List<String> v5TransactionColumns = <String>[
  'user_edited_fields',
  'merged_into_id',
  'merged_from_transaction_id',
];

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 81);

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final List<QueryRow> rows = await db
      .customSelect('PRAGMA table_info($table);')
      .get();
  return rows.map((QueryRow row) => row.data['name'] as String).toList();
}

void main() {
  group('a fresh install at v5', () {
    late AppDatabase db;

    setUp(() => db = openPlainTestDatabase());
    tearDown(() async => db.close());

    test('reports a schema version of at least 5', () {
      // No longer an exact number — `schema_v7_migration_test.dart` is now the
      // one place the *current* version is pinned. This file's job is to
      // assert that v5's own additions survive, which stays true at every
      // later version.
      expect(db.schemaVersion, greaterThanOrEqualTo(5));
    });

    test('every v5 column is present on transactions', () async {
      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v5TransactionColumns),
      );
    });
  });

  group('upgrading a v4 install', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-v5-migration');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('an existing database at v4 upgrades to v5, keeping its rows and '
        'inventing no edit or merge history', () async {
      // The same technique the v3 and v4 tests use: build the current schema,
      // drop exactly what v5 added, rewind `user_version`, and reopen so the
      // real `onUpgrade(4 -> 5)` branch runs rather than a re-implementation
      // of it.
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      await db.customStatement(
        "INSERT INTO transactions (merchant_raw_text, amount_amount, "
        "amount_currency, amount_minor) "
        "VALUES ('EXTRA MART 0042', '152.75', 'SAR', 15275);",
      );

      for (final String column in v5TransactionColumns) {
        await db.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column;',
        );
      }
      // v7's tables and columns come off through `rewindPastV7`, which also
      // sets `user_version` — see `schema_v7_migration_test.dart`. Keeping that
      // knowledge in one file means this test never needs updating when a
      // later version adds a column.
      await rewindPastV7(db, toVersion: 4);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      expect(
        await _columnNames(db, 'transactions'),
        containsAll(v5TransactionColumns),
      );

      final Map<String, Object?> row =
          (await db
                  .customSelect(
                    'SELECT amount_amount, merchant_raw_text, '
                    'user_edited_fields, merged_into_id, '
                    'merged_from_transaction_id FROM transactions',
                  )
                  .get())
              .single
              .data;

      expect(row['amount_amount'], '152.75');
      expect(row['merchant_raw_text'], 'EXTRA MART 0042');

      expect(
        row['user_edited_fields'],
        isNull,
        reason:
            'NULL means "nobody has edited this row", which is the honest '
            'value for every pre-existing row. A backfilled protection list '
            'would freeze rows against enrichment nobody asked to freeze',
      );
      expect(row['merged_into_id'], isNull);
      expect(row['merged_from_transaction_id'], isNull);

      await db.close();
    });
  });

  group('KHA-69 — the audit chain across the upgrade (decision: option a)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('massrofy-kha69');
      dbFile = File('${tempDir.path}/app.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('audit rows written by a post-P3a build still verify after the v4 to '
        'v5 upgrade', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      AuditLogDao auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
      TransactionDao dao = TransactionDao(db, auditLogDao);

      // Written with a real sub-second timestamp — the exact shape that broke
      // before P3a, and the shape every entry the running app writes has.
      await dao.insertManual(
        amount: Money.parse('152.75', currency: 'SAR'),
        merchantRawText: 'EXTRA MART',
        occurredAt: DateTime.utc(2026, 7, 15, 10),
        direction: 'debit',
        transactionType: 'pos_purchase',
        affectsSpend: true,
        now: DateTime.utc(2026, 7, 15, 10, 0, 0, 456),
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);

      // Rewind to v4 and reopen, so the migration genuinely runs over a
      // database that already holds audit history.
      for (final String column in v5TransactionColumns) {
        await db.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column;',
        );
      }
      // v7's tables and columns come off through `rewindPastV7`, which also
      // sets `user_version` — see `schema_v7_migration_test.dart`. Keeping that
      // knowledge in one file means this test never needs updating when a
      // later version adds a column.
      await rewindPastV7(db, toVersion: 4);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
      dao = TransactionDao(db, auditLogDao);
      await db.customStatement('SELECT 1;');

      expect(
        await auditLogDao.verifyChainIntegrity(),
        isTrue,
        reason:
            'option (a) commits us to the migration touching no audit '
            'row. If this fails, something now rewrites history during an '
            'upgrade and the KHA-69 decision must be revisited.',
      );

      // And the chain continues cleanly across the version boundary: an entry
      // written after the upgrade chains onto one written before it.
      await dao.insertManual(
        amount: Money.parse('20.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 16, 10),
        direction: 'debit',
        transactionType: 'pos_purchase',
        affectsSpend: true,
        now: DateTime.utc(2026, 7, 16, 10, 0, 0, 789),
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);

      await db.close();
    });

    test('the v5 migration writes no audit_entry row of its own — option (b) '
        'was explicitly NOT taken', () async {
      AppDatabase db = AppDatabase(NativeDatabase(dbFile));
      final AuditLogDao auditLogDao = AuditLogDao(
        db,
        auditChainKey: _testChainKey,
      );
      final TransactionDao dao = TransactionDao(db, auditLogDao);
      await dao.insertManual(
        amount: Money.parse('10.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 15, 10),
        direction: 'debit',
        transactionType: 'pos_purchase',
        affectsSpend: true,
      );

      final int before =
          (await db.customSelect('SELECT COUNT(*) c FROM audit_entry;').get())
                  .single
                  .data['c']!
              as int;

      for (final String column in v5TransactionColumns) {
        await db.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column;',
        );
      }
      // v7's tables and columns come off through `rewindPastV7`, which also
      // sets `user_version` — see `schema_v7_migration_test.dart`. Keeping that
      // knowledge in one file means this test never needs updating when a
      // later version adds a column.
      await rewindPastV7(db, toVersion: 4);
      await db.close();

      db = AppDatabase(NativeDatabase(dbFile));
      await db.customStatement('SELECT 1;');

      final int after =
          (await db.customSelect('SELECT COUNT(*) c FROM audit_entry;').get())
                  .single
                  .data['c']!
              as int;

      expect(
        after,
        before,
        reason:
            'a re-chaining migration (option b) would have had to write '
            'to the trail, which is the operation an append-only trail exists '
            'to make impossible. Option (a) is what avoids needing to.',
      );

      await db.close();
    });
  });
}
