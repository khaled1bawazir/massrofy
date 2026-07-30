/// **design.md §1's information architecture, made real** — KHA-35 / KHA-36.
///
/// The app's `BottomNav` and the More menu that hangs off it. Everything a user
/// can reach past the lock gate hangs off this widget, which is what keeps
/// ADR-005's guarantee checkable: `app.dart` constructs it only in the unlocked
/// branch, so there is exactly one place to look.
///
/// ---
///
/// ## Four tabs, as design.md §1 always specified — KHA-37 closes the gap
///
/// design.md §5 specifies a four-tab `BottomNav`: **Home · Transactions ·
/// Reports · More**. P5a shipped **three**, and said so out loud rather than
/// shipping a dead tab:
///
/// > ~~"The Reports hub (S-28) is KHA-37 in P5b and does not exist yet. Shipping
/// > a fourth tab that opens onto a placeholder would be the exact failure
/// > `transaction_detail_screen.dart` names about action buttons — 'rendering
/// > buttons now, wired to nothing, would be worse than their absence' — with the
/// > aggravating factor that a nav tab is permanent furniture the user taps by
/// > accident. So this ships Home · Transactions · More, with a one-line honest
/// > note in the More menu."~~
///
/// That disclosure is discharged. `ReportsHubHost` exists, is reachable, and the
/// tab slots in at **index 2** exactly as the note predicted — one entry added to
/// the list below, because the bar is built from that list rather than hard-coded.
/// The More menu's *"Reports arrive in the next release"* line is removed in the
/// same change: a placeholder that outlives the thing it stood in for is worse
/// than never having written it, and `p5b_shell_navigation_test.dart` asserts it
/// is gone rather than trusting anyone to remember.
///
/// ## Why an `IndexedStack` and not a swapped child
///
/// `IndexedStack` keeps every tab's `State` and scroll position alive while
/// showing one. Rebuilding the Home dashboard from scratch on every return from
/// the transactions tab would re-open Drift streams and re-render the month
/// total — a visible flicker on the app's headline figure, and the opposite of
/// NFR-R2's "no perceptible wait". The cost is that all tabs are built at
/// startup; with four tabs over shared providers that is still cheap, because the
/// reports and the list read the *same* `ledgerViewProvider` emission rather than
/// opening a stream each.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/security/app_lock_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'categorization_routes.dart';
import 'home_screen.dart';
import 'ingestion_routes.dart';
import 'ledger_routes.dart';
import 'reports_routes.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final List<_Destination> destinations = <_Destination>[
      _Destination(
        id: 'home',
        label: l10n.navHome,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        page: const HomeScreen(),
      ),
      _Destination(
        id: 'transactions',
        label: l10n.navTransactions,
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        // The same host the "View all" route pushes, so there is one
        // implementation of "what the transaction list shows".
        page: const TransactionListHost(),
      ),
      // **KHA-37** — design.md §1's third tab, at index 2 as the P5a note said it
      // would be. `ReportsHubHost` is a real destination: S-28 with four working
      // drill-downs, not a placeholder.
      _Destination(
        id: 'reports',
        label: l10n.navReports,
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        page: const ReportsHubHost(),
      ),
      _Destination(
        id: 'more',
        label: l10n.navMore,
        icon: Icons.more_horiz,
        selectedIcon: Icons.more_horiz,
        page: const MoreMenuScreen(),
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          for (final _Destination destination in destinations) destination.page,
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int index) => setState(() => _tab = index),
        destinations: <Widget>[
          for (final _Destination destination in destinations)
            NavigationDestination(
              // Keyed on the stable id, never on the localised label: a `Key`
              // built from translated text changes with the OS language, which
              // would silently reshuffle element identity on a locale change
              // and make every test that names a tab locale-specific.
              key: Key('nav.${destination.id}'),
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

/// One tab. A value type so the bar and the stack are built from the same list
/// and cannot drift out of step by an index.
class _Destination {
  /// A stable, locale-independent identifier, used for the widget `Key`.
  final String id;

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const _Destination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

/// **S-40's root** — the menu of everything that is not a tab.
///
/// Grouped rather than a flat list, because a flat list of eight destinations
/// is a list nobody reads. The groups follow the mental model the product is
/// organised around: your money (where it is), organising (how it is labelled),
/// the app itself.
class MoreMenuScreen extends ConsumerWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.navMore)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
        children: <Widget>[
          _GroupHeader(label: l10n.moreSectionData),
          _MenuRow(
            rowKey: const Key('more.banks'),
            icon: Icons.account_balance_outlined,
            label: l10n.banksTitle,
            onTap: () => openBanks(context),
          ),
          _MenuRow(
            rowKey: const Key('more.addTransaction'),
            icon: Icons.add_circle_outline,
            label: l10n.manualEntryTitle,
            onTap: () => openManualEntry(context),
          ),
          _MenuRow(
            rowKey: const Key('more.recentlyDeleted'),
            icon: Icons.restore_from_trash_outlined,
            label: l10n.recentlyDeletedTitle,
            onTap: () => openRecentlyDeleted(context),
          ),

          const SizedBox(height: 16),
          _GroupHeader(label: l10n.moreSectionOrganise),
          _MenuRow(
            rowKey: const Key('more.needsReview'),
            icon: Icons.flag_outlined,
            label: l10n.needsReviewTitle,
            onTap: () => openNeedsReview(context),
          ),
          _MenuRow(
            rowKey: const Key('more.categories'),
            icon: Icons.label_outline,
            label: l10n.categoriesTitle,
            onTap: () => openCategoryManagement(context),
          ),
          _MenuRow(
            rowKey: const Key('more.rules'),
            icon: Icons.rule,
            label: l10n.learnedRulesTitle,
            onTap: () => openLearnedRules(context),
          ),

          const SizedBox(height: 16),
          _GroupHeader(label: l10n.moreSectionApp),
          // **KHA-133.** ADR-006's KHA-133 subsection places this in
          // "Settings → Diagnostics"; the More menu's App section *is* this
          // app's settings surface, so the action lives here rather than
          // behind a Diagnostics screen that would exist only to hold one row.
          //
          // Discovery is a known weak point of this whole decision — ADR-006
          // says so plainly ("the re-check button is found only by a user who
          // goes looking"). The standing fix is US-A6's parser-health panel,
          // not a fourth nav tab.
          _MenuRow(
            rowKey: const Key('more.recheckBanks'),
            icon: Icons.refresh,
            label: l10n.recheckBanksTitle,
            onTap: () => openRecheckBanks(context),
          ),
          _MenuRow(
            rowKey: const Key('more.lockNow'),
            icon: Icons.lock_outline,
            label: l10n.homeLockNow,
            onTap: () => ref.read(appLockControllerProvider.notifier).lock(),
          ),
          // P5a's *"Reports arrive in the next release"* line stood here. KHA-37
          // shipped them as the third tab, so the line is gone — a placeholder
          // that outlives the thing it stood in for is worse than never having
          // written it.
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.ink500,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  final Key rowKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsetsDirectional.only(bottom: 8),
    child: ListTile(
      key: rowKey,
      leading: Icon(icon),
      title: Text(label),
      // `Icons.chevron_right` is not one of Flutter's auto-mirroring icons, so
      // `arrow_forward_ios` is used instead: it *is* direction-aware, and under
      // Arabic RTL it points the way the reader's eye travels rather than
      // against it (design.md §3.1).
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    ),
  );
}
