/// Riverpod wiring for the P4a categorization spine (KHA-30, KHA-31).
///
/// ## This file is the composition root for the learning loop
///
/// Two things happen here that happen nowhere else, and both are the reason
/// the P1 review's rule — *"a component with no production call site is
/// library code, not shipped behaviour"* — is satisfied for this phase:
///
///  1. **The starter list is seeded.** [categorizationServiceProvider] calls
///     `ensureDefaultsSeeded` the first time it is built for an unlocked
///     session, so design §4's thirteen categories exist in the database of a
///     real install and not only in tests.
///  2. **The categorizer is bound into ingestion.**
///     [ingestionCategorizerProvider] adapts `CategorizationService` to the
///     `CategorizeWrittenTransaction` callback `IngestionPipeline` accepts.
///     That adapter lives *here*, in the layer that already depends on both
///     features, which is how architecture §3's "`ingestion` never imports
///     `categorization`" is honoured — the same technique
///     `ledger_providers.dart` uses to keep `features/ledger` from importing
///     `features/parsing`.
///
/// **P4b routes the screens this file used to say did not exist.** The header
/// note below is kept, corrected rather than deleted, because it recorded a
/// real gate:
///
/// > ~~"No screen is routed by this file, and none exists yet. P4a is the data
/// > and domain spine; the pickers, the review inbox and the learned-rules
/// > screen are P4b (KHA-32/33/34), which is gated behind KHA-87/88."~~
///
/// That gate is discharged: KHA-87/88/94/96/98/99/100/101/102/103/104/105 are
/// all closed, and KHA-106/107 land in the same PR as these screens. So this
/// file now also supplies the read models S-14/S-16/S-18 render and the write
/// service they call — see the second half of the file.
///
/// ## Everything is null while the app is locked
///
/// Like every other provider in this app: ADR-005 makes the lock
/// cryptographic, so while locked there is no database and the honest value is
/// nothing at all.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/categorization_config.dart';
import '../../data/dao/audit_log_dao.dart';
import '../../data/dao/category_dao.dart';
import '../../data/dao/merchant_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';
import '../../features/categorization/categories.dart';
import '../../features/categorization/categorization_service.dart';
import '../../features/categorization/category_correction.dart';
import '../../features/categorization/learned_rules.dart';
import '../../features/ingestion/ingestion_pipeline.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../screens/category_management_screen.dart' show CategoryListItem;
import 'app_providers.dart';
// KHA-144: Home's review count is composed from the same providers S-18's tabs
// render, so the two cannot disagree. Dart permits these cyclic library imports
// and the three provider files already reference each other both ways.
import 'ingestion_providers.dart' show reviewQueueProvider;
import 'ledger_providers.dart' show ReviewInboxView, reviewInboxProvider;

/// The categorization DAOs and service for the current unlocked session, with
/// the default categories already seeded.
final FutureProvider<CategorizationService?> categorizationServiceProvider =
    FutureProvider<CategorizationService?>((Ref ref) async {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        return null;
      }

      final CategorizationService service = CategorizationService(
        categoryDao: CategoryDao(session.database, session.auditLogDao),
        merchantDao: MerchantDao(session.database, session.auditLogDao),
        transactionDao: session.transactionDao,
      );

      // Idempotent (`INSERT OR IGNORE` per row), so running it on every
      // unlocked session costs thirteen no-op statements and guarantees that
      // the row AC-C1.1 depends on exists — including on an install that
      // upgraded from schema v5, where the migration deliberately seeded
      // nothing (see `app_database.dart`).
      await service.ensureDefaultsSeeded();
      return service;
    });

/// The adapter the ingestion pipeline calls after writing a transaction.
///
/// Returns null while locked, which the pipeline handles by simply not
/// categorising — the same shape as a missing `entityResolver`.
final FutureProvider<CategorizeWrittenTransaction?>
ingestionCategorizerProvider = FutureProvider<CategorizeWrittenTransaction?>((
  Ref ref,
) async {
  final CategorizationService? service = await ref.watch(
    categorizationServiceProvider.future,
  );
  if (service == null) {
    return null;
  }
  return (int transactionId) =>
      service.categorizeTransaction(transactionId: transactionId);
});

