/// **What S-16 renders, and what "why is this categorized this way" answers**
/// — KHA-34 (US-D4) and KHA-31/KHA-32's provenance requirement.
///
/// Two value types, both assembled in the presentation layer's providers from
/// rows this feature already owns, and both deliberately **plain values with no
/// database in them**. That is the same discipline `review_queue.dart` follows,
/// and it buys the same two things: the widget layer never imports `data/`
/// (architecture §3), and a widget test for the learned-rules screen needs no
/// database at all.
library;

// `StoredCategorySource` and `CategoryReviewReason` arrive through
// `categories.dart`'s re-export of `data/dao/category_fields.dart`, which is
// the one import feature code is meant to use for that vocabulary.
import 'categories.dart';

/// One row of S-16 — *"{Merchant} → {Category}"*.
final class LearnedRule {
  final int ruleId;
  final int merchantId;

  /// What the user reads: the merchant's canonical name, as first observed.
  final String merchantName;

  /// ADR-008's normalised key. Shown as a secondary line, because two rules
  /// that look identically named but key differently is exactly the situation
  /// a user needs to be able to see (it is what an alias link would fix).
  final String merchantKey;

  final String categoryId;

  /// `user` (taught by a correction) or `seed` (shipped with the app).
  /// AC-D3.1 makes a user rule outrank a seed rule for the same merchant, so
  /// the distinction is worth showing rather than flattening.
  final String source;

  /// How many times this rule has fired — the mockup's *"12 matching
  /// transactions"* line.
  final int appliedCount;

  final DateTime updatedAt;
  final DateTime? lastAppliedAt;

  const LearnedRule({
    required this.ruleId,
    required this.merchantId,
    required this.merchantName,
    required this.merchantKey,
    required this.categoryId,
    required this.source,
    required this.appliedCount,
    required this.updatedAt,
    this.lastAppliedAt,
  });

  bool get isUserTaught => source == 'user';

  /// Ids only — a merchant name is the user's own commercial history (NFR-S4).
  @override
  String toString() => 'LearnedRule(#$ruleId → merchant $merchantId)';
}

/// **"Why is this categorized this way?"** — KHA-31's promise, as a value the
/// detail screen can render on request.
///
/// ## Why this exists as a type rather than three fields on the screen
///
/// KHA-31 requires every automatic categorization to remain traceable to its
/// audit entry, and KHA-32/33 route the first screens that show a category at
/// all. A screen that rendered `category_source` directly would answer *"rule"*
/// — which is not an answer. The answer is *"the rule you taught for Panda
/// Foods, on 12 July, at confidence 1.00, and here is the audit entry"*, and
/// assembling that needs the rule row, the merchant row and the trail.
///
/// Building it here means the same explanation appears identically wherever it
/// is shown, and that a test can assert the explanation without a widget.
final class CategoryProvenance {
  final int transactionId;

  /// The stored `category_source` — see [StoredCategorySource]. Never null in
  /// this type: a row that has none is [StoredCategorySource.none], which is a
  /// real answer ("the app looked and could not decide") rather than an absence.
  final String source;

  final String? categoryId;

  /// Null for a user choice and for an undecided row.
  final double? confidence;

  /// The rule that fired, when one did **and it still exists**. Null after the
  /// rule was deleted — KHA-103 clears `category_rule_id` with the rule, so a
  /// dangling id cannot reach here, and this type must not imply otherwise.
  final LearnedRule? rule;

  /// The audit entries for this transaction's category, newest last. This is
  /// the literal trail NFR-A2 requires, surfaced instead of summarised: the
  /// count, the actors and the field changes are what let a user reconstruct a
  /// figure rather than take the app's word for it.
  final List<CategoryAuditEntry> auditTrail;

  const CategoryProvenance({
    required this.transactionId,
    required this.source,
    required this.auditTrail,
    this.categoryId,
    this.confidence,
    this.rule,
  });

  /// True when a person answered this question (AC-D3.1's ownership signal).
  bool get isUserChosen => source == StoredCategorySource.user;

  /// True when a merchant rule put the category there (AC-D2.2).
  bool get isAutomatic => source == StoredCategorySource.rule;

  /// True when the app looked and declined to decide — the honest state behind
  /// an *Uncategorized* chip that is **not** simply "nothing happened yet".
  bool get isUndecided =>
      source == StoredCategorySource.none && categoryId == null;

