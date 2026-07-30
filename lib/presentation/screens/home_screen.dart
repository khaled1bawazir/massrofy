/// **S-08 — Home.** Mockup: `docs/mockups/home.html` (+ `home-en.html`, the
/// LTR mirror). **KHA-35, US-E1, AC-E1.1–E1.4, AC-C4.2, AC-A1.3, NFR-R2.**
///
/// Replaces `HomePlaceholderScreen`, which existed from P1 to P4b to prove the
/// unlock → decrypt → read chain worked and said so in its own doc comment.
///
/// ---
///
/// ## The four acceptance criteria, and where each one lives
///
/// | AC | Where |
/// |---|---|
/// | **E1.1** current-month total visible on the first screen, no navigation | [MonthTotalCard], first thing under the app bar |
/// | **E1.2** the total reflects an added or corrected transaction on return | `periodReportProvider` is a **Drift stream** — the figure changes without anyone navigating, let alone returning |
/// | **E1.3** zero/empty state, not a blank or an error | `MonthTotalCard`'s empty branch (explicit `0.00` + caption) plus [_HomeEmptyState] |
/// | **E1.4** calendar months; on the 1st the total resets, prior month stays viewable | [PeriodSelector] + `PeriodRangeNotifier.refreshIfTrackingCurrentMonth`, armed from `app.dart`'s resume handler |
///
/// AC-C4.2's review count rides along in `ReviewCountCard`, which P4b already
/// built for the placeholder and which moves here unchanged.
///
/// ## NFR-R2 — "no perceptible wait, responsive during background processing"
///
/// Nothing on this screen awaits ingestion. Every section reads a Drift stream
/// that yields whatever the ledger holds *right now*, so a historical import
/// grinding through a year of SMS in the background changes the figures as it
/// goes rather than blocking the first paint. The one thing the screen does
/// wait for is the encrypted session opening (ADR-005), and it renders a
/// spinner for that rather than a zero.
///
/// ## Why this screen is a `ConsumerWidget` and its parts are not
///
/// The codebase's rule is that screens are pure widgets and `Consumer` *hosts*
/// do the joining (see `categorization_routes.dart`). Home is the one screen
/// that is genuinely a composition of five independent data sections rather
/// than one shape over one value, so it is the host, and every part it renders
/// — `MonthTotalCard`, `PeriodSelector`, `TransactionListItem`,
/// `SpentVsKeptCard` — is a pure widget over plain values. The rule is
/// preserved where it pays for itself: the testable pieces stay testable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/categorization/categories.dart';
import '../../features/ingestion/sms_permission_service.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/period_totals.dart';
import '../../features/security/app_lock_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/categorization_providers.dart';
import '../providers/ingestion_providers.dart';
import '../providers/ledger_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';
import '../widgets/period_widgets.dart';
import '../widgets/review_count_card.dart';
import '../widgets/transaction_list_item.dart';
import 'categorization_routes.dart';
import 'ledger_routes.dart';
import 'sms_limited_mode_screen.dart';

