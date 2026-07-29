/// **The wiring that makes P4b's screens reachable** — KHA-32, KHA-33, KHA-34,
/// KHA-97.
///
/// ## Why this file exists at all
///
/// `docs/lessons.md` records the failure this file closes, twice over:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code — it
/// > expires the moment someone adds a route, silently."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// Until this PR, `NeedsReviewScreen`, `TransactionDetailScreen` and
/// `RecentlyDeletedScreen` all existed, were fully tested, and were **never
/// constructed by production code** — `app.dart` routed `HomePlaceholderScreen`
/// and `LockGateScreen` and nothing else. This file is the construction site. A
/// future reachability question about any of these screens is answered by
/// grepping for the `open*` functions below.
///
/// ## The shape: hosts, not screens
///
/// Every screen in this app is a `StatelessWidget`/`StatefulWidget` over plain
/// values with no provider in it, so widget tests are pure render tests and no
/// screen can read something the app lock has not unlocked (ADR-005). That
/// leaves somebody to do the joining, and it is these `Consumer` **hosts**:
/// they watch providers, render design.md §3.4's loading/error/locked states,
/// and hand the screen values plus callbacks.
///
/// Keeping the hosts here rather than beside each screen means the *navigation
/// graph* is one file a reviewer can read end to end, which is the property
/// that was missing when the gate above was written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/category_dao.dart'
    show CategoryDeleteDecision, ProtectedCategoryError;
import '../../data/db/app_database.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/categorization_service.dart';
import '../../features/categorization/category_correction.dart';
import '../../features/categorization/learned_rules.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/internal_transfer_decision.dart';
import '../../features/ledger/ledger_mapping.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/transaction_edit.dart';
import '../../features/ledger/transaction_merge.dart';
import '../../features/ledger/unparsed_completion.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/categorization_providers.dart';
import '../providers/ingestion_providers.dart';
import '../providers/ledger_providers.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/category_widgets.dart';
import 'category_management_screen.dart';
import 'complete_unparsed_screen.dart';
import 'learned_rules_screen.dart';
import 'needs_review_screen.dart';
import 'recently_deleted_screen.dart';
import 'transaction_detail_screen.dart';

// =========================================================================
// The navigation graph. Every route P4b adds is opened by one of these four
// functions and by nothing else.
// =========================================================================

/// **S-18** — the Needs Review inbox.
Future<void> openNeedsReview(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const NeedsReviewHost()));

/// **S-14/S-15** — category management.
Future<void> openCategoryManagement(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const CategoryManagementHost()));

/// **S-16/S-17** — learned rules.
Future<void> openLearnedRules(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const LearnedRulesHost()));

/// **S-44 — Recently Deleted** (US-B8).
///
/// Not a P4b feature, and routed here anyway for a specific reason: S-11's
/// "this transaction is no longer here" copy tells the user *"you can find it
/// under Recently deleted"*, and a sentence that names a place the user cannot
/// reach is worse than no sentence. The screen and its provider both shipped in
/// P3b-2 (KHA-26); only the route was missing.
Future<void> openRecentlyDeleted(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const RecentlyDeletedHost()));

/// **S-11** — one transaction's detail, by id.
///
/// By id rather than by value on purpose: the screen must show the row as it is
/// *now*, and a value captured when the list was built would go stale the
/// moment a correction lands — which, on this screen, is the most likely thing
/// to happen next.
Future<void> openTransactionDetail(BuildContext context, int transactionId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailHost(transactionId: transactionId),
      ),
    );

// =========================================================================
// The correction flow — §6, shared by every entry point in §6.1.
// =========================================================================