/// Every category, live — the source for every picker (AC-C3.1's *"available
/// in every picker"*) and for the breakdown's resolver.
///
/// A stream so a category created in one place appears everywhere else with no
/// manual refresh (architecture §7.5).
final StreamProvider<List<Category>> categoriesProvider =
    StreamProvider<List<Category>>((Ref ref) async* {
      final CategorizationService? service = await ref.watch(
        categorizationServiceProvider.future,
      );
      if (service == null) {
        yield const <Category>[];
        return;
      }
      // `watchAll()` emits its current value immediately and again on every
      // change, so this is a complete stream on its own — no priming yield.
      // Each emission is re-read through the service rather than mapped here,
      // so the row → domain conversion has exactly one implementation.
      yield* service.categoryDao.watchAll().asyncMap(
        (List<CategoryRow> _) => service.categories(),
      );
    });

/// A resolver over the current categories — what makes AC-C1.1's *"never a
/// blank"* true for anything that renders a transaction.
final FutureProvider<CategoryResolver> categoryResolverProvider =
    FutureProvider<CategoryResolver>((Ref ref) async {
      final List<Category> categories = await ref.watch(
        categoriesProvider.future,
      );
      // Falls back to the compiled-in list while locked or before seeding, so
      // a caller never has to handle "no resolver yet".
      return categories.isEmpty
          ? CategoryResolver.defaults()
          : CategoryResolver(categories);
    });

// =========================================================================
// P4b — the read models and the write service the four screens use
// (KHA-32, KHA-33, KHA-34, KHA-97).
//
// Everything below follows the same two rules as everything above:
//
//  1. **Null / empty while locked.** ADR-005 makes the lock cryptographic, so
//     there is no database and the honest value is nothing at all — never a
//     stale cache of the last unlocked state.
//  2. **Streams, not polling.** A background ingestion run that flags a
//     transaction updates the review count and the inbox with no manual
//     refresh (architecture §7.5).
// =========================================================================

/// The multi-row write path — KHA-33's bulk/undo and KHA-34's re-apply.
final FutureProvider<CategoryCorrectionService?>
categoryCorrectionServiceProvider = FutureProvider<CategoryCorrectionService?>((
  Ref ref,
) async {
  final UnlockedDatabaseSession? session = await ref.watch(
    unlockedDatabaseSessionProvider.future,
  );
  final CategorizationService? service = await ref.watch(
    categorizationServiceProvider.future,
  );
  if (session == null || service == null) {
    return null;
  }
  return CategoryCorrectionService(
    categorization: service,
    transactionDao: session.transactionDao,
    merchantDao: service.merchantDao,
  );
});

/// **S-14's rows** — every category with how many transactions use it.
///
/// The count is what S-15's dialog quotes back when the user tries to delete
/// ("this category has 12 transactions"), so it is read from the same method
/// the delete path uses rather than derived from a list this screen happens to
/// hold. One query per category is deliberate: there are thirteen of them plus
/// whatever the user created, and a hand-rolled `GROUP BY` here would be a
/// second implementation of "which transactions count as using a category"
/// that could disagree with `CategoryDao.countTransactionsUsing`.
final StreamProvider<List<CategoryListItem>> categoryListProvider =
    StreamProvider<List<CategoryListItem>>((Ref ref) async* {
      final CategorizationService? service = await ref.watch(
        categorizationServiceProvider.future,
      );
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (service == null || session == null) {
        yield const <CategoryListItem>[];
        return;
      }

      // Driven off the *transaction* stream as well as the category list:
      // deleting a transaction changes a count on this screen, and a screen
      // whose numbers only refreshed when a category changed would show a
      // stale "12 transactions" for as long as the user stayed on it.
      await for (final List<TransactionRow> _
          in session.transactionDao.watchLive()) {
        final List<Category> categories = await service.categories();
        yield <CategoryListItem>[
          for (final Category category in categories)
            CategoryListItem(
              category: category,
              transactionCount: await service.categoryDao
                  .countTransactionsUsing(category.id),
            ),
        ];
      }
    });

