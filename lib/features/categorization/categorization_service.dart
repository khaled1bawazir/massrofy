/// **The learning loop, assembled** — KHA-30 + KHA-31, Epics C and D.
///
/// This is the one place the three halves meet: the category store, the
/// merchant identity store, and the tiered matcher. Everything with a decision
/// in it lives in a pure function elsewhere (`MerchantMatcher.match`,
/// `MerchantKey.of`); this class is the wiring that reads rows, calls them, and
/// writes the result through the DAOs.
///
/// ## The electric-bill case, end to end (AC-D2.1)
///
/// > *Once the user has categorized a payment to the electric utility as
/// > Utilities, a new message from that same utility arrives ALREADY
/// > categorized as Utilities, with no user action.*
///
/// Both halves are here:
///
///  1. [applyUserCategory] — the user corrects one transaction. It writes the
///     category **and**, because `learnRule` defaults to true, creates the
///     rule `merchant → category` (AC-D1.1). A second correction to a
///     different category updates that same rule rather than adding a rival
///     (AC-D1.2), because `merchant_rule.merchant_id` is `UNIQUE`.
///  2. [categorizeTransaction] — ingestion calls this for each newly written
///     transaction. The next bill from the same utility produces the same
///     merchant key, hits the rule at tier T1, and is categorised with no user
///     action and an audit entry attributed to the system.
///
/// `test/features/categorization/electric_bill_test.dart` runs exactly that
/// sequence against a real database.
///
/// ## What this class will not do
///
///  - **Overwrite a person's choice** (AC-D3.1/D3.2). Checked here, and again
///    at the write boundary in `TransactionDao.applyAutomaticCategory`.
///  - **Create or mutate a rule automatically** (ADR-008). The only caller of
///    `MerchantDao.upsertRule` in this file is [applyUserCategory].
///  - **Assert that two spellings are the same merchant on its own
///    initiative.** A merchant row is created for a key the app has not seen;
///    an *alias* linking two keys is only ever created by the user
///    ([linkMerchantAlias]).
library;

import '../../data/dao/category_dao.dart';
import '../../data/dao/merchant_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';
import 'categories.dart';
import 'merchant_key.dart';
import 'merchant_matcher.dart';

/// What [CategorizationService.categorizeTransaction] did, and why.
///
/// An enum rather than a bool because "we did not categorise this" has five
/// genuinely different causes and the caller (and the tests) should be able to
/// tell them apart — *"the user already decided"* and *"we have never seen
/// this shop"* call for completely different follow-up.
enum CategorizationResult {
  /// A rule matched at or above the threshold and the category was written,
  /// with an audit entry attributed to `system_rule`.
  applied,

  /// A candidate matched below `autoApplyThreshold`, or matched only at T4
  /// (which never auto-applies). Left uncategorized and flagged for review.
  flaggedLowConfidence,

  /// No candidate matched at any tier — AC-D2.4. Left uncategorized and
  /// flagged, with the merchant recorded so the *next* message from this shop
  /// resolves to the same identity.
  ///
  /// Covers both *"never seen this shop"* and *"seen it, but nobody has said
  /// where its spending belongs"*; the two are told apart on the row itself by
  /// `review_reason` ([CategoryReviewReason.unknownMerchant] versus
  /// [CategoryReviewReason.noRuleForMerchant]), because the review inbox asks
  /// the user a different question for each.
  flaggedUnknownMerchant,

  /// The transaction carries no merchant text at all (a transfer, an ATM
  /// withdrawal). Nothing is written: see [MerchantKey.ofOrNull] for why an
  /// empty key must never become a merchant.
  skippedNoMerchant,

  /// A person has already answered this question (AC-D3.1), or the row already
  /// carries a category. Nothing is written.
  skippedAlreadyDecided,
}

/// The outcome, with enough detail for a review screen to explain itself.
final class CategorizationOutcome {
  final CategorizationResult result;

  /// The category that was applied, when [result] is
  /// [CategorizationResult.applied].
  final String? categoryId;

  /// The merchant this transaction was resolved to, when one could be.
  final int? merchantId;

  /// The matcher's verdict, verbatim — including a T4 "did you mean…"
  /// suggestion, which is deliberately *not* persisted anywhere. The matcher
  /// is pure and cheap, so P4b's review screen re-runs it to render the
  /// suggestion rather than this build adding a column for a guess.
  final MerchantMatch match;