/// **Opens S-12/S-13 for one transaction and applies the result.**
///
/// This is the single implementation of design.md §6 behind all of §6.1's entry
/// points (list row, detail screen, review inbox). One implementation is what
/// makes "the same sheet, the same rule store" true rather than aspirational —
/// KHA-101 was filed because two correction surfaces had drifted apart, and the
/// cheapest way not to repeat that is to have one.
///
/// The snackbar is AC-D5.3's count *and* AC-C5.2's undo. It is deliberately a
/// snackbar rather than a dialog: §6.6 chose undo over confirmation for this
/// operation because a category correction is low-stakes and reversible, and
/// making the reversible thing cheap is what stops the learning loop going
/// untrained (NFR-U7).
Future<void> correctTransactionCategory({
  required BuildContext context,
  required WidgetRef ref,
  required int transactionId,

  /// Zero in widget tests, so the scope strip resolves deterministically
  /// instead of racing a real 3-second timer.
  Duration autoConfirmDelay = const Duration(seconds: 3),
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final CategoryCorrectionService? service = await ref.read(
    categoryCorrectionServiceProvider.future,
  );
  final UnlockedDatabaseSession? session = await ref.read(
    unlockedDatabaseSessionProvider.future,
  );
  if (service == null || session == null || !context.mounted) {
    // Locked, or the session went away while the sheet was being opened.
    // Silently doing nothing is right: the lock gate is already on screen.
    return;
  }

  final TransactionRow? row = await session.transactionDao.byIdOrNull(
    transactionId,
  );
  final List<Category> categories = await ref.read(categoriesProvider.future);
  if (row == null || !context.mounted) {
    return;
  }

  // The merchant is resolved read-only: opening a picker must not write a
  // merchant row for a user who is about to dismiss it.
  final MerchantRow? merchant = await service.merchantFor(row);
  final int? merchantId = merchant?.id;
  final String? existingRuleCategoryId = merchantId == null
      ? null
      : (await service.merchantDao.ruleForMerchant(merchantId))?.categoryId;
  if (!context.mounted) {
    return;
  }

  final CategoryPickResult? picked = await showCategoryPickerSheet(
    context: context,
    categories: categories,
    currentCategoryId: row.categoryId,
    merchantName: merchant?.canonicalName ?? row.merchantRawText,
    existingRuleCategoryId: existingRuleCategoryId,
    autoConfirmDelay: autoConfirmDelay,
    affectedCountFor: merchantId == null
        ? null
        : (String _) => service.countUncategorizedSiblings(
            merchantId: merchantId,
            excludingTransactionId: transactionId,
          ),
    onCreateCategory:
        ({
          required String name,
          required String iconToken,
          required CategoryGroup group,
        }) async {
          final CategoryRow? created = await service.categorization.categoryDao
              .createCustom(
                name: name,
                iconToken: iconToken,
                groupKey: group.key,
              );
          // Null propagates unchanged — it is AC-C3.2's duplicate-name answer,
          // not an error, and the sheet renders the message.
          if (created == null) {
            return null;
          }
          // Re-read through the service so the row → domain conversion has one
          // implementation, and so the returned value carries whatever defaults
          // the DAO filled in.
          final List<Category> refreshed = await service.categorization
              .categories();
          return refreshed.firstWhere(
            (Category c) => c.id == created.id,
            orElse: () => DefaultCategories.uncategorized,
          );
        },
  );
  if (picked == null || !context.mounted) {
    // Dismissed. Nothing was written — the sheet applies nothing until it pops
    // with a result.
    return;
  }

  final CategoryCorrection correction = await service.correct(
    transactionId: transactionId,
    categoryId: picked.categoryId,
    scope: picked.scope,
  );
  if (!context.mounted) {
    return;
  }

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      // AC-D5.3 — *"the merchant-wide option creates/updates the rule and
      // STATES HOW MANY existing transactions were affected."* The two
      // sentences are different because the facts are: a one-off says what it
      // did to one row and makes no claim about the rest.
      content: Text(
        correction.otherTransactionsUpdated > 0 &&
                correction.merchantName != null
            ? l10n.correctionAppliedToMany(
                correction.totalTransactionsUpdated,
                correction.merchantName!,
              )
            : l10n.correctionAppliedToOne,
      ),
      action: correction.undo.isRestorable
          ? SnackBarAction(
              label: l10n.commonUndo,
              onPressed: () async {
                // AC-C5.2 — every affected row goes back to *its own* prior
                // category, and the rule change goes back too (§6.4's "undo
                // reverts the rule change, not just this transaction").
                await service.undo(correction.undo);
              },
            )
          : null,
    ),
  );
}

// =========================================================================
// Hosts
// =========================================================================

