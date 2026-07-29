/// **KHA-78 / AC-B11.2 — the user rules on an internal-transfer candidate.**
/// US-B11, risk R-7, architecture §4.2 `InternalTransferLink`.
///
/// ---
///
/// ## What P3b-1 left open, and why it was left rather than forgotten
///
/// P3b-1 shipped the *detection* half: `internal_transfer.dart` derives a
/// state for each transfer at read time, the detail screen shows a "Possible
/// internal transfer" badge, and the Spent-vs-Kept card counts how many items
/// need review. What it could not ship was the *action*, because confirming a
/// candidate mutates a transaction and therefore owes an append-only audit
/// entry (NFR-A2) — which `docs/build-plan.md` v1.3 groups into P3b-2's
/// mutation surface, so the whole surface gets one `security-sensitive` review
/// pass instead of the same invariants being re-derived by a reviewer twice.
///
/// ## Confirm and reject are not mirror images
///
/// They write different states and they mean different things:
///
/// | Action | Writes | Effect |
/// |---|---|---|
/// | **Confirm** | `internal` on **both legs** | The pair leaves spend on the next total (AC-B11.1). The outgoing leg stops inflating the figure; the incoming leg stops counting as income |
/// | **Reject** | `external` on **both legs** | The pair counts normally — and, critically, the detector stops re-proposing it |
///
/// That second half of "reject" is the part worth being explicit about.
/// Rejection is not "do nothing": doing nothing would leave the derived state
/// as `candidate`, the flag would come back on the next read, and the user
/// would be asked the same question forever. `InternalTransferAnalysis
/// .stateFor` gives a persisted value precedence over a derived one precisely
/// so a decision *sticks* — R-7's requirement that resolving the flag should
/// **teach** the app, not merely silence it once.
///
/// ## Why both legs, in one database transaction
///
/// A confirmation that landed on one leg only would exclude the outgoing side
/// from spend while the incoming side stayed classified as income. Both
/// figures on the Spent-vs-Kept card would then be wrong, in opposite
/// directions, from a single half-applied write — and nothing on screen would
/// explain it. [TransactionDao.setInternalTransferDecision] takes a list of
/// ids and writes them, with their audit entries, inside one `transaction()`
/// block: either the whole decision is recorded or none of it is.
library;

import '../../data/dao/transaction_dao.dart';
import 'internal_transfer.dart';

/// What the user decided about a candidate pair.
enum InternalTransferVerdict {
  /// "Yes, this went to my own account." Writes
  /// [InternalTransferState.internal].
  confirmedInternal,

  /// "No, this was a payment to someone else." Writes
  /// [InternalTransferState.external] so the detector stops proposing it.
  rejectedExternal;

  /// The persisted state this verdict writes.
  String get persistedState => switch (this) {
    InternalTransferVerdict.confirmedInternal => InternalTransferState.internal,
    InternalTransferVerdict.rejectedExternal => InternalTransferState.external,
  };
}

/// Records the user's decision about an internal-transfer pair.
final class InternalTransferDecisionService {
  final TransactionDao transactionDao;

  const InternalTransferDecisionService({required this.transactionDao});

  /// Applies [verdict] to both legs of [link].
  ///
  /// The group id is written on confirmation so the two rows are joined by a
  /// durable identifier rather than only by a re-derivable coincidence of
  /// amount and time — architecture §4.2's `InternalTransferLink.groupId`. It
  /// is deliberately **not** written on rejection: the rows are not a pair, so
  /// recording a group linking them would assert something the user has just
  /// denied.
  Future<void> decidePair(
    InternalTransferLink link,
    InternalTransferVerdict verdict, {
    DateTime? now,
  }) => decidePairByIds(
    outTransactionId: link.outTransactionId,
    inTransactionId: link.inTransactionId,
    groupId: link.groupId,
    verdict: verdict,
    now: now,
  );

  /// The same decision, addressed by the three things the write actually uses.
  ///
  /// Added for P4b's review-inbox wiring (KHA-32). `TransferReviewItem` — the
  /// value type S-18 renders — carries the two ids and the group id but **not**
  /// `InternalTransferEvidence`, because the card never displays it. Rebuilding
  /// a whole [InternalTransferLink] at the call site would have meant inventing
  /// an evidence value to satisfy the constructor, and an invented evidence
  /// value is exactly the kind of thing that later gets read as if it were
  /// observed.
  ///
  /// Note that [decidePair] has always ignored `link.evidence` for the write:
  /// this method is not a new capability, it is the existing one stated in
  /// terms of its real inputs.
  Future<void> decidePairByIds({
    required int outTransactionId,
    required int inTransactionId,
    required String groupId,
    required InternalTransferVerdict verdict,
    DateTime? now,
  }) {
    return transactionDao.setInternalTransferDecision(
      transactionIds: <int>[outTransactionId, inTransactionId],
      state: verdict.persistedState,
      // Deliberately **not** written on rejection: the rows are not a pair, so
      // recording a group linking them would assert something the user has
      // just denied.
      groupId: verdict == InternalTransferVerdict.confirmedInternal
          ? groupId
          : null,
      actorDetail: 'internal_transfer_${verdict.name}',
      now: now,
    );
  }

  /// Applies [verdict] to a single transaction that has **no pair** — KHA-80's
  /// unpairable case (a cross-currency near-match, or a leg whose instrument
  /// never resolved).
  ///
  /// Only [InternalTransferVerdict.rejectedExternal] is offered here, and the
  /// asymmetry is a correctness decision rather than a UI simplification:
  /// there is no second leg to exclude, so "confirm as internal" on one row
  /// alone would remove an outgoing amount from spend while the matching
  /// incoming amount — in another currency, or on an unidentified instrument —
  /// carried on counting as income. That produces a Spent-vs-Kept figure that
  /// reconciles with nothing, which is exactly the silently-wrong number this
  /// app exists to avoid. Rejecting is safe because it changes no total; it
  /// only stops the app asking again.
  Future<void> dismissUnpairable(int transactionId, {DateTime? now}) {
    return transactionDao.setInternalTransferDecision(
      transactionIds: <int>[transactionId],
      state: InternalTransferState.external,
      actorDetail: 'internal_transfer_unpairable_dismissed',
      now: now,
    );
  }
}