/// **S-16's rows** — every learned rule with its merchant and category
/// (AC-D4.1).
///
/// `watchAllRules` rather than `enabledRules`: this is the screen a user opens
/// to *find* a rule that is behaving oddly, and a rule that exists but is
/// disabled is exactly the kind of thing that would otherwise be invisible and
/// inexplicable.
final StreamProvider<List<LearnedRule>> learnedRulesProvider =
    StreamProvider<List<LearnedRule>>((Ref ref) async* {
      final CategorizationService? service = await ref.watch(
        categorizationServiceProvider.future,
      );
      if (service == null) {
        yield const <LearnedRule>[];
        return;
      }

      await for (final List<MerchantRuleRow> rules
          in service.merchantDao.watchAllRules()) {
        final Map<int, MerchantRow> merchants = <int, MerchantRow>{
          for (final MerchantRow merchant
              in await service.merchantDao.allMerchants())
            merchant.id: merchant,
        };
        yield <LearnedRule>[
          for (final MerchantRuleRow rule in rules)
            // A rule whose merchant row is gone is dropped rather than rendered
            // with a placeholder name. `merchant_rule.merchant_id` is a foreign
            // key so this should be unreachable; if it ever happens, a row
            // reading "→ Groceries" with no merchant is worse than one missing
            // row, because the user cannot act on it.
            if (merchants[rule.merchantId] case final MerchantRow merchant)
              LearnedRule(
                ruleId: rule.id,
                merchantId: rule.merchantId,
                merchantName: merchant.canonicalName,
                merchantKey: merchant.merchantKey,
                categoryId: rule.categoryId,
                source: rule.source,
                appliedCount: rule.appliedCount,
                updatedAt: rule.updatedAt,
                lastAppliedAt: rule.lastAppliedAt,
              ),
        ];
      }
    });

/// **S-18's low-confidence tab** — every transaction the app has flagged.
///
/// Includes ADR-017's possible duplicates *and* KHA-32's categorization flags;
/// `NeedsReviewScreen` tells them apart by `reviewReason`. One stream rather
/// than two, because they are one column and splitting the read would let the
/// two halves disagree about what "flagged" means.
final StreamProvider<List<FlaggedTransactionItem>> flaggedTransactionsProvider =
    StreamProvider<List<FlaggedTransactionItem>>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield const <FlaggedTransactionItem>[];
        return;
      }
      yield* session.transactionDao.watchNeedingReview().map(
        (List<TransactionRow> rows) => <FlaggedTransactionItem>[
          for (final TransactionRow row in rows)
            FlaggedTransactionItem(
              transactionId: row.id,
              // The exact decimal string, straight from the column. ADR-002:
              // nothing on this read path parses a figure into a double, and
              // `amountMinor` — the non-authoritative indexing column — is
              // deliberately not touched.
              amount: row.amountAmount,
              currencyCode: row.amountCurrency,
              merchantRawText: row.merchantRawText,
              occurredAt: row.occurredAt,
              reviewReason: row.reviewReason,
              possibleDuplicateOfId: row.possibleDuplicateOfId,
            ),
        ],
      );
    });