/// **S-18** — joins four providers into one inbox.
class NeedsReviewHost extends ConsumerWidget {
  /// Zero in widget tests. Threaded rather than read from a global so a test
  /// never has to pump a real 3-second timer.
  final Duration autoConfirmDelay;

  const NeedsReviewHost({
    this.autoConfirmDelay = const Duration(seconds: 3),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ReviewQueueItem>> unparsed = ref.watch(
      reviewQueueProvider,
    );
    final AsyncValue<List<FlaggedTransactionItem>> flagged = ref.watch(
      flaggedTransactionsProvider,
    );
    final AsyncValue<Map<int, CategoryAssignment>> assignments = ref.watch(
      flaggedCategoryAssignmentsProvider,
    );
    final AsyncValue<ReviewInboxView> inbox = ref.watch(reviewInboxProvider);

    // design.md §3.4's Error state, ahead of everything else: a failed read of
    // any of these lists must not render as an empty inbox, because an empty
    // inbox is this screen's *good news* state and showing it wrongly is the
    // single most misleading thing this screen can do.
    if (unparsed.hasError || flagged.hasError || inbox.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.needsReviewTitle)),
        body: CategorySectionError(
          message: l10n.reviewInboxUnavailable,
          onRetry: () {
            ref.invalidate(reviewQueueProvider);
            ref.invalidate(flaggedTransactionsProvider);
            ref.invalidate(reviewInboxProvider);
          },
        ),
      );
    }
    if (unparsed.isLoading || flagged.isLoading || inbox.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.needsReviewTitle)),
        body: const Center(
          key: Key('needsReview.loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final ReviewInboxView view = inbox.value ?? ReviewInboxView.empty;
    return NeedsReviewScreen(
      unparsed: unparsed.value ?? const <ReviewQueueItem>[],
      flagged: flagged.value ?? const <FlaggedTransactionItem>[],
      transfers: view.transfers,
      unreadable: view.unreadable,
      categoryAssignments:
          assignments.value ?? const <int, CategoryAssignment>{},
      onCategorize: (FlaggedTransactionItem item) => correctTransactionCategory(
        context: context,
        ref: ref,
        transactionId: item.transactionId,
        autoConfirmDelay: autoConfirmDelay,
      ),
      onOpenFlagged: (FlaggedTransactionItem item) =>
          openTransactionDetail(context, item.transactionId),
      onFillInDetails: (ReviewQueueItem item) =>
          _openCompleteUnparsed(context, item),
      onNotATransaction: (ReviewQueueItem item) async {
        final UnlockedDatabaseSession? session = await ref.read(
          unlockedDatabaseSessionProvider.future,
        );
        // US-A4: an update, never a delete — see `review_queue.dart` for why
        // deleting would make the message reappear on the next sweep.
        await session?.rawMessageDao.dismissAsNotTransaction(item.rawMessageId);
      },
      onMergeDuplicate: (FlaggedTransactionItem item) async {
        final TransactionMergeService? merge = await ref.read(
          transactionMergeServiceProvider.future,
        );
        final int? other = item.possibleDuplicateOfId;
        if (merge == null || other == null) {
          return;
        }
        // `confirmedByUser` is the service's guard against a *programmer*
        // merging by accident; the dialog the card already showed is the guard
        // against a *user* doing so. Neither substitutes for the other.
        await merge.merge(
          survivorId: item.transactionId,
          mergedAwayId: other,
          confirmedByUser: true,
        );
      },
      onKeepBothDuplicates: (FlaggedTransactionItem item) async {
        final UnlockedDatabaseSession? session = await ref.read(
          unlockedDatabaseSessionProvider.future,
        );
        // AC-A5.3 — two genuine purchases. Clears the duplicate flag *only*;
        // both rows stay live and stay in every total.
        await session?.transactionDao.resolveDuplicateFlag(
          id: item.transactionId,
        );
      },
      onTransferVerdict: (TransferReviewItem item, bool isOwnAccount) async {
        final InternalTransferDecisionService? decisions = await ref.read(
          internalTransferDecisionServiceProvider.future,
        );
        if (decisions == null) {
          return;
        }
        if (!item.isPair) {
          // KHA-80: only rejection is offered for an unpairable leg, and the
          // card only ever calls this with false.
          await decisions.dismissUnpairable(item.transactionId);
          return;
        }
        await decisions.decidePairByIds(
          outTransactionId: item.transactionId,
          inTransactionId: item.counterpartTransactionId!,
          groupId: item.groupId!,
          verdict: isOwnAccount
              ? InternalTransferVerdict.confirmedInternal
              : InternalTransferVerdict.rejectedExternal,
        );
      },
    );
  }

  /// S-19 is P3b-2's screen and already wired to its own service; opening it
  /// from here is the last missing link rather than new behaviour.
  ///
  /// It deliberately has **no category picker** — its own doc comment explains
  /// that a picker with nothing behind it would have been a lie in P3b-2. Now
  /// that there *is* something behind it, the honest fix is to let the user
  /// categorise the resulting transaction from its detail screen, which the
  /// completion flow lands on; adding a second picker with different behaviour
  /// is exactly the two-surfaces-disagreeing shape KHA-101 was filed for.
  void _openCompleteUnparsed(BuildContext context, ReviewQueueItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CompleteUnparsedHost(item: item)),
    );
  }
}

