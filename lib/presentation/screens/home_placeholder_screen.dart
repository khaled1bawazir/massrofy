import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ledger/period_totals.dart';
import '../../features/security/app_lock_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/categorization_providers.dart';
import '../providers/ledger_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/spent_vs_kept_card.dart';
import 'categorization_routes.dart';

/// **P1 scope note:** the real Home dashboard (S-08,
/// `docs/mockups/home.html`) — current-month total, budget mini-list, recent
/// transactions — is P5 work (KHA-35) and still is. This screen exists to
/// prove the P1 chain end-to-end: the app launched, the lock gate
/// authenticated, the DB Master Key was unwrapped, and the user is looking at
/// *something* rendered past the lock gate — plus a manual "Lock now" action so
/// the re-lock path (ADR-005) is exercisable without waiting for the OS to
/// background the app.
///
/// Watching [unlockedDatabaseSessionProvider] below is what makes this the
/// screen that actually proves the encrypted datastore and audit trail are
/// wired end to end in the real app, not just reachable from a test.
///
/// ## **P4b adds two things, and they are not placeholder-shaped**
///
///  1. **`ReviewCountCard` (AC-C4.2)** — *"the count of items needing review is
///     visible from the main screen"*. That AC names *the main screen*, and
///     this is the main screen until KHA-35 replaces it. Deferring it to P5
///     would leave AC-C4.2 unmet by a shipped build while the review inbox it
///     points at was fully working, which is the "half-shipped AC" shape
///     `docs/lessons.md` warns about.
///  2. **Navigation to the four P4b screens.** Until this PR `app.dart` routed
///     only this screen and the lock gate, so `NeedsReviewScreen`,
///     `TransactionDetailScreen` and everything else was unreachable code.
///     A list of entries here is deliberately plain — S-08's real information
///     architecture (a 4-tab `BottomNav`) is KHA-35's, and inventing a
///     different one now would be work P5 has to undo.
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
      body: ListView(
        padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 20),
          // **P3b-1 — S-32's figure, made reachable.** design.md puts the
          // full Spent-vs-Kept screen in P5, but AC-B10.3's arithmetic
          // ships now, and a computation with no production call site is
          // library code rather than shipped behaviour (the P1 review's
          // finding). Rendering it here means the whole chain — unlock,
          // decrypt, read the ledger, classify, convert, net — actually
          // executes in the running app.
          const _SpentVsKeptSection(),
          const SizedBox(height: 20),
          const ReviewCountCard(),
          const SizedBox(height: 12),
          const _CategorizationLinks(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () =>
                ref.read(appLockControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Lock now'),
          ),
        ],
      ),
    );
  }
}

/// **design.md §5's `ReviewCountCard`, and AC-C4.2.**
///
/// Two visual states, and the difference is the point (design.md §5's own
/// spec): at zero it says *"All caught up"* and **recedes**; above zero it
/// carries the flag icon, the count and a tap target.
///
/// A queue that shouted at you about being empty would train you to ignore it,
/// which is exactly what you must not do to a review queue in a money app.
///
/// Renders all four of design.md §3.4's states for a data-backed section:
/// loading (a spinner, not a "0" the user would believe), error (an honest
/// message, again not a zero), locked/empty (the reassuring state — while
/// locked `reviewCountsProvider` yields `ReviewCounts.empty`, which is the
/// truthful value: with no key there is no database to count).
class ReviewCountCard extends ConsumerWidget {
  const ReviewCountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ReviewCounts> countsAsync = ref.watch(
      reviewCountsProvider,
    );

