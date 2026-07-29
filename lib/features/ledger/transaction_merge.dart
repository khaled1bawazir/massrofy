/// **ADR-017 D2 — the enrichment merge.** KHA-64 (second half), AC-A5.2,
/// NFR-A2, NFR-A6, risk R-8.
///
/// ---
///
/// ## Read this before changing anything in this file
///
/// `docs/build-plan.md` calls this *"the single highest-risk operation in
/// P3 … the only place in the entire product where two records become one"*,
/// and risk R-8 states the standard it has to meet:
///
/// > **Silently deleting a real transaction is worse than an inflated total.**
///
/// An inflated total is on screen, the user sees two rows, and one tap fixes
/// it. A transaction that vanished is invisible: the user never learns it
/// existed, so they cannot even know to look. That asymmetry is why the four
/// properties below are structural — enforced by types and by the shape of the
/// code — rather than left to whoever reads the file next being careful.
///
/// ### 1. Nothing is ever destroyed
///
/// A "merge" does not remove a row. The absorbed transaction is **soft-deleted
/// and marked `mergedIntoId`**; the survivor is marked
/// `mergedFromTransactionId`. Both rows remain readable, both keep their own
/// `sourceMessageId`, and `restore()` reverses the entire operation. NFR-A6 —
/// *"no derived figure may exist that cannot be traced back to its constituent
/// transactions"* — is met literally: the merged figure traces to two rows,
/// and both rows are still there to be opened.
///
/// KHA-64 asks for exactly this: *"the merged result must remain traceable to
/// both source messages"*.
///
/// ### 2. It is never automatic
///
/// [DuplicateAction] still has **no `delete` case**, and nothing in
/// `IngestionPipeline` calls this service. The only entry point is
/// [TransactionMergeService.merge], and its only caller is a user action in
/// the review inbox. ADR-017's D2 row says *"if it enriches an existing
/// record, merge — and write an audit entry recording the merge"*, and the
/// deliberate reading taken here is that the *decision* is the user's; the app
/// may propose, never dispose.
///
/// There is a test asserting no production code path outside the explicit
/// user-confirmed service reaches [TransactionDao.mergeDuplicatePair].
///
/// ### 3. Enrichment fills gaps; it never overwrites
///
/// [MergePlan.between] copies a field **only** when the survivor's is null.
/// It cannot replace a value, and it cannot clear one — [MergeEnrichment]'s
/// fields are plain nullables where null means "leave alone", so there is no
/// way to express "write null" even by mistake. Two records that disagree
/// about a value are not a merge candidate; they are a question for the user.
///
/// ### 4. A user's edit is never undone by a merge
///
/// `user_edited_fields` (AC-B5.3) is consulted before every copy. If a person
/// corrected the merchant name on the survivor, an incoming merge will not
/// "enrich" it back to what the parser produced — even if the survivor's value
/// were somehow null. User intent outranks the parser, and a merge is a
/// parser-adjacent operation.
///
/// ## What makes two transactions mergeable at all
///
/// [MergePlan.between] refuses outright — [MergeRefusal] — when the two rows
/// disagree about anything that would make them *different movements* rather
/// than two records of one: a different amount or currency, a different
/// direction, or a different transaction type. This is the guard that stops a
/// mis-tapped merge from making a real purchase disappear into an unrelated
/// one. It is checked in a pure function so it is exhaustively testable
/// without a database.
library;

import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';

/// Why two transactions may not be merged.
///
/// A closed set, mapped to localised copy by the UI. Each value names a *fact
/// about the two rows*, never a judgement — the user is told what differs so
/// they can decide whether the app is wrong or they are.
enum MergeRefusal {
  /// The same row twice. Reachable via a stale screen after another merge.
  sameTransaction,

  /// One or both rows are already soft-deleted (possibly by an earlier
  /// merge). Merging a deleted row would resurrect it into a figure it is not
  /// part of.
  notLive,

  /// Different amounts, or the same number in different currencies. Two
  /// different amounts are two different movements — `Money`'s `==` compares
  /// value **and** currency, so 100 USD never silently matches 100 SAR.
  amountDiffers,

