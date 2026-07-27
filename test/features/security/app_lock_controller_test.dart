import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/crypto/db_master_key_store.dart';
import 'package:massrofy/core/crypto/lockout_state_repository.dart';
import 'package:massrofy/core/crypto/wrapped_key.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/features/security/app_lock_controller.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/features/security/biometric_gate.dart';
import 'package:riverpod/riverpod.dart';

/// An in-memory fake [LockoutStateRepository] — a `Map` standing in for
/// `flutter_secure_storage`, so these tests can prove persistence behaviour
/// (survives a fresh controller, i.e. simulates an app restart) without a
/// real platform channel. Two [AppLockController]s configured with the
/// *same instance* of this fake is exactly how the tests below simulate
/// "the app process restarted, but the secure-storage-backed state on disk
/// did not."
class _FakeLockoutStateRepository implements LockoutStateRepository {
  LockoutState _stored = LockoutState.empty;
  int writeCount = 0;

  @override
  Future<LockoutState> read() async => _stored;

  @override
  Future<void> write(LockoutState state) async {
    writeCount++;
    _stored = state;
  }

  @override
  Future<void> clear() async {
    _stored = LockoutState.empty;
  }
}

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
  late _FakeLockoutStateRepository lockoutStateRepository;

  setUp(() {
    container = ProviderContainer();
    controller = container.read(appLockControllerProvider.notifier);
    biometricGate = _FakeBiometricGate();
    keyStore = _FakeDbMasterKeyRepository();
    lockoutStateRepository = _FakeLockoutStateRepository();
    controller.configure(
      biometricGate: biometricGate,
      keyStore: keyStore,
      logger: SafeLogger(DiagnosticRingBuffer()),
      lockoutStateRepository: lockoutStateRepository,
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

  group('ADR-005 lockout counter survives an app restart (item 5 — previously '
      'this was an in-memory-only int field that silently reset to zero the '
      'moment the process/Notifier was recreated, defeating the lockout)', () {
    test('a fresh AppLockController (simulating a restart) backed by the '
        'SAME persisted lockout state immediately reports lockedOut, '
        'rather than starting the attacker back at zero', () async {
      biometricGate.nextResult = false;
      for (int i = 0; i < 5; i++) {
        await controller.authenticate();
      }
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.lockedOut,
      );

      // Simulate a full app restart: a brand new ProviderContainer (so
      // a brand new AppLockController, with none of the first one's
      // in-memory state), but configured with the SAME
      // lockoutStateRepository instance — standing in for the same
      // flutter_secure_storage-backed data surviving on disk across
      // the restart.
      final ProviderContainer restartedContainer = ProviderContainer();
      addTearDown(restartedContainer.dispose);
      final AppLockController restartedController = restartedContainer.read(
        appLockControllerProvider.notifier,
      );
      final _FakeBiometricGate restartedBiometricGate = _FakeBiometricGate();
      restartedController.configure(
        biometricGate: restartedBiometricGate,
        keyStore: _FakeDbMasterKeyRepository(),
        logger: SafeLogger(DiagnosticRingBuffer()),
        lockoutStateRepository: lockoutStateRepository,
      );

      // Before authenticate() runs even once on the "restarted"
      // controller, its build() reports the generic default (locked) —
      // rehydration happens lazily inside authenticate() (a
      // Notifier.build() cannot be async). Calling authenticate() once
      // is what proves the persisted lockout is honoured: it must be a
      // no-op (still cooling down), not a fresh biometric prompt.
      await restartedController.authenticate();
      expect(
        restartedContainer.read(appLockControllerProvider).status,
        AppLockStatus.lockedOut,
      );
      expect(
        restartedBiometricGate.callCount,
        0,
        reason:
            'a persisted, still-active lockout must block the prompt '
            'from firing at all, exactly like the in-process cooldown '
            'check already does',
      );
    });

    test('a successful unlock clears the persisted lockout state, not just '
        'the in-memory counter', () async {
      biometricGate.nextResult = false;
      for (int i = 0; i < 5; i++) {
        await controller.authenticate();
      }
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.lockedOut,
      );

      // Manually escape the lockedOut UI state the same way waiting out
      // the real cooldown would (this test is about what happens to
      // the *persisted* state on the next successful unlock, not about
      // the cooldown-expiry timing itself, which is covered elsewhere).
      controller.lock(); // resets in-memory state to a plain `locked`
      biometricGate.nextResult = true;
      await controller.authenticate();
      expect(
        container.read(appLockControllerProvider).status,
        AppLockStatus.unlocked,
      );

      final LockoutState persisted = await lockoutStateRepository.read();
      expect(persisted.consecutiveFailures, 0);
      expect(persisted.lockedOutUntil, isNull);
    });
  });
}
