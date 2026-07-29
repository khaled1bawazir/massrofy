/// **The correction flow's write side** — KHA-33 (US-C2, US-C5, US-D5) and
/// KHA-34 (US-D4).
///
/// `CategorizationService` already owns the two *single-transaction* writes:
/// the automatic path and `applyUserCategory`. This file owns the three
/// operations that act on **more than one row at once**, because each of them
/// has a property that a per-row loop in a widget would get wrong:
///
///  1. [CategoryCorrectionService.correct] — one correction, with US-D5's
///     scope choice, which may also update the merchant's other uncategorized
///     transactions (AC-C5.1) and must report **how many** (AC-D5.3).
///  2. [CategoryCorrectionService.undo] — AC-C5.2's *"reverts all affected
///     transactions to their **prior** categories, not to a default"*, which
///     is only possible because step 1 took a snapshot first.
///  3. [CategoryCorrectionService.reapplyRuleToHistory] — AC-D4.4's explicit
///     re-apply, one audit entry per affected transaction.
///
/// ## Two paths write history, and the difference is the user's consent
///
/// This is the single most important distinction in this file, so it is stated
/// once, here:
///
/// | Path | What it touches | Why |
/// |---|---|---|
/// | [correct] with [CorrectionScope.thisAndFuture] | this row + the merchant's other **uncategorized** rows | AC-C5.1 names *"several **uncategorized** transactions from the same merchant"*. Filling in blanks is what the user just asked for by implication. |
/// | [reapplyRuleToHistory] | every non-user-owned row of that merchant, **including already-categorized ones** | AC-D4.4 requires the app to **ASK** before this. Rewriting a category the app previously applied changes last month's figures, so it is never a side effect — it is a question with a Yes and a No. |
///
/// Neither path ever touches a row a **person** categorized (AC-D3.1). That is
/// checked here *and* refused again at the write boundary in
/// `TransactionDao.applyAutomaticCategory`, the same belt-and-braces shape the
/// rest of the categorization code uses.
///
/// ## Every one of these operations audits, including the undo
///
/// NFR-A2/NFR-A3. A bulk action that wrote no history would leave the user
/// unable to reconstruct why a figure moved, which `docs/PRD.md` treats as a
/// defect rather than a gap. The undo appends entries; it never removes the
/// ones it is undoing.
library;

import '../../data/dao/merchant_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';
import 'categorization_service.dart';
import 'merchant_key.dart';

/// **US-D5's scope question**, as a type rather than a bool.
///
/// A bool would have to be named something like `learnRule`, and the two
/// choices the user is actually offered — *"just this one"* and *"this and
/// future ones from this shop"* — are not the negation of each other in the
/// user's head. Naming them makes the call sites read like the design doc.
enum CorrectionScope {
  /// **US-D5's one-off.** The supermarket purchase that was really a gift.
  ///
  /// AC-D5.2 is explicit that this must **not** disturb an existing rule: a
  /// rule already learned for this merchant keeps applying to later
  /// transactions. So this scope writes exactly one row and touches no rule at
  /// all — not even to "refresh" it.
  thisTransactionOnly,

  /// **The default** (design.md §6.4), because it is what trains the learning
  /// loop and is very likely the intent. Creates or updates the merchant rule
  /// (AC-D1.1/D1.2) and fills in the merchant's other uncategorized
  /// transactions (AC-C5.1).
  thisAndFuture,
}

/// What one correction did — enough for the toast (AC-D5.3) and for the undo.
final class CategoryCorrection {
  final int transactionId;

  /// The category the user chose. Null means the explicit *Uncategorized*
  /// choice, which never becomes a rule.
  final String? categoryId;

  final CorrectionScope scope;

  /// The merchant's canonical name, for the toast's *"…from Panda Foods…"*.
  /// Null when the transaction names no merchant at all (a transfer, an ATM
  /// withdrawal) — the toast then simply omits the clause.
  final String? merchantName;

