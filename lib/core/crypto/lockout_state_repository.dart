import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ADR-005's failed-attempt/backoff counter, restated: *"backoff state
/// stored outside the encrypted DB (it must survive a locked DB)."*
///
/// This is an immutable snapshot of that state — how many consecutive
/// authentication failures have happened, and (once the 5-failure
/// threshold is crossed) the timestamp the current lockout cooldown ends.
class LockoutState {
  final int consecutiveFailures;
  final DateTime? lockedOutUntil;

  const LockoutState({required this.consecutiveFailures, this.lockedOutUntil});

  /// The state before any failure has ever been recorded (or after a
  /// successful unlock clears it).
  static const LockoutState empty = LockoutState(consecutiveFailures: 0);
}

/// Persists [AppLockController]'s lockout counter so it survives an app
/// restart — the whole point of a lockout is defeated if force-quitting
/// and reopening the app resets the count back to zero, which is exactly
/// what happened before this class existed: `_consecutiveFailures` was an
/// in-memory-only `int` field on a `Notifier`, torn down and recreated
/// with every fresh process.
///
/// Deliberately **not** stored inside the encrypted SQLCipher database:
/// this state must be readable and writable *before* the database can be
/// opened (indeed, its entire purpose is to gate whether unlocking is even
/// attempted), so it lives in `flutter_secure_storage`
/// (`EncryptedSharedPreferences` on Android — itself Keystore-backed) —
/// exactly where ADR-004 already keeps the wrapped DB Master Key blobs, for
/// the same "must survive a locked DB" reason.
abstract interface class LockoutStateRepository {
  Future<LockoutState> read();
  Future<void> write(LockoutState state);
  Future<void> clear();
}

class SecureStorageLockoutStateRepository implements LockoutStateRepository {
  static const String _failuresKey = 'lockout_consecutive_failures';
  static const String _untilKey = 'lockout_until_epoch_millis';

  final FlutterSecureStorage secureStorage;

  const SecureStorageLockoutStateRepository({
    FlutterSecureStorage? secureStorage,
  }) : secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<LockoutState> read() async {
    final String? failuresRaw = await secureStorage.read(key: _failuresKey);
    final String? untilRaw = await secureStorage.read(key: _untilKey);

    final int failures = failuresRaw == null
        ? 0
        : (int.tryParse(failuresRaw) ?? 0);
    final DateTime? until = untilRaw == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(untilRaw) ?? 0,
            isUtc: true,
          );

    return LockoutState(consecutiveFailures: failures, lockedOutUntil: until);
  }

  @override
  Future<void> write(LockoutState state) async {
    await secureStorage.write(
      key: _failuresKey,
      value: state.consecutiveFailures.toString(),
    );
    final DateTime? until = state.lockedOutUntil;
    if (until != null) {
      await secureStorage.write(
        key: _untilKey,
        value: until.toUtc().millisecondsSinceEpoch.toString(),
      );
    } else {
      await secureStorage.delete(key: _untilKey);
    }
  }

  @override
  Future<void> clear() async {
    await secureStorage.delete(key: _failuresKey);
    await secureStorage.delete(key: _untilKey);
  }
}