  const CategorizationOutcome({
    required this.result,
    required this.match,
    this.categoryId,
    this.merchantId,
  });

  @override
  String toString() => 'CategorizationOutcome(${result.name})';
}

/// Orchestrates categories, merchants, rules and matching.
final class CategorizationService {
  final CategoryDao categoryDao;
  final MerchantDao merchantDao;
  final TransactionDao transactionDao;

  const CategorizationService({
    required this.categoryDao,
    required this.merchantDao,
    required this.transactionDao,
  });

  /// Writes the design §4 starter list if it is not already there — idempotent,
  /// so it is safe (and intended) to call on every unlocked session.
  ///
  /// Seeding lives here rather than in the schema migration so there is one
  /// implementation shared by fresh installs, upgrades and tests. A migration
  /// that seeded separately would be a second copy of design §4 that could
  /// drift from `DefaultCategories.seed`.
  Future<void> ensureDefaultsSeeded({DateTime? now}) async {
    for (final Category category in DefaultCategories.seed) {
      await categoryDao.ensureSeedRow(
        id: category.id,
        key: category.key,
        nameAr: category.nameAr,
        nameEn: category.nameEn,
        iconToken: category.iconToken,
        colorToken: category.colorToken,
        groupKey: category.group.key,
        isProtected: category.isProtected,
        sortOrder: category.sortOrder,
        now: now,
      );
    }
  }

  /// Every category, as domain values.
  Future<List<Category>> categories() async =>
      (await categoryDao.all()).map(_toCategory).toList();

  /// A resolver over the stored categories — the thing that makes AC-C1.1's
  /// *"never a blank"* true at read time.
  ///
  /// Falls back to the compiled-in seed list when the table is empty, so a
  /// read that happens before [ensureDefaultsSeeded] still resolves to
  /// *Uncategorized* rather than to nothing.
  Future<CategoryResolver> resolver() async {
    final List<Category> stored = await categories();
    return stored.isEmpty
        ? CategoryResolver.defaults()
        : CategoryResolver(stored);
  }

  /// Assembles the matcher's input from the three stored tables.
  ///
  /// One merchant, its user-linked aliases, and its rule if it has one. Built
  /// in Dart rather than as a SQL join so the matcher stays a pure function
  /// over plain values — see `merchant_matcher.dart`'s library note.
  ///
  /// ## KHA-104 — the read half of the dangling-rule guard
  ///
  /// A rule whose `category_id` names no category is dropped here, so it cannot
  /// reach the matcher at all. `MerchantDao.upsertRule` refuses to *write* such
  /// a rule; this defends the rows that are already stored — written before
  /// that check existed, or by raw SQL, or by a future writer that has not read
  /// this file. Two independent guards on the same property, deliberately, in
  /// the way AC-D3.1's protection is doubled up.
  ///
  /// **Dropping the rule, not the merchant.** The candidate stays in the list
  /// with `categoryId` and `ruleId` null, so the shop is still *identified* —
  /// which is what stops a second `merchant` row being created for it — but it
  /// teaches nothing. The transaction lands in
  /// [CategorizationResult.flaggedUnknownMerchant] with reason
  /// `no_rule_for_merchant`, i.e. the app asks the user rather than stamping a
  /// category nothing can render.
  Future<List<MerchantCandidate>> loadCandidates() async {
    final List<MerchantRow> merchants = await merchantDao.allMerchants();
    final List<MerchantAliasRow> aliases = await merchantDao.allAliases();
    final List<MerchantRuleRow> rules = await merchantDao.enabledRules();
    final CategoryResolver knownCategories = await resolver();

    final Map<int, Set<String>> aliasesByMerchant = <int, Set<String>>{};
    for (final MerchantAliasRow alias in aliases) {
      aliasesByMerchant
          .putIfAbsent(alias.merchantId, () => <String>{})
          .add(alias.aliasKey);
    }
    final Map<int, MerchantRuleRow> ruleByMerchant = <int, MerchantRuleRow>{
      for (final MerchantRuleRow rule in rules)
        // [CategoryResolver.isKnown], not [CategoryResolver.resolve]: `resolve`
        // never returns null — that is what makes AC-C1.1's "never a blank"
        // true — so it cannot tell "this id is unknown" apart from "this id is
        // Uncategorized". A *writer* has to tell those apart even though a
        // renderer does not, which is exactly what `isKnown` exists for.
        if (knownCategories.isKnown(rule.categoryId)) rule.merchantId: rule,
    };

    return <MerchantCandidate>[
      for (final MerchantRow merchant in merchants)
        MerchantCandidate(
          merchantId: merchant.id,
          merchantKey: merchant.merchantKey,
          aliasKeys: aliasesByMerchant[merchant.id] ?? const <String>{},
          categoryId: ruleByMerchant[merchant.id]?.categoryId,
          ruleId: ruleByMerchant[merchant.id]?.id,
          ruleSource: ruleByMerchant[merchant.id]?.source,
        ),
    ];
  }

