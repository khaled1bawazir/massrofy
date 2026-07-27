// ADR-003's genuine, on-device SQLCipher encryption coverage.
//
// ## Why this file exists, and why it is not just a copy of the desktop test
// `test/data/db/app_database_encryption_test.dart` covers the same three
// assertions, but running on the HOST machine's Dart VM under
// `flutter test` — where this Android-only app has no real SQLCipher
// native library available (no `windows/`/`linux/`/`macos/` Flutter runner
// project exists, per ADR-001's Android-only scope, and
// `sqlcipher_flutter_libs` only ships a *precompiled* binary for Android;
// every other platform needs a local CMake+OpenSSL build tied to a
// platform runner project this app deliberately doesn't have). That file's
// cipher-dependent tests are therefore marked skipped in that environment,
// honestly, rather than silently forced green.
//
// This file is the resolution to that gap: it runs the same three
// assertions as an `integration_test` — meaning it is compiled into the
// real app and executed **on an actual Android device/emulator**, where
// `sqlcipher_flutter_libs`' precompiled Android binary genuinely is
// present. There is no environment-dependent skip logic anywhere in this
// file; if SQLCipher genuinely isn't wired up correctly on Android, these
// tests fail, full stop.
//
// Run via:
//   flutter test integration_test/db_encryption_test.dart -d <deviceId>
// — see the dedicated `android-sqlcipher-integration-test` CI job in
// `.github/workflows/ci.yml`, which boots a headless Android emulator
// specifically so this executes on every PR, not just compiles.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/data/db/db_connection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// Two distinct, genuinely 64-hex-character (32-byte / 256-bit, ADR-003)
// raw keys — see `test/data/db/app_database_encryption_test.dart`'s doc
// comment on the bug a wrong-length key here previously masked (SQLCipher
// silently falling back to passphrase-KDF mode).
const String _testKeyHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _wrongKeyHex =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    final Directory appDocsDir = await getApplicationDocumentsDirectory();
    tempDir = await Directory(
      p.join(appDocsDir.path, 'massrofy_cipher_integration_test'),
    ).create(recursive: true);
    dbFile = File(
      p.join(
        tempDir.path,
        'test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      ),
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'ADR-003 (on-device): a database created with a key cannot be opened '
    'with the wrong key',
    (WidgetTester tester) async {
      final AppDatabase db = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _testKeyHex),
      );
      await db.customStatement('PRAGMA user_version;'); // forces a real open
      await db.close();

      final AppDatabase wrongKeyDb = AppDatabase(
        openEncryptedConnectionAtFile(file: dbFile, rawKeyHex: _wrongKeyHex),
      );
      await expectLater(
        wrongKeyDb.customSelect('SELECT * FROM sqlite_master').get(),
        throwsA(anything),
      );
      await wrongKeyDb.close();
    },
  );

  testWidgets(
    'ADR-003 (on-device): opening the raw file with a plain (unkeyed) '
    'sqlite3 connection cannot read it either',
    (WidgetTester tester) async {
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
    },
  );

  testWidgets(
    'ADR-003 (on-device): opening with the correct key can read the file '
    'back',
    (WidgetTester tester) async {
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
      expect(rows, isNotEmpty);
      await reopened.close();
    },
  );

  testWidgets(
    'ADR-003 (on-device): the production openEncryptedConnection() path '
    "(path_provider-backed, this app's real production call site — see "
    'app_providers.dart) genuinely encrypts, exercised for real here '
    'because path_provider has a real platform channel to answer to only '
    'on-device, never under host `flutter test`',
    (WidgetTester tester) async {
      final AppDatabase db = AppDatabase(
        openEncryptedConnection(
          rawKeyHex: _testKeyHex,
          fileName: 'massrofy_integration_test_prod_path.sqlite',
        ),
      );
      await db.customStatement('PRAGMA user_version;');
      await db.close();

      final Directory appDocsDir = await getApplicationDocumentsDirectory();
      final File prodStyleFile = File(
        p.join(appDocsDir.path, 'massrofy_integration_test_prod_path.sqlite'),
      );
      addTearDown(() {
        if (prodStyleFile.existsSync()) {
          prodStyleFile.deleteSync();
        }
      });

      final sqlite3.Database raw = sqlite3.sqlite3.open(prodStyleFile.path);
      addTearDown(raw.dispose);
      expect(
        () => raw.select('SELECT * FROM sqlite_master'),
        throwsA(anything),
      );
    },
  );

  // --- Regression: the background-isolate cipher-configuration bug ---------
  //
  // `openEncryptedConnection()` opens the file through
  // `NativeDatabase.createInBackground`, which spawns a SEPARATE isolate and
  // opens the database there. The SQLCipher library override
  // (`sqlite3_open.open.overrideFor(...)`) is isolate-local static state, so
  // configuring it on the calling isolate is a no-op for that background
  // isolate: it would load plain, non-cipher SQLite, `PRAGMA key` would
  // silently do nothing, and the fail-closed `PRAGMA cipher_version` check
  // in `_applyEncryptionPragmas` would throw — meaning the real production
  // path could never open the database at all, even though every test that
  // used a same-isolate `NativeDatabase` passed happily.
  //
  // The fix is drift's `isolateSetup:` callback, which runs inside each
  // spawned isolate before the file is opened. This test is the guard on
  // that fix: it drives a full write-then-read-back round trip through the
  // background-isolate path, so it fails loudly if the `isolateSetup:`
  // wiring is ever dropped again. Note the other tests here deliberately
  // cannot catch this — they use `openEncryptedConnectionAtFile`, which
  // opens on the current isolate.
  testWidgets(
    'ADR-003 (on-device) REGRESSION: the background-isolate production path '
    '(createInBackground) genuinely loads SQLCipher in the spawned isolate '
    'and can round-trip data — guards the isolateSetup: cipher-configuration '
    'fix',
    (WidgetTester tester) async {
      const String fileName = 'massrofy_integration_test_isolate_setup.sqlite';

      final AppDatabase db = AppDatabase(
        openEncryptedConnection(rawKeyHex: _testKeyHex, fileName: fileName),
      );

      final Directory appDocsDir = await getApplicationDocumentsDirectory();
      final File dbFileOnDisk = File(p.join(appDocsDir.path, fileName));
      addTearDown(() {
        if (dbFileOnDisk.existsSync()) {
          dbFileOnDisk.deleteSync();
        }
      });

      // Any statement forces the background isolate to actually open the
      // file. Before the isolateSetup: fix this threw the fail-closed
      // StateError ('SQLCipher is not available in this sqlite3 build'),
      // because the spawned isolate never got the cipher override.
      await db.customStatement(
        'CREATE TABLE isolate_probe (id INTEGER PRIMARY KEY, note TEXT);',
      );
      await db.customStatement(
        "INSERT INTO isolate_probe (id, note) VALUES (1, 'written via "
        "background isolate');",
      );

      // Read it back through the same background-isolate connection: proves
      // the connection is not merely openable but genuinely usable.
      final List<Map<String, Object?>> rows = await db
          .customSelect('SELECT note FROM isolate_probe WHERE id = 1')
          .map((row) => row.data)
          .get();
      expect(rows, hasLength(1));
      expect(rows.single['note'], 'written via background isolate');
      await db.close();

      // ...and that what it wrote is genuinely encrypted on disk, so this
      // test can never pass by silently falling back to plain SQLite.
      final sqlite3.Database raw = sqlite3.sqlite3.open(dbFileOnDisk.path);
      addTearDown(raw.dispose);
      expect(
        () => raw.select('SELECT * FROM isolate_probe'),
        throwsA(anything),
      );
    },
  );

  testWidgets('sanity: a plain (non-cipher-keyed) in-memory Drift database still '
      'works normally on-device too — proves this test file is exercising '
      'real Drift/sqlite3 wiring, not a broken harness reporting false '
      'positives', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final List<Map<String, Object?>> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row.data)
        .get();
    expect(rows, isNotEmpty);
    await db.close();
  });
}