/// Each flagged transaction's category and confidence band, for the chips S-18
/// renders (KHA-32).
///
/// Keyed by transaction id and supplied alongside the list rather than folded
/// into `FlaggedTransactionItem`, because that type lives in
/// `features/ingestion` and architecture §3 forbids
/// `ingestion → categorization`. This is the layer that already depends on both.
final StreamProvider<Map<int, CategoryAssignment>>
flaggedCategoryAssignmentsProvider =
    StreamProvider<Map<int, CategoryAssignment>>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield const <int, CategoryAssignment>{};
        return;
      }
      final CategoryResolver resolver = await ref.watch(
        categoryResolverProvider.future,
      );
      yield* session.transactionDao.watchNeedingReview().map(
        (List<TransactionRow> rows) => <int, CategoryAssignment>{
          for (final TransactionRow row in rows)
            row.id: assignmentFor(row, resolver),
        },
      );
    });

/// Bands a stored row into what a `CategoryChip` needs.
///
/// Exposed (rather than private) so a screen, a provider and a test all band a
/// row the same way: what counts as "confident" is a product decision, and
/// three copies of it would be three chances to disagree about what the user is
/// being told.
CategoryAssignment assignmentFor(
  TransactionRow row,
  CategoryResolver resolver,
) => _assignment(
  resolver: resolver,
  categoryId: row.categoryId,
  categorySource: row.categorySource,
  categoryConfidence: row.categoryConfidence,
  needsReview: row.needsReview,
  reviewReason: row.reviewReason,
);

/// The same banding, for a [LedgerTransaction] rather than a raw
/// [TransactionRow] (P5a, KHA-36).
///
/// The list screens work in domain objects — they need `Money`, the resolved
/// instrument and the internal-transfer verdict, none of which a raw row
/// carries — so they cannot call [assignmentFor]. Both delegate to
/// [_assignment] rather than one re-deriving the band, because "what counts as
/// confident" is a product decision and two implementations of it is two
/// chances to tell the user different things about the same transaction.
CategoryAssignment assignmentForTransaction(
  LedgerTransaction transaction,
  CategoryResolver resolver,
) => _assignment(
  resolver: resolver,
  categoryId: transaction.categoryId,
  categorySource: transaction.categorySource,
  categoryConfidence: transaction.categoryConfidence,
  needsReview: transaction.needsReview,
  reviewReason: transaction.reviewReason,
);

CategoryAssignment _assignment({
  required CategoryResolver resolver,
  required String? categoryId,
  required String? categorySource,
  required double? categoryConfidence,
  required bool needsReview,
  required String? reviewReason,
}) => CategoryAssignment(
  category: resolver.resolve(categoryId),
  band: ConfidenceBand.of(
    source: categorySource,
    confidence: categoryConfidence,
    categoryId: categoryId,
    autoApplyThreshold: CategorizationConfig.autoApplyThreshold,
  ),
  confidence: categoryConfidence,
  needsReview: needsReview,
  reviewReason: reviewReason,
);

/// Every **live transaction row**, for counting only (KHA-144).
///
/// `watchLive()` verbatim — deliberately the *same* query the ledger and
/// `flaggedTransactionsProvider` read from, so Home's figure cannot describe a
/// narrower set of rows than the lists it claims to summarise. That divergence
/// is precisely what KHA-144 was.
///
/// Raw rows rather than domain objects because the three fields the count needs
/// (`needsReview`, `categoryId`, `id`) all live on the row, and mapping several
/// hundred rows into `LedgerTransaction`s just to count them would repeat work
/// `ledgerViewProvider` already does for the screen beside it.
final StreamProvider<List<TransactionRow>> reviewCountRowsProvider =
    StreamProvider<List<TransactionRow>>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        // Locked: ADR-005 makes the lock cryptographic, so there is no database
        // and "nothing" is the truthful answer rather than a stale cache.
        yield const <TransactionRow>[];
        return;
      }
      // One subscription, opened once and closed when the provider is disposed
      // — see [reviewCountsProvider] for why that property matters here.
      yield* session.transactionDao.watchLive();
    });

