import 'package:drift/drift.dart';

import '../../core/money/currency_exponents.dart';
import '../../core/money/money.dart';
import '../../core/money/sign_convention.dart';
import '../db/app_database.dart';
import '../db/tables/transaction_table.dart';
import 'audit_log_dao.dart';

part 'transaction_dao.g.dart';

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
  Future<int> create({
    String? merchantRawText,
    required Money amount,
    String? categoryId,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final int id = await into(transactions).insert(
        TransactionsCompanion.insert(
          merchantRawText: Value<String?>(merchantRawText),
          amountAmount: amount.toCanonicalString(),
          amountCurrency: amount.currencyCode,
          amountMinor: _toMinorUnitsBestEffort(amount),
          categoryId: Value<String?>(categoryId),
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

  /// Re-categorises an existing transaction, writing a before/after audit
  /// entry for the `categoryId` field (US-F5, AC-F5.1).
  Future<void> updateCategory({
    required int id,
    required String? newCategoryId,
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
          categoryId: Value<String?>(newCategoryId),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'transaction',
        entityId: id.toString(),
        action: 'update',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'categoryId',
            from: existing.categoryId,
            to: newCategoryId,
          ),
        ],
      );
    });
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

  /// Restores a soft-deleted transaction (US-B8.2).
  Future<void> restore({
    required int id,
    required String actor,
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
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
        fieldChanges: const <AuditFieldChange>[
          AuditFieldChange(field: 'isDeleted', from: 'true', to: 'false'),
        ],
      );
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
