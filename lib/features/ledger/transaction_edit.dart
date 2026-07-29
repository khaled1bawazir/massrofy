/// **US-B5, US-B6, US-B8 — editing, deleting and restoring a transaction.**
/// KHA-26, AC-B5.1/2/3, AC-B6.1/2/3/4, AC-B8.1/2/3.
///
/// ---
///
/// ## The single idea this whole file is built around
///
/// > **User intent outranks the parser. Always, and permanently.**
///
/// AC-B5.3 states it as a scenario — *"a later re-scan of SMS must not
/// overwrite the user's edit"* — but it is really a rule about every automated
/// write path that will ever exist, including ones not written yet (P7's
/// statement reconciliation is the next one). A rule that lives only in the
/// re-scan code is a rule the next write path will not know about. So it lives
/// in the **data**: [TransactionDao.applyUserEdit] records which fields a
/// person touched, and every automated writer must consult that record. See
/// `lib/data/dao/user_edited_fields.dart`.
///
/// ## Why deletion is soft, and what that actually buys
///
/// OQ-8/X17 and AC-B8.1 make deletion reversible: the row is hidden, not
/// destroyed. Only "erase everything" (US-F3, ADR-011) is a true hard delete,
/// and AC-B8.3 is explicit that what it destroys is *not* recoverable from
/// Recently Deleted.
///
/// The reason is the same asymmetry that governs dedup (ADR-017) and merging
/// (risk R-8): **an item wrongly hidden is visible in Recently Deleted and
/// restorable in one tap; an item wrongly destroyed is gone.** In a ledger, the
/// recoverable error is always the better one to make.
///
/// It also gives AC-B6.3 — *"a deleted transaction is not resurrected by
/// re-scanning its source SMS"* — for free at two independent layers, which is
/// worth stating because it is easy to assume only one of them is doing the
/// work:
///
///  1. **The message layer.** Re-scanning does not reach the transaction layer
///     at all. `raw_message.content_hmac` is UNIQUE (ADR-017 D1), so a second
///     sighting of the same SMS is suppressed before anything is parsed. This
///     is the mechanism that actually fires.
///  2. **The transaction layer.** Even if a message did get through, the
///     deleted row still exists, so a re-import cannot "re-create" it — there
///     is nothing missing to re-create. A *hard* delete would have removed the
///     row and the next sweep would have happily written it back, which is
///     precisely the resurrection AC-B6.3 forbids.
///
/// ## Everything here writes history (NFR-A2, AC-B6.4)
///
/// Edit, delete and restore each append an audit entry with actor and
/// before/after, inside the same database transaction as the change. KHA-26 is
/// blunt about the standard: *"A delete whose history is not recorded is a
/// defect."*
library;

import '../../core/money/money.dart';
import '../../core/money/sign_convention.dart';
import '../../data/dao/audit_log_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';

/// What the user changed on the edit form (design.md S-20).
///
/// Every field is an `Edited<T>?`: null means *"the form did not offer a
/// change to this"*, `Edited(null)` means *"clear it"*. See
/// `lib/core/types/edited.dart` — that distinction is what lets the user
/// remove a wrongly-parsed merchant name instead of only replacing it.
final class TransactionEditDraft {
  final Edited<String>? amountText;

  /// Only meaningful alongside [amountText]; the two are parsed together
  /// because NFR-A5 does not permit an amount without a currency.
  final String? currencyCode;

  final Edited<String?>? merchantRawText;
  final Edited<DateTime?>? occurredAt;
  final Edited<String>? direction;
  final Edited<String>? transactionType;
  final Edited<String?>? categoryId;
  final Edited<int?>? instrumentId;
  final Edited<String?>? counterpartyName;

  const TransactionEditDraft({
    this.amountText,
    this.currencyCode,
    this.merchantRawText,
    this.occurredAt,
    this.direction,
    this.transactionType,
    this.categoryId,
    this.instrumentId,
    this.counterpartyName,
  });

  /// No amount, no merchant (NFR-S4).
  @override
  String toString() => 'TransactionEditDraft(...)';
}

/// The outcome of an edit attempt.
sealed class TransactionEditResult {
  const TransactionEditResult();
}

/// The edit was applied, with its audit entry.
final class TransactionEditApplied extends TransactionEditResult {
  /// The field names that actually changed. Empty when the user pressed Save
  /// without altering anything — a legitimate no-op that writes nothing, so
  /// the change history is not padded with entries recording that nothing
  /// happened (US-F5 is read by a person).
  final List<String> changedFields;

  const TransactionEditApplied(this.changedFields);
}

/// Nothing was written. [invalidFields] holds [TransactionField] constants.
final class TransactionEditRejected extends TransactionEditResult {
  final List<String> invalidFields;
  final AmountProblemOnEdit? amountProblem;