  final int? merchantId;

  /// **AC-D5.3's number.** How many *other* transactions were updated
  /// alongside this one. Zero for [CorrectionScope.thisTransactionOnly], and
  /// zero for a merchant whose other transactions were all already answered.
  ///
  /// Deliberately excludes the transaction the user was looking at: the toast
  /// says *"…and 11 others"*-shaped things, and counting the row in front of
  /// them as one of the "affected" would read as one too many.
  final int otherTransactionsUpdated;

  /// True when a rule was created or updated (AC-D1.1/D1.2). False for a
  /// one-off, for an *Uncategorized* choice, and for a merchantless row.
  final bool ruleWritten;

  /// Everything needed to put the world back — see
  /// [CategoryCorrectionService.undo].
  final CorrectionUndoToken undo;

  const CategoryCorrection({
    required this.transactionId,
    required this.categoryId,
    required this.scope,
    required this.otherTransactionsUpdated,
    required this.ruleWritten,
    required this.undo,
    this.merchantId,
    this.merchantName,
  });

  /// Total rows whose category this correction changed, including the one the
  /// user was looking at. This is the figure the mockup's toast prints
  /// (*"Updated 12 transactions from Panda Foods"*).
  int get totalTransactionsUpdated => otherTransactionsUpdated + 1;

  /// Ids and counts only — no category name, no merchant (NFR-S4).
  @override
  String toString() =>
      'CategoryCorrection(#$transactionId, ${scope.name}, '
      '+$otherTransactionsUpdated)';
}

/// The exact prior state of everything a correction touched.
///
/// Held in memory by the screen that showed the snackbar, and discarded when
/// the snackbar goes away. Nothing is persisted: an undo is an *immediate*
/// affordance (design.md §6.6 — "reversibility as a friction-reducer"), and a
/// durable undo log would be a second, weaker copy of the audit trail that
/// already records every one of these writes.
final class CorrectionUndoToken {
  /// One snapshot per transaction the correction wrote, in the order they were
  /// written. Restored in reverse, so the row the user was looking at is the
  /// last thing to move back and the screen behind the snackbar settles once.
  final List<CategorySnapshot> transactionSnapshots;

  /// The merchant rule's id and category **before** the correction, or null
  /// when there was no rule.
  ///
  /// design.md §6.4 is explicit that the undo *"reverts the rule change, not
  /// just this transaction"*. Leaving a rule the user has just undone in place
  /// would mean the next message from that shop silently re-applied the
  /// category they rejected.
  final int? priorRuleId;
  final String? priorRuleCategoryId;

  /// The rule this correction created or updated, when it wrote one.
  final int? writtenRuleId;

  /// True when the correction **created** the rule, so undoing means deleting
  /// it rather than restoring a previous category.
  final bool ruleWasCreated;

  const CorrectionUndoToken({
    required this.transactionSnapshots,
    this.priorRuleId,
    this.priorRuleCategoryId,
    this.writtenRuleId,
    this.ruleWasCreated = false,
  });

  /// True when there is anything to put back. False after a correction that
  /// changed nothing (e.g. re-confirming the category a row already had).
  bool get isRestorable =>
      transactionSnapshots.isNotEmpty || writtenRuleId != null;
}

/// What a re-apply-to-history did — AC-D4.4's *"honour the answer"*, made
/// observable.
final class RuleReapplyResult {
  final int ruleId;
  final int merchantId;
  final String categoryId;

  /// Rows actually rewritten. Excludes rows a **person** categorized, which
  /// AC-D3.1 protects even from an explicit re-apply: the user asked to apply
  /// the *rule* to history, not to overrule their own past decisions.
  final int transactionsUpdated;

  /// Rows skipped because a person owns their category. Reported rather than
  /// silently dropped, so the screen can say *"12 updated, 2 left as you set
  /// them"* instead of a number that does not add up.
  final int transactionsSkippedUserOwned;

