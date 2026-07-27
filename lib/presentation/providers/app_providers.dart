/// Dependency wiring for the whole app (a very small, explicit "DI
/// container" expressed as Riverpod providers — see architecture.md's
/// choice of Riverpod over Bloc). Every provider here is deliberately
/// overridable in tests via `ProviderScope(overrides: [...])`, which is
/// exactly how `test/features/security/app_lock_controller_test.dart` and
/// the lock-gate widget tests inject fakes instead of the real
/// Keystore/biometric/secure-storage plugins.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/crypto/android_keystore_key_manager.dart';
import '../../core/crypto/db_master_key_store.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/passphrase_key_deriver.dart';
import '../../core/logging/diagnostic_ring_buffer.dart';
import '../../core/logging/safe_logger.dart';
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
      );
});
