import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/data/db/db_connection.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../support/plain_test_database.dart';

// ADR-003 requires a raw **32-byte (256-bit)** key — i.e. exactly 64 hex
// characters. The two constants below were previously 62 hex characters
// (31 bytes) each — one byte short. SQLCipher does not reject a
// wrong-length `PRAGMA key = "x'...'"` value; it silently falls back to
// treating the hex string as a *passphrase* run through its own PBKDF2, not
// as the raw key ADR-003 specifies ("we supply a raw 32-byte key ...
// bypassing SQLCipher's own PBKDF2"). That fallback still "worked" (the
// database still opened and was still encrypted with *something*), which
// is exactly why this was easy to miss — the tests never actually asserted
// the key length, so a 31-byte value never failed anything. Fixed here to
// be genuinely 64 hex characters (verified by the `RegExp` assertion in
// `setUpAll` below, so a future accidental truncation fails loudly instead
// of silently degrading to passphrase mode again).
const String _testKeyHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _wrongKeyHex =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

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
/// passing or dishonestly forced green.
///
/// **This is not where the real, required, gating SQLCipher coverage
/// lives.** That is `integration_test/db_encryption_test.dart`, which runs
/// the same three assertions as an on-device Android integration test —
/// executed for real (never skipped) by the dedicated
/// `android-sqlcipher-integration-test` CI job
/// (`.github/workflows/ci.yml`), which boots a headless Android emulator
/// specifically so `sqlcipher_flutter_libs`' real, precompiled Android
/// binary is genuinely exercised on every PR. The tests in *this* file are
/// a best-effort desktop-side check, kept because they're cheap and catch
/// obvious regressions instantly wherever a desktop cipher build happens
/// to be available — they were never the load-bearing guarantee.
bool _cipherAvailable = false;
String? _cipherUnavailableReason;

void main() {
  // Guard the guard: assert both fixture keys are genuinely 64 hex
  // characters (32 bytes / 256 bits) *before* anything else in this file
  // runs, so a future accidental edit that shortens either constant fails
  // immediately and loudly (a `TestFailure` at the very top of the run)
  // instead of silently degrading SQLCipher into passphrase-KDF mode again
  // — precisely the bug this file previously shipped with undetected.
  final RegExp rawKeyPattern = RegExp(r'^[0-9a-f]{64}$');
  test('fixture keys are exactly 64 lowercase hex chars (ADR-003 sanity '
      'check on the test data itself)', () {
    expect(
      rawKeyPattern.hasMatch(_testKeyHex),
      isTrue,
      reason: '_testKeyHex must be a 256-bit (64 hex char) raw key',
    );
    expect(
      rawKeyPattern.hasMatch(_wrongKeyHex),
      isTrue,
      reason: '_wrongKeyHex must be a 256-bit (64 hex char) raw key',
    );
    expect(
      _testKeyHex,
      isNot(_wrongKeyHex),
      reason: 'the two fixture keys must actually differ',
    );
  });

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

  group('PRAGMA-key interpolation is guarded by shape validation, not trusted '
      'blindly (the SQL-injection-shaped-risk fix) — this group needs no real '
      'cipher library, because the validation runs before any SQL touches '
      'the connection', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'massrofy_db_keyvalidation_test_',
      );
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<void> expectRejected(String badKeyHex) async {
      final AppDatabase db = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: badKeyHex),
      );
      await expectLater(
        db.customStatement('PRAGMA user_version;'),
        throwsA(isA<ArgumentError>()),
      );
    }

    test('a key one hex character short of 64 is rejected', () async {
      await expectRejected(_testKeyHex.substring(0, 63));
    });

    test('a key one hex character too long is rejected', () async {
      await expectRejected('${_testKeyHex}0');
    });

    test('a value containing a quote character (an actual injection attempt) '
        'is rejected outright, never interpolated', () async {
      await expectRejected("${_testKeyHex.substring(0, 60)}'; --");
    });

    test('upper-case hex is rejected (only the exact lower-case form '
        'DbMasterKeyStore.bytesToHex produces is accepted)', () async {
      await expectRejected(_testKeyHex.toUpperCase());
    });

    test('a validly-shaped 64-char lower-case hex key is never rejected by '
        'the shape check itself (any failure past this point would be a '
        'different, environment-dependent error — e.g. no cipher library '
        '— never ArgumentError)', () async {
      final AppDatabase db = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
      );
      try {
        await db.customStatement('PRAGMA user_version;');
      } catch (e) {
        expect(
          e,
          isNot(isA<ArgumentError>()),
          reason:
              'a well-formed key must never fail the shape validation '
              'itself — only environment-dependent cipher availability '
              'may still fail here',
        );
      }
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