  const RuleReapplyResult({
    required this.ruleId,
    required this.merchantId,
    required this.categoryId,
    required this.transactionsUpdated,
    required this.transactionsSkippedUserOwned,
  });

  @override
  String toString() =>
      'RuleReapplyResult(rule $ruleId, $transactionsUpdated updated, '
      '$transactionsSkippedUserOwned kept)';
}

/// The multi-row half of the learning loop.
final class CategoryCorrectionService {
  final CategorizationService categorization;
  final TransactionDao transactionDao;
  final MerchantDao merchantDao;

  const CategoryCorrectionService({
    required this.categorization,
    required this.transactionDao,
    required this.merchantDao,
  });

  /// **The correction flow's one write** — design.md §6, AC-C2.1, AC-C2.3,
  /// AC-C5.1, AC-D5.1/D5.2/D5.3.
  ///
  /// Order of operations matters and is not arbitrary:
  ///
  ///  1. Snapshot the row **before** anything is written, or the undo has
  ///     nothing to restore.
  ///  2. Write the user's category on the row they were looking at. This alone
  ///     satisfies AC-C2.1/C2.2 — the correction is complete at this point, and
  ///     everything after it is the scope question's consequence.
  ///  3. If the scope is [CorrectionScope.thisAndFuture], learn the rule and
  ///     fill in the merchant's other uncategorized rows.
  ///
  /// Returns a [CategoryCorrection] whose counts the screen renders verbatim.
  Future<CategoryCorrection> correct({
    required int transactionId,
    required String? categoryId,
    required CorrectionScope scope,
    String actor = 'user',
    DateTime? now,
  }) async {
    final TransactionRow? row = await transactionDao.byIdOrNull(transactionId);
    if (row == null) {
      // A correction offered from a stale screen after the transaction was
      // deleted. Nothing to write and nothing to undo — returning an empty
      // result rather than throwing keeps a stale tap harmless.
      return CategoryCorrection(
        transactionId: transactionId,
        categoryId: categoryId,
        scope: scope,
        otherTransactionsUpdated: 0,
        ruleWritten: false,
        undo: const CorrectionUndoToken(
          transactionSnapshots: <CategorySnapshot>[],
        ),
      );
    }

    final List<CategorySnapshot> snapshots = <CategorySnapshot>[
      CategorySnapshot.of(row),
    ];

    // The rule as it stands *before* this correction, captured for the undo.
    // Read before the write, because `applyUserCategory` may replace it.
    final MerchantRuleRow? priorRule = row.merchantId == null
        ? null
        : await merchantDao.ruleForMerchant(row.merchantId!);

    final bool learnRule = scope == CorrectionScope.thisAndFuture;
    await categorization.applyUserCategory(
      transactionId: transactionId,
      categoryId: categoryId,
      learnRule: learnRule,
      actor: actor,
      now: now,
    );

    // Re-read: `applyUserCategory` may have created and linked the merchant
    // row, and everything below needs that id.
    final TransactionRow written = await transactionDao.byId(transactionId);
    final int? merchantId = written.merchantId;
    final MerchantRuleRow? newRule = merchantId == null
        ? null
        : await merchantDao.ruleForMerchant(merchantId);
    // Split into two steps rather than one conjunction. Dart's flow analysis
    // carries the `newRule != null` narrowing through a `final bool` local, so
    // `newRule.id` below needs no `!` and no `?.` — the type system is holding
    // the invariant rather than a comment claiming it.
    final bool ruleChanged =
        newRule != null &&
        (priorRule == null || priorRule.categoryId != newRule.categoryId);
    final bool ruleWritten = learnRule && ruleChanged;
    final int? writtenRuleId = ruleWritten ? newRule.id : null;

    int others = 0;
    if (learnRule && merchantId != null && categoryId != null) {
      others = await _fillUncategorizedSiblings(
        merchantId: merchantId,
        excludingTransactionId: transactionId,
        categoryId: categoryId,
        ruleId: newRule?.id,
        snapshots: snapshots,
        now: now,
      );
    }

    final MerchantRow? merchant = merchantId == null
        ? null
        : await merchantDao.byId(merchantId);

    return CategoryCorrection(
      transactionId: transactionId,
      categoryId: categoryId,
      scope: scope,
      merchantId: merchantId,
      merchantName: merchant?.canonicalName,
      otherTransactionsUpdated: others,
      ruleWritten: ruleWritten,
      undo: CorrectionUndoToken(
        transactionSnapshots: snapshots,
        priorRuleId: priorRule?.id,
        priorRuleCategoryId: priorRule?.categoryId,
        writtenRuleId: writtenRuleId,
        ruleWasCreated: ruleWritten && priorRule == null,
      ),
    );
  }