/// **S-19** — P3b-2's "complete an unparsed message" form, which until now had
/// no route into it either.
///
/// The form validates for the user's benefit and the service validates for the
/// data's, and the two are deliberately not the same code (see
/// `unparsed_completion.dart`). So a `CompletionRejected` from the service is
/// fed back into the form as [CompleteUnparsedScreen.rejectedFields] rather
/// than shown as a toast: AC-B4.2 requires the message to name the missing
/// field, and the field is where the user is looking.
class CompleteUnparsedHost extends ConsumerStatefulWidget {
  final ReviewQueueItem item;

  const CompleteUnparsedHost({required this.item, super.key});

  @override
  ConsumerState<CompleteUnparsedHost> createState() =>
      _CompleteUnparsedHostState();
}

class _CompleteUnparsedHostState extends ConsumerState<CompleteUnparsedHost> {
  List<String> _rejectedFields = const <String>[];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return CompleteUnparsedScreen(
      item: widget.item,
      rejectedFields: _rejectedFields,
      onSave: (UnparsedCompletionDraft draft) async {
        final UnparsedCompletionService? service = await ref.read(
          unparsedCompletionServiceProvider.future,
        );
        if (service == null) {
          return;
        }
        final CompletionResult result = await service.complete(draft);
        // `context.mounted` rather than the State's `mounted`: this callback is
        // a closure created in `build`, so the `context` it captured is the one
        // that must still be alive, and checking the *element* is what the
        // `use_build_context_synchronously` lint is actually asking for. They
        // agree here, but only one of them is checkable by the analyzer.
        if (!context.mounted) {
          return;
        }
        // Resolved into locals before the switch, so the navigator and
        // messenger are looked up once, while the element is provably alive.
        final NavigatorState navigator = Navigator.of(context);
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        switch (result) {
          case CompletionAccepted(:final int transactionId):
            // Straight to the new transaction, which is where the category can
            // be set — S-19 deliberately has no picker of its own (see
            // `NeedsReviewHost._openCompleteUnparsed`).
            navigator.pop();
            await navigator.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    TransactionDetailHost(transactionId: transactionId),
              ),
            );
          case CompletionRejected(:final List<String> missingFields):
            setState(() => _rejectedFields = missingFields);
          case CompletionMessageUnavailable():
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.completionMessageGone)),
            );
        }
      },
    );
  }
}

/// **S-14/S-15** — category management.
class CategoryManagementHost extends ConsumerWidget {
  const CategoryManagementHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategoryListItem>> items = ref.watch(
      categoryListProvider,
    );
    final AppLocalizations l10n = AppLocalizations.of(context);

