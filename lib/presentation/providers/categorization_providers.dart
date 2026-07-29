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
import '../screens/category_management_screen.dart' show CategoryListItem;
import 'app_providers.dart';

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
) => CategoryAssignment(
  category: resolver.resolve(row.categoryId),
  band: ConfidenceBand.of(
    source: row.categorySource,
    confidence: row.categoryConfidence,
    categoryId: row.categoryId,
    autoApplyThreshold: CategorizationConfig.autoApplyThreshold,
  ),
  confidence: row.categoryConfidence,
  needsReview: row.needsReview,
  reviewReason: row.reviewReason,
);

/// **AC-C4.2 — the review count, visible from the main screen.**
///
/// KHA-32's done-check states how it must be computed:
///
/// > *"The review count on the home screen equals the number of flagged plus
/// > uncategorized items, verified against the data layer."*
///
/// So it is derived from the ledger on every emission rather than accumulated:
/// a counter that is incremented and decremented drifts, and this one is
/// checkable against the rows it claims to describe.
///
/// Deliberately a **union, not a sum**: a transaction that is both
/// uncategorized *and* flagged is one thing needing review, and adding the two
/// figures would tell the user there are twice as many problems as there are.
final StreamProvider<ReviewCounts> reviewCountsProvider =
    StreamProvider<ReviewCounts>((Ref ref) async* {
      final UnlockedDatabaseSession? session = await ref.watch(
        unlockedDatabaseSessionProvider.future,
      );
      if (session == null) {
        yield ReviewCounts.empty;
        return;
      }
      // **One stream, held for this provider's whole lifetime.**
      //
      // An earlier draft also folded in the unparsed-message queue, by reading
      // `reviewQueueProvider`. Two problems, and the second is the one that
      // decided it:
      //
      //  1. KHA-32's done-check defines this number precisely — *"the number of
      //     flagged plus uncategorized items"* — and says nothing about
      //     unparsed messages. Adding them would make the figure unverifiable
      //     against the criterion it exists to satisfy. S-18's tabs already
      //     carry their own counts, which is where that question belongs.
      //  2. Combining a second Drift stream means **cancelling** one, and a
      //     cancelled Drift query stream schedules a zero-duration cleanup
      //     timer (`StreamQueryStore.markAsClosed`). Held over into a disposed
      //     widget tree that is a *"Timer is still pending"* failure; in the
      //     app it is a subscription churning on every emission. One
      //     subscription, opened once and closed when the provider is, has
      //     neither problem.
      await for (final List<TransactionRow> rows
          in session.transactionDao.watchLive()) {
        yield ReviewCounts.fromRows(rows);
      }
    });

/// The figures behind AC-C4.2's badge, kept apart rather than pre-summed so a
/// screen can explain what the number is made of.
final class ReviewCounts {
  /// Rows carrying `needs_review` — duplicates, transfers, low-confidence
  /// categorizations.
  final int flagged;

  /// Rows with no category (AC-C1.2's *"assigned Uncategorized and counted in
  /// the review queue"*).
  final int uncategorized;

  /// The **union** of the two — what the badge shows, and KHA-32's done-check
  /// figure verbatim. See [reviewCountsProvider] for why this is not
  /// `flagged + uncategorized`.
  final int needingAttention;

  const ReviewCounts({
    required this.flagged,
    required this.uncategorized,
    required this.needingAttention,
  });

  /// The AC-C4.2 computation itself, as a pure function over rows.
  ///
  /// Separated from the provider so a test can assert the arithmetic against a
  /// list it built by hand — KHA-32's done-check says the count must be
  /// *"verified against the data layer"*, and a figure that can only be
  /// observed through a stream is one nobody verifies.
  factory ReviewCounts.fromRows(List<TransactionRow> rows) {
    int flagged = 0;
    int uncategorized = 0;
    int needingAttention = 0;
    for (final TransactionRow row in rows) {
      final bool isFlagged = row.needsReview;
      final bool isUncategorized = row.categoryId == null;
      if (isFlagged) {
        flagged++;
      }
      if (isUncategorized) {
        uncategorized++;
      }
      if (isFlagged || isUncategorized) {
        needingAttention++;
      }
    }
    return ReviewCounts(
      flagged: flagged,
      uncategorized: uncategorized,
      needingAttention: needingAttention,
    );
  }

  static const ReviewCounts empty = ReviewCounts(
    flagged: 0,
    uncategorized: 0,
    needingAttention: 0,
  );

  /// The single figure S-08's `ReviewCountCard` renders.
  int get total => needingAttention;

  @override
  String toString() => 'ReviewCounts($total)';
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
