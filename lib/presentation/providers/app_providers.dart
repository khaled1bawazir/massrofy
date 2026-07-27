/// Dependency wiring for the whole app (a very small, explicit "DI
/// container" expressed as Riverpod providers — see architecture.md's
/// choice of Riverpod over Bloc). Every provider here is deliberately
/// overridable in tests via `ProviderScope(overrides: [...])`, which is
/// exactly how `test/features/security/app_lock_controller_test.dart` and
/// the lock-gate widget tests inject fakes instead of the real
/// Keystore/biometric/secure-storage plugins.
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/crypto/android_keystore_key_manager.dart';
import '../../core/crypto/audit_chain_key_store.dart';
import '../../core/crypto/db_master_key_store.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/lockout_state_repository.dart';
import '../../core/crypto/passphrase_key_deriver.dart';
import '../../core/logging/diagnostic_ring_buffer.dart';
import '../../core/logging/safe_logger.dart';
import '../../data/dao/audit_log_dao.dart';
import '../../data/dao/raw_message_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';
import '../../data/db/db_connection.dart';
import '../../features/security/app_lock_controller.dart';
import '../../features/security/biometric_gate.dart';
import '../../features/security/privacy_overlay.dart';

/// One shared diagnostic ring buffer for the whole app session (ADR-015).
final Provider<DiagnosticRingBuffer> diagnosticRingBufferProvider =
    Provider<DiagnosticRingBuffer>((Ref ref) => DiagnosticRingBuffer());

/// The one permitted logging entry point (ADR-015, NFR-S4).
final Provider<SafeLogger> safeLoggerProvider = Provider<SafeLogger>(
  (Ref ref) => SafeLogger(ref.watch(diagnosticRingBufferProvider)),
);

/// ADR-004's Keystore-backed half of the key hierarchy.
final Provider<KeyManager> keyManagerProvider = Provider<KeyManager>(
  (Ref ref) => const AndroidKeystoreKeyManager(),
);

/// ADR-004's passphrase/recovery-secret half — a documented P1 stub, see
/// `passphrase_key_deriver.dart`.
final Provider<PassphraseKeyDeriver> passphraseKeyDeriverProvider =
    Provider<PassphraseKeyDeriver>(
      (Ref ref) => const Hkdf256PassphraseKeyDeriver(),
    );

/// `flutter_secure_storage` instance backing the two wrapped-key blobs
/// (ADR-004). A single shared instance is fine — the plugin itself is
/// stateless from the Dart side.
final Provider<FlutterSecureStorage> secureStorageProvider =
    Provider<FlutterSecureStorage>((Ref ref) => const FlutterSecureStorage());

/// Orchestrates ADR-004's key hierarchy end to end.
final Provider<DbMasterKeyStore> dbMasterKeyStoreProvider =
    Provider<DbMasterKeyStore>(
      (Ref ref) => DbMasterKeyStore(
        keyManager: ref.watch(keyManagerProvider),
        passphraseKeyDeriver: ref.watch(passphraseKeyDeriverProvider),
        secureStorage: ref.watch(secureStorageProvider),
      ),
    );

/// ADR-010's Keystore-held `auditChainKey` half — the production source
/// that previously did not exist (`AuditLogDao` was only ever constructed
/// directly in tests with a made-up key). Mirrors [dbMasterKeyStoreProvider]
/// on purpose — see `audit_chain_key_store.dart`'s doc comment.
final Provider<AuditChainKeyStore> auditChainKeyStoreProvider =
    Provider<AuditChainKeyStore>(
      (Ref ref) => AuditChainKeyStore(
        keyManager: ref.watch(keyManagerProvider),
        secureStorage: ref.watch(secureStorageProvider),
      ),
    );

/// ADR-005's failed-attempt/lockout counter, persisted so it survives an
/// app restart (see `lockout_state_repository.dart`'s doc comment for why
/// this was a real gap before).
final Provider<LockoutStateRepository> lockoutStateRepositoryProvider =
    Provider<LockoutStateRepository>(
      (Ref ref) => SecureStorageLockoutStateRepository(
        secureStorage: ref.watch(secureStorageProvider),
      ),
    );

/// ADR-005's biometric/device-credential prompt.
final Provider<BiometricGate> biometricGateProvider = Provider<BiometricGate>(
  (Ref ref) => LocalAuthBiometricGate(),
);

/// ADR-014's app-switcher obscuring channel.
final Provider<PrivacyGate> privacyGateProvider = Provider<PrivacyGate>(
  (Ref ref) => const PrivacyGate(),
);