  /// **AC-C5.1 — the bulk half of a "this and future" correction.**
  ///
  /// Only rows that are **uncategorized** and **not user-owned** are touched:
  ///
  ///  - *uncategorized*, because AC-C5.1 says so, and because rewriting a
  ///    category the app previously applied is AC-D4.4's operation, which has
  ///    to ask first (see this library's table);
  ///  - *not user-owned*, because AC-D3.1 protects a person's answer from every
  ///    automatic path, and "the user corrected a different transaction" is
  ///    still not the same as "the user corrected this one".
  ///
  /// Written through `applyAutomaticCategory` with the rule named, so each
  /// affected row gets a **system-attributed** audit entry citing the rule
  /// (AC-F5.2) — which is the honest description: the person categorised one
  /// transaction, and the rule they taught categorised the rest.
  Future<int> _fillUncategorizedSiblings({
    required int merchantId,
    required int excludingTransactionId,
    required String categoryId,
    required int? ruleId,
    required List<CategorySnapshot> snapshots,
    DateTime? now,
  }) async {
    final String? storedId = normalizeStoredCategoryId(categoryId);
    if (storedId == null) {
      // The explicit *Uncategorized* choice. Filling other blanks with a blank
      // is not a categorization, and stamping `category_source` across a
      // merchant's history to record it would be noise in the audit trail.
      return 0;
    }

    int updated = 0;
    for (final TransactionRow sibling in await transactionDao.liveForMerchant(
      merchantId,
    )) {
      if (sibling.id == excludingTransactionId) {
        continue;
      }
      if (sibling.categoryId != null || isUserOwnedCategory(sibling)) {
        continue;
      }
      snapshots.add(CategorySnapshot.of(sibling));
      final bool written = await transactionDao.applyAutomaticCategory(
        id: sibling.id,
        categoryId: storedId,
        // The rule the user just taught is a user rule, so the row records the
        // same certainty the matcher would have given it at T1. Anything lower
        // would make an identical future message look *more* confident than
        // this one.
        confidence: 1.0,
        ruleId: ruleId,
        merchantId: merchantId,
        actorDetail: ruleId == null
            ? 'bulk_categorize'
            : 'merchant_rule:$ruleId',
        now: now,
      );
      if (written) {
        updated++;
      } else {
        // Refused at the write boundary — the row is user-owned after all.
        // Drop the snapshot again so the undo does not "restore" a row that
        // never moved.
        snapshots.removeLast();
      }
    }
    return updated;
  }