/// **AC-C4.2 — the count of items needing review, visible from the main
/// screen.**
///
/// ## KHA-144 — what this used to count, and why it was wrong
///
/// Until this fix the figure was computed from the **transactions table
/// alone**. On a real device that produced the worst possible outcome: 833
/// genuine bank messages sat in `More → Organising → Needs review → Not
/// understood`, correctly retained per AC-A4.1/NFR-A7 — and Home said *"All
/// caught up"*, with the card not even tappable, because none of those 833
/// rows is a transaction. The app was doing exactly the right thing and
/// reporting that it had nothing to do.
///
/// The old code documented that exclusion as deliberate, citing KHA-32's
/// done-check (*"flagged plus uncategorized items"*). That reasoning read one
/// issue's done-check as if it were the acceptance criterion. Reading the ACs
/// themselves, together, gives the opposite answer:
///
///  - **AC-C4.2** — *"the count of **items needing review** is visible from the
///    main screen."* Not "the count of flagged transactions". The Needs Review
///    inbox (S-18) is what "items needing review" denotes.
///  - **AC-A4.1** — an unparsed financial SMS *"appears in a **Needs review** /
///    unparsed list"*. It is an item in that queue by the PRD's own words.
///  - **AC-C1.2** — an uncategorized transaction is *"counted in the review
///    queue"*.
///  - **AC-B11.2** — an undecidable transfer is *"**flagged for review**"*.
///  - **design.md Flow C** settles it independently: *"S-08 (tap review count)
///    → S-18 [**Unparsed** tab] → S-19"*. Home's count is the entry point to
///    the unparsed tab, so a count that excludes unparsed items makes the
///    product's own documented flow unreachable — which is exactly what the
///    untappable "All caught up" card was.
///
/// So the figure is now the whole inbox: S-18's three tabs, plus AC-C1.2's
/// uncategorized rows.
///
/// ## Composed from three providers rather than one merged stream
///
/// The old comment gave a real reason not to `await for` over two Drift
/// streams in one provider body: combining them means **cancelling** one, and a
/// cancelled Drift query stream schedules a zero-duration cleanup timer
/// (`StreamQueryStore.markAsClosed`) that surfaces as *"A Timer is still
/// pending"* in a widget test and as subscription churn on a device.
///
/// That objection is answered rather than ignored. Each source stays in **its
/// own** provider, so Riverpod owns exactly one subscription per source for
/// that provider's lifetime and nothing is ever cancelled mid-flight; this
/// provider is a plain (synchronous) `Provider` that only *combines the
/// `AsyncValue`s they already expose*. It opens no stream of its own.
///
/// Reusing `reviewQueueProvider` and `reviewInboxProvider` — the very providers
/// `NeedsReviewHost` renders the tabs from — is the other half of the fix: the
/// count and the queue are now structurally incapable of disagreeing, because
/// they are the same reads.
final Provider<AsyncValue<ReviewCounts>> reviewCountsProvider =
    Provider<AsyncValue<ReviewCounts>>((Ref ref) {
      final AsyncValue<List<TransactionRow>> rows = ref.watch(
        reviewCountRowsProvider,
      );
      // S-18's "Not understood" tab (AC-A4.1) — raw messages, not transactions.
      final AsyncValue<List<ReviewQueueItem>> unparsed = ref.watch(
        reviewQueueProvider,
      );
      // S-18's "Transfers" tab (AC-B11.2).
      final AsyncValue<ReviewInboxView> inbox = ref.watch(reviewInboxProvider);

      // design.md §3.4's Error state, ahead of everything: a failed read must
      // never render as a reassuring zero. `ReviewCountCard` turns this into an
      // honest message, and "All caught up" is the one thing it must not say
      // when it does not know.
      for (final AsyncValue<Object?> part in <AsyncValue<Object?>>[
        rows,
        unparsed,
        inbox,
      ]) {
        if (part.hasError) {
          return AsyncValue<ReviewCounts>.error(
            part.error!,
            part.stackTrace ?? StackTrace.empty,
          );
        }
      }

      // `.value` is non-null from the first emission onward and stays non-null
      // across a refresh, so a re-read shows the previous figure rather than
      // flickering back to a spinner.
      final List<TransactionRow>? liveRows = rows.value;
      final List<ReviewQueueItem>? queue = unparsed.value;
      final ReviewInboxView? view = inbox.value;
      if (liveRows == null || queue == null || view == null) {
        return const AsyncValue<ReviewCounts>.loading();
      }

      return AsyncValue<ReviewCounts>.data(
        ReviewCounts.from(
          rows: liveRows,
          transferTransactionIds: <int>{
            for (final TransferReviewItem item in view.transfers)
              item.transactionId,
          },
          unparsedMessages: queue.length,
        ),
      );
    });