  /// **The automatic path.** Categorises one transaction if — and only if — a
  /// rule matches confidently and nobody has already decided.
  ///
  /// Called by the ingestion pipeline for every newly written transaction. Safe
  /// to call more than once for the same id: a transaction that already carries
  /// a category returns [CategorizationResult.skippedAlreadyDecided] without
  /// writing.
  Future<CategorizationOutcome> categorizeTransaction({
    required int transactionId,
    DateTime? now,
  }) async {
    final TransactionRow? row = await transactionDao.byIdOrNull(transactionId);
    if (row == null) {
      return const CategorizationOutcome(
        result: CategorizationResult.skippedAlreadyDecided,
        match: MerchantMatch.none,
      );
    }

    // AC-D3.1, first of two independent checks (the second is inside
    // `applyAutomaticCategory`). An already-categorised row is also left alone:
    // re-deciding a settled question is a P4b operation the user asks for
    // explicitly ("re-apply to history", AC-D4.4), never a side effect of
    // ingestion.
    if (isUserOwnedCategory(row) || row.categoryId != null) {
      return const CategorizationOutcome(
        result: CategorizationResult.skippedAlreadyDecided,
        match: MerchantMatch.none,
      );
    }

    final String? key = MerchantKey.ofOrNull(row.merchantRawText);
    if (key == null) {
      return const CategorizationOutcome(
        result: CategorizationResult.skippedNoMerchant,
        match: MerchantMatch.none,
      );
    }

    final MerchantMatch match = MerchantMatcher.match(
      row.merchantRawText,
      await loadCandidates(),
    );

    // ## Which merchant row this transaction is linked to
    //
    // Only a match that *identifies* the shop may set `merchant_id`:
    //
    //  - T1/T2 (exact key or user-linked alias) — the same shop by definition.
    //  - T3 at the shipped threshold — the same significant tokens in a
    //    different arrangement, i.e. a cosmetic variant. Linking it is also
    //    what keeps the loop consistent: the *next* message with the same
    //    variant spelling matches the same way and lands in the same place.
    //  - T3 below the threshold and **T4 never link**, because they are
    //    guesses. Asserting identity on a guess is the silent merge AC-D2.3
    //    forbids, and it would be worse than a wrong category: a category is
    //    one tap to fix, a merged identity quietly re-points every future
    //    message from one shop onto another's rule.
    //
    // Everything else gets a merchant row of its own, keyed on what the
    // message actually said.
    final bool matchIdentifiesMerchant =
        match.merchantId != null &&
        match.tier != MatchTier.editDistance &&
        (match.tier != MatchTier.tokenSet || match.canAutoApply);

    final int merchantId = matchIdentifiesMerchant
        ? match.merchantId!
        : await merchantDao.ensureMerchant(
            merchantKey: key,
            canonicalName: row.merchantRawText!,
            firstSeenMessageId: row.sourceMessageId,
            now: now,
          );

    if (match.canAutoApply) {
      final bool written = await transactionDao.applyAutomaticCategory(
        id: transactionId,
        categoryId: match.categoryId,
        confidence: match.confidence,
        ruleId: match.ruleId,
        merchantId: merchantId,
        // AC-F5.2 — the audit entry names the rule that fired. Formatted as
        // `merchant_rule:<id>` so the entity and its id are both recoverable
        // from the trail alone.
        actorDetail: 'merchant_rule:${match.ruleId}',
        now: now,
      );
      if (!written) {
        // The write boundary refused: a person owns this field. The service's
        // own check above should have caught it, so this is the redundant
        // guard doing its job rather than a normal path.
        return CategorizationOutcome(
          result: CategorizationResult.skippedAlreadyDecided,
          match: match,
          merchantId: merchantId,
        );
      }
      await merchantDao.recordRuleApplied(ruleId: match.ruleId!, at: now);
      return CategorizationOutcome(
        result: CategorizationResult.applied,
        match: match,
        categoryId: match.categoryId,
        merchantId: merchantId,
      );
    }

    // Not confident enough (or a tier that may never apply). ADR-008's last
    // row: Uncategorized + `needsReview`. The transaction stays fully visible
    // and fully counted — an uncategorized transaction is in the Uncategorized
    // bucket of the breakdown, so AC-C1.3's reconciliation is unaffected.
    final bool lowConfidence = match.tier != MatchTier.none;
    // Three distinct things the user could be asked, so three distinct
    // reasons — see `CategoryReviewReason`. A merchant the app recognises but
    // has no rule for is *not* an "unknown merchant", and telling the user it
    // is would be a small lie repeated on every row.
    final String reviewReason = lowConfidence
        ? CategoryReviewReason.lowConfidenceCategory
        : (match.merchantId == null
              ? CategoryReviewReason.unknownMerchant
              : CategoryReviewReason.noRuleForMerchant);

    await transactionDao.applyAutomaticCategory(
      id: transactionId,
      categoryId: null,
      confidence: match.confidence,
      merchantId: merchantId,
      actorDetail: 'no_rule_matched',
      flagForReview: true,
      reviewReason: reviewReason,
      now: now,
    );

    return CategorizationOutcome(
      result: lowConfidence
          ? CategorizationResult.flaggedLowConfidence
          : CategorizationResult.flaggedUnknownMerchant,
      match: match,
      merchantId: merchantId,
    );
  }