  /// **AC-C5.2 — undo, restoring each transaction's own prior category.**
  ///
  /// Not "set them all back to Uncategorized": a bulk action can sweep up rows
  /// that had different categories, and a default-restoring undo would quietly
  /// destroy information while claiming to be safe.
  ///
  /// Also reverts the rule (design.md §6.4). Restored in reverse write order
  /// so the row the user is looking at moves last.
  ///
  /// Returns how many transactions were actually put back; a row deleted since
  /// the correction is skipped rather than resurrected.
  Future<int> undo(
    CorrectionUndoToken token, {
    String actor = 'user',
    DateTime? now,
  }) async {
    int restored = 0;
    for (final CategorySnapshot snapshot
        in token.transactionSnapshots.reversed) {
      final bool ok = await transactionDao.restoreCategorySnapshot(
        snapshot: snapshot,
        actor: actor,
        actorDetail: 'undo_correction',
        now: now,
      );
      if (ok) {
        restored++;
      }
    }

    // The rule half. Deleting a rule this correction created, or putting back
    // the category it replaced — never "leave the rule and hope".
    final int? writtenRuleId = token.writtenRuleId;
    if (writtenRuleId != null) {
      if (token.ruleWasCreated) {
        await merchantDao.deleteRule(id: writtenRuleId, actor: actor, now: now);
      } else if (token.priorRuleCategoryId != null) {
        final MerchantRuleRow? rule = await merchantDao.ruleById(writtenRuleId);
        if (rule != null) {
          await merchantDao.upsertRule(
            merchantId: rule.merchantId,
            categoryId: token.priorRuleCategoryId!,
            source: rule.source,
            actor: actor,
            now: now,
          );
        }
      }
    }
    return restored;
  }

  /// **AC-D4.2 + AC-D4.4 — change what a rule says, and optionally re-apply it
  /// to history.**
  ///
  /// [reapplyToHistory] is the answer to the prompt S-17 shows; the caller must
  /// have asked. Passing `false` changes only what *future* transactions get
  /// (AC-D4.2) and leaves every existing row exactly as it is.
  ///
  /// The category is validated by `MerchantDao.upsertRule`, which refuses a
  /// rule naming a category that does not exist (KHA-104's write-side guard) —
  /// **this screen is the second writer that guard was fixed for**, and it goes
  /// through the same method rather than around it. A refusal returns null and
  /// nothing at all is written, including no history rewrite.
  Future<RuleReapplyResult?> editRule({
    required int ruleId,
    required String categoryId,
    required bool reapplyToHistory,
    String actor = 'user',
    DateTime? now,
  }) async {
    final MerchantRuleRow? rule = await merchantDao.ruleById(ruleId);
    if (rule == null) {
      return null;
    }

    final int written = await merchantDao.upsertRule(
      merchantId: rule.merchantId,
      categoryId: categoryId,
      source: rule.source,
      actor: actor,
      now: now,
    );
    if (written < 0) {
      // KHA-104's refusal sentinel: the category does not exist. Nothing was
      // written, so nothing is re-applied either — a history rewrite pointing
      // at an unrenderable category is strictly worse than no rewrite.
      return null;
    }

    if (!reapplyToHistory) {
      return RuleReapplyResult(
        ruleId: written,
        merchantId: rule.merchantId,
        categoryId: categoryId,
        transactionsUpdated: 0,
        transactionsSkippedUserOwned: 0,
      );
    }
    return reapplyRuleToHistory(
      ruleId: written,
      merchantId: rule.merchantId,
      categoryId: categoryId,
      now: now,
    );
  }