    return countsAsync.when(
      loading: () => const Padding(
        key: Key('home.reviewCount.loading'),
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // A failed read must never render as "0 need review" — a reassuring zero
      // the user believes is worse than an error they can act on. Same rule the
      // Spent-vs-Kept section below follows for a figure.
      error: (Object error, StackTrace stackTrace) => Text(
        key: const Key('home.reviewCount.error'),
        l10n.reviewCountUnavailable,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
      data: (ReviewCounts counts) {
        final bool clear = counts.total == 0;
        return InkWell(
          key: const Key('home.reviewCount'),
          onTap: clear ? null : () => openNeedsReview(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              color: clear ? AppColors.surface : AppColors.secondaryTint10,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: clear ? AppColors.ink100 : AppColors.warningFill,
              ),
            ),
            child: Row(
              children: <Widget>[
                // NFR-U4: icon AND words, never a bare coloured dot.
                Icon(
                  clear ? Icons.task_alt : Icons.flag_outlined,
                  color: clear ? AppColors.success : AppColors.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        clear
                            ? l10n.reviewCountAllClear
                            : l10n.reviewCountNeedsReview(counts.total),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: clear
                              ? AppColors.ink700
                              : AppColors.warningText,
                        ),
                      ),
                      if (!clear) ...<Widget>[
                        const SizedBox(height: 2),
                        // The breakdown, because "9 items" with no explanation
                        // is a number the user cannot act on. AC-C1.2 counts
                        // uncategorized rows in this queue, and a user who did
                        // not know that would be looking for nine *problems*.
                        Text(
                          l10n.reviewCountBreakdown(
                            counts.uncategorized,
                            counts.flagged,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.ink700),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!clear) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The navigation P4b adds. Plain rows rather than S-08's `BottomNav`, because
/// the real information architecture belongs to KHA-35 and building half of it
/// here would be work P5 has to undo.
class _CategorizationLinks extends StatelessWidget {
  const _CategorizationLinks();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        _NavRow(
          navKey: const Key('home.nav.needsReview'),
          icon: Icons.flag_outlined,
          label: l10n.needsReviewTitle,
          onTap: () => openNeedsReview(context),
        ),
        _NavRow(
          navKey: const Key('home.nav.categories'),
          icon: Icons.label_outline,
          label: l10n.categoriesTitle,
          onTap: () => openCategoryManagement(context),
        ),
        _NavRow(
          navKey: const Key('home.nav.rules'),
          icon: Icons.rule,
          label: l10n.learnedRulesTitle,
          onTap: () => openLearnedRules(context),
        ),
        // Not a P4b screen — S-44 shipped in P3b-2 with no route into it. It
        // is listed here because S-11's "no longer here" copy tells the user
        // to look for their transaction under Recently deleted, and a sentence
        // that names a place the user cannot reach is worse than no sentence.
        _NavRow(
          navKey: const Key('home.nav.recentlyDeleted'),
          icon: Icons.restore_from_trash_outlined,
          label: l10n.recentlyDeletedTitle,
          onTap: () => openRecentlyDeleted(context),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final Key navKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavRow({
    required this.navKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsetsDirectional.only(bottom: 8),
    child: ListTile(
      key: navKey,
      leading: Icon(icon),
      title: Text(label),
      // Mirrors automatically under RTL, because `Icons.chevron_right` is
      // direction-aware in a `ListTile` trailing slot only if we say so —
      // `Directionality` handles the row order, and the arrow is decorative.
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

/// The four states design.md §3.4 requires of every screen section, for the
/// one section on this screen that reads real data.
///
/// **Locked** is not a fifth branch here: while the app is locked
/// `periodReportProvider` yields [PeriodReport.empty], because ADR-005 makes
/// the lock cryptographic and there is genuinely no database to read. The
/// empty state and the locked state look the same *and should* — in both, the
/// honest statement is "no figures", not a cached number from last time.
class _SpentVsKeptSection extends ConsumerWidget {
  const _SpentVsKeptSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PeriodReport> reportAsync = ref.watch(
      periodReportProvider,
    );
    final AppLocalizations l10n = AppLocalizations.of(context);

    return reportAsync.when(
      data: (PeriodReport report) => SpentVsKeptCard(report: report),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // A failed read must never render as "0.00" — a zero the user believes
      // is worse than an error they can act on.
      error: (Object error, StackTrace stackTrace) => Text(
        l10n.totalsNoneForPeriod,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
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