  /// **The user path** — US-C2, AC-D1.1, AC-D1.2, AC-D3.1.
  ///
  /// Writes the category the person chose and, unless [learnRule] is false,
  /// teaches the rule that makes the *next* transaction from this merchant
  /// arrive already categorised.
  ///
  /// ## `learnRule: false` is US-D5's "this transaction only"
  ///
  /// The scope-choice **UI** is a later issue (US-D5 / KHA-33) and is not
  /// built here. The parameter exists because the write path needs it either
  /// way, and because a one-off correction must not become a rule — with the
  /// property AC-D5.2 asks for: a previously learned rule is left completely
  /// untouched, so it still applies to the next transaction.
  ///
  /// Passing a null [categoryId] (or the explicit *Uncategorized* id) never
  /// creates a rule: "I do not know what this is" is not a lesson, and storing
  /// it as one would auto-file every future transaction from that merchant into
  /// Uncategorized and call it a decision.
  Future<void> applyUserCategory({
    required int transactionId,
    required String? categoryId,
    bool learnRule = true,
    String actor = 'user',
    DateTime? now,
  }) async {
    final TransactionRow? row = await transactionDao.byIdOrNull(transactionId);
    if (row == null) {
      return;
    }

    final String? key = MerchantKey.ofOrNull(row.merchantRawText);
    final String? storedCategoryId = normalizeStoredCategoryId(categoryId);

    int? merchantId = row.merchantId;
    if (key != null && merchantId == null) {
      merchantId = await merchantDao.ensureMerchant(
        merchantKey: key,
        canonicalName: row.merchantRawText!,
        firstSeenMessageId: row.sourceMessageId,
        now: now,
      );
    }

    await transactionDao.setUserCategory(
      id: transactionId,
      categoryId: storedCategoryId,
      merchantId: merchantId,
      actor: actor,
      now: now,
    );

    if (!learnRule) {
      return;
    }
    await learnRuleFromCorrection(
      transactionId: transactionId,
      categoryId: storedCategoryId,
      actor: actor,
      now: now,
    );
  }