    return items.when(
      loading: () => const CategoryManagementScreen(
        items: <CategoryListItem>[],
        isLoading: true,
      ),
      error: (Object error, StackTrace stackTrace) => CategoryManagementScreen(
        items: const <CategoryListItem>[],
        errorMessage: l10n.categoriesUnavailable,
      ),
      data: (List<CategoryListItem> data) => CategoryManagementScreen(
        items: data,
        onRename: (Category category, String name) async {
          final CategorizationService? service = await ref.read(
            categorizationServiceProvider.future,
          );
          if (service == null) {
            return false;
          }
          try {
            // AC-C3.4 — the id never changes, so no transaction is
            // re-categorised. Null means the new name collides.
            return await service.categoryDao.rename(
                  id: category.id,
                  newName: name,
                ) !=
                null;
          } on ProtectedCategoryError {
            // Unreachable through this screen — the row offers no rename
            // affordance for a protected category — but caught rather than
            // allowed to crash the app if a future caller reaches it.
            return false;
          }
        },
        onDelete: (Category category, CategoryDeleteDecision decision) async {
          final CategorizationService? service = await ref.read(
            categorizationServiceProvider.future,
          );
          try {
            await service?.categoryDao.deleteCategory(
              id: category.id,
              decision: decision,
              actor: 'user',
            );
          } on ProtectedCategoryError {
            // Same reasoning as the rename above.
          }
        },
        onCreate:
            ({
              required String name,
              required String iconToken,
              required CategoryGroup group,
            }) async {
              final CategorizationService? service = await ref.read(
                categorizationServiceProvider.future,
              );
              if (service == null) {
                return null;
              }
              final CategoryRow? created = await service.categoryDao
                  .createCustom(
                    name: name,
                    iconToken: iconToken,
                    groupKey: group.key,
                  );
              if (created == null) {
                return null; // AC-C3.2 — duplicate name.
              }
              final List<Category> refreshed = await service.categories();
              return refreshed.firstWhere(
                (Category c) => c.id == created.id,
                orElse: () => DefaultCategories.uncategorized,
              );
            },
      ),
    );
  }
}

/// **S-44** — Recently Deleted, wired to the provider P3b-2 already built.
class RecentlyDeletedHost extends ConsumerWidget {
  const RecentlyDeletedHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<RecentlyDeletedView> view = ref.watch(
      recentlyDeletedProvider,
    );

    return view.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.recentlyDeletedTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: Text(l10n.recentlyDeletedTitle)),
        body: CategorySectionError(message: l10n.transactionUnavailable),
      ),
      data: (RecentlyDeletedView data) => RecentlyDeletedScreen(
        deleted: data.transactions,
        mergedInto: data.mergedInto,
        onRestore: (LedgerTransaction transaction) async {
          final TransactionEditService? edits = await ref.read(
            transactionEditServiceProvider.future,
          );
          // AC-B8.2. `restore` also clears both sides' merge pointers, so
          // restoring a row a merge absorbed undoes the merge — see
          // `recently_deleted_screen.dart` for why that matters on the one
          // screen built to reassure the user that nothing is lost.
          await edits?.restore(transaction.id);
        },
      ),
    );
  }
}

/// **S-16/S-17** — learned rules.
class LearnedRulesHost extends ConsumerWidget {
  const LearnedRulesHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<LearnedRule>> rules = ref.watch(learnedRulesProvider);
    final AsyncValue<CategoryResolver> resolver = ref.watch(
      categoryResolverProvider,
    );
    final AsyncValue<List<Category>> categories = ref.watch(categoriesProvider);