/// Wires [AppLockController]'s collaborators exactly once, the first time
/// anything reads [appLockControllerProvider] — see
/// `AppLockController.configure`'s doc comment for why this indirection
/// exists (Riverpod `Notifier`s are constructed with no arguments).
///
/// Reading this provider is a side-effecting `Provider<void>` purely so it
/// participates in the same dependency graph as everything else; the
/// `main.dart`/`app.dart` bootstrap forces it to run once at startup via
/// `ref.read(appLockControllerConfiguratorProvider)`.
final Provider<void> appLockControllerConfiguratorProvider = Provider<void>((
  Ref ref,
) {
  ref
      .read(appLockControllerProvider.notifier)
      .configure(
        biometricGate: ref.watch(biometricGateProvider),
        keyStore: ref.watch(dbMasterKeyStoreProvider),
        logger: ref.watch(safeLoggerProvider),
        lockoutStateRepository: ref.watch(lockoutStateRepositoryProvider),
      );
});

/// Bundles the encrypted database and its DAOs for one unlocked session —
/// what [unlockedDatabaseSessionProvider] below produces once
/// [appLockControllerProvider] reports `isUnlocked`.
///
/// This is what makes `openEncryptedConnection`
/// (`lib/data/db/db_connection.dart`) and [AuditLogDao] genuinely reachable
/// production code paths instead of library code nothing in the app ever
/// calls: before this class existed, the encrypted connection function had
/// zero call sites outside tests, and every `AuditLogDao` in the running
/// app would have had to be constructed by hand with nowhere to get a real
/// `auditChainKey` from.
class UnlockedDatabaseSession {
  final AppDatabase database;
  final AuditLogDao auditLogDao;
  final TransactionDao transactionDao;
  final RawMessageDao rawMessageDao;

  const UnlockedDatabaseSession({
    required this.database,
    required this.auditLogDao,
    required this.transactionDao,
    required this.rawMessageDao,
  });
}

/// Opens the real, SQLCipher-encrypted [AppDatabase] the moment
/// [appLockControllerProvider] reports an unlocked state, and closes it
/// again the moment that changes (lock, session-expiry, or provider
/// teardown) — there is deliberately no code path anywhere in this app that
/// can reach an [AppDatabase] without first going through a successful
/// [AppLockController.authenticate] (matches `main.dart`'s documented
/// invariant: *"there is no unencrypted, pre-lock code path that touches
/// the database at all"*).
///
/// A [FutureProvider] (rather than embedding this inside
/// [AppLockController] itself) keeps the lock controller's job narrowly
/// "manage authentication state and key material" — its existing,
/// already-tested public surface (`configure`/`authenticate`/`lock`/
/// `unlockedKeyHexOrNull`) is untouched by this addition. Riverpod
/// recomputes this provider's `Future` automatically whenever
/// [appLockControllerProvider]'s watched value changes, and [ref.onDispose]
/// closes the previous connection whenever that happens — so a lock
/// event can never leave a stale, still-open encrypted connection behind.
final FutureProvider<UnlockedDatabaseSession?> unlockedDatabaseSessionProvider =
    FutureProvider<UnlockedDatabaseSession?>((Ref ref) async {
      final bool isUnlocked = ref.watch(
        appLockControllerProvider.select((state) => state.isUnlocked),
      );
      if (!isUnlocked) {
        return null;
      }

      final AppLockController controller = ref.watch(
        appLockControllerProvider.notifier,
      );
      final String? rawKeyHex = controller.unlockedKeyHexOrNull;
      if (rawKeyHex == null) {
        // Defensive only — `isUnlocked` being true should always imply a
        // key is present (see AppLockController's own invariant doc
        // comment). Treat it the same as "not yet unlocked" rather than
        // throwing, since a transient lock/unlock race is more likely than
        // this ever actually being reachable.
        return null;
      }

      final AuditChainKeyStore auditChainKeyStore = ref.watch(
        auditChainKeyStoreProvider,
      );
      final bool hasChainKey = await auditChainKeyStore.hasExistingKey();
      final List<int> auditChainKey = hasChainKey
          ? await auditChainKeyStore.unlockAuditChainKey()
          : await auditChainKeyStore.provisionNewAuditChainKey();

      final AppDatabase database = AppDatabase(
        openEncryptedConnection(rawKeyHex: rawKeyHex),
      );
      ref.onDispose(() {
        // Fire-and-forget is acceptable here: `close()` returning a Future
        // we don't await is standard Drift teardown practice inside
        // `onDispose` (which itself cannot be async), and nothing reads
        // from `database` again after this provider is torn down.
        unawaited(database.close());
      });

      final AuditLogDao auditLogDao = AuditLogDao(
        database,
        auditChainKey: auditChainKey,
      );
      final TransactionDao transactionDao = TransactionDao(
        database,
        auditLogDao,
      );
      final RawMessageDao rawMessageDao = RawMessageDao(database);

      return UnlockedDatabaseSession(
        database: database,
        auditLogDao: auditLogDao,
        transactionDao: transactionDao,
        rawMessageDao: rawMessageDao,
      );
    });
