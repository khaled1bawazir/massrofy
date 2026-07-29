/// **The stored vocabulary of the categorization columns** — the sibling of
/// `user_edited_fields.dart`, and it exists for the same reason.
///
/// `transactions.category_id`, `category_source` and `review_reason` are read
/// and written by three layers (the DAO, the categorization service, the
/// presentation layer). Every string those columns can hold, and every rule
/// about how they relate, is defined **here, once**, so the write path and the
/// read paths cannot drift apart on what a value means.
///
/// This file lives in `data/` rather than in `features/categorization/`
/// because architecture §3's dependency rule runs `features → data`, never the
/// reverse: `TransactionDao` has to enforce AC-D3.1 at the write boundary, so
/// the constants it enforces against cannot live in a layer it may not import.
/// The feature layer re-exposes them (`CategorySource` in `categories.dart`)
/// so feature code reads naturally without a second set of literals.
library;

import '../db/app_database.dart';
import 'user_edited_fields.dart';

/// The id of the fallback category — design.md §4's *"غير مصنف /
/// Uncategorized"*, the row that always exists (AC-C1.1).
const String uncategorizedCategoryId = 'uncategorized';

/// `transactions.category_source` — architecture §4.2.
abstract final class StoredCategorySource {
  /// A person chose it. **Never overwritten automatically** (AC-D3.1/D3.2).
  static const String user = 'user';

  /// A merchant rule fired (AC-D2.2's "categorized automatically").
  static const String rule = 'rule';

  /// Reserved by architecture §4.2 for a category applied from a shipped
  /// default mapping rather than a learned rule. Nothing writes it yet; the
  /// constant exists so a future writer uses the architecture's word rather
  /// than inventing a fourth.
  static const String defaultAssignment = 'default';

  /// The app looked and could not decide (ADR-008's "no match" row).
  static const String none = 'none';
}

/// `transactions.review_reason` values raised by the **categorizer**.
///
/// Deliberately disjoint from `ReviewReason` in
/// `features/ingestion/duplicate_policy.dart`: both write the same column, and
/// the review inbox (design.md S-18) renders one tab per *question*. Sharing a
/// value between "this might be a duplicate" and "I do not know this shop"
/// would merge two tabs that ask the user for two different decisions.
abstract final class CategoryReviewReason {
  /// ADR-008's last row: no candidate matched at any tier and the app has
  /// never seen this shop before. AC-D2.4's *"a never-before-seen merchant
  /// must be Uncategorized or low-confidence-flagged"*.
  static const String unknownMerchant = 'unknown_merchant';

  /// The merchant **is** recognised — the app has seen it before — but nobody
  /// has ever said which category it belongs in.
  ///
  /// Distinct from [unknownMerchant] because the two ask the user for
  /// different things: *"is this a shop you know?"* versus *"where does this
  /// shop's spending belong?"*. Collapsing them would make the review inbox
  /// say the wrong sentence about half its rows.
  static const String noRuleForMerchant = 'no_rule_for_merchant';

  /// A candidate matched, but below `autoApplyThreshold` — including every
  /// T4 "did you mean…" suggestion, which ADR-008 forbids applying at any
  /// confidence.
  static const String lowConfidenceCategory = 'low_confidence_category';
}

/// The review reasons a *categorization* raised, and therefore the only ones
/// a categorization is allowed to clear.
///
/// Used by `TransactionDao._clearCategoryReviewFlag`. A user answering the
/// category question must not silently clear a duplicate flag: that is a
/// different, still-open question about the user's money.
const Set<String> categoryReviewReasons = <String>{
  CategoryReviewReason.unknownMerchant,
  CategoryReviewReason.noRuleForMerchant,
  CategoryReviewReason.lowConfidenceCategory,
};

/// Collapses the explicit *Uncategorized* id to the null the column actually
/// stores.
///
/// **One stored representation, not two.** See the long note on
/// `transactions.category_id` in `transaction_table.dart`: NULL has meant
/// "uncategorized" since schema v1, so P4a resolves the ambiguity at every
/// write instead of leaving two encodings for later code to remember. Reading
/// goes the other way — `CategoryResolver.resolve` turns null back into the
/// explicit category, which is what makes AC-C1.1's "never a blank" true.
String? normalizeStoredCategoryId(String? categoryId) =>
    categoryId == uncategorizedCategoryId ? null : categoryId;

/// **Everything about one transaction's category, captured so it can be put
/// back exactly** — AC-C5.2's *"undo reverts all affected transactions to
/// their PRIOR categories, not to a default"*.
///
/// ## Why this is a snapshot of six fields and not just `categoryId`
///
/// A bulk categorization does not only change `category_id`. It also stamps
/// `category_source = 'user'`, sets `category_confidence` to 1.0, clears
/// `category_rule_id`, adds `categoryId` to `user_edited_fields`, and lowers a
/// review flag the categorizer had raised. An undo that restored only the id
/// would leave the row **permanently user-owned** — so the learned rule could
/// never categorise it again (AC-D3.1 would forbid it), and the review flag it
/// had raised would stay down. The row would look restored and behave
/// differently forever.
///
/// So the undo restores the whole category-shaped part of the row. Taking a
/// snapshot before the write, rather than computing an inverse afterwards, is
/// what makes that exact rather than approximate.
///
/// **This is a value type, not a row.** It is built from a [TransactionRow] and
/// handed back to `TransactionDao.restoreCategorySnapshot`; nothing else in the
/// app may write these columns together.
final class CategorySnapshot {
  final int transactionId;
  final String? categoryId;
  final String? categorySource;
  final double? categoryConfidence;
  final int? categoryRuleId;

  /// The **encoded** `user_edited_fields` string, carried verbatim. Encoded
  /// rather than decoded because restoring must not reorder or normalise a
  /// column this class does not own.
  final String? userEditedFields;

  final bool needsReview;
  final String? reviewReason;

  const CategorySnapshot({
    required this.transactionId,
    required this.categoryId,
    required this.categorySource,
    required this.categoryConfidence,
    required this.categoryRuleId,
    required this.userEditedFields,
    required this.needsReview,
    required this.reviewReason,
  });

  /// Captures [row]'s category state as it stands right now.
  factory CategorySnapshot.of(TransactionRow row) => CategorySnapshot(
    transactionId: row.id,
    categoryId: row.categoryId,
    categorySource: row.categorySource,
    categoryConfidence: row.categoryConfidence,
    categoryRuleId: row.categoryRuleId,
    userEditedFields: row.userEditedFields,
    needsReview: row.needsReview,
    reviewReason: row.reviewReason,
  );

  /// Ids only — never a category name, never a merchant (NFR-S4, ADR-015).
  @override
  String toString() => 'CategorySnapshot(#$transactionId)';
}

/// **AC-D3.1's precondition, in one function.** True when a person has
/// answered the category question for this row, so no automatic path may
/// write to it.
///
/// Two independent signals, either of which is enough:
///
///  - `user_edited_fields` contains `categoryId` — the app-wide protection
///    mechanism that predates categorization (AC-B5.3) and that the enrichment
///    merge already honours;
///  - `category_source` is `user` — categorization's own statement of the same
///    fact.
///
/// The redundancy is deliberate. They are written together by
/// `TransactionDao.setUserCategory` and read together here, so a defect that
/// dropped either one would still leave the user's choice protected.
bool isUserOwnedCategory(TransactionRow row) =>
    row.categorySource == StoredCategorySource.user ||
    decodeUserEditedFields(
      row.userEditedFields,
    ).contains(TransactionField.categoryId);
