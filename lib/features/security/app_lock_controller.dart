import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod/riverpod.dart';

import '../../core/crypto/db_master_key_store.dart';
import '../../core/crypto/lockout_state_repository.dart';
import '../../core/crypto/wrapped_key.dart'
    show KeystoreKeyInvalidatedException;
import '../../core/logging/log_event.dart';
import '../../core/logging/safe_logger.dart';
import 'app_lock_state.dart';
import 'biometric_gate.dart';

/// ADR-005: the app lock, enforced cryptographically.
///
/// **The important sentence to hold onto while reading this class:**
/// *"Failing or cancelling authentication means the DB Master Key is never
/// unwrapped, so the database physically cannot be opened."* Every method
/// below is written so that is literally true — [unlockedKeyBytesOrNull]
/// only ever becomes non-null after [DbMasterKeyStore.unlockWithKeystore]
/// (or first-run provisioning) genuinely returns key material, which in
/// turn only happens after [BiometricGate.authenticate] succeeds *and* the
/// underlying Android Keystore key itself accepts the operation (see
/// `biometric_gate.dart`'s doc comment for exactly what that second part
/// guarantees). There is no code path here that flips a `bool isUnlocked`
/// flag without the key actually having been recovered.
class AppLockController extends Notifier<AppLockState> {
  /// Number of consecutive failures before ADR-005's exponential backoff
  /// kicks in.
  static const int _failuresBeforeBackoff = 5;

  BiometricGate? _biometricGate;
  DbMasterKeyRepository? _keyStore;
  SafeLogger? _logger;
  LockoutStateRepository? _lockoutStateRepository;

  int _consecutiveFailures = 0;
  Uint8List? _unlockedKeyBytes;

  // Set true the first time this controller has rehydrated its lockout
  // counter from [_lockoutStateRepository] — see [_ensureLockoutStateLoaded].
  // A `Notifier`'s `build()` must stay synchronous (Riverpod does not
  // support an async `build()` for a plain `Notifier`), so this state
  // cannot be loaded there; instead it is lazily loaded the first time
  // [authenticate] runs, which is early enough that a persisted lockout
  // from a previous process is honoured before any new attempt is allowed.
  bool _lockoutStateLoaded = false;

  @override
  AppLockState build() {
    // `ref.onDispose` here would zero the key if the whole provider tree is
    // torn down (e.g. hot restart in dev) — belt-and-braces alongside the
    // explicit `lock()` call path.
    ref.onDispose(_zeroUnlockedKey);
    return const AppLockState.locked();
  }

  /// Wires the collaborators this controller needs. Riverpod `Notifier`s
  /// are constructed with a no-argument constructor (so `NotifierProvider`
  /// can create them), so dependencies are injected via this explicit
  /// setter — called once, immediately after creation, from
  /// `app_providers.dart` — rather than through the constructor. Tests call
  /// this directly with fakes instead of standing up a full
  /// `ProviderContainer` wiring graph.
  void configure({
    required BiometricGate biometricGate,
    required DbMasterKeyRepository keyStore,
    required SafeLogger logger,
    required LockoutStateRepository lockoutStateRepository,
  }) {
    _biometricGate = biometricGate;
    _keyStore = keyStore;
    _logger = logger;
    _lockoutStateRepository = lockoutStateRepository;
  }

  /// The unwrapped DB Master Key, in hex form ready for
  /// `openEncryptedConnection`'s `rawKeyHex` — `null` whenever
  /// [AppLockState.isUnlocked] is false. Exposed so `app_providers.dart`
  /// can open the encrypted database once, right after a successful
  /// unlock; nothing else in the app should cache this value independently.
  String? get unlockedKeyHexOrNull => _unlockedKeyBytes == null
      ? null
      : DbMasterKeyStore.bytesToHex(_unlockedKeyBytes!);