  const TransactionEditRejected(this.invalidFields, {this.amountProblem});
}

/// The transaction id did not resolve. Its own case rather than an exception:
/// it is reachable without any bug — the row could have been erased in another
/// tab of the app's own navigation while the edit form was open.
final class TransactionEditTargetMissing extends TransactionEditResult {
  const TransactionEditTargetMissing();
}

/// Why an edited amount was refused. Mirrors `AmountProblem` in
/// `manual_entry.dart`; kept separate so the two forms' error vocabularies can
/// evolve independently without one silently changing the other's messages.
enum AmountProblemOnEdit { unparsable, negative }

/// **KHA-101's seam** — teaches `merchant → category` after the edit form
/// changes a category.
///
/// A function type rather than a `CategorizationService` field, and that is not
/// squeamishness about coupling: `features/categorization` already imports
/// `features/ledger` (`category_breakdown.dart` needs `PeriodRange` and
/// `LedgerTransaction`), so a field here would close a cycle between two
/// sibling features. The seam is bound in
/// `presentation/providers/ledger_providers.dart` — the layer that already
/// depends on both — which is precisely how `categorization_providers.dart`
/// binds the categorizer into ingestion without `features/ingestion` importing
/// `features/categorization`.
///
/// Implemented by `CategorizationService.learnRuleFromCorrection`. Its extra
/// optional named parameters (`actor`) are allowed by Dart's function subtyping,
/// so the tear-off assigns with no adapter lambda.
typedef LearnCategoryRule =
    Future<void> Function({
      required int transactionId,
      required String? categoryId,
      DateTime? now,
    });

/// Applies edits, soft deletes and restores — the write half of US-B5/B6/B8.
final class TransactionEditService {
  final AppDatabase database;
  final TransactionDao transactionDao;

  /// See [LearnCategoryRule]. Null means *"no categorization service in this
  /// composition"* — the app while locked, and most of the ledger's own tests,
  /// which are about editing rather than about learning. An edit still applies
  /// in full when it is null; only the rule is not taught.
  final LearnCategoryRule? learnCategoryRule;

  const TransactionEditService({
    required this.database,
    required this.transactionDao,
    this.learnCategoryRule,
  });

  /// **AC-B5.1** — applies [draft] to transaction [id].
  ///
  /// Correcting a mis-parsed merchant here corrects it *everywhere*, including
  /// every breakdown, and that is a property of the design rather than
  /// something this method has to arrange: nothing in this app caches a
  /// derived figure (NFR-A6), so every total and every category breakdown is
  /// recomputed from the transaction rows on the next read. There is no second
  /// copy of the merchant name to keep in step.
  Future<TransactionEditResult> edit(
    int id,
    TransactionEditDraft draft, {
    DateTime? now,
  }) async {
    final TransactionRow? existing = await transactionDao.byIdOrNull(id);
    if (existing == null) {
      return const TransactionEditTargetMissing();
    }

    Edited<Money>? amount;
    if (draft.amountText != null) {
      final String currency = draft.currencyCode ?? existing.amountCurrency;
      final Money? parsed = Money.tryParse(
        draft.amountText!.value.trim(),
        currency: currency,
      );
      if (parsed == null) {
        return const TransactionEditRejected(<String>[
          TransactionField.amount,
        ], amountProblem: AmountProblemOnEdit.unparsable);
      }
      if (violationForAmount(parsed) == AmountViolation.negative) {
        // The sign convention, enforced on the edit path as well as the create
        // path. An edit is exactly as capable of inverting a movement's
        // direction as an entry is (defect O-QA-2), and a total that flipped
        // sign because someone typed a minus while correcting a typo would be
        // very hard to explain afterwards.
        return const TransactionEditRejected(<String>[
          TransactionField.amount,
        ], amountProblem: AmountProblemOnEdit.negative);
      }
      amount = Edited<Money>(parsed);
    }

    if (draft.direction != null &&
        !MovementDirection.isKnown(draft.direction!.value)) {
      return const TransactionEditRejected(<String>[
        TransactionField.direction,
      ]);
    }

    final Set<String> before = decodeUserEditedFields(
      existing.userEditedFields,
    );

    await transactionDao.applyUserEdit(
      id: id,
      amount: amount,
      merchantRawText: draft.merchantRawText,
      occurredAt: draft.occurredAt,
      direction: draft.direction,
      transactionType: draft.transactionType,
      categoryId: draft.categoryId,
      instrumentId: draft.instrumentId,
      counterpartyName: draft.counterpartyName,
      now: now,
    );

    // Re-read to report exactly which fields the DAO judged to have changed,
    // rather than which ones the form offered. The two differ whenever the
    // user "changes" a value to what it already was, and the caller (a toast,
    // a test) should hear about the real change set.
    final TransactionRow? after = await transactionDao.byIdOrNull(id);
    final Set<String> nowProtected = decodeUserEditedFields(
      after?.userEditedFields,
    );
    final List<String> changedFields = nowProtected.difference(before).toList()
      ..sort();

    // **KHA-101 — the two correction surfaces agree.** Correcting a category
    // from the detail screen must teach the same rule that correcting it from
    // the categorization surface does, or AC-D2.1's electric-bill promise
    // ("the next bill arrives already categorized") is false for anyone who
    // uses this form.
    //
    // Gated on `changedFields`, not on `draft.categoryId != null`: the DAO is
    // the authority on whether the value actually moved, and someone who
    // pressed Save without touching the category has taught nothing. The flag
    // half of this defect is fixed at the write boundary in
    // `TransactionDao.applyUserEdit`, so it holds even for a caller that never
    // reaches this service.
    final LearnCategoryRule? learner = learnCategoryRule;
    final Edited<String?>? categoryEdit = draft.categoryId;
    if (learner != null &&
        categoryEdit != null &&
        changedFields.contains(TransactionField.categoryId)) {
      // Both nullable locals are tested rather than `!`-asserted. The pair is
      // provably consistent today — `applyUserEdit` only marks `categoryId`
      // touched when the caller passed it — but that is an invariant held in
      // another file, and a null-assertion that depends on one is a crash
      // waiting for someone to add a second way of marking a field edited.
      await learner(
        transactionId: id,
        categoryId: categoryEdit.value,
        now: now,
      );
    }

    return TransactionEditApplied(changedFields);
  }

