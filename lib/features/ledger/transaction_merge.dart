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
/// `sourceMessageId`, and `restore()` reverses the soft delete and the link.
/// NFR-A6 — *"no derived figure may exist that cannot be traced back to its
/// constituent transactions"* — is met literally: the merged figure traces to
/// two rows, and both rows are still there to be opened.
///
/// KHA-64 asks for exactly this: *"the merged result must remain traceable to
/// both source messages"*.
///
/// Two precise statements this property does **not** make, both of which the
/// P3b-2 prose implied and QA falsified by execution (D-QA-7, D-QA-12):
///
///  - **"Pointers both ways" holds per merge, not per survivor.**
///    `merged_from_transaction_id` is a single scalar, so a survivor that
///    absorbs a *second* duplicate overwrites its pointer to the first. The
///    first is still reachable — from its own `mergedIntoId`, and from the
///    survivor's `merge` audit entry, which records `from → to` — so this is
///    reduced convenience, not lost traceability. A set-valued link stays open
///    on KHA-88. What is fixed here is the far worse consequence: undoing one
///    merge no longer clears a *different* merge's pointer (see
///    `TransactionDao.restore`).
///  - **An undo does not un-enrich.** [TransactionMergeService.undo] reverses
///    the soft delete and the link; it deliberately leaves the copied fields
///    on the survivor. This is a decision, not an oversight (D-QA-12): a
///    gap-filled merchant name or fee is *information*, the survivor's own
///    record of it is now weeks old and may have been categorised or corrected
///    on top of, and stripping it would be the merge deleting information on
///    the way out — the exact thing property 3 exists to prevent. Both rows
///    keep the value; neither is wrong.
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
/// **KHA-87 made that sentence true of the money columns too.** P3b-2 applied
/// it to five descriptive fields and left every other column on the absorbed
/// row neither compared nor carried — and the absorbed row is then soft-deleted
/// *whole*. QA reproduced the consequence twice (D-QA-5, D-QA-6): an FX fee and
/// a bank-supplied converted amount silently left `report.fees.base` and
/// `report.spend.base`, which is KHA-74's "money absent from a total with no
/// signal" arriving through a new write path. The fee, the converted amount,
/// the FX rate/date/source and the remaining balance now travel under the same
/// rule, and disagreement about any of them is a refusal.
///
/// ### 4. A user's edit is never undone by a merge
///
/// `user_edited_fields` (AC-B5.3) is consulted before every copy. If a person
/// corrected the merchant name on the survivor, an incoming merge will not
/// "enrich" it back to what the parser produced — even if the survivor's value
/// were somehow null. User intent outranks the parser, and a merge is a
/// parser-adjacent operation.
///
/// **AC-B5.3 says "always", so it now works in both directions** (D-QA-10).
/// P3b-2 implemented the narrower rule "never overwrite the survivor", so a
/// correction sitting on the row being merged *away* lost to the parser's
/// mis-read on the survivor. Whichever row a user corrected, their value is
/// either the one that survives (when the survivor had a gap) or the merge is
/// refused so they can decide — the parser's value never quietly wins.
/// A value copied across also arrives **still protected**
/// ([MergeEnrichment.protectedFields], D-QA-11), because intent that loses its
/// protection in transit does not outrank tomorrow's writer.
///
/// ## What makes two transactions mergeable at all
///
/// [MergePlan.between] refuses outright — [MergeRefusal] — when the two rows
/// disagree about anything that would make them *different movements* rather
/// than two records of one, or about any figure the app reports. This is the
/// guard that stops a mis-tapped merge from making a real purchase disappear
/// into an unrelated one. It is checked in a pure function so it is
/// exhaustively testable without a database.
///
/// It also refuses to build a **chain** in either direction (D-QA-9). P3b-2's
/// "no chains" claim was true only of the absorbed side — a soft-deleted row
/// cannot be merged again ([MergeRefusal.notLive]) — while a *survivor* is
/// still live and could itself be merged away, orphaning the row it had
/// absorbed. [MergeRefusal.chainWouldForm] closes the other direction.
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

  // --- KHA-87: the money-bearing columns (D-QA-5 / D-QA-6) -----------------
  //
  // Each of these fires only when **both** rows hold a value and the two
  // values differ. A null on the survivor is an absence, not a disagreement,
  // and absences are what the enrichment exists to fill — refusing on those
  // would refuse the single most common real duplicate shape (a terse first
  // alert followed by a fuller settlement alert), which is precisely the pair
  // ADR-017 D2 was written to resolve.

  /// The two rows state different FX/international fees. PRD §3.4 reports the
  /// fee as its own figure, so picking one silently would change a number on
  /// screen.
  feeDiffers,

  /// The two rows state different base-currency conversions, FX rates, rate
  /// dates or rate sources (ADR-009). The converted amount is what reaches
  /// the headline base-currency total.
  conversionDiffers,

  /// The two rows report different balances after the movement. Informational
  /// (it enters no total), but a disagreement here means the two alerts are
  /// describing different points in the account's life, which is worth the
  /// user's eye before they become one row.
  remainingBalanceDiffers,

  /// One counts toward "money spent" and the other does not (US-B10/B11), or
  /// the user has ruled differently on the two as internal transfers
  /// (AC-B11.2). Merging would silently move money into or out of the spend
  /// figure.
  spendEffectDiffers,

  /// A field the **user** corrected on one row contradicts the value on the
  /// other (AC-B5.3, D-QA-10). Not something the app may resolve on their
  /// behalf in either direction: it is two statements of intent, and only the
  /// person who made them can say which they meant.
  userEditDiffers,

  /// The row being merged away has itself already absorbed another row, so
  /// merging it again would build a chain `a → b → c` and orphan `a`
  /// (D-QA-9). The mirror of [notLive], which closes the same door from the
  /// other side.
  chainWouldForm,
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
  /// The [TransactionField] names a merge is able to copy from the absorbed
  /// row onto the survivor — i.e. exactly the descriptive fields
  /// [MergeEnrichment] carries.
  ///
  /// Public so a test can assert it against [TransactionField.all] and force a
  /// decision when a new editable field is introduced, rather than letting it
  /// join the "neither compared nor carried" set that caused KHA-87.
  static const Set<String> carriableFields = <String>{
    TransactionField.merchantRawText,
    TransactionField.referenceNumber,
    TransactionField.counterpartyName,
    TransactionField.occurredAt,
    TransactionField.instrumentId,
  };

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

    // D-QA-9. A row that has itself absorbed a duplicate may not be merged
    // away: doing so would soft-delete the middle of a chain and leave the row
    // it absorbed pointing at something that no longer counts. Checked on the
    // merged-away side only — a *survivor* absorbing a second duplicate is
    // legitimate and common (a POS alert, a "card used" alert and a settlement
    // alert are three records of one movement).
    if (mergedAway.mergedFromTransactionId != null) {
      return const MergeRefused(MergeRefusal.chainWouldForm);
    }

    // --- KHA-87: every money-bearing column, compared ----------------------
    //
    // The rule, uniformly: **both sides hold a value and the values differ**
    // is a refusal; anything else falls through to the gap-fill below. Written
    // as an explicit list rather than folded into the fill helper so that the
    // set of compared columns is readable in one place — QA's done check asks
    // that the next column added to `transactions` cannot silently join the
    // "neither compared nor carried" set, and a list you can read is the only
    // version of that check a human actually performs.
    final MergeRefusal? moneyDisagreement = _moneyDisagreement(
      survivor,
      mergedAway,
    );
    if (moneyDisagreement != null) {
      return MergeRefused(moneyDisagreement);
    }

    // Whether each row counts toward spend, and any decision the user has
    // recorded about it being an internal transfer (AC-B11.2). Both change
    // which total the money lands in, so a disagreement is not ours to settle.
    if (survivor.affectsSpend != mergedAway.affectsSpend) {
      return const MergeRefused(MergeRefusal.spendEffectDiffers);
    }
    if (_bothPresentAndDiffer(
      survivor.internalTransferState,
      mergedAway.internalTransferState,
    )) {
      return const MergeRefused(MergeRefusal.spendEffectDiffers);
    }

    // AC-B5.3: whatever the user has edited on the survivor is off limits,
    // even to a gap-filling copy.
    final Set<String> protectedFields = decodeUserEditedFields(
      survivor.userEditedFields,
    );
    // ...and whatever they edited on the row being merged away is a statement
    // of intent too (D-QA-10), which is what the next check is about.
    final Set<String> incomingProtected = decodeUserEditedFields(
      mergedAway.userEditedFields,
    );

    // D-QA-10. A user correction on the losing row must not lose to the
    // parser's text on the survivor. It cannot simply *win* either — that
    // would make a merge overwrite a populated field, breaking property 3 and
    // giving the app two contradicting user statements to arbitrate. So:
    // where the survivor already holds a value (or holds its own protected
    // decision, including a deliberate clear), the pair is refused and the
    // user decides. Where the survivor has a gap, the correction is copied by
    // the ordinary gap-fill below and carries its protection with it.
    for (final String field in incomingProtected) {
      final Object? incomingValue = _fieldValue(mergedAway, field);
      final Object? survivorValue = _fieldValue(survivor, field);
      if (_sameFieldValue(survivorValue, incomingValue)) {
        continue;
      }
      if (survivorValue != null || protectedFields.contains(field)) {
        return const MergeRefused(MergeRefusal.userEditDiffers);
      }
      // The survivor has a gap. That is only rescuable when the enrichment can
      // actually carry the field — `categoryId` (P4 owns the category tables)
      // is user-editable but not something this merge writes, so a correction
      // there would be quietly stranded on the soft-deleted row. Refuse rather
      // than strand it; adding it to `MergeEnrichment` when P4 lands turns
      // this back into a copy with no other change here.
      if (!carriableFields.contains(field)) {
        return const MergeRefused(MergeRefusal.userEditDiffers);
      }
    }

    /// Copies [incoming] onto the survivor only if the survivor has no value
    /// **and** the field is not user-protected. Both conditions, always.
    T? fill<T>(String field, T? current, T? incoming) {
      if (current != null || protectedFields.contains(field)) {
        return null;
      }
      return incoming;
    }

    /// The money equivalent of [fill]. No `field` argument because no money
    /// column is in [TransactionField]'s user-editable vocabulary — an amount
    /// edit is guarded by `amountDiffers` above, well before this point.
    MoneyColumns? fillMoney(MoneyColumns? current, MoneyColumns? incoming) =>
        current != null ? null : incoming;

    final MoneyColumns? survivorConverted = _converted(survivor);
    final MoneyColumns? incomingConverted = _converted(mergedAway);
    final MoneyColumns? carriedConverted = fillMoney(
      survivorConverted,
      incomingConverted,
    );
    final String? carriedFxRate = survivor.fxRate == null
        ? mergedAway.fxRate
        : null;

    // The set of copied fields that were user corrections on the absorbed row
    // (D-QA-11). Only the fields the gap-fill actually copies can appear here:
    // a field the survivor already held is not being written, so nothing about
    // its protection changes.
    final Set<String> carriedProtection = <String>{
      for (final String field in incomingProtected)
        if (carriableFields.contains(field) &&
            _fieldValue(survivor, field) == null &&
            !protectedFields.contains(field) &&
            _fieldValue(mergedAway, field) != null)
          field,
    };

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
        // --- KHA-87 -------------------------------------------------------
        feeAmount: fillMoney(_fee(survivor), _fee(mergedAway)),
        convertedAmount: carriedConverted,
        remainingBalance: fillMoney(
          _remainingBalance(survivor),
          _remainingBalance(mergedAway),
        ),
        fxRate: carriedFxRate,
        fxRateDate: survivor.fxRateDate == null ? mergedAway.fxRateDate : null,
        fxRateSource: survivor.fxRateSource == null
            ? mergedAway.fxRateSource
            : null,
        // ADR-009 case 4 is *derived* state, so it is recomputed rather than
        // gap-filled: a survivor that was waiting for a conversion is no
        // longer waiting once this merge hands it one. Left null (no change)
        // in every other case, including when the survivor was not pending.
        conversionPending:
            survivor.conversionPending &&
                (carriedConverted != null || carriedFxRate != null)
            ? false
            : null,
        // AC-B11.2. Carried as a pair, and only onto a survivor that holds no
        // verdict of its own: a state without its group id (or vice versa)
        // would be half a decision, which the transfer detector cannot read.
        internalTransferState: survivor.internalTransferState == null
            ? mergedAway.internalTransferState
            : null,
        internalTransferGroupId: survivor.internalTransferState == null
            ? mergedAway.internalTransferGroupId
            : null,
        protectedFields: carriedProtection,
      ),
    );
  }

  /// True when both values are present and they differ. A null on either side
  /// is an *absence* of information, which the merge fills rather than
  /// arbitrates.
  static bool _bothPresentAndDiffer(Object? a, Object? b) =>
      a != null && b != null && a != b;

  /// The money-column comparison, in one place.
  ///
  /// Returns the refusal to raise, or null when the two rows are compatible.
  /// Compared as the authoritative stored strings — never as floats, never via
  /// the non-authoritative `_minor` columns (ADR-002).
  static MergeRefusal? _moneyDisagreement(
    TransactionRow survivor,
    TransactionRow mergedAway,
  ) {
    if (_bothPresentAndDiffer(_fee(survivor), _fee(mergedAway))) {
      return MergeRefusal.feeDiffers;
    }
    if (_bothPresentAndDiffer(_converted(survivor), _converted(mergedAway)) ||
        _bothPresentAndDiffer(survivor.fxRate, mergedAway.fxRate) ||
        _bothPresentAndDiffer(survivor.fxRateDate, mergedAway.fxRateDate) ||
        _bothPresentAndDiffer(survivor.fxRateSource, mergedAway.fxRateSource)) {
      return MergeRefusal.conversionDiffers;
    }
    if (_bothPresentAndDiffer(
      _remainingBalance(survivor),
      _remainingBalance(mergedAway),
    )) {
      return MergeRefusal.remainingBalanceDiffers;
    }
    return null;
  }

  static MoneyColumns? _fee(TransactionRow row) => MoneyColumns.read(
    row.feeAmountAmount,
    row.feeAmountCurrency,
    row.feeAmountMinor,
  );

  static MoneyColumns? _converted(TransactionRow row) => MoneyColumns.read(
    row.convertedAmountAmount,
    row.convertedAmountCurrency,
    row.convertedAmountMinor,
  );

  static MoneyColumns? _remainingBalance(TransactionRow row) =>
      MoneyColumns.read(
        row.remainingBalanceAmount,
        row.remainingBalanceCurrency,
        row.remainingBalanceMinor,
      );

  /// Reads one [TransactionField] off a row.
  ///
  /// Exhaustive over the vocabulary a user can edit, so that adding a field to
  /// [TransactionField] without teaching this function about it produces a
  /// visible `null` rather than a silently unprotected value. The four
  /// unreachable cases (`amount`, `currency`, `direction`, `transactionType`)
  /// are guarded by the value comparisons far above and can never reach the
  /// D-QA-10 loop with a difference; they are answered anyway so no field
  /// falls through to the default.
  static Object? _fieldValue(TransactionRow row, String field) =>
      switch (field) {
        TransactionField.merchantRawText => row.merchantRawText,
        TransactionField.referenceNumber => row.referenceNumber,
        TransactionField.counterpartyName => row.counterpartyName,
        TransactionField.occurredAt => row.occurredAt,
        TransactionField.instrumentId => row.instrumentId,
        TransactionField.categoryId => row.categoryId,
        TransactionField.amount => row.amountAmount,
        TransactionField.currency => row.amountCurrency,
        TransactionField.direction => row.direction,
        TransactionField.transactionType => row.transactionType,
        _ => null,
      };

  /// Value equality that treats two `DateTime`s naming the same instant as the
  /// same value, which `==` on `DateTime` does not do across UTC/local.
  static bool _sameFieldValue(Object? a, Object? b) {
    if (a is DateTime && b is DateTime) {
      return a.isAtSameMomentAs(b);
    }
    return a == b;
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
            // Stated explicitly rather than relied on as a default (O-QA-5).
            // This is the one call site in the app, and it is reached only
            // after `confirmedByUser` above, so `'user'` is a fact here rather
            // than an assumption.
            actor: 'user',
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
  /// [TransactionDao.restore] clears `mergedIntoId` on the restored row and —
  /// **only when it names that row** (KHA-88 / D-QA-8) — the survivor's
  /// `mergedFromTransactionId`, and records the reversal in the change history
  /// of **both** rows. An undo that left no trace would be its own audit
  /// failure, and until KHA-88 that sentence was true of the restored row
  /// alone: the survivor was written to and audited nothing.
  ///
  /// What it deliberately does *not* reverse is the enrichment — see property
  /// 1 in this library's doc comment for why (D-QA-12).
  Future<void> undo(int mergedAwayId, {DateTime? now}) =>
      transactionDao.restore(
        id: mergedAwayId,
        actor: 'user',
        actorDetail: 'duplicate_merge_undo',
        now: now,
      );
}