  /// One is a debit and the other a credit. A purchase and its refund are
  /// emphatically not duplicates of each other; merging them would delete a
  /// real movement and net out to a figure matching neither (US-B7).
  directionDiffers,

  /// Different transaction types — a withdrawal and a purchase, say. Merging
  /// across types would silently change which totals the money lands in.
  typeDiffers,
}

/// The decision about one proposed merge: either a plan, or a refusal.
sealed class MergeAssessment {
  const MergeAssessment();
}

/// The merge is legal. [enrichment] is what the survivor will absorb — often
/// nothing, which is still a valid merge (removing the duplicate from the
/// total is the point; enrichment is the bonus).
final class MergeAllowed extends MergeAssessment {
  final int survivorId;
  final int mergedAwayId;
  final MergeEnrichment enrichment;

  const MergeAllowed({
    required this.survivorId,
    required this.mergedAwayId,
    required this.enrichment,
  });
}

/// The merge is refused, with the reason the UI must show.
final class MergeRefused extends MergeAssessment {
  final MergeRefusal reason;
  const MergeRefused(this.reason);
}

/// The pure decision function: given two stored rows, may they be merged, and
/// what would the survivor gain?
abstract final class MergePlan {
  /// Assesses merging [mergedAway] into [survivor].
  ///
  /// The **caller chooses which row survives**, and the choice is not
  /// arbitrary: the review inbox offers the older row as the survivor by
  /// default, because it is the one already referenced by whatever the user
  /// has looked at, and because keeping the earlier `occurredAt` matches when
  /// the movement actually happened rather than when the second alert arrived.
  static MergeAssessment between({
    required TransactionRow survivor,
    required TransactionRow mergedAway,
  }) {
    if (survivor.id == mergedAway.id) {
      return const MergeRefused(MergeRefusal.sameTransaction);
    }
    if (survivor.isDeleted || mergedAway.isDeleted) {
      return const MergeRefused(MergeRefusal.notLive);
    }
    // Compared as the authoritative canonical strings the write path stored,
    // never as floats and never via the non-authoritative `_minor` column
    // (ADR-002). Two rows written by this app for the same amount hold
    // byte-identical text.
    if (survivor.amountAmount != mergedAway.amountAmount ||
        survivor.amountCurrency != mergedAway.amountCurrency) {
      return const MergeRefused(MergeRefusal.amountDiffers);
    }
    if (survivor.direction != mergedAway.direction) {
      return const MergeRefused(MergeRefusal.directionDiffers);
    }
    if (survivor.transactionType != mergedAway.transactionType) {
      return const MergeRefused(MergeRefusal.typeDiffers);
    }

    // AC-B5.3: whatever the user has edited on the survivor is off limits,
    // even to a gap-filling copy.
    final Set<String> protectedFields = decodeUserEditedFields(
      survivor.userEditedFields,
    );

    /// Copies [incoming] onto the survivor only if the survivor has no value
    /// **and** the field is not user-protected. Both conditions, always.
    T? fill<T>(String field, T? current, T? incoming) {
      if (current != null || protectedFields.contains(field)) {
        return null;
      }
      return incoming;
    }

    return MergeAllowed(
      survivorId: survivor.id,
      mergedAwayId: mergedAway.id,
      enrichment: MergeEnrichment(
        merchantRawText: fill(
          TransactionField.merchantRawText,
          survivor.merchantRawText,
          mergedAway.merchantRawText,
        ),
        referenceNumber: fill(
          TransactionField.referenceNumber,
          survivor.referenceNumber,
          mergedAway.referenceNumber,
        ),
        counterpartyName: fill(
          TransactionField.counterpartyName,
          survivor.counterpartyName,
          mergedAway.counterpartyName,
        ),
        occurredAt: fill(
          TransactionField.occurredAt,
          survivor.occurredAt,
          mergedAway.occurredAt,
        ),
        instrumentId: fill(
          TransactionField.instrumentId,
          survivor.instrumentId,
          mergedAway.instrumentId,
        ),
      ),
    );
  }
}