  /// An empty provenance, for a row nothing has ever categorised. Used rather
  /// than null so the screen has no "no provenance" branch to get wrong.
  static CategoryProvenance unknown(int transactionId) => CategoryProvenance(
    transactionId: transactionId,
    source: StoredCategorySource.none,
    auditTrail: const <CategoryAuditEntry>[],
  );

  @override
  String toString() => 'CategoryProvenance(#$transactionId, $source)';
}

/// One line of the "why" — a projection of an `audit_entry` row, narrowed to
/// the categorization action.
final class CategoryAuditEntry {
  final DateTime changedAt;

  /// ADR-010's actor vocabulary: `user`, `system_rule`, `system`. The whole
  /// value of the trail is that it distinguishes what the app did from what
  /// the person did, so this is never flattened to a friendly string here —
  /// the widget maps it to localised words.
  final String actor;

  /// e.g. `merchant_rule:7`, `undo_correction`, or null.
  final String? actorDetail;

  final String? fromCategoryId;
  final String? toCategoryId;

  const CategoryAuditEntry({
    required this.changedAt,
    required this.actor,
    this.actorDetail,
    this.fromCategoryId,
    this.toCategoryId,
  });

  /// The rule id named by [actorDetail], when it names one.
  ///
  /// Parsed rather than stored as an int because the trail is append-only and
  /// deliberately holds *text* (ADR-010): the entry has to stay readable after
  /// the rule it names is deleted, and an integer foreign key could not.
  int? get namedRuleId {
    const String prefix = 'merchant_rule:';
    final String? detail = actorDetail;
    if (detail == null || !detail.startsWith(prefix)) {
      return null;
    }
    return int.tryParse(detail.substring(prefix.length));
  }

  @override
  String toString() => 'CategoryAuditEntry($actor, $changedAt)';
}

/// **KHA-32's confidence display** — how sure the app was, in words a person
/// can act on rather than a bare number.
///
/// NFR-U4 forbids carrying meaning by colour alone, and a raw `0.82` carries it
/// by *numeracy* alone, which is barely better. So the number is banded and the
/// band is what the UI names; the number itself is still shown beside it for
/// anyone who wants it, because hiding it would make the app less auditable
/// than the audit trail it keeps.
enum ConfidenceBand {
  /// No category, and no candidate at any tier — AC-D2.4's never-before-seen
  /// merchant.
  none,

  /// A candidate matched but below `autoApplyThreshold`, or at a tier that may
  /// never auto-apply (T4). The app is asking.
  low,

  /// At or above the threshold: applied automatically (AC-D2.2).
  confident,

  /// A person decided. Not "1.00 confidence" — a different kind of fact.
  userChosen;

  /// Bands a stored `(source, confidence)` pair.
  ///
  /// [userChosen] is checked first and independently of the number, because
  /// `setUserCategory` stores 1.0 for a person's choice and the two must not be
  /// rendered with the same words: *"we are very sure"* and *"you told us"* are
  /// different statements, and only one of them is the app's opinion.
  static ConfidenceBand of({
    required String? source,
    required double? confidence,
    required String? categoryId,
    required double autoApplyThreshold,
  }) {
    if (source == StoredCategorySource.user) {
      return ConfidenceBand.userChosen;
    }
    if (categoryId == null) {
      return (confidence ?? 0) > 0 ? ConfidenceBand.low : ConfidenceBand.none;
    }
    return (confidence ?? 0) >= autoApplyThreshold
        ? ConfidenceBand.confident
        : ConfidenceBand.low;
  }
}

/// A category plus how it got there — everything a `CategoryChip` needs.
final class CategoryAssignment {
  final Category category;
  final ConfidenceBand band;
  final double? confidence;

  /// True when the row carries the categorizer's own review flag. Distinct
  /// from `band == low`: a flag persists until the user answers it, whereas the
  /// band is recomputed from the stored numbers on every read.
  final bool needsReview;

  /// A [CategoryReviewReason] constant, when the flag came from the
  /// categorizer. Drives which *question* the review inbox asks — "is this a
  /// shop you know?" is not the same as "where does this shop's spending
  /// belong?".
  final String? reviewReason;

  const CategoryAssignment({
    required this.category,
    required this.band,
    this.confidence,
    this.needsReview = false,
    this.reviewReason,
  });

  @override
  String toString() => 'CategoryAssignment(${category.id}, ${band.name})';
}