/// How many rows the recent-activity preview shows before deferring to S-10.
///
/// Five, matching the mockup. The preview exists to make the headline figure
/// feel accountable ("that total came from *these*"), not to be a second
/// transaction list — the tab one tap away already is one.
const int kHomeRecentTransactionCount = 5;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PeriodRange period = ref.watch(ledgerPeriodProvider);
    final PeriodRangeNotifier periods = ref.read(ledgerPeriodProvider.notifier);
    final AsyncValue<PeriodReport> reportAsync = ref.watch(
      periodReportProvider,
    );
    final AsyncValue<LedgerView> ledgerAsync = ref.watch(ledgerViewProvider);
    final AsyncValue<SmsPermissionStatus> permission = ref.watch(
      smsPermissionStatusProvider,
    );

    final PeriodReport? report = reportAsync.value;
    final LedgerView ledger = ledgerAsync.value ?? LedgerView.empty;
    final List<LedgerTransaction> inPeriod = ledger.inPeriod(period);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.appTitle)),
      floatingActionButton: FloatingActionButton(
        key: const Key('home.addTransaction'),
        // **An explicit hero tag, and it is not cosmetic.** `AppShell` keeps
        // every tab alive in an `IndexedStack`, so this FAB and the
        // transaction list's are in the same route subtree at the same time.
        // Two `FloatingActionButton`s with Flutter's shared default tag in one
        // subtree is an assertion failure the moment any route transition runs
        // a hero animation — i.e. the first time the user opens anything.
        // Caught by `p5a_shell_navigation_test.dart`.
        heroTag: 'fab.home',
        // NFR-U2 — a bare "+" glyph announces as nothing useful.
        tooltip: l10n.homeAddManually,
        onPressed: () => openManualEntry(context),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 96),
        children: <Widget>[
          // **AC-A1.3.** Shown when access was granted once and has since gone
          // — including Android 11+ auto-revoking it for an unused app. A
          // banner rather than a takeover screen, because taking over the app
          // would hide the very data the banner exists to say is still intact.
          //
          // Deliberately NOT shown before the user has been through onboarding
          // at all: that state is the onboarding gate's, and showing "ingestion
          // has stopped" to someone who never started it would be false.
          if (permission.value != null && !permission.value!.allowsIngestion)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: SmsAccessRevokedBanner(
                onFix: () =>
                    ref.read(smsPermissionServiceProvider).openAppSettings(),
              ),
            ),

          PeriodSelector(
            period: period,
            isCurrentMonth: periods.isCurrentMonth,
            onPreviousMonth: () => periods.shiftMonths(-1),
            onNextMonth: () => periods.shiftMonths(1),
            onCurrentMonth: periods.showCurrentMonth,
          ),
          const SizedBox(height: 8),

          // AC-E1.1 — the answer to "what did I spend this month", first, with
          // no navigation.
          MonthTotalCard(
            totals: report?.spend ?? PeriodTotals.empty,
            isLoading: reportAsync.isLoading,
            hasError: reportAsync.hasError,
          ),
          const SizedBox(height: 12),

          // AC-C4.2 — the review count, visible from the main screen.
          const ReviewCountCard(),
          const SizedBox(height: 12),

          // **S-32 Spent vs Kept moved to the Reports hub in P5b (KHA-37).**
          //
          // P3b-1 put the card here with a note saying so:
          //
          // > ~~"design.md files this under the Reports hub, which is KHA-37 in
          // > P5b. It sits here in the meantime rather than nowhere: a
          // > computation with no production call site is library code, not
          // > shipped behaviour. P5b moves it to S-28."~~
          //
          // This is that move — `SpentVsKeptHost` / S-32. Home is back to the
          // five elements design.md §7 S-08 actually lists (`MonthTotalCard`,
          // `ReviewCountCard`, budgets, the recent preview, the FAB), and the
          // card itself is unchanged and still reachable, so nothing became
          // library code again.
          _SectionHeader(
            title: l10n.homeRecentTransactions,
            actionLabel: l10n.homeViewAll,
            onAction: inPeriod.isEmpty
                ? null
                : () => openTransactionList(context),
          ),
          const SizedBox(height: 4),
          _RecentTransactions(
            transactions: inPeriod,
            internalTransferStates: ledger.internalTransferStates,
            isLoading: ledgerAsync.isLoading,
            hasError: ledgerAsync.hasError,
          ),

          const SizedBox(height: 24),
          // ADR-005's re-lock path, exercisable without waiting for the OS to
          // background the app. Carried over from the placeholder screen, where
          // it was a hard-coded English string — now localised.
          OutlinedButton.icon(
            key: const Key('home.lockNow'),
            onPressed: () =>
                ref.read(appLockControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline),
            label: Text(l10n.homeLockNow),
          ),
        ],
      ),
    );
  }
}

/// A section title with an optional "View all" link, matching the mockup's
/// `.section-title` row.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      // Absent rather than disabled when there is nothing to view: an empty
      // list already says so, and a greyed-out link beside it is one more
      // thing to interpret.
      if (onAction != null)
        TextButton(
          key: const Key('home.viewAllTransactions'),
          onPressed: onAction,
          child: Text(actionLabel),
        ),
    ],
  );
}

/// The recent-activity preview, with all four of design.md §3.4's states.
class _RecentTransactions extends ConsumerWidget {
  final List<LedgerTransaction> transactions;
  final Map<int, String> internalTransferStates;
  final bool isLoading;
  final bool hasError;

  const _RecentTransactions({
    required this.transactions,
    required this.internalTransferStates,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (isLoading) {
      return const Padding(
        key: Key('home.recent.loading'),
        padding: EdgeInsetsDirectional.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasError) {
      // Never an empty list: "you have no transactions" is this section's
      // reassuring state, and showing it for a failed read is the single most
      // misleading thing it can do.
      return CategorySectionError(
        message: l10n.transactionUnavailable,
        onRetry: () => ref.invalidate(ledgerViewProvider),
      );
    }
    if (transactions.isEmpty) {
      return const _HomeEmptyState();
    }

    final AsyncValue<CategoryResolver> resolver = ref.watch(
      categoryResolverProvider,
    );
    final List<LedgerTransaction> preview = transactions
        .take(kHomeRecentTransactionCount)
        .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      child: Column(
        children: <Widget>[
          for (final LedgerTransaction txn in preview)
            TransactionListItem(
              transaction: txn,
              internalTransferState: internalTransferStates[txn.id],
              categoryAssignment: resolver.value == null
                  ? null
                  : assignmentForTransaction(txn, resolver.value!),
              onTap: () => openTransactionDetail(context, txn.id),
            ),
        ],
      ),
    );
  }
}

/// **AC-E1.3's empty state**, and the reason it carries a button.
///
/// The mockup's copy makes two promises at once: a bank message arrives *by
/// itself* (US-B15 — there is nothing to set up), and cash can be entered by
/// hand (US-B4). Without the second half, a user with no bank SMS yet is
/// looking at a screen with nothing to do on it, which reads as a broken app
/// rather than an empty one.
class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      key: const Key('home.empty'),
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.inbox_outlined, size: 44, color: AppColors.ink300),
          const SizedBox(height: 12),
          Text(
            l10n.homeEmptyTitle,
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.homeEmptyBody,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('home.empty.addManually'),
            onPressed: () => openManualEntry(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.homeAddManually),
          ),
        ],
      ),
    );
  }
}