  /// Runs the biometric/device-credential prompt and, on success, either
  /// provisions a fresh DB Master Key (first run) or unlocks the existing
  /// one. On failure, applies ADR-005's lockout/backoff policy.
  Future<void> authenticate() async {
    final BiometricGate biometricGate = _requireConfigured(
      _biometricGate,
      'biometricGate',
    );
    final DbMasterKeyRepository keyStore = _requireConfigured(
      _keyStore,
      'keyStore',
    );
    final SafeLogger logger = _requireConfigured(_logger, 'logger');
    _requireConfigured(_lockoutStateRepository, 'lockoutStateRepository');

    // ADR-005: the lockout counter must survive an app restart, not just
    // live as long as this `Notifier` does — otherwise force-quitting and
    // reopening the app during an active cooldown resets the attacker's
    // budget back to zero, defeating the whole point of a lockout. This
    // rehydrates once, the first time `authenticate()` runs after this
    // controller was (re-)created, so a persisted lockout from a previous
    // process is honoured before the check below ever runs.
    await _ensureLockoutStateLoaded();

    if (state.status == AppLockStatus.lockedOut) {
      final DateTime? until = state.lockedOutUntil;
      if (until != null && DateTime.now().isBefore(until)) {
        return; // still cooling down — caller's UI should show the countdown
      }
    }

    state = const AppLockState(status: AppLockStatus.authenticating);

    final bool authenticated = await biometricGate.authenticate(
      reason: 'Unlock to view your data',
    );
    if (!authenticated) {
      await _handleFailure(logger);
      return;
    }

    try {
      final bool firstRun = !(await keyStore.hasExistingKey());
      final Uint8List keyBytes = firstRun
          ? await keyStore.provisionNewDatabaseKey()
          : await keyStore.unlockWithKeystore();

      _unlockedKeyBytes = keyBytes;
      _consecutiveFailures = 0;
      // A successful unlock is the one moment it's safe to forget the
      // lockout history entirely — clear the persisted counter along with
      // the in-memory one, so the next failure (whenever it happens, even
      // after a restart) starts counting from zero again.
      await _lockoutStateRepository!.clear();
      state = const AppLockState(status: AppLockStatus.unlocked);
      logger.info(
        LogEvent(
          category: firstRun
              ? 'lock.first_run_provisioned'
              : 'lock.unlock_succeeded',
        ),
      );
    } on KeystoreKeyInvalidatedException {
      // ADR-004's documented recovery trigger. The full recovery-secret UI
      // is Epic I/P8 work (see DbMasterKeyStore.unwrapWithRecoverySecret);
      // for this P1 slice we surface it as a failure rather than silently
      // treating it as an ordinary wrong-auth attempt, so a future recovery
      // flow has a distinct state to hook into.
      logger.warning(const LogEvent(category: 'lock.keystore_invalidated'));
      state = const AppLockState(status: AppLockStatus.failed);
    } catch (_) {
      await _handleFailure(logger);
    }
  }

  Future<void> _handleFailure(SafeLogger logger) async {
    _consecutiveFailures++;
    logger.warning(
      LogEvent(category: 'lock.auth_failed', count: _consecutiveFailures),
    );
    DateTime? lockedOutUntil;
    if (_consecutiveFailures >= _failuresBeforeBackoff) {
      final int extraFailures = _consecutiveFailures - _failuresBeforeBackoff;
      final int backoffSeconds =
          30 * (1 << extraFailures.clamp(0, 6)); // exponential, capped
      lockedOutUntil = DateTime.now().add(Duration(seconds: backoffSeconds));
      state = AppLockState(
        status: AppLockStatus.lockedOut,
        lockedOutUntil: lockedOutUntil,
      );
    } else {
      state = const AppLockState(status: AppLockStatus.failed);
    }

    // Persist immediately (not just on the eventual successful unlock) —
    // this is the fix for ADR-005's lockout counter surviving a restart.
    await _lockoutStateRepository!.write(
      LockoutState(
        consecutiveFailures: _consecutiveFailures,
        lockedOutUntil: lockedOutUntil,
      ),
    );
  }

  /// Loads any previously-persisted lockout state exactly once per
  /// controller lifetime — see [_lockoutStateLoaded]'s doc comment for why
  /// this can't happen in [build] instead.
  Future<void> _ensureLockoutStateLoaded() async {
    if (_lockoutStateLoaded) return;
    _lockoutStateLoaded = true;

    final LockoutState persisted = await _lockoutStateRepository!.read();
    _consecutiveFailures = persisted.consecutiveFailures;
    final DateTime? until = persisted.lockedOutUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      state = AppLockState(
        status: AppLockStatus.lockedOut,
        lockedOutUntil: until,
      );
    }
  }

  /// ADR-005 re-lock policy: called once the configured grace period (0s by
  /// default) has elapsed after `AppLifecycleState.paused`. Zeroes the
  /// in-memory key and drops back to a locked state — [sessionExpired]
  /// distinguishes "was open, backgrounded too long" from a plain cold
  /// launch so the UI can show the banner
  /// `docs/mockups/lock-gate.html`'s session-expired state uses.
  void lock({bool sessionExpired = false}) {
    _zeroUnlockedKey();
    state = AppLockState(
      status: sessionExpired
          ? AppLockStatus.sessionExpired
          : AppLockStatus.locked,
    );
  }

  void _zeroUnlockedKey() {
    final Uint8List? bytes = _unlockedKeyBytes;
    if (bytes != null) {
      DbMasterKeyStore.zeroize(bytes);
    }
    _unlockedKeyBytes = null;
  }

  T _requireConfigured<T>(T? value, String name) {
    if (value == null) {
      throw StateError(
        'AppLockController.$name was not configured — call configure(...) '
        'before authenticate().',
      );
    }
    return value;
  }
}

/// `NotifierProvider` wiring — see `lib/presentation/providers/app_providers.dart`
/// for where [AppLockController.configure] is actually called with real
/// (or, in tests, fake) collaborators.
final NotifierProvider<AppLockController, AppLockState>
appLockControllerProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
