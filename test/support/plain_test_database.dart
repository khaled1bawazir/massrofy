import 'package:drift/native.dart';
import 'package:massrofy/data/db/app_database.dart';

/// Opens an [AppDatabase] over a plain (non-encrypted) in-memory
/// `NativeDatabase` — used by DAO/business-logic tests where the point
/// under test is trigger/DAO/audit-chain/soft-delete behaviour, which is
/// identical regardless of whether the underlying bytes happen to be
/// SQLCipher-encrypted. Encryption is a bottom-layer `PRAGMA key` concern
/// (see `lib/data/db/db_connection.dart`); a best-effort desktop-side check
/// of that property lives in
/// `test/data/db/app_database_encryption_test.dart`, but the real,
/// required, gating coverage is
/// `integration_test/db_encryption_test.dart`, run on-device by CI's
/// `android-sqlcipher-integration-test` job (ADR-003).
///
/// **Why this file exists (read before assuming it's an oversight):** on
/// this project's current CI/dev toolchain, `sqlcipher_flutter_libs`'
/// native library is only reliably available for the app's actual shipping
/// target, Android (a precompiled binary needing no local build step — see
/// that package's README). Desktop platforms (Windows/Linux/macOS) require
/// a local CMake+OpenSSL build tied to a platform runner project
/// (`windows/`, `linux/`, `macos/`), which this Android-only app
/// intentionally does not have (ADR-001 context: side-loaded Android app,
/// no other target). Using a plain in-memory database for pure DAO/trigger
/// logic tests keeps those tests fast, reliable everywhere `flutter test`
/// runs, and honest about what they verify — they were never testing
/// encryption in the first place.
AppDatabase openPlainTestDatabase() => AppDatabase(NativeDatabase.memory());