/// The figures behind AC-C4.2's badge, kept apart rather than pre-summed so a
/// screen can explain what the number is made of.
final class ReviewCounts {
  /// Rows carrying `needs_review` — duplicates, low-confidence
  /// categorizations. S-18's "Low confidence" tab.
  final int flagged;

  /// Rows with no category (AC-C1.2's *"assigned Uncategorized and counted in
  /// the review queue"*).
  final int uncategorized;

  /// Rows with an open "is this account yours?" question (AC-B11.2). S-18's
  /// "Transfers" tab.
  ///
  /// Derived by the internal-transfer detector rather than stored on the row,
  /// which is why it arrives as a set of ids rather than a column.
  final int transfers;

  /// Unparsed financial messages in the raw-message queue (AC-A4.1). S-18's
  /// "Not understood" tab — **833 of these on the device that raised KHA-144.**
  final int unparsed;

  /// The **union** of [flagged], [uncategorized] and [transfers] — one *row*
  /// counted once however many questions it raises.
  ///
  /// A union rather than a sum because a transaction that is uncategorized
  /// *and* flagged is one thing to look at, and adding the figures would tell
  /// the user there are twice as many problems as there are.
  final int needingAttention;

  const ReviewCounts({
    required this.flagged,
    required this.uncategorized,
    required this.needingAttention,
    this.transfers = 0,
    this.unparsed = 0,
  });

  /// The AC-C4.2 computation itself, as a pure function over its inputs.
  ///
  /// Separated from the provider so a test can assert the arithmetic against
  /// values it built by hand — KHA-32's done-check says the count must be
  /// *"verified against the data layer"*, and a figure that can only be
  /// observed through a stream is one nobody verifies.
  factory ReviewCounts.from({
    required List<TransactionRow> rows,
    Set<int> transferTransactionIds = const <int>{},
    int unparsedMessages = 0,
  }) {
    int flagged = 0;
    int uncategorized = 0;
    int transfers = 0;
    int needingAttention = 0;
    for (final TransactionRow row in rows) {
      final bool isFlagged = row.needsReview;
      final bool isUncategorized = row.categoryId == null;
      final bool hasTransferQuestion = transferTransactionIds.contains(row.id);
      if (isFlagged) {
        flagged++;
      }
      if (isUncategorized) {
        uncategorized++;
      }
      if (hasTransferQuestion) {
        transfers++;
      }
      if (isFlagged || isUncategorized || hasTransferQuestion) {
        needingAttention++;
      }
    }
    return ReviewCounts(
      flagged: flagged,
      uncategorized: uncategorized,
      transfers: transfers,
      unparsed: unparsedMessages,
      needingAttention: needingAttention,
    );
  }

  /// The transaction-only half, for callers that have rows and nothing else.
  ///
  /// Kept because several tests and the QA probe suite assert the arithmetic
  /// this way. It is **not** the figure Home shows — [total] adds the unparsed
  /// queue on top — so nothing should treat it as AC-C4.2's number.
  factory ReviewCounts.fromRows(List<TransactionRow> rows) =>
      ReviewCounts.from(rows: rows);

  static const ReviewCounts empty = ReviewCounts(
    flagged: 0,
    uncategorized: 0,
    needingAttention: 0,
  );

