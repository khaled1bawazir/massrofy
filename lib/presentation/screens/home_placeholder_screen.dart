import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/security/app_lock_controller.dart';
import '../l10n/generated/app_localizations.dart';

/// **P1 scope note:** the real Home dashboard (S-08,
/// `docs/mockups/home.html`) — current-month total, review-count card,
/// budget mini-list, recent transactions — is P5 work and depends on
/// domain-model phases (P2-P4) that haven't landed yet. This placeholder
/// exists only to prove the whole P1 chain end-to-end: the app launched,
/// the lock gate authenticated, the DB Master Key was unwrapped, and the
/// user is looking at *something* rendered past the lock gate — plus a
/// manual "Lock now" action so the re-lock path (ADR-005) is exercisable
/// without waiting for the OS to background the app.
class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

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