  /// **AC-D4.4's re-apply**, on its own so it can be called from the S-17
  /// prompt and tested directly.
  ///
  /// > *"A bulk historical re-apply that writes no history is a defect — the
  /// > user must be able to reconstruct why last month's figures changed."*
  ///
  /// So this deliberately loops one row at a time through
  /// `applyAutomaticCategory`, which writes **one audit entry per affected
  /// transaction** naming the rule (AC-F5.2, NFR-A2). A single bulk `UPDATE`
  /// would be faster and would leave the user unable to answer that question,
  /// which the issue calls a defect in as many words.
  Future<RuleReapplyResult> reapplyRuleToHistory({
    required int ruleId,
    required int merchantId,
    required String categoryId,
    DateTime? now,
  }) async {
    int updated = 0;
    int skipped = 0;
    for (final TransactionRow row in await transactionDao.liveForMerchant(
      merchantId,
    )) {
      if (isUserOwnedCategory(row)) {
        // AC-D3.1 outranks an explicit re-apply. The user asked to apply the
        // RULE to history, not to overrule the decisions they made by hand.
        skipped++;
        continue;
      }
      if (row.categoryId == categoryId) {
        // Already says this. Writing it again would append an audit entry
        // whose before/after is `X → X` — a record of a change that did not
        // happen, which is the dishonest-history shape the DAO warns about.
        continue;
      }
      final bool written = await transactionDao.applyAutomaticCategory(
        id: row.id,
        categoryId: categoryId,
        confidence: 1.0,
        ruleId: ruleId,
        merchantId: merchantId,
        actorDetail: 'merchant_rule:$ruleId',
        now: now,
      );
      if (written) {
        updated++;
      } else {
        skipped++;
      }
    }
    if (updated > 0) {
      // Only when the rule actually fired. Bumping `applied_count` for a
      // re-apply that changed nothing would inflate S-16's "Applied to N
      // transactions" line, which is the one number on that screen a user
      // might reason about when deciding whether a rule is worth keeping.
      await merchantDao.recordRuleApplied(ruleId: ruleId, at: now);
    }
    return RuleReapplyResult(
      ruleId: ruleId,
      merchantId: merchantId,
      categoryId: categoryId,
      transactionsUpdated: updated,
      transactionsSkippedUserOwned: skipped,
    );
  }

  /// **AC-D4.3 — deleting a rule stops future auto-categorization and leaves
  /// history alone.**
  ///
  /// Both halves are the point. "Forgetting a lesson is not forgetting the
  /// money": the transactions the rule already categorised keep their
  /// categories, because they are a record of what happened, and the user
  /// deleting a rule is saying *"stop doing this from now on"*, not *"pretend
  /// you never did"*.
  Future<void> deleteRule({
    required int ruleId,
    String actor = 'user',
    DateTime? now,
  }) => merchantDao.deleteRule(id: ruleId, actor: actor, now: now);

  /// How many of this merchant's live transactions a re-apply would rewrite —
  /// the **N** in S-17's *"Yes, re-apply to N transactions"* and in AC-D5.3's
  /// count, computed before anything is written so the prompt cannot promise a
  /// number the write does not deliver.
  Future<int> countReapplyCandidates({
    required int merchantId,
    required String categoryId,
  }) async {
    int count = 0;
    for (final TransactionRow row in await transactionDao.liveForMerchant(
      merchantId,
    )) {
      if (isUserOwnedCategory(row) || row.categoryId == categoryId) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// How many of this merchant's live transactions a
  /// [CorrectionScope.thisAndFuture] correction would fill in — the number the
  /// scope strip shows *before* the user commits (design.md §6.4's
  /// `affectedCount`).
  Future<int> countUncategorizedSiblings({
    required int merchantId,
    required int excludingTransactionId,
  }) async {
    int count = 0;
    for (final TransactionRow row in await transactionDao.liveForMerchant(
      merchantId,
    )) {
      if (row.id == excludingTransactionId ||
          row.categoryId != null ||
          isUserOwnedCategory(row)) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// The merchant a transaction belongs to, resolving it from
  /// `merchant_raw_text` when the row carries no link yet.
  ///
  /// Read-only: unlike `CategorizationService.applyUserCategory`, this never
  /// *creates* a merchant row. A picker sheet that is only being opened must
  /// not write to the database — the user may still dismiss it.
  Future<MerchantRow?> merchantFor(TransactionRow row) async {
    if (row.merchantId != null) {
      return merchantDao.byId(row.merchantId!);
    }
    final String? key = MerchantKey.ofOrNull(row.merchantRawText);
    return key == null ? null : merchantDao.byKey(key);
  }
}
