import 'package:drift/drift.dart';

import '../../core/money/currency_exponents.dart';
import '../../core/money/money.dart';
import '../../core/money/sign_convention.dart';
import '../../core/types/edited.dart';
import '../db/app_database.dart';
import '../db/tables/transaction_table.dart';
import 'audit_log_dao.dart';
import 'category_fields.dart';
import 'user_edited_fields.dart';

export '../../core/types/edited.dart' show Edited;
export 'category_fields.dart'
    show
        CategoryReviewReason,
        StoredCategorySource,
        isUserOwnedCategory,
        normalizeStoredCategoryId,
        uncategorizedCategoryId;
export 'user_edited_fields.dart'
    show TransactionField, decodeUserEditedFields, encodeUserEditedFields;

part 'transaction_dao.g.dart';

/// One stored ADR-002 money triple, carried **verbatim** between two rows.
///
/// ## Why a triple of raw column values and not a `Money`
///
/// KHA-87's fix has to move an absorbed row's fee (or converted amount) onto
/// the survivor without changing it. Parsing the stored text into a [Money]
/// and re-serialising it would be a round trip through two conversions that
/// can *fail* (`Money.tryParse` returns null on anything it does not like) and
/// that recomputes `..._minor` — the non-authoritative indexing column ADR-002
/// says is never the source of truth. A byte-for-byte copy of the three
/// columns cannot lose a fraction, cannot fail, and cannot disagree with what
/// the original write path stored.
///
/// There is deliberately no `double`/`num` anywhere in this type. The
/// authoritative value is [amount], an exact decimal **string**.
final class MoneyColumns {
  /// The authoritative exact decimal string, e.g. `'9.2'`.
  final String amount;

  /// ISO-ish currency code as stored, e.g. `'SAR'`.
  final String currency;

  /// The non-authoritative minor-unit column, copied as-is (may be null on a
  /// row written before the exponent for its currency was known).
  final int? minor;

  const MoneyColumns({
    required this.amount,
    required this.currency,
    this.minor,
  });

  /// Reads the triple off a row, or null when the row holds no such amount.
  ///
  /// Both text columns must be present: half a money triple is not a value,
  /// and treating it as one is how a currency-less number reaches a total.
  static MoneyColumns? read(String? amount, String? currency, int? minor) {
    if (amount == null || currency == null) {
      return null;
    }
    return MoneyColumns(amount: amount, currency: currency, minor: minor);
  }

  /// Value equality on the **authoritative** pair only. Two rows written by
  /// this app for the same amount hold byte-identical text (the same reasoning
  /// `MergePlan.between` already applies to `amount_amount`), and `minor` is
  /// derived, so letting it participate would make a merge refuse on a
  /// difference that carries no information.
  @override
  bool operator ==(Object other) =>
      other is MoneyColumns &&
      other.amount == amount &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  /// NFR-S4: an amount is not personal data, but keep the habit of terse
  /// diagnostics anyway.
  @override
  String toString() => 'MoneyColumns($amount $currency)';
}

/// The fields a merge will copy onto the surviving transaction.
///
/// **Every field here is null-means-"leave it alone".** There is no
/// `Edited<T>` wrapper on purpose, and the asymmetry with
/// [TransactionDao.applyUserEdit] is the point: an *edit* must be able to
/// clear a field, because the user may be removing something wrong; a *merge*
/// may only ever fill a gap. ADR-017 D2 says a merge "enriches" — it adds
/// information that was missing. Letting it write null would let it delete
/// information, which is the R-8 failure mode wearing a different hat.
///
/// ## KHA-87 — the money-bearing fields are here now
///
/// P3b-2 shipped this type carrying five descriptive fields only. QA (D-QA-5 /
/// D-QA-6) demonstrated the consequence by execution: the absorbed row is
/// soft-deleted *whole*, so its FX fee and its bank-supplied converted amount
/// left the ledger with it and a reported figure — `report.fees.base`,
/// `report.spend.base` — silently went from a real number to null. That is
/// KHA-74's failure mode (money absent from a total with no signal) arriving
/// through a new write path.
///
/// So the money columns now travel under the **same** gap-fill rule as the
/// descriptive ones: copied only when the survivor has nothing there, never
/// overwriting. Where both rows hold a value and the values disagree,
/// `MergePlan.between` refuses the pair outright rather than picking a winner
/// — see `MergeRefusal` in `lib/features/ledger/transaction_merge.dart`.
///
/// Built by `MergePlan.between` in
/// `lib/features/ledger/transaction_merge.dart`, which is where the policy
/// (and its tests) live.
final class MergeEnrichment {
  final String? merchantRawText;
  final String? referenceNumber;
  final String? counterpartyName;
  final DateTime? occurredAt;
  final int? instrumentId;

  // --- KHA-87: the money-bearing columns -----------------------------------

  /// PRD §3.4's separately-reported FX/international fee.
  final MoneyColumns? feeAmount;

  /// ADR-009's bank-supplied conversion into the base currency.
  final MoneyColumns? convertedAmount;

  /// Informational only; never summed (see the column's own doc comment).
  final MoneyColumns? remainingBalance;

  /// The FX rate as an exact decimal **string** (ADR-002: a rate is not a
  /// float and not a `Money`).
  final String? fxRate;
  final DateTime? fxRateDate;
  final String? fxRateSource;

  /// ADR-009 case 4. **The one field here that is not a gap-fill**: it is
  /// derived state ("this row has no conversion at all"), so when a merge
  /// hands the survivor a conversion it must also stop claiming the survivor
  /// is waiting for one. `MergePlan.between` sets this to `false` in exactly
  /// that case and leaves it null otherwise.
  final bool? conversionPending;

  // --- AC-B11.2: the user's internal-transfer verdict ----------------------

  /// A decision the **user** recorded (`internal` | `candidate` | `external`),
  /// carried with its group id or not at all.
  ///
  /// Not money, but it decides whether money counts: an `internal` leg is out
  /// of spend and an `external` one is in it, and a stored verdict outranks
  /// anything the read-time detector would derive. Leaving it on a
  /// soft-deleted row would make the user's answer silently stop applying and
  /// move the spend figure — in *either* direction, so there is no "safe" way
  /// to drop it. A disagreement between the two rows is refused
  /// (`MergeRefusal.spendEffectDiffers`) rather than resolved here.
  final String? internalTransferState;
  final String? internalTransferGroupId;

  // --- KHA-89 / D-QA-11: protection travels with the value -----------------

  /// Field names (from [TransactionField]) whose value is being copied from
  /// the absorbed row **and was user-edited there**.
  ///
  /// Without this, a merge copies a person's correction onto the survivor and
  /// the survivor records it as parser output, so the next automated writer
  /// (another merge, a re-scan, P7's statement import) is free to overwrite
  /// it. AC-B5.3 is *"user intent outranks the parser, always"*, and intent
  /// that silently loses its protection in transit does not outrank anything.
  final Set<String> protectedFields;

  const MergeEnrichment({
    this.merchantRawText,
    this.referenceNumber,
    this.counterpartyName,
    this.occurredAt,
    this.instrumentId,
    this.feeAmount,
    this.convertedAmount,
    this.remainingBalance,
    this.fxRate,
    this.fxRateDate,
    this.fxRateSource,
    this.conversionPending,
    this.internalTransferState,
    this.internalTransferGroupId,
    this.protectedFields = const <String>{},
  });

  /// Nothing to copy — the survivor already knew everything the other row did.
  static const MergeEnrichment none = MergeEnrichment();

  /// True when this merge would change no field on the survivor. The merge is
  /// still worth performing (it is what removes the duplicate from the total),
  /// but the UI can describe it differently.
  bool get isEmpty =>
      merchantRawText == null &&
      referenceNumber == null &&
      counterpartyName == null &&
      occurredAt == null &&
      instrumentId == null &&
      feeAmount == null &&
      convertedAmount == null &&
      remainingBalance == null &&
      fxRate == null &&
      fxRateDate == null &&
      fxRateSource == null &&
      conversionPending == null &&
      internalTransferState == null &&
      internalTransferGroupId == null &&
      protectedFields.isEmpty;