  /// **AC-B6.1/B6.2/B6.4** — soft-deletes a transaction after the caller has
  /// obtained an explicit confirmation.
  ///
  /// The confirmation itself is the UI's job (AC-B6.2 requires a
  /// `ConfirmationDialog`, design.md flow H); this method is the write. It is
  /// named `softDelete` rather than `delete` at every layer so nobody reaches
  /// for it thinking it destroys anything.
  Future<void> softDelete(int id, {DateTime? now}) => transactionDao.softDelete(
    id: id,
    actor: 'user',
    actorDetail: 'user_delete',
    now: now,
  );

  /// **AC-B8.2** — restores a soft-deleted transaction with its history
  /// intact. See [TransactionDao.restore] for why "intact" is literal here.
  Future<void> restore(int id, {DateTime? now}) => transactionDao.restore(
    id: id,
    actor: 'user',
    actorDetail: 'user_restore',
    now: now,
  );
}

/// **AC-B5.2 — "the detail view shows BOTH the original auto-detected value
/// and the user-edited value."**
///
/// ## Why this is read from the audit trail rather than a stored column
///
/// The tempting implementation is an `original_merchant` column written once
/// at ingestion. It is worse in three ways: it needs a twin column per
/// editable field, it says nothing about *who* changed the value or *when*,
/// and — the real problem — it is a second copy of a fact the audit trail
/// already records, free to drift from it. NFR-A2 already requires every
/// mutation to carry `{field, from, to}`; AC-B5.2 is that data, read back.
///
/// The "original" is the `from` of the **earliest** entry that mentions the
/// field, so a field edited three times still shows what the parser first
/// produced rather than the previous edit.
final class TransactionEditHistory {
  /// Field name → the value before any user edit. Only fields that have
  /// actually been edited appear.
  final Map<String, String?> originalValues;

  const TransactionEditHistory(this.originalValues);

  static const TransactionEditHistory none = TransactionEditHistory(
    <String, String?>{},
  );

  /// The parser's original value for [field], or null if the user never
  /// changed it (in which case the row's current value *is* the original and
  /// the detail view shows one value, not two).
  String? originalFor(String field) => originalValues[field];

  bool get isEmpty => originalValues.isEmpty;

  /// Builds the history from one transaction's audit entries, **oldest
  /// first** — which is the order [AuditLogDao.queryFor] returns them in.
  ///
  /// Only `update` entries by a human actor are considered. A `create` entry's
  /// `from` is null by definition (there was no previous value), and a
  /// `system_rule` or `parser` update is not a *user* edit — showing "the
  /// original was X" because a rule pack re-classified something would put
  /// words in the user's mouth.
  static TransactionEditHistory fromAuditEntries(
    Iterable<AuditEntryRow> entries,
    AuditLogDao dao,
  ) {
    final Map<String, String?> originals = <String, String?>{};
    for (final AuditEntryRow entry in entries) {
      if (entry.action != 'update' || entry.actor != 'user') {
        continue;
      }
      for (final AuditFieldChange change in dao.decodeFieldChanges(entry)) {
        // `putIfAbsent`: the *first* recorded `from` for a field is the
        // parser's value. Later edits overwrite each other's `to`, never this.
        originals.putIfAbsent(change.field, () => change.from);
      }
    }
    return TransactionEditHistory(originals);
  }
}
