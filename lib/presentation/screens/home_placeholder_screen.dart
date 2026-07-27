import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/security/app_lock_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';

/// **P1 scope note:** the real Home dashboard (S-08,
/// `docs/mockups/home.html`) — current-month total, review-count card,
/// budget mini-list, recent transactions — is P5 work and depends on
/// domain-model phases (P2-P4) that haven't landed yet. This placeholder
/// exists only to prove the whole P1 chain end-to-end: the app launched,
/// the lock gate authenticated, the DB Master Key was unwrapped, and the
/// user is looking at *something* rendered past the lock gate — plus a
/// manual "Lock now" action so the re-lock path (ADR-005) is exercisable
/// without waiting for the OS to background the app.
///
/// Watching [unlockedDatabaseSessionProvider] below is what makes this the
/// screen that actually proves the encrypted datastore and audit trail are
/// wired end to end in the real app, not just reachable from a test: this
/// is the first (and, in this P1 slice, only) production widget that reads
/// that provider, which is what causes `openEncryptedConnection` and
/// `AuditLogDao` to genuinely execute the moment a real user unlocks the
/// app — see that provider's doc comment for the full chain.
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UnlockedDatabaseSession?> sessionAsync = ref.watch(
      unlockedDatabaseSessionProvider,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.homePlaceholderTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.homePlaceholderBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // Purely diagnostic, P1-only text — proves the encrypted
            // database + audit-chain-key wiring actually ran, not a
            // user-facing feature (the real Home screen is P5 work).
            _DatabaseSessionStatus(sessionAsync: sessionAsync),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(appLockControllerProvider.notifier).lock(),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseSessionStatus extends StatelessWidget {
  final AsyncValue<UnlockedDatabaseSession?> sessionAsync;
  const _DatabaseSessionStatus({required this.sessionAsync});

  @override
  Widget build(BuildContext context) {
    return sessionAsync.when(
      data: (UnlockedDatabaseSession? session) => Text(
        session == null
            ? 'Encrypted datastore: not yet open'
            : 'Encrypted datastore: open — audit trail ready',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      loading: () => const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (Object error, StackTrace stackTrace) => Text(
        'Encrypted datastore: unavailable',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
