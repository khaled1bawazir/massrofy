import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/db_master_key_store.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/features/security/biometric_gate.dart';
import 'package:riverpod/riverpod.dart';

/// A fake [BiometricGate] whose result is fully scripted by the test —
/// no real fingerprint sensor or platform channel involved.
class _FakeBiometricGate implements BiometricGate {
  bool nextResult = true;
  int callCount = 0;

  @override
  Future<bool> authenticate({required String reason}) async {
    callCount++;
    return nextResult;
  }
}

/// A fake [DbMasterKeyRepository] — no `flutter_secure_storage`, no
/// Android Keystore, just an in-memory stand-in so `AppLockController`'s
/// state machine can be tested on its own.
class _FakeDbMasterKeyRepository implements DbMasterKeyRepository {
  bool keyExists = false;
  bool throwKeystoreInvalidated = false;
  bool throwGenericError = false;

  @override
  Future<bool> hasExistingKey() async => keyExists;

  @override
  Future<Uint8List> provisionNewDatabaseKey() async {
    keyExists = true;
    return Uint8List.fromList(List<int>.filled(32, 1));
  }

  @override
  Future<Uint8List> unlockWithKeystore() async {
    if (throwKeystoreInvalidated) {
      throw const KeystoreKeyInvalidatedException();
    }
    if (throwGenericError) {
      throw StateError('boom');
    }
    return Uint8List.fromList(List<int>.filled(32, 2));
  }
}

void main() {
  late ProviderContainer container;
  late AppLockController controller;
  late _FakeBiometricGate biometricGate;
  late _FakeDbMasterKeyRepository keyStore;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(appLockControllerProvider.notifier);
    biometricGate = _FakeBiometricGate();
    keyStore = _FakeDbMasterKeyRepository();
    controller.configure(
      biometricGate: biometricGate,
      keyStore: keyStore,
      logger: SafeLogger(DiagnosticRingBuffer()),
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('starts locked', () {
    expect(
      container.read(appLockControllerProvider).status,
      AppLockStatus.locked,
    );
  });

  test(
    'successful authentication on first run provisions a key and unlocks',
    () async {
      await controller.authenticate();
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.unlocked,
      );
      expect(controller.unlockedKeyHexOrNull, isNotNull);
      expect(keyStore.keyExists, isTrue);
    },
  );

  test(
    'successful authentication on a later run unlocks via Keystore',
    () async {
      keyStore.keyExists = true;
      await controller.authenticate();
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.unlocked,
      );
    },
  );

  test('FAILED OR CANCELLED AUTHENTICATION NEVER UNLOCKS (ADR-005 core '
      'guarantee) — the key is never produced, so no data could ever be '
      'visible', () async {
    biometricGate.nextResult = false;
    await controller.authenticate();
    final AppLockState state = container.read(appLockControllerProvider);
    expect(state.status, AppLockStatus.failed);
    expect(controller.unlockedKeyHexOrNull, isNull);
    expect(state.isUnlocked, isFalse);
  });

  test(
    '5 consecutive failures trigger lockout with exponential backoff',
    () async {
      biometricGate.nextResult = false;
      for (int i = 0; i < 5; i++) {
        await controller.authenticate();
      }
      final AppLockState state = container.read(appLockControllerProvider);
      expect(state.status, AppLockStatus.lockedOut);
      expect(state.lockedOutUntil, isNotNull);
      expect(state.lockedOutUntil!.isAfter(DateTime.now()), isTrue);
    },
  );

  test(
    'authenticate() is a no-op while still cooling down from a lockout',
    () async {
      biometricGate.nextResult = false;
      for (int i = 0; i < 5; i++) {
        await controller.authenticate();
      }
      final int callsAfterLockout = biometricGate.callCount;
      await controller.authenticate(); // should be ignored — still locked out
      expect(biometricGate.callCount, callsAfterLockout);
    },
  );

  test('a KeystoreKeyInvalidatedException surfaces as a failed state, not a '
      'silent unlock (ADR-004 recovery trigger)', () async {
    keyStore.keyExists = true;
    keyStore.throwKeystoreInvalidated = true;
    await controller.authenticate();
    expect(
      container.read(appLockControllerProvider).status,
      AppLockStatus.failed,
    );
    expect(controller.unlockedKeyHexOrNull, isNull);
  });

  test('lock() zeroes the key and returns to a locked state', () async {
    await controller.authenticate();
    expect(controller.unlockedKeyHexOrNull, isNotNull);

    controller.lock();
    expect(
      container.read(appLockControllerProvider).status,
      AppLockStatus.locked,
    );
    expect(controller.unlockedKeyHexOrNull, isNull);
  });

  test(
    'lock(sessionExpired: true) reports the session-expired state',
    () async {
      await controller.authenticate();
      controller.lock(sessionExpired: true);
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.sessionExpired,
      );
    },
  );

  test('authenticate() before configure() throws a clear StateError', () {
    final ProviderContainer freshContainer = ProviderContainer();
    addTearDown(freshContainer.dispose);
    final AppLockController fresh = freshContainer.read(
      appLockControllerProvider.notifier,
    );
    expect(fresh.authenticate(), throwsA(isA<StateError>()));
  });
}