    return rules.when(
      loading: () => LearnedRulesScreen(
        rules: const <LearnedRule>[],
        resolver: CategoryResolver.defaults(),
        isLoading: true,
      ),
      error: (Object error, StackTrace stackTrace) => LearnedRulesScreen(
        rules: const <LearnedRule>[],
        resolver: CategoryResolver.defaults(),
        errorMessage: l10n.learnedRulesUnavailable,
      ),
      data: (List<LearnedRule> data) => LearnedRulesScreen(
        rules: data,
        resolver: resolver.value ?? CategoryResolver.defaults(),
        categories: categories.value ?? const <Category>[],
        onCountAffected: (LearnedRule rule, String categoryId) async {
          final CategoryCorrectionService? service = await ref.read(
            categoryCorrectionServiceProvider.future,
          );
          if (service == null) {
            return 0;
          }
          return service.countReapplyCandidates(
            merchantId: rule.merchantId,
            categoryId: categoryId,
          );
        },
        onEditRule: (RuleEditRequest request) async {
          final CategoryCorrectionService? service = await ref.read(
            categoryCorrectionServiceProvider.future,
          );
          if (service == null) {
            return null;
          }
          // **KHA-104's write-side guard covers this path too**, and that is
          // the reason the edit goes through `CategoryCorrectionService.editRule`
          // rather than calling `MerchantDao.upsertRule` from here: this screen
          // is the second writer of merchant rules, and it uses the same
          // validated entry point the first one does. A null result is the
          // refusal sentinel surfacing, and it stops the history rewrite too.
          final RuleReapplyResult? result = await service.editRule(
            ruleId: request.ruleId,
            categoryId: request.categoryId,
            reapplyToHistory: request.reapplyToHistory,
          );
          return result?.transactionsUpdated;
        },
        onDeleteRule: (LearnedRule rule) async {
          final CategoryCorrectionService? service = await ref.read(
            categoryCorrectionServiceProvider.future,
          );
          // AC-D4.3 — future transactions stop following it; already-
          // categorized transactions keep their categories.
          await service?.deleteRule(ruleId: rule.ruleId);
        },
      ),
    );
  }
}

/// **S-11** — one transaction, live.
class TransactionDetailHost extends ConsumerWidget {
  final int transactionId;
  final Duration autoConfirmDelay;

  const TransactionDetailHost({
    required this.transactionId,
    this.autoConfirmDelay = const Duration(seconds: 3),
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UnlockedDatabaseSession?> sessionAsync = ref.watch(
      unlockedDatabaseSessionProvider,
    );
    final AsyncValue<CategoryResolver> resolver = ref.watch(
      categoryResolverProvider,
    );

    return sessionAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
        body: CategorySectionError(message: l10n.transactionUnavailable),
      ),
      data: (UnlockedDatabaseSession? session) {
        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
            body: const CategoryLockedState(),
          );
        }
        return StreamBuilder<List<TransactionRow>>(
          // Watching the live list rather than reading one row once: a
          // correction made from this screen has to be visible on this screen,
          // and a one-shot read would leave the chip showing the old category
          // until the user navigated away and back.
          stream: session.transactionDao.watchLive(),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<TransactionRow>> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }
                final TransactionRow? row = snapshot.data
                    ?.where((TransactionRow r) => r.id == transactionId)
                    .firstOrNull;
                if (row == null) {
                  // Deleted, or merged away, while this screen was open. Saying
                  // so beats rendering a blank detail screen.
                  return Scaffold(
                    appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
                    body: CategoryEmptyState(
                      icon: Icons.receipt_long_outlined,
                      headline: l10n.transactionGoneTitle,
                      body: l10n.transactionGoneBody,
                    ),
                  );
                }

                final List<LedgerTransaction> mapped = toLedgerTransactions(
                  <TransactionRow>[row],
                );
                if (mapped.isEmpty) {
                  // KHA-74: the row exists but this build cannot read its
                  // amount. Never rendered as a transaction with a blank
                  // figure — the review inbox's data-problem banner is where
                  // this is explained.
                  return Scaffold(
                    appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
                    body: CategorySectionError(
                      message: l10n.transactionUnavailable,
                    ),
                  );
                }

                return TransactionDetailScreen(
                  transaction: mapped.single,
                  categoryAssignment: assignmentFor(
                    row,
                    resolver.value ?? CategoryResolver.defaults(),
                  ),
                  onEditCategory: () => correctTransactionCategory(
                    context: context,
                    ref: ref,
                    transactionId: transactionId,
                    autoConfirmDelay: autoConfirmDelay,
                  ),
                  loadCategoryProvenance: () async {
                    final CategorizationService? service = await ref.read(
                      categorizationServiceProvider.future,
                    );
                    if (service == null) {
                      return CategoryProvenance.unknown(transactionId);
                    }
                    return loadCategoryProvenance(
                      session: session,
                      merchantDao: service.merchantDao,
                      transactionId: transactionId,
                    );
                  },
                );
              },
        );
      },
    );
  }
}
