import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod/riverpod.dart';

import '../../core/crypto/db_master_key_store.dart';
import '../../core/crypto/lockout_state_repository.dart';
import '../../core/crypto/wrapped_key.dart'
    show
        KeystoreFailureKind,
        KeystoreKeyInvalidatedException,
        KeystoreOperationException;
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

    // KHA-72/KHA-75: this call used to sit outside any `try`. `local_auth`
    // 3.x throws (it does not return `false`) for every platform-level
    // problem, so any of those propagated straight out of `authenticate()`
    // and left `state` stuck on [AppLockStatus.authenticating] — which
    // renders identically to `locked` and offers no way forward. The lock
    // gate is the only screen in the product, so that is a hung app.
    final bool authenticated;
    try {
      authenticated = await biometricGate.authenticate(
        reason: 'Unlock to view your data',
      );
    } on BiometricGateUnavailableException {
      // A device fault, not a failed attempt — see that exception's doc
      // comment. Deliberately routed through [_handlePlatformFault], which
      // does NOT touch the lockout counter.
      _handlePlatformFault(logger, const LogEvent(category: 'lock.gate_error'));
      return;
    }
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
    } on KeystoreOperationException catch (e) {
      // KHA-75, the whole point of this issue. This branch used to be a
      // bare `catch (_) { _handleFailure(...); }`, which did two harmful
      // things at once:
      //  1. it discarded the only evidence of what actually went wrong, so
      //     a total, 100%-reproducible platform bug was indistinguishable
      //     from a wrong fingerprint and took two review cycles to find; and
      //  2. it counted the app's own fault against ADR-005's 5-attempt
      //     budget, so users hit a lockout within seconds of first launch.
      // Both are fixed here: a fixed, PII-free category per failure kind
      // (never an interpolated string — ADR-015), and no counter increment.
      _handlePlatformFault(logger, _keystoreFailureEvent(e.kind));
    } catch (_) {
      // Anything else at all (a bug in the store layer, an unexpected
      // StateError). Still not evidence that the user's credential was
      // wrong, so it is still a platform fault, not a failed attempt.
      _handlePlatformFault(
        logger,
        const LogEvent(category: 'lock.unlock_error.unexpected'),
      );
    }
  }

  /// Every category string this class can log for a Keystore failure, as
  /// `const` literals chosen by a `switch` — ADR-015 requires the category
  /// passed to [SafeLogger] to be a compile-time constant at the call site,
  /// so the platform's own error string is never interpolated into a log
  /// line (that is how a value would eventually leak into one).
  ///
  /// These strings are what a maintainer greps for in the in-app
  /// diagnostics (ADR-015's ring buffer). The matching, `adb logcat`-visible
  /// line comes from `KeystoreChannel.logFailure` on the Kotlin side.
  static LogEvent _keystoreFailureEvent(KeystoreFailureKind kind) {
    return switch (kind) {
      KeystoreFailureKind.invalidArgument => const LogEvent(
        category: 'lock.keystore_error.invalid_argument',
      ),
      KeystoreFailureKind.userNotAuthenticated => const LogEvent(
        category: 'lock.keystore_error.user_not_authenticated',
      ),
      KeystoreFailureKind.platform => const LogEvent(
        category: 'lock.keystore_error.platform',
      ),
      KeystoreFailureKind.unknown => const LogEvent(
        category: 'lock.keystore_error.unknown',
      ),
    };
  }

  /// Handles a failure that is the *device's* or *this app's* fault rather
  /// than a wrong credential (KHA-72 item 2, made urgent by KHA-75).
  ///
  /// Contrast with [_handleFailure]: this one deliberately does **not**
  /// increment [_consecutiveFailures], does not persist anything, and can
  /// therefore never trigger ADR-005's exponential backoff. Locking someone
  /// out of their own financial records for minutes because the Keystore
  /// hiccuped — or because of a bug we shipped — is punishing the user for
  /// our fault.
  ///
  /// It resolves to [AppLockStatus.failed], reusing S-09's existing
  /// "Authentication failed. Try again." copy, because a *distinct*
  /// "authentication unavailable" state needs new user-facing copy and
  /// therefore a design answer — `docs/mockups/lock-gate.html` has no such
  /// state today. That remains KHA-72's scope; what matters here and is
  /// fixed here is that the user is never stuck on a screen that does
  /// nothing, and never locked out for a fault that isn't theirs.
  void _handlePlatformFault(SafeLogger logger, LogEvent event) {
    logger.warning(event);
    state = const AppLockState(status: AppLockStatus.failed);
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
