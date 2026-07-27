import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/data/db/db_connection.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../support/plain_test_database.dart';

const String _testKeyHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd';
const String _wrongKeyHex =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

/// Whether a genuine SQLCipher-capable `sqlite3` native library resolved
/// successfully in *this* test run. Populated once in `setUpAll`.
///
/// **Read this before assuming the cipher tests below are unconditionally
/// green.** `sqlcipher_flutter_libs` ships a precompiled binary for
/// Android (this app's only real target — no local build step needed) but
/// requires a local CMake+OpenSSL build tied to a desktop platform runner
/// project (`windows/`, `linux/`, `macos/`) for desktop dev machines / CI
/// runners, which this Android-only app does not have. Where that build
/// isn't available, the tests in the first group below are marked
/// **skipped**, with the reason printed, rather than silently reported as
/// passing or dishonestly forced green — see the PR description for the
/// full statement of what this means for local/CI coverage versus a real
/// Android device.
bool _cipherAvailable = false;
String? _cipherUnavailableReason;

void main() {
  setUpAll(() async {
    try {
      final Directory probeDir = await Directory.systemTemp.createTemp(
        'massrofy_cipher_probe_',
      );
      final File probeFile = File(p.join(probeDir.path, 'probe.sqlite'));
      final AppDatabase probe = AppDatabase(
        openEncryptedConnectionAtFile(file: probeFile, rawKeyHex: _testKeyHex),
      );
      await probe.customStatement('PRAGMA user_version;');
      await probe.close();
      probeDir.deleteSync(recursive: true);
      _cipherAvailable = true;
    } catch (e) {
      _cipherAvailable = false;
      _cipherUnavailableReason = e.toString();
    }
  });

  group('ADR-003 — the DB file on disk must not be readable/parseable without '
      'the key (P1 required test — see _cipherAvailable doc comment above if '
      'these show as skipped)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('massrofy_db_test_');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'a database created with a key cannot be opened with the wrong key',
      () async {
        if (!_cipherAvailable) {
          markTestSkipped(
            'No cipher-capable sqlite3 native library in this test '
            'environment: $_cipherUnavailableReason',
          );
          return;
        }

        final AppDatabase db = AppDatabase(
          openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
        );
        await db.customStatement('PRAGMA user_version;'); // forces the DB open
        await db.close();

        // Re-open the same file with a different key.
        final AppDatabase wrongKeyDb = AppDatabase(
          openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _wrongKeyHex),
        );
        // Reading the sqlite_master table forces SQLite to actually parse
        // the page headers — with the wrong key, this must fail because
        // the bytes genuinely do not decrypt into valid SQLite pages.
        await expectLater(
          wrongKeyDb.customSelect('SELECT * FROM sqlite_master').get(),
          throwsA(anything),
        );
        await wrongKeyDb.close();
      },
    );

    test('opening the raw file with a plain (unkeyed) sqlite3 connection '
        'cannot read it either', () async {
      if (!_cipherAvailable) {
        markTestSkipped(
          'No cipher-capable sqlite3 native library in this test '
          'environment: $_cipherUnavailableReason',
        );
        return;
      }

      final AppDatabase db = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
      );
      await db.customStatement('PRAGMA user_version;');
      await db.close();

      final sqlite3.Database raw = sqlite3.sqlite3.open(dbFile.path);
      addTearDown(raw.dispose);
      expect(
        () => raw.select('SELECT * FROM sqlite_master'),
        throwsA(anything),
      );
    });

    test('opening with the correct key can read the file back', () async {
      if (!_cipherAvailable) {
        markTestSkipped(
          'No cipher-capable sqlite3 native library in this test '
          'environment: $_cipherUnavailableReason',
        );
        return;
      }

      final AppDatabase db = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
      );
      await db.customStatement('PRAGMA user_version;');
      await db.close();

      final AppDatabase reopened = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
      );
      final List<Map<String, Object?>> rows = await reopened
          .customSelect('SELECT name FROM sqlite_master WHERE type = "table"')
          .map((row) => row.data)
          .get();
      expect(rows, isNotEmpty); // schema tables are readable with the right key
      await reopened.close();
    });
  });

  group('ADR-003 — forward migration from an empty install', () {
    // This group uses a PLAIN in-memory database deliberately — it is
    // testing schema creation and trigger installation (MigrationStrategy),
    // which is identical whether or not the underlying bytes are
    // encrypted, so it stays reliable in every environment regardless of
    // native cipher-library availability (see the file-level doc comment).
    test('schemaVersion 1 creates all tables and the audit triggers', () async {
      final AppDatabase db = openPlainTestDatabase();

      final List<String> tableNames =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((row) => row.data['name'] as String)
              .toList();

      expect(
        tableNames,
        containsAll(<String>[
          'audit_entry',
          'raw_message',
          'transactions',
          'app_settings',
        ]),
      );

      final List<String> triggerNames =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'trigger'",
                  )
                  .get())
              .map((row) => row.data['name'] as String)
              .toList();
      expect(
        triggerNames,
        containsAll(<String>['audit_no_update', 'audit_no_delete']),
      );

      await db.close();
    });
  });
}