  /// The single figure S-08's `ReviewCountCard` renders.
  ///
  /// A **sum**, not a union, and that is safe rather than sloppy: an unparsed
  /// message is by definition one the parser could not turn into a transaction,
  /// so it has no row in the transactions table and cannot already be inside
  /// [needingAttention]. The two sets are disjoint by construction.
  int get total => needingAttention + unparsed;

  @override
  String toString() =>
      'ReviewCounts(total: $total, unparsed: $unparsed, '
      'flagged: $flagged, uncategorized: $uncategorized, '
      'transfers: $transfers)';
}

/// **KHA-31 — "why is this categorized this way?", assembled.**
///
/// A function rather than a provider family: the detail screen calls it once,
/// on demand, when the user taps the affordance. A family provider would keep
/// one cached entry per transaction the user ever looked at, for an answer that
/// is only interesting while it is on screen.
Future<CategoryProvenance> loadCategoryProvenance({
  required UnlockedDatabaseSession session,
  required MerchantDao merchantDao,
  required int transactionId,
}) async {
  final TransactionRow? row = await session.transactionDao.byIdOrNull(
    transactionId,
  );
  if (row == null) {
    return CategoryProvenance.unknown(transactionId);
  }

  // The rule, when the row still names one. KHA-103 clears `category_rule_id`
  // together with the rule it named, so a non-null id here should be a live
  // rule — but it is *read* rather than assumed, because this screen is the one
  // place where being wrong about that would print a merchant name whose rule
  // no longer exists.
  LearnedRule? rule;
  final int? ruleId = row.categoryRuleId;
  if (ruleId != null) {
    final MerchantRuleRow? ruleRow = await merchantDao.ruleById(ruleId);
    final MerchantRow? merchant = ruleRow == null
        ? null
        : await merchantDao.byId(ruleRow.merchantId);
    if (ruleRow != null && merchant != null) {
      rule = LearnedRule(
        ruleId: ruleRow.id,
        merchantId: ruleRow.merchantId,
        merchantName: merchant.canonicalName,
        merchantKey: merchant.merchantKey,
        categoryId: ruleRow.categoryId,
        source: ruleRow.source,
        appliedCount: ruleRow.appliedCount,
        updatedAt: ruleRow.updatedAt,
        lastAppliedAt: ruleRow.lastAppliedAt,
      );
    }
  }

  final List<AuditEntryRow> entries = await session.auditLogDao.queryFor(
    'transaction',
    transactionId.toString(),
  );

  return CategoryProvenance(
    transactionId: transactionId,
    source: row.categorySource ?? StoredCategorySource.none,
    categoryId: row.categoryId,
    confidence: row.categoryConfidence,
    rule: rule,
    auditTrail: <CategoryAuditEntry>[
      for (final AuditEntryRow entry in entries)
        // Only `categorize` entries. An edit to the amount is real history and
        // belongs in the full change-history screen (S-45), but it is not an
        // answer to "why is this categorized this way", and putting it here
        // would bury the entries that are.
        if (entry.action == 'categorize')
          CategoryAuditEntry(
            changedAt: entry.changedAt,
            actor: entry.actor,
            actorDetail: entry.actorDetail,
            fromCategoryId: _categoryFieldValue(
              entry,
              from: true,
              dao: session.auditLogDao,
            ),
            toCategoryId: _categoryFieldValue(
              entry,
              from: false,
              dao: session.auditLogDao,
            ),
          ),
    ],
  );
}

/// Pulls the `categoryId` before/after out of an audit entry's encoded field
/// changes, or null when the entry does not carry one.
String? _categoryFieldValue(
  AuditEntryRow entry, {
  required bool from,
  required AuditLogDao dao,
}) {
  for (final AuditFieldChange change in dao.decodeFieldChanges(entry)) {
    if (change.field == TransactionField.categoryId) {
      return from ? change.from : change.to;
    }
  }
  return null;
}