  /// True when this merge moves a **reported money figure** onto the survivor.
  ///
  /// Separate from [isEmpty] so a caller (and a test) can distinguish "the
  /// survivor gained a merchant name" from "the survivor gained the fee that
  /// would otherwise have left the ledger". `remainingBalance` is excluded
  /// deliberately: it enters no total.
  bool get carriesMoney =>
      feeAmount != null || convertedAmount != null || fxRate != null;

  /// No merchant, no counterparty (NFR-S4).
  @override
  String toString() => 'MergeEnrichment(empty: $isEmpty, money: $carriesMoney)';
}

/// A P1-minimal ledger DAO — see `lib/data/db/tables/transaction_table.dart`
/// for why this table is intentionally small. Its purpose in this phase is
/// to prove the audit-trail mechanism (ADR-010) against a genuine mutation
/// path: every method below that changes a row also writes an
/// [AuditLogDao.append] call **inside the same Drift `transaction()`
/// block**, so the ledger row and its audit entry can never drift apart —
/// either both are committed, or (on any error) neither is, which is what
/// NFR-R6 ("an app crash ... must not corrupt or lose already-recorded
/// transactions") requires of the write path.
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  final AuditLogDao auditLogDao;

  TransactionDao(super.attachedDatabase, this.auditLogDao);

  /// Creates a new transaction row and its matching `create` audit entry.
  ///
  /// ## KHA-79 — this method is guarded now, and that is a behaviour change
  ///
  /// P3b-1 settled the sign convention (`lib/core/money/sign_convention.dart`)
  /// and guarded the two *shipping* write paths, but not this one, because it
  /// had no production caller: it is a P1-era method whose original purpose
  /// was to prove the audit mechanism. QA found the gap and, more to the
  /// point, found a green test **pinning the wrong invariant** — that
  /// `create()` accepted a negative amount and round-tripped its sign.
  ///
  /// P3b-2 is the phase that adds real callers reaching for exactly this
  /// method (manual entry, the enrichment merge, transfer confirmation), so
  /// the guard lands *before* they do rather than after. The test that pinned
  /// the old behaviour has been rewritten to pin the rejection —
  /// deliberately, in the same change, because "a currently-green test asserts
  /// the opposite" is the situation in which a correct guard gets reverted by
  /// the next person instead of the test being fixed.
  ///
  /// **Note for callers and test authors:** [checkMovementAmount] throws
  /// *synchronously*, before this method's `Future` is ever constructed. A
  /// `.catchError(...)` on the returned future will not see it, and a test
  /// must write `expect(() => dao.create(...), throwsA(...))` rather than
  /// `expectLater(dao.create(...), throwsA(...))`.
  Future<int> create({
    String? merchantRawText,
    required Money amount,
    String? categoryId,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    checkMovementAmount(amount, context: 'create');
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          // Normalised even here, on a method with no production caller, so
          // that no write path in this DAO can be the one that stores the
          // literal `uncategorized` id (see `category_fields.dart`). The
          // provenance columns are deliberately left unset: this method takes
          // an arbitrary `actor` and cannot honestly claim the category was
          // a user's choice or a rule's.
          categoryId: Value<String?>(normalizeStoredCategoryId(categoryId)),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );
      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'create',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'amount',
            from: null,
            to: amount.toCanonicalString(),
          ),
          AuditFieldChange(
            field: 'currency',
            from: null,
            to: amount.currencyCode,
          ),
          if (merchantRawText != null)
            AuditFieldChange(
              field: 'merchantRawText',
              from: null,
              to: merchantRawText,
            ),
        ],
      );
      return id;
    });
  }

  /// **The user's own categorization** (US-C2, AC-D3.1) — writes the category,
  /// records it as user-chosen, and protects it from every automatic path.
  ///
  /// ## Four columns move together, and that is the point
  ///
  /// P1 shipped an `updateCategory` that wrote `category_id` alone. P4a
  /// replaces it, because a category id now travels with three facts about
  /// *how it got there* (`category_source`, `category_confidence`,
  /// `category_rule_id`), and a method that wrote one without the others would
  /// leave a row saying "a rule put this here" about a choice a person made.
  /// There is deliberately no remaining method on this DAO that writes
  /// `category_id` without also settling its provenance.
  ///
  /// ## Why this also writes `user_edited_fields`
  ///
  /// That column is the app's existing answer to *"may an automatic path
  /// overwrite this field?"* (AC-B5.3, `user_edited_fields.dart`), and it is
  /// already consulted by the enrichment merge. Reusing it — rather than
  /// giving categories a private protection flag — means **AC-D3.1's "user
  /// correction always wins" is enforced by two independent mechanisms** that
  /// were not written by the same phase: this column, and
  /// [applyAutomaticCategory]'s explicit source check.
  ///
  /// ## Uncategorized is stored as NULL
  ///
  /// Passing the literal `uncategorized` id is normalised to null here, so the
  /// database holds exactly one representation of "uncategorized" — see the
  /// column's doc comment in `transaction_table.dart`. Choosing Uncategorized
  /// explicitly is still a *user choice*, so it still protects the field: the
  /// app must not re-categorise something the user deliberately blanked.
  /// [merchantId] links the transaction to the merchant row the correction
  /// taught a rule about (KHA-31). Left absent when null, so a caller with no
  /// merchant cannot accidentally *unlink* one that is already there.
  Future<void> setUserCategory({
    required int id,
    required String? categoryId,
    int? merchantId,
    String actor = 'user',
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    final String? storedId = normalizeStoredCategoryId(categoryId);

    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      final Set<String> protectedFields = <String>{
        ...decodeUserEditedFields(existing.userEditedFields),
        TransactionField.categoryId,
      };

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          categoryId: Value<String?>(storedId),
          categorySource: const Value<String?>(StoredCategorySource.user),
          // Certainty by construction: a person said so. Recorded rather than
          // left null so a screen can render one confidence rule for every
          // row instead of special-casing the null.
          categoryConfidence: const Value<double?>(1.0),
          // The rule (if one had fired) no longer explains this category, and
          // leaving its id would make the detail screen credit a rule for the
          // user's own decision.
          categoryRuleId: const Value<int?>(null),
          merchantId: merchantId == null
              ? const Value<int?>.absent()
              : Value<int?>(merchantId),
          userEditedFields: Value<String?>(
            encodeUserEditedFields(protectedFields),
          ),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      // The category question is answered, so a review flag raised *by the
      // categorizer* is spent (AC-C4.3). A flag raised by anything else —
      // a possible duplicate, an unproven transfer — is untouched: those are
      // different questions and answering one does not answer the other.
      await _clearCategoryReviewFlag(id: id, existing: existing);

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        // ADR-010's vocabulary has a word for this and it is not `update`.
        action: 'categorize',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: TransactionField.categoryId,
            from: existing.categoryId,
            to: storedId,
          ),
          AuditFieldChange(
            field: 'categorySource',
            from: existing.categorySource,
            to: StoredCategorySource.user,
          ),
        ],
      );
    });
  }

  /// **An automatic categorization** (AC-D2.1, AC-D2.2, AC-F5.2) — applied
  /// only if no person has already answered the question.
  ///
  /// Returns true when the category was written, false when the write was
  /// refused because the user owns the field.
  ///
  /// ## The refusal is here, at the write boundary, on purpose
  ///
  /// `CategorizationService` checks the same thing before it even matches, and
  /// that check is the one that normally fires. This one exists because
  /// AC-D3.1 — *"the user's explicit choice is never silently overridden by
  /// any automatic re-learning"* — must survive a **future** caller that has
  /// not read the service. `checkMovementAmount` is guarded in the same
  /// belt-and-braces way and for the same reason (KHA-79: the unguarded path
  /// was the one that had no caller yet).
  ///
  /// Two signals are consulted, either of which vetoes the write:
  ///
  ///  - `user_edited_fields` contains `categoryId` — the app-wide "a person
  ///    edited this" mechanism;
  ///  - `category_source` is already `user` — the categorization-specific
  ///    statement of the same fact.
  ///
  /// They are redundant by design. A row written by [setUserCategory] carries
  /// both, so a bug that dropped one would still be caught by the other.
  Future<bool> applyAutomaticCategory({
    required int id,
    required String? categoryId,
    required double confidence,
    int? ruleId,
    int? merchantId,
    required String actorDetail,
    bool flagForReview = false,
    String? reviewReason,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    final String? storedId = normalizeStoredCategoryId(categoryId);

    return transaction<bool>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      if (isUserOwnedCategory(existing)) {
        // Not an error, and not silent either: the caller is told, and the
        // stored row keeps the user's answer. Nothing is written at all — not
        // even the merchant link — because a write here is what the AC forbids.
        return false;
      }

      final bool applying = storedId != existing.categoryId;

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          categoryId: Value<String?>(storedId),
          categorySource: Value<String?>(
            storedId == null
                ? StoredCategorySource.none
                : StoredCategorySource.rule,
          ),
          categoryConfidence: Value<double?>(confidence),
          categoryRuleId: Value<int?>(ruleId),
          // Recorded even when nothing was categorised: knowing *which* shop
          // this was is useful on its own, and it is what stops a second
          // merchant row being created for the same key next time.
          merchantId: Value<int?>(merchantId),
          // Only ever raises a flag, never lowers one: an existing flag was
          // raised by a different question (a possible duplicate, an unproven
          // transfer) and clearing it here would answer a question nobody
          // asked. See `_clearCategoryReviewFlag` for the only lowering path.
          needsReview: flagForReview
              ? const Value<bool>(true)
              : const Value<bool>.absent(),
          reviewReason: flagForReview && !existing.needsReview
              ? Value<String?>(reviewReason)
              : const Value<String?>.absent(),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      // **AC-F5.2 / NFR-A2 — "every automatic categorization writes an audit
      // entry attributed to the SYSTEM and naming the rule that fired."**
      //
      // Written only when a category was actually applied. A pass that found
      // nothing has not categorised anything, and an entry saying "the system
      // considered this and did nothing" on every uncategorised transaction
      // would bury the entries that record a real decision (US-F5 is read by
      // a person). The row still says so, in `category_source = 'none'`.
      if (applying && storedId != null) {
        await auditLogDao.append(
          entityType: 'transaction',
          entityId: id.toString(),
          action: 'categorize',
          // ADR-010's actor vocabulary. Not 'user' — the whole value of this
          // entry is that it distinguishes what the app did from what the
          // person did.
          actor: 'system_rule',
          // Names the rule that fired, which is the "why" AC-D2.2 wants and
          // the "which rule applied" AC-F5.2 requires.
          actorDetail: actorDetail,
          changedAt: timestamp,
          fieldChanges: <AuditFieldChange>[
            AuditFieldChange(
              field: TransactionField.categoryId,
              from: existing.categoryId,
              to: storedId,
            ),
            AuditFieldChange(
              field: 'categoryConfidence',
              from: existing.categoryConfidence?.toString(),
              to: confidence.toString(),
            ),
          ],
        );
      }

      return true;
    });
  }

  /// Lowers a review flag **only** when the categorizer is the one that raised
  /// it.
  ///
  /// The check is on [TransactionRow.reviewReason], not on the boolean: a row
  /// flagged as a possible duplicate is still a possible duplicate after the
  /// user categorises it, and clearing that would hide an unresolved money
  /// question behind an unrelated action.
  Future<void> _clearCategoryReviewFlag({
    required int id,
    required TransactionRow existing,
  }) async {
    if (!existing.needsReview ||
        !categoryReviewReasons.contains(existing.reviewReason)) {
      return;
    }
    await (update(
      transactions,
    )..where((Transactions t) => t.id.equals(id))).write(
      const TransactionsCompanion(
        needsReview: Value<bool>(false),
        reviewReason: Value<String?>(null),
      ),
    );
  }

  /// Soft-deletes a transaction (US-B8: hidden and restorable — only
  /// "erase everything", ADR-011/P8, is a true hard delete, AC-B8.3).
  Future<void> softDelete({
    required int id,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          isDeleted: const Value<bool>(true),
          // P3a: AC-B6.4 asks the change history to show *when* a deletion
          // happened. The audit entry has always carried that, and now the
          // row does too, which is what the Recently Deleted list (US-B8)
          // orders by.
          deletedAt: Value<DateTime?>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'delete',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'isDeleted',
            from: existing.isDeleted.toString(),
            to: 'true',
          ),
        ],
      );
    });
  }

  /// Restores a soft-deleted transaction (US-B8, **AC-B8.2**).
  ///
  /// ## "With its full prior history intact"
  ///
  /// AC-B8.2 asks for the transaction back *with its history*, and the shape
  /// of this method is what delivers that literally rather than approximately:
  /// a soft delete never removed anything, so restoring is a single boolean
  /// flip. No row is recreated, so the row **id is the same id**, so every
  /// audit entry ever written against it — including the deletion — is still
  /// addressed by `queryFor('transaction', id)` and still chained. A
  /// delete-then-reinsert implementation would produce a new id and orphan the
  /// entire history, which is the failure this AC is written to prevent.
  ///
  /// The restore itself is appended to that same history, so the record reads
  /// created → deleted → restored, not created → (gap).
  ///
  /// [reads the row first] so the audit entry carries a genuine before/after
  /// (NFR-A2) instead of the previously hard-coded `from: 'true'` — which was
  /// a *claim* about the prior state rather than an observation of it, and
  /// would have been a lie for any row that was not actually deleted.
  ///
  /// ## KHA-88 / D-QA-8 — undoing a merge touches a **second** row
  ///
  /// Restoring a row that was merged away is how a user undoes a merge, so
  /// this method also has to unpick the survivor's half of the link. P3b-2
  /// wrote that as an unconditional clear, which was correct only for a
  /// survivor that had ever absorbed exactly one row. QA reproduced both
  /// consequences:
  ///
  ///  1. **It cleared a pointer that named a different row.** With two merges
  ///     into one survivor, undoing the *first* nulled the survivor's pointer
  ///     to the *second*. The two halves of the link then contradicted each
  ///     other and nothing in the app could detect it. The clear is now
  ///     guarded by an identity check: the survivor's
  ///     `merged_from_transaction_id` is cleared **only when it names the row
  ///     being restored**.
  ///  2. **It wrote to the survivor and audited nothing against it.** NFR-A2
  ///     is *"every mutation writes an append-only audit entry"*, and
  ///     `transaction_merge.dart` says in its own words that *"an undo that
  ///     left no trace would be its own audit failure"* — which was true of
  ///     the absorbed row only. The survivor now gets its own `merge_undo`
  ///     entry, appended **inside this same `transaction()` block** as the
  ///     write it describes, so the row and its history cannot drift apart.
  Future<void> restore({
    required int id,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          isDeleted: const Value<bool>(false),
          deletedAt: const Value<DateTime?>(null),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'restore',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'isDeleted',
            from: existing.isDeleted.toString(),
            to: 'false',
          ),
          // Restoring a row that was merged away is how a user undoes a merge.
          // Recording the pointer's removal makes that reversal explicit in
          // the history rather than something the reader has to infer.
          if (existing.mergedIntoId != null)
            AuditFieldChange(
              field: 'mergedIntoId',
              from: existing.mergedIntoId.toString(),
              to: null,
            ),
        ],
      );

      if (existing.mergedIntoId != null) {
        final int survivorId = existing.mergedIntoId!;

        // The restored row stops claiming it was absorbed. Unconditional, and
        // safely so: this pointer is on the row being restored, so it cannot
        // name anybody else's merge.
        await (update(
          transactions,
        )..where((Transactions t) => t.id.equals(id))).write(
          const TransactionsCompanion(mergedIntoId: Value<int?>(null)),
        );

        // The survivor's half, guarded. `getSingleOrNull` rather than
        // `getSingle` because a dangling id is data we should not crash on:
        // the undo of *this* row's merge must still complete.
        final TransactionRow? survivor =
            await (select(transactions)
                  ..where((Transactions t) => t.id.equals(survivorId)))
                .getSingleOrNull();

        // **The identity check (D-QA-8).** Clear the survivor's pointer only
        // when it actually names the row being restored. If the survivor has
        // since absorbed a different duplicate, that later merge is none of
        // this undo's business and its link stays intact.
        if (survivor != null && survivor.mergedFromTransactionId == id) {
          await (update(
            transactions,
          )..where((Transactions t) => t.id.equals(survivorId))).write(
            TransactionsCompanion(
              mergedFromTransactionId: const Value<int?>(null),
              updatedAt: Value<DateTime>(timestamp),
            ),
          );

          // NFR-A2: the survivor row was mutated, so the survivor's own
          // history records it. Without this the change history reads
          // "created, merged" with no reversal, and US-F5 shows a merge that
          // was undone as though it still stands.
          //
          // A distinct action name (`merge_undo`, not `restore`) because this
          // entry is about a row that was never deleted and is not being
          // restored — it is the survivor losing an absorbed duplicate.
          await auditLogDao.append(
            entityType: 'transaction',
            entityId: survivorId.toString(),
            action: 'merge_undo',
            actor: actor,
            actorDetail: actorDetail ?? 'duplicate_merge_undo_survivor',
            changedAt: timestamp,
            fieldChanges: <AuditFieldChange>[
              AuditFieldChange(
                field: 'mergedFromTransactionId',
                from: id.toString(),
                to: null,
              ),
            ],
          );
        }
      }
    });
  }

  // -------------------------------------------------------------------------
  // P2 — the SMS ingestion write path (ADR-006, ADR-007, ADR-017)
  // -------------------------------------------------------------------------

  /// Writes a transaction derived from a parsed SMS, together with its
  /// `create` audit entry, in **one** database transaction.
  ///
  /// ## Read the `actor` argument carefully
  ///
  /// NFR-A2 requires the audit trail to name the actor, and to distinguish
  /// "the user did this" from "a rule did this". Ingestion writes
  /// `actor: 'parser'` with `actorDetail: <ruleId>`, so the change history
  /// (US-F5) can say *"auto-detected by rule `baj-pos-purchase-ar` from pack
  /// `sa-core@2026.07.28`"* rather than the useless *"created"*. Getting this
  /// wrong makes every later "why is this number what it is?" unanswerable.
  ///
  /// Returns the new row id. Does **not** advance the ingestion watermark —
  /// that is the caller's job, and it must happen inside the caller's own
  /// `transaction()` block together with this write (ADR-006).
  Future<int> insertFromParsedSms({
    required Money amount,
    Money? convertedAmount,
    Money? feeAmount,
    String? fxRate,
    DateTime? fxRateDate,
    String? fxRateSource,
    bool conversionPending = false,
    Money? remainingBalance,
    String? merchantRawText,
    String? counterpartyName,
    String? counterpartyBankName,
    DateTime? occurredAt,
    String? timeSource,
    required String direction,
    required String transactionType,
    required bool affectsSpend,
    String? referenceNumber,
    String? instrumentKind,
    String? instrumentMaskedRef,
    int? instrumentId,
    required int sourceMessageId,
    required String rulePackId,
    required String rulePackVersion,
    required String ruleId,
    bool needsReview = false,
    String? reviewReason,
    int? possibleDuplicateOfId,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    // Defence in depth for the sign convention: the pipeline already routes a
    // negative or zero amount to the review queue rather than reaching here
    // (see `IngestionPipeline._writeTransaction`), so this throw is for a
    // future caller that forgets. Failing loudly at the write boundary beats
    // a negative magnitude reaching a total three screens away, where it
    // would silently invert the movement direction — defect O-QA-2's shape.
    checkMovementAmount(amount, context: 'insertFromParsedSms');
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          convertedAmountAmount: Value<String?>(
            convertedAmount?.toCanonicalString(),
          ),
          convertedAmountCurrency: Value<String?>(
            convertedAmount?.currencyCode,
          ),
          convertedAmountMinor: Value<int?>(
            convertedAmount == null
                ? null
                : _toMinorUnitsBestEffort(convertedAmount),
          ),
          feeAmountAmount: Value<String?>(feeAmount?.toCanonicalString()),
          feeAmountCurrency: Value<String?>(feeAmount?.currencyCode),
          feeAmountMinor: Value<int?>(
            feeAmount == null ? null : _toMinorUnitsBestEffort(feeAmount),
          ),
          fxRate: Value<String?>(fxRate),
          // KHA-70 / AC-B9.3. All three are written from what the message
          // supported and are left NULL/false otherwise — never defaulted, so
          // "we do not know the rate date" stays distinguishable from "the
          // rate date is today".
          fxRateDate: Value<DateTime?>(fxRateDate),
          fxRateSource: Value<String?>(fxRateSource),
          conversionPending: Value<bool>(conversionPending),
          remainingBalanceAmount: Value<String?>(
            remainingBalance?.toCanonicalString(),
          ),
          remainingBalanceCurrency: Value<String?>(
            remainingBalance?.currencyCode,
          ),
          remainingBalanceMinor: Value<int?>(
            remainingBalance == null
                ? null
                : _toMinorUnitsBestEffort(remainingBalance),
          ),
          counterpartyName: Value<String?>(counterpartyName),
          counterpartyBankName: Value<String?>(counterpartyBankName),
          occurredAt: Value<DateTime?>(occurredAt),
          timeSource: Value<String?>(timeSource),
          direction: Value<String>(direction),
          transactionType: Value<String>(transactionType),
          affectsSpend: Value<bool>(affectsSpend),
          referenceNumber: Value<String?>(referenceNumber),
          instrumentKind: Value<String?>(instrumentKind),
          instrumentMaskedRef: Value<String?>(instrumentMaskedRef),
          // P3a: the resolved FK. Null is AC-B1.3's explicit unknown — the
          // message named no instrument, or named one we could not key on.
          instrumentId: Value<int?>(instrumentId),
          provenance: const Value<String>('sms'),
          sourceMessageId: Value<int?>(sourceMessageId),
          rulePackId: Value<String?>(rulePackId),
          rulePackVersion: Value<String?>(rulePackVersion),
          ruleId: Value<String?>(ruleId),
          needsReview: Value<bool>(needsReview),
          reviewReason: Value<String?>(reviewReason),
          possibleDuplicateOfId: Value<int?>(possibleDuplicateOfId),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'create',
        actor: 'parser',
        actorDetail: '$rulePackId@$rulePackVersion/$ruleId',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'amount',
            from: null,
            to: amount.toCanonicalString(),
          ),
          AuditFieldChange(
            field: 'currency',
            from: null,
            to: amount.currencyCode,
          ),
          AuditFieldChange(
            field: 'transactionType',
            from: null,
            to: transactionType,
          ),
          AuditFieldChange(field: 'direction', from: null, to: direction),
          AuditFieldChange(
            field: 'provenance',
            from: null,
            to: 'sms#$sourceMessageId',
          ),
          if (merchantRawText != null)
            AuditFieldChange(
              field: 'merchantRawText',
              from: null,
              to: merchantRawText,
            ),
        ],
      );
      return id;
    });
  }

  // -------------------------------------------------------------------------
  // P3a — completing an unparsed message by hand (KHA-64, S-19, AC-A4.2)
  // -------------------------------------------------------------------------

  /// Writes the transaction a user produced by filling in the fields the
  /// parser could not read, together with its `create` audit entry.
  ///
  /// ## Why this is not `insertFromParsedSms` with a different actor
  ///
  /// Three things differ, and each of them matters to somebody:
  ///
  ///  - **Actor is `user`, not `parser`** (NFR-A2). The change history must
  ///    not claim a rule produced numbers a person typed; that is precisely
  ///    the distinction ADR-010 asks the actor field to carry.
  ///  - **`provenanceDetail` is `manual_completion`** while `provenance`
  ///    stays `sms` and [sourceMessageId] stays set. KHA-64 is explicit:
  ///    *"Provenance must record this as SMS-derived-with-manual-completion,
  ///    not as plain manual entry — the source message reference is still
  ///    real and NFR-A1 must not lose it."*
  ///  - **There is no rule reference.** No rule matched; recording one would
  ///    be a lie the parser-health panel would then act on.
  ///
  /// The caller is responsible for reclassifying the raw message so it leaves
  /// the review queue — see `UnparsedCompletionService`, which does both
  /// inside one database transaction.
  Future<int> insertManualCompletion({
    required Money amount,
    String? merchantRawText,
    required DateTime occurredAt,
    required String direction,
    required String transactionType,
    required bool affectsSpend,
    int? instrumentId,
    String? instrumentKind,
    String? instrumentMaskedRef,
    String? referenceNumber,
    required int sourceMessageId,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    // **This is defect O-QA-2's write path.** The S-19 form accepted a
    // negative amount and let it invert the movement direction; KHA-26 owns
    // the field-level validation and the error message, but the invariant
    // itself belongs here, where every completion must pass through it.
    // `lib/core/money/sign_convention.dart` states the contract the form has
    // to satisfy.
    checkMovementAmount(amount, context: 'insertManualCompletion');
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          occurredAt: Value<DateTime?>(occurredAt),
          // The user stated the time explicitly on the S-19 form; it did not
          // come from the message text and it is not a delivery-time
          // fallback, so neither of the SMS time sources would be honest.
          timeSource: const Value<String?>('user_stated'),
          direction: Value<String>(direction),
          transactionType: Value<String>(transactionType),
          affectsSpend: Value<bool>(affectsSpend),
          referenceNumber: Value<String?>(referenceNumber),
          instrumentKind: Value<String?>(instrumentKind),
          instrumentMaskedRef: Value<String?>(instrumentMaskedRef),
          instrumentId: Value<int?>(instrumentId),
          provenance: const Value<String>('sms'),
          provenanceDetail: const Value<String?>('manual_completion'),
          sourceMessageId: Value<int?>(sourceMessageId),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'create',
        actor: 'user',
        actorDetail: 'review_queue_completion',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'amount',
            from: null,
            to: amount.toCanonicalString(),
          ),
          AuditFieldChange(
            field: 'currency',
            from: null,
            to: amount.currencyCode,
          ),
          AuditFieldChange(
            field: 'transactionType',
            from: null,
            to: transactionType,
          ),
          AuditFieldChange(field: 'direction', from: null, to: direction),
          AuditFieldChange(
            field: 'provenance',
            from: null,
            to: 'sms#$sourceMessageId/manual_completion',
          ),
          if (merchantRawText != null)
            AuditFieldChange(
              field: 'merchantRawText',
              from: null,
              to: merchantRawText,
            ),
        ],
      );
      return id;
    });
  }

  // -------------------------------------------------------------------------
  // P3b-2 — the mutation surface (KHA-26, KHA-64, KHA-78)
  //
  // Everything below either creates a record a person typed, or changes one
  // that already exists. NFR-A2 applies to every one of them: the row change
  // and its audit entry are written inside the **same** `transaction()` block,
  // so there is no window in which a mutation exists without its history.
  // -------------------------------------------------------------------------

  /// **US-B4 — a transaction the user entered from scratch**, with no SMS
  /// behind it. Cash spending is the motivating case (OQ-19), and it is
  /// first-class rather than a fallback.
  ///
  /// ## How this differs from [insertManualCompletion], which it resembles
  ///
  /// [insertManualCompletion] completes a message the parser could not read:
  /// `provenance` stays `sms` because a real message exists and NFR-A1 must
  /// keep pointing at it. Here there is **no message at all**, so `provenance`
  /// is `manual` and `sourceMessageId` is null. That difference is what
  /// AC-B4.3's "Manual" badge is rendered from, and what lets AC-B1.2's
  /// "show me the original SMS" panel honestly say there isn't one.
  ///
  /// The sign convention is enforced here as well as in the form, for the
  /// reason stated on [create]: the form protects the person, the write
  /// boundary protects the data, and neither trusts the other.
  Future<int> insertManual({
    required Money amount,
    String? merchantRawText,
    required DateTime occurredAt,
    required String direction,
    required String transactionType,
    required bool affectsSpend,
    int? instrumentId,
    String? categoryId,
    String? referenceNumber,
    String? counterpartyName,
    DateTime? now,
  }) {
    checkMovementAmount(amount, context: 'insertManual');
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          // P4a: a category typed into the manual-entry form is a person's
          // choice, so it arrives with the same provenance `setUserCategory`
          // writes — including the protection that stops the learning loop
          // from overwriting it later (AC-D3.1). Normalised through the shared
          // helper so this path cannot be the one that stores the literal
          // `uncategorized` id.
          categoryId: Value<String?>(normalizeStoredCategoryId(categoryId)),
          categorySource: categoryId == null
              ? const Value<String?>.absent()
              : const Value<String?>(StoredCategorySource.user),
          categoryConfidence: categoryId == null
              ? const Value<double?>.absent()
              : const Value<double?>(1.0),
          userEditedFields: categoryId == null
              ? const Value<String?>.absent()
              : Value<String?>(
                  encodeUserEditedFields(<String>{TransactionField.categoryId}),
                ),
          occurredAt: Value<DateTime?>(occurredAt),
          // The user stated when it happened. Neither SMS time source would be
          // truthful, and `received_at_fallback` would be actively wrong —
          // there was no message to receive.
          timeSource: const Value<String?>('user_stated'),
          direction: Value<String>(direction),
          transactionType: Value<String>(transactionType),
          affectsSpend: Value<bool>(affectsSpend),
          referenceNumber: Value<String?>(referenceNumber),
          counterpartyName: Value<String?>(counterpartyName),
          instrumentId: Value<int?>(instrumentId),
          provenance: const Value<String>('manual'),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'create',
        actor: 'user',
        actorDetail: 'manual_entry',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'amount',
            from: null,
            to: amount.toCanonicalString(),
          ),
          AuditFieldChange(
            field: 'currency',
            from: null,
            to: amount.currencyCode,
          ),
          AuditFieldChange(
            field: 'transactionType',
            from: null,
            to: transactionType,
          ),
          AuditFieldChange(field: 'direction', from: null, to: direction),
          AuditFieldChange(field: 'provenance', from: null, to: 'manual'),
          if (merchantRawText != null)
            AuditFieldChange(
              field: 'merchantRawText',
              from: null,
              to: merchantRawText,
            ),
        ],
      );
      return id;
    });
  }

  /// **US-B5 — the user corrects a field on an existing transaction.**
  ///
  /// ## Two things happen here, and the second one is the important one
  ///
  /// 1. The named fields are written, and every actual change becomes one
  ///    `{field, from, to}` entry in a single `update` audit row. AC-B5.2's
  ///    *"the detail view shows both the original auto-detected value and the
  ///    user-edited value"* is served from exactly that record — see
  ///    `TransactionEditHistory` — rather than from a duplicate "original"
  ///    column that could drift from it.
  /// 2. Each changed field's name is added to `user_edited_fields`, which is
  ///    **AC-B5.3**: no later automated write (a re-scan, or ADR-017 D2's
  ///    enrichment merge) may overwrite it. User intent outranks the parser,
  ///    permanently, and that has to be recorded at the moment of the edit
  ///    because afterwards there is no way to tell a user's value from a
  ///    parser's.
  ///
  /// A parameter left null means *"do not touch this field"*; passing
  /// `Edited(null)` means *"clear it"* — see `core/types/edited.dart` for why
  /// that distinction needs a wrapper.
  ///
  /// Writing a value identical to the stored one is **not** recorded as a
  /// change and does not mark the field protected: the user opening the edit
  /// form and pressing Save without typing has not expressed an intent about
  /// anything, and treating that as ten permanent overrides would freeze the
  /// row against all future enrichment for no reason.
  Future<void> applyUserEdit({
    required int id,
    Edited<Money>? amount,
    Edited<String?>? merchantRawText,
    Edited<DateTime?>? occurredAt,
    Edited<String>? direction,
    Edited<String>? transactionType,
    Edited<String?>? categoryId,
    Edited<int?>? instrumentId,
    Edited<String?>? referenceNumber,
    Edited<String?>? counterpartyName,
    String actor = 'user',
    String? actorDetail,
    DateTime? now,
  }) {
    if (amount != null) {
      checkMovementAmount(amount.value, context: 'applyUserEdit');
    }
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      final List<AuditFieldChange> changes = <AuditFieldChange>[];
      final Set<String> touched = <String>{};

      // A tiny local helper so each field below is one line and the
      // "did it actually change?" test cannot be forgotten on one of them.
      void record(String field, String? from, String? to) {
        if (from == to) {
          return;
        }
        changes.add(AuditFieldChange(field: field, from: from, to: to));
        touched.add(field);
      }

      TransactionsCompanion companion = TransactionsCompanion(
        updatedAt: Value<DateTime>(timestamp),
      );

      if (amount != null) {
        final Money next = amount.value;
        record(
          TransactionField.amount,
          existing.amountAmount,
          next.toCanonicalString(),
        );
        record(
          TransactionField.currency,
          existing.amountCurrency,
          next.currencyCode,
        );
        companion = companion.copyWith(
          amountAmount: Value<String>(next.toCanonicalString()),
          amountCurrency: Value<String>(next.currencyCode),
          amountMinor: Value<int>(_toMinorUnitsBestEffort(next)),
        );
      }
      if (merchantRawText != null) {
        record(
          TransactionField.merchantRawText,
          existing.merchantRawText,
          merchantRawText.value,
        );
        companion = companion.copyWith(
          merchantRawText: Value<String?>(merchantRawText.value),
        );
      }
      if (occurredAt != null) {
        record(
          TransactionField.occurredAt,
          existing.occurredAt?.toUtc().toIso8601String(),
          occurredAt.value?.toUtc().toIso8601String(),
        );
        companion = companion.copyWith(
          occurredAt: Value<DateTime?>(occurredAt.value),
          // The user stated the time; the row must stop claiming the message
          // did (architecture §7.4's `timeSource` vocabulary).
          timeSource: const Value<String?>('user_stated'),
        );
      }
      if (direction != null) {
        record(TransactionField.direction, existing.direction, direction.value);
        companion = companion.copyWith(
          direction: Value<String>(direction.value),
        );
      }
      if (transactionType != null) {
        record(
          TransactionField.transactionType,
          existing.transactionType,
          transactionType.value,
        );
        companion = companion.copyWith(
          transactionType: Value<String>(transactionType.value),
        );
      }
      if (categoryId != null) {
        // P4a: the edit form can change a category too, and when it does, the
        // three provenance columns have to move with it — exactly as they do
        // in [setUserCategory]. Leaving them behind would produce a row whose
        // category a person typed and whose `category_source` still credits a
        // rule, and the automatic path reads that column to decide whether it
        // may overwrite (AC-D3.1). Normalised through the same helper so this
        // path cannot be the one that stores the literal `uncategorized` id.
        final String? storedCategoryId = normalizeStoredCategoryId(
          categoryId.value,
        );
        record(
          TransactionField.categoryId,
          existing.categoryId,
          storedCategoryId,
        );
        // Only when the value genuinely changed — the same restraint the
        // method already applies to `user_edited_fields`. Someone who opened
        // the edit form and pressed Save without touching the category has not
        // expressed an intent about it, and stamping `source = user` on that
        // would freeze the row against the learning loop for nothing.
        if (existing.categoryId != storedCategoryId) {
          companion = companion.copyWith(
            categoryId: Value<String?>(storedCategoryId),
            categorySource: const Value<String?>(StoredCategorySource.user),
            categoryConfidence: const Value<double?>(1.0),
            categoryRuleId: const Value<int?>(null),
          );
        }
      }
      if (instrumentId != null) {
        record(
          TransactionField.instrumentId,
          existing.instrumentId?.toString(),
          instrumentId.value?.toString(),
        );
        companion = companion.copyWith(
          instrumentId: Value<int?>(instrumentId.value),
        );
      }
      if (referenceNumber != null) {
        record(
          TransactionField.referenceNumber,
          existing.referenceNumber,
          referenceNumber.value,
        );
        companion = companion.copyWith(
          referenceNumber: Value<String?>(referenceNumber.value),
        );
      }
      if (counterpartyName != null) {
        record(
          TransactionField.counterpartyName,
          existing.counterpartyName,
          counterpartyName.value,
        );
        companion = companion.copyWith(
          counterpartyName: Value<String?>(counterpartyName.value),
        );
      }

      if (changes.isEmpty) {
        // Nothing changed. Writing an audit entry saying so would fill the
        // change history with noise and make the entries that *do* record a
        // change harder to find (US-F5 is read by a person).
        return;
      }

      // A fresh set, not `decode(...)..addAll(...)`: the decoder returns a
      // `const {}` for the "nobody has edited this" case, and mutating that
      // throws. Copying is also simply the right shape here — the decoded set
      // is a *reading* of stored state and should not be edited in place.
      final Set<String> protectedFields = <String>{
        ...decodeUserEditedFields(existing.userEditedFields),
        ...touched,
      };
      companion = companion.copyWith(
        userEditedFields: Value<String?>(
          encodeUserEditedFields(protectedFields),
        ),
      );

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(companion);

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'update',
        actor: actor,
        actorDetail: actorDetail ?? 'manual_edit',
        changedAt: timestamp,
        fieldChanges: changes,
      );
    });
  }

  /// **KHA-78 / AC-B11.2 — the user rules on an internal-transfer candidate.**
  ///
  /// Writes `internal_transfer_state` (+ the group id) **and** the audit entry
  /// in one database transaction, for both legs of the pair when both are
  /// supplied. The atomicity is not ceremonial: a confirmation that persisted
  /// on one leg only would exclude the outgoing side from spend while leaving
  /// the incoming side classified as income, and the period figures would stop
  /// reconciling with each other in a way nothing on screen could explain.
  ///
  /// [state] is an [InternalTransferState] value (`internal` | `candidate` |
  /// `external`). Confirming writes `internal` and the pair leaves spend on
  /// the next total; rejecting writes `external`, which the read-time detector
  /// honours over its own derivation (`InternalTransferAnalysis.stateFor`), so
  /// it stops re-proposing a pair the user has already dismissed.
  ///
  /// The decision also clears the review flag, because the thing that needed
  /// reviewing has been reviewed — leaving it set would keep the item in the
  /// inbox after the user acted on it, which reads as the app ignoring them.
  Future<void> setInternalTransferDecision({
    required List<int> transactionIds,
    required String state,
    String? groupId,
    String actor = 'user',
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      for (final int id in transactionIds) {
        final TransactionRow existing = await (select(
          transactions,
        )..where((Transactions t) => t.id.equals(id))).getSingle();

        await (update(
          transactions,
        )..where((Transactions t) => t.id.equals(id))).write(
          TransactionsCompanion(
            internalTransferState: Value<String?>(state),
            internalTransferGroupId: Value<String?>(groupId),
            // The user has ruled; the flag has served its purpose.
            needsReview: const Value<bool>(false),
            reviewReason: const Value<String?>(null),
            updatedAt: Value<DateTime>(timestamp),
          ),
        );

        await auditLogDao.append(
          entityType: 'transaction',
          entityId: id.toString(),
          action: 'update',
          actor: actor,
          actorDetail: actorDetail ?? 'internal_transfer_decision',
          changedAt: timestamp,
          fieldChanges: <AuditFieldChange>[
            AuditFieldChange(
              field: 'internalTransferState',
              from: existing.internalTransferState,
              to: state,
            ),
            AuditFieldChange(
              field: 'internalTransferGroupId',
              from: existing.internalTransferGroupId,
              to: groupId,
            ),
          ],
        );
      }
    });
  }

  /// **ADR-017 D2's enrichment merge — KHA-64, and the single highest-risk
  /// operation in P3.**
  ///
  /// Read `docs/architecture.md` risk R-8 before changing anything here:
  /// *"silently deleting a real transaction is worse than an inflated
  /// total"*. Three properties make that safe, and all three are structural
  /// rather than a matter of care:
  ///
  ///  1. **Nothing is destroyed.** The merged-away row is soft-deleted and
  ///     carries `mergedIntoId`; the survivor carries
  ///     `mergedFromTransactionId`. Both source messages remain readable from
  ///     their own rows, which is NFR-A6's traceability holding literally.
  ///     `restore()` reverses the whole thing.
  ///  2. **It is never automatic.** There is no caller of this method in the
  ///     ingestion pipeline, and `DuplicateAction` still has no `delete` case,
  ///     so dedup cannot reach it. The only caller is
  ///     `TransactionMergeService`, which requires an explicit user action.
  ///  3. **The enrichment is decided elsewhere and passed in.** This method
  ///     applies [enrichment]; it does not compute it. The policy — never
  ///     overwrite a non-null value, never overwrite a user-edited field — is
  ///     a pure function in `features/ledger/transaction_merge.dart` with its
  ///     own tests, because a policy tangled up with a database transaction is
  ///     a policy nobody can exhaustively test.
  ///
  /// Both audit entries are written inside this one `transaction()` block, so
  /// the merge is atomic across both rows and their history (KHA-64: *"a merge
  /// that loses the merged-away side's history is a defect"*).
  ///
  /// ## O-QA-5 — [actor] is required, with no default
  ///
  /// This method is public, and until KHA-90 it defaulted `actor` to `'user'`.
  /// A future background caller could therefore have merged two rows and
  /// written an audit entry claiming a *person* did it, by omitting one named
  /// argument. NFR-A2's whole point is telling "the user did this" apart from
  /// "a rule did this", and an audit trail that can be wrong about which is
  /// worse than one that is merely incomplete. Making it required costs one
  /// argument at the single existing call site and forces any future
  /// non-user caller to say so out loud, in the same place a reviewer is
  /// already looking.
  Future<void> mergeDuplicatePair({
    required int survivorId,
    required int mergedAwayId,
    required MergeEnrichment enrichment,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow survivor = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(survivorId))).getSingle();
      final TransactionRow mergedAway = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(mergedAwayId))).getSingle();

      // --- 0. Does the survivor's protected set change? --------------------
      //
      // D-QA-11: a value the merge copies from the absorbed row was, on that
      // row, a *user correction*. It has to arrive on the survivor still
      // marked as one, or the survivor holds a user-authored value the app
      // believes came from the parser and the next automated writer is free
      // to overwrite it. Computed here (rather than in `MergePlan`) because
      // it is a union with what the survivor already had, which only the row
      // read a line above knows.
      //
      // `null` means "no change", which keeps it consistent with every other
      // enrichment field on this method: null is always "leave it alone".
      final Set<String> survivorProtected = decodeUserEditedFields(
        survivor.userEditedFields,
      );
      final Set<String> unionProtected = <String>{
        ...survivorProtected,
        ...enrichment.protectedFields,
      };
      final String? mergedProtectedFields =
          unionProtected.length == survivorProtected.length
          ? null
          : encodeUserEditedFields(unionProtected);

      // --- 1. The survivor absorbs whatever it was missing -----------------
      final List<AuditFieldChange> survivorChanges = <AuditFieldChange>[
        AuditFieldChange(
          field: 'mergedFromTransactionId',
          from: survivor.mergedFromTransactionId?.toString(),
          to: mergedAwayId.toString(),
        ),
        if (enrichment.merchantRawText != null)
          AuditFieldChange(
            field: TransactionField.merchantRawText,
            from: survivor.merchantRawText,
            to: enrichment.merchantRawText,
          ),
        if (enrichment.referenceNumber != null)
          AuditFieldChange(
            field: TransactionField.referenceNumber,
            from: survivor.referenceNumber,
            to: enrichment.referenceNumber,
          ),
        if (enrichment.counterpartyName != null)
          AuditFieldChange(
            field: TransactionField.counterpartyName,
            from: survivor.counterpartyName,
            to: enrichment.counterpartyName,
          ),
        if (enrichment.occurredAt != null)
          AuditFieldChange(
            field: TransactionField.occurredAt,
            from: survivor.occurredAt?.toUtc().toIso8601String(),
            to: enrichment.occurredAt!.toUtc().toIso8601String(),
          ),
        if (enrichment.instrumentId != null)
          AuditFieldChange(
            field: TransactionField.instrumentId,
            from: survivor.instrumentId?.toString(),
            to: enrichment.instrumentId.toString(),
          ),
        // --- KHA-87: the money the survivor is absorbing -------------------
        //
        // Recorded field by field so US-F5 can answer "why did this
        // transaction's fee appear out of nowhere?" with "the merge on the
        // 29th carried it from the other alert" rather than with silence.
        if (enrichment.feeAmount != null)
          AuditFieldChange(
            field: 'feeAmount',
            from: survivor.feeAmountAmount,
            to: enrichment.feeAmount!.amount,
          ),
        if (enrichment.convertedAmount != null)
          AuditFieldChange(
            field: 'convertedAmount',
            from: survivor.convertedAmountAmount,
            to: enrichment.convertedAmount!.amount,
          ),
        if (enrichment.remainingBalance != null)
          AuditFieldChange(
            field: 'remainingBalance',
            from: survivor.remainingBalanceAmount,
            to: enrichment.remainingBalance!.amount,
          ),
        if (enrichment.fxRate != null)
          AuditFieldChange(
            field: 'fxRate',
            from: survivor.fxRate,
            to: enrichment.fxRate,
          ),
        if (enrichment.fxRateDate != null)
          AuditFieldChange(
            field: 'fxRateDate',
            from: survivor.fxRateDate?.toUtc().toIso8601String(),
            to: enrichment.fxRateDate!.toUtc().toIso8601String(),
          ),
        if (enrichment.fxRateSource != null)
          AuditFieldChange(
            field: 'fxRateSource',
            from: survivor.fxRateSource,
            to: enrichment.fxRateSource,
          ),
        if (enrichment.conversionPending != null)
          AuditFieldChange(
            field: 'conversionPending',
            from: survivor.conversionPending.toString(),
            to: enrichment.conversionPending.toString(),
          ),
        if (enrichment.internalTransferState != null)
          AuditFieldChange(
            field: 'internalTransferState',
            from: survivor.internalTransferState,
            to: enrichment.internalTransferState,
          ),
        if (enrichment.internalTransferGroupId != null)
          AuditFieldChange(
            field: 'internalTransferGroupId',
            from: survivor.internalTransferGroupId,
            to: enrichment.internalTransferGroupId,
          ),
        // --- KHA-89 / D-QA-11: the protection travelling with the value ----
        if (mergedProtectedFields != null)
          AuditFieldChange(
            field: 'userEditedFields',
            from: survivor.userEditedFields,
            to: mergedProtectedFields,
          ),
      ];

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(survivorId))).write(
        TransactionsCompanion(
          merchantRawText: enrichment.merchantRawText == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.merchantRawText),
          referenceNumber: enrichment.referenceNumber == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.referenceNumber),
          counterpartyName: enrichment.counterpartyName == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.counterpartyName),
          occurredAt: enrichment.occurredAt == null
              ? const Value<DateTime?>.absent()
              : Value<DateTime?>(enrichment.occurredAt),
          instrumentId: enrichment.instrumentId == null
              ? const Value<int?>.absent()
              : Value<int?>(enrichment.instrumentId),
          // KHA-87. Each money triple is written whole or not at all —
          // `Value.absent()` on every one of its three columns — so a survivor
          // can never end up holding an amount without its currency.
          feeAmountAmount: enrichment.feeAmount == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.feeAmount!.amount),
          feeAmountCurrency: enrichment.feeAmount == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.feeAmount!.currency),
          feeAmountMinor: enrichment.feeAmount == null
              ? const Value<int?>.absent()
              : Value<int?>(enrichment.feeAmount!.minor),
          convertedAmountAmount: enrichment.convertedAmount == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.convertedAmount!.amount),
          convertedAmountCurrency: enrichment.convertedAmount == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.convertedAmount!.currency),
          convertedAmountMinor: enrichment.convertedAmount == null
              ? const Value<int?>.absent()
              : Value<int?>(enrichment.convertedAmount!.minor),
          remainingBalanceAmount: enrichment.remainingBalance == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.remainingBalance!.amount),
          remainingBalanceCurrency: enrichment.remainingBalance == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.remainingBalance!.currency),
          remainingBalanceMinor: enrichment.remainingBalance == null
              ? const Value<int?>.absent()
              : Value<int?>(enrichment.remainingBalance!.minor),
          fxRate: enrichment.fxRate == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.fxRate),
          fxRateDate: enrichment.fxRateDate == null
              ? const Value<DateTime?>.absent()
              : Value<DateTime?>(enrichment.fxRateDate),
          fxRateSource: enrichment.fxRateSource == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.fxRateSource),
          conversionPending: enrichment.conversionPending == null
              ? const Value<bool>.absent()
              : Value<bool>(enrichment.conversionPending!),
          internalTransferState: enrichment.internalTransferState == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.internalTransferState),
          internalTransferGroupId: enrichment.internalTransferGroupId == null
              ? const Value<String?>.absent()
              : Value<String?>(enrichment.internalTransferGroupId),
          // D-QA-11. `absent()` when nothing new is protected, so a merge that
          // copies only parser output leaves the column exactly as it was.
          userEditedFields: mergedProtectedFields == null
              ? const Value<String?>.absent()
              : Value<String?>(mergedProtectedFields),
          mergedFromTransactionId: Value<int?>(mergedAwayId),
          // The pair has been resolved by the user, so the duplicate flag that
          // asked them to resolve it comes off.
          needsReview: const Value<bool>(false),
          reviewReason: const Value<String?>(null),
          possibleDuplicateOfId: const Value<int?>(null),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: survivorId.toString(),
        action: 'merge',
        actor: actor,
        actorDetail: actorDetail ?? 'duplicate_merge_survivor',
        changedAt: timestamp,
        fieldChanges: survivorChanges,
      );

      // --- 2. The other row stops counting, without ceasing to exist -------
      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(mergedAwayId))).write(
        TransactionsCompanion(
          isDeleted: const Value<bool>(true),
          deletedAt: Value<DateTime?>(timestamp),
          mergedIntoId: Value<int?>(survivorId),
          needsReview: const Value<bool>(false),
          reviewReason: const Value<String?>(null),
          possibleDuplicateOfId: const Value<int?>(null),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: mergedAwayId.toString(),
        action: 'merge',
        actor: actor,
        actorDetail: actorDetail ?? 'duplicate_merge_absorbed',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'isDeleted',
            from: mergedAway.isDeleted.toString(),
            to: 'true',
          ),
          AuditFieldChange(
            field: 'mergedIntoId',
            from: mergedAway.mergedIntoId?.toString(),
            to: survivorId.toString(),
          ),
        ],
      );
    });
  }

  /// Marks an **existing** transaction as a possible duplicate of [otherId].
  ///
  /// ADR-017's rule is "flag, never auto-remove", and a flag is only half
  /// useful if it sits on one side of the pair: the user opening either row
  /// must see it. So the pipeline flags the incoming row at insert time and
  /// calls this for its counterpart.
  ///
  /// Note this is an `update`, so the audit entry is a genuine before/after
  /// (NFR-A2) and the actor is `system_rule` — it was not the user.
  Future<void> flagAsPossibleDuplicate({
    required int id,
    required int otherId,
    required String reviewReason,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final TransactionRow existing = await (select(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).getSingle();

      await (update(
        transactions,
      )..where((Transactions t) => t.id.equals(id))).write(
        TransactionsCompanion(
          needsReview: const Value<bool>(true),
          reviewReason: Value<String?>(reviewReason),
          possibleDuplicateOfId: Value<int?>(otherId),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'update',
        actor: 'system_rule',
        actorDetail: 'duplicate_policy',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'needsReview',
            from: existing.needsReview.toString(),
            to: 'true',
          ),
          AuditFieldChange(
            field: 'reviewReason',
            from: existing.reviewReason,
            to: reviewReason,
          ),
        ],
      );
    });
  }

  /// The transactions ADR-017's D2/D3 tiers must compare an incoming message
  /// against.
  ///
  /// Bounded by [since] so the query stays cheap as the ledger grows: D3's
  /// window is 15 minutes and D2's reference numbers are per-instrument, so
  /// scanning years of history would cost time for no additional matches.
  /// Soft-deleted rows are excluded — a transaction the user deleted must not
  /// silently suppress or flag a new one.
  Future<List<TransactionRow>> duplicateCandidatesSince(DateTime since) {
    return (select(transactions)..where(
          (Transactions t) =>
              t.isDeleted.equals(false) &
              t.occurredAt.isBiggerOrEqualValue(since),
        ))
        .get();
  }

  Future<List<TransactionRow>> all() => select(transactions).get();

  /// Every live transaction, newest movement first — the source for the bank
  /// tree's totals (AC-B2.1/B2.2/B2.3) and for the transaction list.
  ///
  /// Soft-deleted rows are excluded here rather than filtered per screen:
  /// US-B6/B8 require a deleted transaction to be out of every list and every
  /// total until restored, and a screen that forgot the filter would show it
  /// in one of them. The Recently Deleted view uses [watchDeleted] instead.
  Stream<List<TransactionRow>> watchLive() {
    return (select(transactions)
          ..where((Transactions t) => t.isDeleted.equals(false))
          ..orderBy(<OrderClauseGenerator<Transactions>>[
            (Transactions t) => OrderingTerm.desc(t.occurredAt),
            (Transactions t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  Stream<List<TransactionRow>> watchDeleted() {
    return (select(transactions)
          ..where((Transactions t) => t.isDeleted.equals(true))
          ..orderBy(<OrderClauseGenerator<Transactions>>[
            (Transactions t) => OrderingTerm.desc(t.deletedAt),
          ]))
        .watch();
  }

  /// One instrument's transactions — AC-B2.3's *"only that instrument's
  /// transactions are listed"*. The total shown next to them is computed in
  /// Dart from exactly this list (ADR-002 forbids a SQL `SUM`), which is what
  /// makes the two agree by construction.
  Future<List<TransactionRow>> forInstrument(int instrumentId) {
    return (select(transactions)
          ..where(
            (Transactions t) =>
                t.instrumentId.equals(instrumentId) & t.isDeleted.equals(false),
          )
          ..orderBy(<OrderClauseGenerator<Transactions>>[
            (Transactions t) => OrderingTerm.desc(t.occurredAt),
          ]))
        .get();
  }

  Future<TransactionRow?> byIdOrNull(int id) => (select(
    transactions,
  )..where((Transactions t) => t.id.equals(id))).getSingleOrNull();

  /// Everything flagged for the user's attention — the "low confidence" half
  /// of the Needs Review inbox (design.md S-18), which includes possible
  /// duplicates (AC-A5.2).
  Stream<List<TransactionRow>> watchNeedingReview() {
    return (select(transactions)
          ..where(
            (Transactions t) =>
                t.needsReview.equals(true) & t.isDeleted.equals(false),
          )
          ..orderBy(<OrderClauseGenerator<Transactions>>[
            (Transactions t) => OrderingTerm.desc(t.occurredAt),
          ]))
        .watch();
  }

  Future<TransactionRow> byId(int id) => (select(
    transactions,
  )..where((Transactions t) => t.id.equals(id))).getSingle();

  /// Best-effort derivation of the non-authoritative `_minor` column
  /// (ADR-002) for indexing/range filters only — **never** used for
  /// arithmetic. Looks up the *actual* currency's minor-unit exponent via
  /// [minorUnitExponentFor] (`lib/core/money/currency_exponents.dart`) —
  /// previously this hard-coded a 2-decimal exponent for every currency,
  /// which silently produced a wrong (100x too large, then truncated)
  /// `_minor` value for 0-decimal currencies like JPY and a wrong (10x too
  /// small) value for 3-decimal currencies like KWD/BHD/JOD.
  int _toMinorUnitsBestEffort(Money amount) {
    final int exponent = minorUnitExponentFor(amount.currencyCode);
    final List<String> parts = amount.toCanonicalString().split('.');
    final String wholePart = parts[0];
    final String rawFractionPart = parts.length > 1 ? parts[1] : '';
    final String fractionPart = exponent == 0
        ? ''
        : rawFractionPart.padRight(exponent, '0').substring(0, exponent);
    final int sign = wholePart.startsWith('-') ? -1 : 1;
    final String digits = '${wholePart.replaceFirst('-', '')}$fractionPart';
    return sign * int.parse(digits);
  }
}