/// The outcome of a merge attempt.
sealed class MergeResult {
  const MergeResult();
}

/// The merge was performed. Both rows still exist; one has stopped counting.
final class MergeCompleted extends MergeResult {
  final int survivorId;
  final int mergedAwayId;

  /// True when the survivor gained at least one field it did not have.
  final bool enriched;

  const MergeCompleted({
    required this.survivorId,
    required this.mergedAwayId,
    required this.enriched,
  });
}

/// The merge was refused by [MergePlan.between].
final class MergeRejected extends MergeResult {
  final MergeRefusal reason;
  const MergeRejected(this.reason);
}

/// One or both transaction ids did not resolve.
final class MergeTargetMissing extends MergeResult {
  const MergeTargetMissing();
}

/// The caller did not pass an explicit user confirmation, so **nothing was
/// read and nothing was written**.
///
/// Its own result type rather than being folded into [MergeRejected]: those
/// are refusals about the *data*, this is a refusal about *authority*, and a
/// test asserting "an unconfirmed merge changes nothing" should not be able to
/// pass by accident because the amounts happened to differ too.
final class MergeNotConfirmed extends MergeResult {
  const MergeNotConfirmed();
}

/// **The only way to merge two transactions in this app.**
///
/// Every call is a user action. There is no scheduled, background or
/// ingestion-time caller, and adding one would require adding it here, under
/// this doc comment, where a reviewer would see it — the same control
/// `DuplicateAction`'s missing `delete` case provides one layer down.
final class TransactionMergeService {
  final AppDatabase database;
  final TransactionDao transactionDao;

  const TransactionMergeService({
    required this.database,
    required this.transactionDao,
  });

  /// Merges [mergedAwayId] into [survivorId] **after the user has explicitly
  /// confirmed it**.
  ///
  /// [confirmedByUser] is a required named argument with no default. That is
  /// deliberate and it is the cheapest possible enforcement of R-8's "never
  /// automatic": a future caller cannot merge by forgetting a parameter, and a
  /// reader of any call site can see the confirmation without opening this
  /// file. Passing `false` performs no write at all.
  Future<MergeResult> merge({
    required int survivorId,
    required int mergedAwayId,
    required bool confirmedByUser,
    DateTime? now,
  }) async {
    if (!confirmedByUser) {
      // Not an exception: a UI can legitimately construct the call and then
      // find the confirmation dialog was dismissed. Nothing is read, nothing
      // is written, and the pair stays flagged for a decision.
      return const MergeNotConfirmed();
    }

    return database.transaction<MergeResult>(() async {
      final TransactionRow? survivor = await transactionDao.byIdOrNull(
        survivorId,
      );
      final TransactionRow? mergedAway = await transactionDao.byIdOrNull(
        mergedAwayId,
      );
      if (survivor == null || mergedAway == null) {
        return const MergeTargetMissing();
      }

      final MergeAssessment assessment = MergePlan.between(
        survivor: survivor,
        mergedAway: mergedAway,
      );
      switch (assessment) {
        case MergeRefused(:final MergeRefusal reason):
          return MergeRejected(reason);
        case MergeAllowed(:final MergeEnrichment enrichment):
          await transactionDao.mergeDuplicatePair(
            survivorId: survivorId,
            mergedAwayId: mergedAwayId,
            enrichment: enrichment,
            now: now,
          );
          return MergeCompleted(
            survivorId: survivorId,
            mergedAwayId: mergedAwayId,
            enriched: !enrichment.isEmpty,
          );
      }
    });
  }

  /// Undoes a merge by restoring the absorbed row.
  ///
  /// A merge is reversible precisely because it destroyed nothing.
  /// [TransactionDao.restore] clears both `mergedIntoId` and the survivor's
  /// `mergedFromTransactionId`, and records the reversal in the change history
  /// — an undo that left no trace would be its own audit failure.
  Future<void> undo(int mergedAwayId, {DateTime? now}) =>
      transactionDao.restore(
        id: mergedAwayId,
        actor: 'user',
        actorDetail: 'duplicate_merge_undo',
        now: now,
      );
}