  /// **The rule half of a correction, on its own** — AC-D1.1, AC-D1.2.
  ///
  /// Ensures the merchant row for the transaction's `merchant_raw_text` and
  /// upserts `merchant → category`. It writes **nothing to the transaction**:
  /// that is the caller's half, and separating them is what lets a *second*
  /// correction surface reuse the learning without also re-writing a category
  /// it has already written.
  ///
  /// ## Why this is public (KHA-101 / D-QA-27-4)
  ///
  /// Two user-facing writes can set a category: [applyUserCategory] (the
  /// categorization surface) and `TransactionDao.applyUserEdit` (the P3b-2 edit
  /// form). They behaved differently in two user-visible ways, and QA's fix
  /// direction is *"route every category write through one path"*. The flag
  /// half now lives at the write boundary in the DAO, where every caller gets
  /// it. This is the other half: the edit path calls it through the
  /// `LearnCategoryRule` seam in `features/ledger/transaction_edit.dart`, wired
  /// in `presentation/providers/ledger_providers.dart` — the layer that already
  /// depends on both features, so `features/ledger` never imports
  /// `features/categorization` and the dependency arrow stays acyclic. That is
  /// the same technique `categorization_providers.dart` uses to bind the
  /// categorizer into ingestion.
  ///
  /// Does nothing — deliberately, not defensively — when there is no category
  /// to teach or no merchant to teach it about. *"I do not know what this is"*
  /// is not a lesson, and storing it as one would auto-file every future
  /// transaction from that merchant into Uncategorized and call it a decision.
  Future<void> learnRuleFromCorrection({
    required int transactionId,
    required String? categoryId,
    String actor = 'user',
    DateTime? now,
  }) async {
    final String? storedCategoryId = normalizeStoredCategoryId(categoryId);
    if (storedCategoryId == null) {
      return;
    }
    final TransactionRow? row = await transactionDao.byIdOrNull(transactionId);
    if (row == null) {
      return;
    }

    final String? key = MerchantKey.ofOrNull(row.merchantRawText);
    int? merchantId = row.merchantId;
    if (key != null && merchantId == null) {
      merchantId = await merchantDao.ensureMerchant(
        merchantKey: key,
        canonicalName: row.merchantRawText!,
        firstSeenMessageId: row.sourceMessageId,
        now: now,
      );
      // The transaction should also *hold* the link, so the two correction
      // surfaces leave a row in the same shape. Written through the narrow
      // [TransactionDao.linkMerchant] rather than through `setUserCategory`,
      // deliberately: re-running the category write here would append a second
      // `categorize` audit entry whose before/after is `X → X`, i.e. a record
      // of a change that did not happen. This method's contract is *"it writes
      // nothing to the transaction's category"*, and it keeps it.
      await transactionDao.linkMerchant(
        id: transactionId,
        merchantId: merchantId,
        actor: actor,
        now: now,
      );
    }
    if (merchantId == null) {
      return;
    }

    // AC-D1.1 creates the rule; AC-D1.2 updates it when the user corrects a
    // second transaction from the same merchant to a different category.
    // `upsertRule` is the only method that can change what a rule says, and it
    // requires an actor — ADR-008's "user-driven only", made mechanical.
    await merchantDao.upsertRule(
      merchantId: merchantId,
      categoryId: storedCategoryId,
      source: 'user',
      actor: actor,
      now: now,
    );
  }

  /// Links an alternative spelling to an existing merchant — ADR-008's
  /// cross-script answer (R-5), and the **only** way two keys ever become one
  /// merchant.
  ///
  /// Returns false when the alias key is already in use, because one spelling
  /// naming two merchants is an ambiguity the matcher would have to resolve by
  /// guessing.
  Future<bool> linkMerchantAlias({
    required int merchantId,
    required String aliasText,
    String actor = 'user',
    DateTime? now,
  }) async {
    final String? aliasKey = MerchantKey.ofOrNull(aliasText);
    if (aliasKey == null) {
      return false;
    }
    final int? id = await merchantDao.linkAlias(
      merchantId: merchantId,
      aliasKey: aliasKey,
      script: MerchantKey.scriptOf(aliasText).key,
      actor: actor,
      now: now,
    );
    return id != null;
  }

  static Category _toCategory(CategoryRow row) => Category(
    id: row.id,
    key: row.key,
    nameAr: row.nameAr,
    nameEn: row.nameEn,
    iconToken: row.iconToken,
    colorToken: row.colorToken,
    group: CategoryGroup.fromKey(row.groupKey),
    isSystem: row.isSystem,
    isProtected: row.isProtected,
    isArchived: row.isArchived,
    sortOrder: row.sortOrder,
  );
}
