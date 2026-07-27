import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

bool _cipherLibraryConfigured = false;

/// Ensures `package:sqlite3`'s dynamic-library lookup resolves to the real
/// **SQLCipher** binary `sqlcipher_flutter_libs` bundles, instead of plain
/// (unencrypted-capable) SQLite.
///
/// ## How the encryption actually happens (ADR-003)
/// `sqlcipher_flutter_libs` ships genuine SQLCipher native libraries as an
/// ordinary Flutter plugin (a native library bundled into the app package
/// for each platform) — classic Flutter plugin packaging, not the newer
/// Dart "hooks"/native-assets build mechanism. (This project tried the
/// newer `sqlite3` 3.x + hooks approach first; see the `sqlite3`/`drift`
/// version comments in `pubspec.yaml` for why it moved back to this
/// approach — in short, `flutter test` did not reliably wire the
/// native-assets mapping into the compiled test kernel on this Flutter
/// version, which would have meant shipping ADR-003's core guarantee
/// unverified by an automated test.) On Android specifically,
/// `package:sqlite3` must be told explicitly to load the SQLCipher binary
/// instead of its own default (`openCipherOnAndroid`, from
/// `sqlcipher_flutter_libs`); every other platform's build only ever has
/// the SQLCipher library on its native search path in the first place, so
/// no override is needed there — this matches `sqlcipher_flutter_libs`'
/// own documented usage exactly.
///
/// This function is idempotent and cheap to call from every entry point
/// below — production code and tests alike — so nobody has to remember to
/// call it separately before opening a database.
void _ensureCipherLibraryConfigured() {
  if (_cipherLibraryConfigured) return;
  sqlite3_open.open.overrideFor(
    sqlite3_open.OperatingSystem.android,
    openCipherOnAndroid,
  );
  _cipherLibraryConfigured = true;
}

/// Opens the SQLCipher-encrypted local database file for production use.
///
/// [_applyEncryptionPragmas] is what actually keys the connection: it runs
/// `PRAGMA key = "x'<64 hex chars>'"` **before** Drift/`sqlite3` issues any
/// other statement against the file, exactly as ADR-003 specifies ("we
/// supply a raw 32-byte key ... bypassing SQLCipher's own PBKDF2 (our key is
/// already high-entropy and already KDF-protected upstream — ADR-004)").
///
/// If [rawKeyHex] is wrong (or the pragma is skipped entirely), every
/// subsequent statement against an already-encrypted file fails — SQLite
/// reads back as `file is not a database` / `SQLITE_NOTADB`, because the
/// page headers genuinely do not parse as SQLite pages without the correct
/// key. That is what makes "the DB file on disk is unreadable without the
/// key" a property of the file format itself, not an application-level
/// promise — see `test/data/db/app_database_encryption_test.dart`.
QueryExecutor openEncryptedConnection({
  required String rawKeyHex,
  String fileName = 'massrofy.sqlite',
}) {
  return LazyDatabase(() async {
    _ensureCipherLibraryConfigured();
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dir.path, fileName));
    return NativeDatabase.createInBackground(
      file,
      setup: (sqlite3.Database db) => _applyEncryptionPragmas(db, rawKeyHex),
    );
  });
}

/// Opens an SQLCipher-encrypted database at an explicit [file] path — used
/// by tests that need a real file on disk (to reopen it without the key and
/// assert it cannot be read), bypassing `path_provider` entirely since that
/// plugin has no real platform channel to answer to under `flutter test`.
QueryExecutor openEncryptedConnectionAtFile({
  required File file,
  required String rawKeyHex,
}) {
  _ensureCipherLibraryConfigured();
  return NativeDatabase(
    file,
    setup: (sqlite3.Database db) => _applyEncryptionPragmas(db, rawKeyHex),
  );
}

/// An in-memory SQLCipher-encrypted connection — fast, isolated, and still
/// exercises the real cipher code path (unlike a bare in-memory
/// `NativeDatabase.memory()` without a key). Suitable for the majority of
/// DAO/business-logic tests that don't need to inspect the file on disk.
QueryExecutor openEncryptedMemoryConnection({required String rawKeyHex}) {
  _ensureCipherLibraryConfigured();
  return NativeDatabase.memory(
    setup: (sqlite3.Database db) => _applyEncryptionPragmas(db, rawKeyHex),
  );
}

void _applyEncryptionPragmas(sqlite3.Database db, String rawKeyHex) {
  // ADR-003's exact configuration, applied on every connection open:
  db.execute("PRAGMA key = \"x'$rawKeyHex'\";");

  // Defensive check straight from sqlcipher_flutter_libs' own docs: the
  // `PRAGMA key` above fails *silently* if the loaded native library is
  // plain SQLite rather than SQLCipher, which would otherwise mean this
  // app quietly starts writing an unencrypted database — precisely the
  // failure NFR-S1 exists to prevent. `cipher_version` is only ever
  // non-empty when SQLCipher is genuinely the library in use.
  final sqlite3.ResultSet cipherVersion = db.select('PRAGMA cipher_version;');
  if (cipherVersion.isEmpty) {
    throw StateError(
      'SQLCipher is not available in this sqlite3 build — refusing to open '
      'the database, since doing so would silently create an UNENCRYPTED '
      'file (ADR-003/NFR-S1). Check that sqlcipher_flutter_libs is a '
      'dependency and its native library loaded correctly for this platform.',
    );
  }

  db.execute('PRAGMA cipher_memory_security = ON;');
  db.execute('PRAGMA journal_mode = WAL;');
  // NFR-R6: a device restart mid-write must not corrupt or lose recorded
  // transactions — full fsync on every commit on the ledger path.
  db.execute('PRAGMA synchronous = FULL;');
}
