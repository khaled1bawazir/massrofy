/// Transfers between the user's **own** accounts and cards — KHA-29, US-B11,
/// AC-B11.1, AC-B11.2, architecture §4.2 `InternalTransferLink`, risk R-7.
///
/// ---
///
/// ## The invariant this file exists to hold
///
/// > **Moving money to yourself is not spending.** A transfer whose other
/// > side is one of the user's own instruments must never appear in a spend
/// > total or in a category breakdown.
///
/// It is stated as a correctness invariant in `docs/PRD.md` (US-B11),
/// `docs/architecture.md` §4.2 and `docs/build-plan.md`, which is a strong
/// hint that it is also the easiest one to get quietly wrong: an internal
/// transfer that leaks into spend inflates every figure the product exists to
/// produce, and it does so *plausibly* — the number still looks like money
/// the user moved.
///
/// ## What the app can actually see, and what it therefore cannot assume
///
/// A transfer SMS names a counterparty **by name** (`AHMED N ALMUTAIRI`,
/// `MERIDIAN LOGISTICS LLC`) and sometimes their bank. It does **not** name
/// the destination account number. So there is no field to match against the
/// user's own instruments, and any classification based on the counterparty
/// *name* would be a guess — including the tempting one, "the name matches
/// the account holder, so it must be me".
///
/// The evidence that genuinely exists is the **pair**: an outgoing transfer
/// from one of the user's instruments and an incoming transfer to a
/// *different* one of the user's instruments, for the same amount, at
/// approximately the same time. Every instrument row in this database was
/// created from a message sent to *this user's* phone about *this user's*
/// account (US-B15), so "both legs landed on known instruments" is exactly
/// the fact "both sides are mine".
///
/// ## Three states, and why there are three rather than two
///
/// | State | Meaning | Effect on spend |
/// |---|---|---|
/// | [InternalTransferState.internal] | Determined internal: paired legs **and** a matching reference number, or the user said so | **Excluded** (AC-B11.1) |
/// | [InternalTransferState.candidate] | Paired legs, no corroborating reference number — probably internal, not provably | **Still counted**, and flagged for review (AC-B11.2) |
/// | [InternalTransferState.external] | Determined third-party | Counted normally |
///
/// The middle state is risk R-7's answer and architecture §4.2 is explicit
/// about it: *"`confirmedByUser = false` means the pair is a candidate, and
/// candidates do not change spend totals until confirmed."* The bias is
/// deliberate and asymmetric, and it is the same bias ADR-017 takes on
/// duplicates: an **over**-stated total is visible on screen and correctable
/// in one tap; an under-stated one is invisible and the user never learns
/// they were told the wrong number. So an unproven internal transfer keeps
/// counting as spend and shouts, rather than quietly disappearing.
///
/// ## Derived at read time, persisted only when a person decides
///
/// [InternalTransferDetector.analyze] is a **pure function over a list of
/// transactions**. Nothing is cached, which is NFR-A6's requirement that no
/// derived figure exist that cannot be traced back to its constituents — the
/// same list the screen displays is the list the exclusion was computed from.
///
/// It also solves a sequencing problem for free: the two legs of a transfer
/// routinely arrive in separate SMS minutes or hours apart, and a decision
/// made at ingestion time would have to be revisited when the second leg
/// lands. A read-time derivation simply sees both.
///
/// The persisted `internal_transfer_state` column (schema v4) exists for the
/// **user's** decision, which outranks anything derived — see
/// [InternalTransferAnalysis.stateFor]. Writing to it is KHA-26/P3b-2's
/// mutation surface; this file only reads it.
library;

import 'ledger_transaction.dart';
import 'transaction_types.dart';

/// The persisted values of `Transaction.internal_transfer_state`.
///
/// String constants, not an `enum`, for the same reason as everywhere else in
/// this package: this is also the column's stored vocabulary.
abstract final class InternalTransferState {
  /// Both legs are the user's own instruments, and the app can prove it (or
  /// the user has confirmed it). Excluded from every spend total and every
  /// category breakdown (AC-B11.1).
  static const String internal = 'internal';

  /// Looks internal but is not proven. Flagged for review (AC-B11.2) and
  /// **still counted as spend** until confirmed.
  static const String candidate = 'candidate';

  /// Determined to be a genuine third-party transfer. Counted normally.
  static const String external = 'external';

  static const Set<String> all = <String>{internal, candidate, external};

  static bool isKnown(String value) => all.contains(value);
}

/// The `reviewReason` written for AC-B11.2's flag, so the Needs Review inbox
/// (design.md S-18) can render the right copy rather than free text.
const String reviewReasonPossibleInternalTransfer =
    'possible_internal_transfer';

/// **KHA-80 — why a transfer could not even become a candidate.**
///
/// Distinct from [InternalTransferState], and the distinction is the whole
/// issue: a *candidate* is a pair the detector found but cannot prove, and it
/// was already flagged. These are transfers the detector could not **pair at
/// all**, which fell through into ordinary spend carrying no flag whatsoever —
/// even though `_evidenceFor`'s own doc comment promised one for the
/// cross-currency case.
///
/// The user-visible consequence of leaving this unflagged is worse than it
/// sounds. The direction of the arithmetic error is safe (spend is
/// over-stated, never under-stated, which is this app's deliberate bias), but
/// AC-B11.2 asks for *"flagged for review rather than silently classified
/// either way"* and an unflagged over-statement is invisible rather than
/// correctable. The user is simply never told the figure may include a
/// movement to their own account.
///
/// ## The rule is evidence-based, not blanket, and that is deliberate
///
/// A flag is only raised when a **near-match partner actually exists**: an
/// opposite-direction transfer, within the pairing window, on a different
/// instrument, disqualified by exactly one axis. A lone outgoing transfer with
/// nothing resembling a counterpart anywhere is correctly classified as a
/// third-party payment and is *not* flagged.
///
/// The alternative — flagging every transfer whose instrument did not resolve
/// — was rejected. Early in the app's life that is most of them (risk R-7's
/// bootstrapping problem), and a review inbox that lists everything is a
/// review inbox nobody opens. A flag that fires on evidence keeps the queue
/// worth reading.
enum TransferReviewReason {
  /// The two legs match on direction, instrument-distinctness and time, but
  /// are denominated in **different currencies**, so no pair can be formed
  /// without inventing a rate — which ADR-009 forbids.
  ///
  /// Both legs stay visible as spend. This flag is the "as a review item" half
  /// of the promise `_evidenceFor` has always made in its doc comment.
  crossCurrencyNearMatch,

  /// The legs match on amount, currency, direction and time, but **one of them
  /// landed on no resolvable instrument** (its message carried too few digits
  /// to key on), so the app cannot say the movement stayed between the user's
  /// own accounts.
  ///
  /// Risk R-7 in its purest form, and the common case on a new install.
  unresolvedInstrument,
}

/// The `reviewReason` constants for [TransferReviewReason], mirroring
/// [reviewReasonPossibleInternalTransfer]'s role: a machine-readable key the
/// UI maps to localised copy. A cross-currency near-match and a
/// missing-instrument near-match need *different sentences* — "we found a
/// matching transfer in another currency" versus "we could not tell which
/// account this reached" — so they are not collapsed into one reason.
abstract final class TransferReviewReasonKey {
  static const String crossCurrency = 'transfer_cross_currency_near_match';
  static const String unresolvedInstrument = 'transfer_unresolved_instrument';

  static String forReason(TransferReviewReason reason) => switch (reason) {
    TransferReviewReason.crossCurrencyNearMatch => crossCurrency,
    TransferReviewReason.unresolvedInstrument => unresolvedInstrument,
  };
}

/// What made a pair believable. Carried so the UI can explain *why* a total
/// excluded something — NFR-A6 again: a figure the user cannot interrogate is
/// a figure they cannot trust.
enum InternalTransferEvidence {
  /// Both legs carry the same reference number. This is ADR-017's D2-grade
  /// evidence: a bank-issued reference number shared by two messages is not a
  /// coincidence.
  referenceMatch,

  /// Same amount, same currency, opposite directions, two of the user's own
  /// instruments, close in time. Strong, but a genuine same-amount pair of
  /// unrelated transfers is possible — so this yields a candidate, not a
  /// determination.
  amountAndTime,

  /// The user said so. Outranks everything.
  userConfirmed,
}

/// One matched pair — architecture §4.2's `InternalTransferLink`.
final class InternalTransferLink {
  /// Stable, derived from the two ids so the same pair always produces the
  /// same group id across rebuilds (and so a persisted link written later by
  /// P3b-2 lines up with a derived one).
  final String groupId;

  final int outTransactionId;
  final int inTransactionId;
  final InternalTransferEvidence evidence;

  const InternalTransferLink({
    required this.groupId,
    required this.outTransactionId,
    required this.inTransactionId,
    required this.evidence,
  });

  /// True when this pair is proven rather than merely plausible.
  bool get isDetermined => evidence != InternalTransferEvidence.amountAndTime;

  /// Ids and evidence only — no amount, no counterparty (NFR-S4).
  @override
  String toString() => 'InternalTransferLink($groupId, ${evidence.name})';
}

/// The result of running the detector over a set of transactions.
final class InternalTransferAnalysis {
  /// Transaction id → derived state. Only transfers appear here.
  final Map<int, String> _derivedStateById;

  /// Transaction id → the link it belongs to.
  final Map<int, InternalTransferLink> _linkById;

  /// **KHA-80.** Transaction id → why this transfer could not be paired at
  /// all. Only transfers that are *not* in [links] can appear here.
  final Map<int, TransferReviewReason> _unpairableById;

  final List<InternalTransferLink> links;

  const InternalTransferAnalysis._({
    required Map<int, String> derivedStateById,
    required Map<int, InternalTransferLink> linkById,
    required Map<int, TransferReviewReason> unpairableById,
    required this.links,
  }) : _derivedStateById = derivedStateById,
       _linkById = linkById,
       _unpairableById = unpairableById;

  /// Nothing matched. Used as the neutral value when a caller has no
  /// transaction list to analyse (e.g. a per-instrument view that must not
  /// re-derive pairs from a slice that contains only one side).
  static const InternalTransferAnalysis empty = InternalTransferAnalysis._(
    derivedStateById: <int, String>{},
    linkById: <int, InternalTransferLink>{},
    unpairableById: <int, TransferReviewReason>{},
    links: <InternalTransferLink>[],
  );

  /// The state to use for [transaction].
  ///
  /// **A persisted state always wins.** If the row carries an explicit
  /// `internalTransferState`, that is a decision a person made (or a future
  /// ingestion-time determination), and re-deriving over the top of it would
  /// let a screen silently overrule the user. The derived value is only a
  /// fallback for rows nobody has ruled on.
  ///
  /// Returns `null` for a transaction that is not a transfer at all, which is
  /// different from "a transfer we could not classify" ([
  /// InternalTransferState.candidate]) — the same explicit-unknown discipline
  /// AC-B1.3 applies to fields.
  String? stateFor(LedgerTransaction transaction) {
    final String? persisted = transaction.internalTransferState;
    if (persisted != null && InternalTransferState.isKnown(persisted)) {
      return persisted;
    }
    return _derivedStateById[transaction.id];
  }

  /// The link [transactionId] belongs to, or null.
  InternalTransferLink? linkFor(int transactionId) => _linkById[transactionId];

  /// **KHA-80 / AC-B11.2** — why [transaction] could not be paired, or null if
  /// it was paired or is not a transfer at all.
  ///
  /// A persisted decision suppresses this, for the same reason it outranks a
  /// derived state in [stateFor]: once the user has said "this is external",
  /// re-raising a review flag on the same movement every time the screen
  /// rebuilds is the app arguing with them.
  TransferReviewReason? unpairableReasonFor(LedgerTransaction transaction) {
    final String? persisted = transaction.internalTransferState;
    if (persisted != null && InternalTransferState.isKnown(persisted)) {
      return null;
    }
    return _unpairableById[transaction.id];
  }

  bool get isEmpty => links.isEmpty;
}

/// Finds internal-transfer pairs in a set of transactions.
abstract final class InternalTransferDetector {
  /// How far apart the two legs of one transfer may be.
  ///
  /// 24 hours, not minutes: a same-bank transfer posts both legs within
  /// seconds, but a transfer between two different banks routinely posts the
  /// credit the next working day. A window shorter than that would classify
  /// the common cross-bank case as third-party spending — the exact error
  /// US-B11 exists to prevent. A window much longer starts pairing unrelated
  /// same-amount transfers, which is why it is not simply "the period".
  static const Duration defaultWindow = Duration(hours: 24);

  /// Derives a state for every transfer in [transactions].
  ///
  /// Pairing is greedy and one-to-one: the strongest evidence is consumed
  /// first, and each leg can belong to at most one pair. Without the
  /// one-to-one rule, three transfers of the same amount would produce three
  /// mutually contradictory pairings and a total that changes depending on
  /// iteration order.
  static InternalTransferAnalysis analyze(
    Iterable<LedgerTransaction> transactions, {
    Duration window = defaultWindow,
  }) {
    final List<LedgerTransaction> outgoing = <LedgerTransaction>[];
    final List<LedgerTransaction> incoming = <LedgerTransaction>[];

    // KHA-80: every live, dated transfer, *including* the ones that cannot
    // pair. The pairing lists below deliberately exclude those; the
    // near-match pass at the end needs to see them, because a transfer that
    // cannot pair is exactly what it is looking for.
    final List<LedgerTransaction> allTransfers = <LedgerTransaction>[];

    for (final LedgerTransaction txn in transactions) {
      // A deleted transaction is out of every total (US-B8), so it must not
      // pair either — pairing it would exclude a live transfer on the
      // strength of a row the user has thrown away.
      if (txn.isDeleted ||
          !TransactionType.transferTypes.contains(txn.transactionType)) {
        continue;
      }
      // An undated transfer cannot be windowed against anything, so it is
      // beyond both pairing and near-matching.
      if (txn.occurredAt == null) {
        continue;
      }
      allTransfers.add(txn);

      // Both legs must have landed on a *known* instrument to **pair**. A
      // transfer whose instrument could not be resolved (too few digits to key
      // on) tells us nothing about whose account it hit, and guessing from a
      // name is exactly what AC-B11.2 forbids. It is not discarded, though —
      // it goes to the near-match pass, which is KHA-80's fix.
      if (txn.instrument == null) {
        continue;
      }
      if (txn.transactionType == TransactionType.transferOut) {
        outgoing.add(txn);
      } else {
        incoming.add(txn);
      }
    }

    final List<_Candidate> candidates = <_Candidate>[];
    for (final LedgerTransaction out in outgoing) {
      for (final LedgerTransaction inbound in incoming) {
        final InternalTransferEvidence? evidence = _evidenceFor(
          out: out,
          inbound: inbound,
          window: window,
        );
        if (evidence != null) {
          candidates.add(_Candidate(out, inbound, evidence));
        }
      }
    }

    // Strongest evidence first, then oldest first, then by id — a total
    // order, so the same input always yields the same pairing. A pairing that
    // depended on map iteration order would make a period total change
    // between two runs over identical data, which is the kind of bug that
    // destroys trust in a banking figure and is nearly impossible to
    // reproduce.
    candidates.sort((_Candidate a, _Candidate b) {
      final int byEvidence = a.evidence.index.compareTo(b.evidence.index);
      if (byEvidence != 0) {
        return byEvidence;
      }
      final int byTime = a.out.occurredAt!.compareTo(b.out.occurredAt!);
      return byTime != 0 ? byTime : a.out.id.compareTo(b.out.id);
    });

    final Set<int> used = <int>{};
    final Map<int, String> stateById = <int, String>{};
    final Map<int, InternalTransferLink> linkById =
        <int, InternalTransferLink>{};
    final List<InternalTransferLink> links = <InternalTransferLink>[];

    for (final _Candidate candidate in candidates) {
      if (used.contains(candidate.out.id) ||
          used.contains(candidate.inbound.id)) {
        continue;
      }
      used
        ..add(candidate.out.id)
        ..add(candidate.inbound.id);

      final InternalTransferLink link = InternalTransferLink(
        groupId: groupIdFor(
          outTransactionId: candidate.out.id,
          inTransactionId: candidate.inbound.id,
        ),
        outTransactionId: candidate.out.id,
        inTransactionId: candidate.inbound.id,
        evidence: candidate.evidence,
      );
      links.add(link);

      final String state = link.isDetermined
          ? InternalTransferState.internal
          : InternalTransferState.candidate;
      stateById[candidate.out.id] = state;
      stateById[candidate.inbound.id] = state;
      linkById[candidate.out.id] = link;
      linkById[candidate.inbound.id] = link;
    }

    return InternalTransferAnalysis._(
      derivedStateById: stateById,
      linkById: linkById,
      unpairableById: _findUnpairable(
        allTransfers,
        paired: used,
        window: window,
      ),
      links: links,
    );
  }

  /// **KHA-80** — the near-match pass, run over the transfers pairing left
  /// behind.
  ///
  /// Only transfers not in [paired] are considered, so a movement the app
  /// already understands is never second-guessed. For each remaining transfer
  /// it looks for a partner that matched on **every axis except one**, and
  /// reports which axis failed.
  ///
  /// Both sides of a near-match are flagged, not just the outgoing one. The
  /// outgoing leg is the one inflating spend, but the incoming leg is
  /// classified as *income* (`SpendClassification`), so leaving it unflagged
  /// would over-state income by the same movement — one unexplained figure
  /// traded for another.
  static Map<int, TransferReviewReason> _findUnpairable(
    List<LedgerTransaction> transfers, {
    required Set<int> paired,
    required Duration window,
  }) {
    final Map<int, TransferReviewReason> reasons =
        <int, TransferReviewReason>{};

    for (final LedgerTransaction a in transfers) {
      if (paired.contains(a.id) ||
          a.transactionType != TransactionType.transferOut) {
        continue;
      }
      for (final LedgerTransaction b in transfers) {
        if (paired.contains(b.id) ||
            b.transactionType != TransactionType.transferIn) {
          continue;
        }
        final TransferReviewReason? reason = _nearMatchReason(
          out: a,
          inbound: b,
          window: window,
        );
        if (reason == null) {
          continue;
        }
        // Recorded for both legs. `putIfAbsent` keeps the first (strongest,
        // by enum declaration order) reason rather than letting a later,
        // weaker near-match overwrite it.
        reasons.putIfAbsent(a.id, () => reason);
        reasons.putIfAbsent(b.id, () => reason);
      }
    }
    return reasons;
  }

  /// What single axis stopped [out] and [inbound] from pairing, or null when
  /// they are not a near-match at all (more than one axis differs, or they
  /// were never comparable).
  static TransferReviewReason? _nearMatchReason({
    required LedgerTransaction out,
    required LedgerTransaction inbound,
    required Duration window,
  }) {
    // Time is a precondition of both cases, not an axis that may fail: two
    // transfers a month apart are unrelated, not a near-match.
    if (out.occurredAt!.difference(inbound.occurredAt!).abs() > window) {
      return null;
    }

    final LedgerInstrument? outInstrument = out.instrument;
    final LedgerInstrument? inInstrument = inbound.instrument;

    // --- Case (a): both instruments known, but the currencies differ -------
    //
    // 2,000.00 SAR out of the current account and 533.19 USD into savings,
    // minutes apart, is overwhelmingly one movement — but pairing it needs a
    // rate, and ADR-009 forbids inventing one. Both legs stay in their totals;
    // the user is told why.
    if (outInstrument != null && inInstrument != null) {
      if (outInstrument.id == inInstrument.id) {
        return null;
      }
      if (out.amount.currencyCode != inbound.amount.currencyCode) {
        return TransferReviewReason.crossCurrencyNearMatch;
      }
      // Same currency and both instruments known: `_evidenceFor` already had
      // its chance at this pair. If it declined, the amounts differ, and two
      // different amounts are two different movements — not a near-match.
      return null;
    }

    // --- Case (b): exactly one side has no resolved instrument -------------
    //
    // Risk R-7's bootstrapping problem. The amounts must match exactly here:
    // without a resolved instrument on one side, amount-and-time is the only
    // evidence there is, and loosening it would flag unrelated movements.
    if (outInstrument == null && inInstrument == null) {
      return null;
    }
    if (out.amount != inbound.amount) {
      return null;
    }
    return TransferReviewReason.unresolvedInstrument;
  }

  /// The deterministic group id for a pair.
  static String groupIdFor({
    required int outTransactionId,
    required int inTransactionId,
  }) => 'itl:$outTransactionId:$inTransactionId';

  /// What, if anything, makes [out] and [inbound] two legs of one movement.
  static InternalTransferEvidence? _evidenceFor({
    required LedgerTransaction out,
    required LedgerTransaction inbound,
    required Duration window,
  }) {
    // The same instrument cannot transfer to itself. Without this, a bank
    // that sends both an "outgoing" and an "incoming" message for the *same*
    // leg would pair a transaction with its own echo and delete real spend
    // from the total.
    if (out.instrument!.id == inbound.instrument!.id) {
      return null;
    }
    // Exact magnitude match, in the same currency. `Money`'s `==` compares
    // value and currency, so this cannot accidentally match 100 USD against
    // 100 SAR — and cross-currency internal transfers (which do exist) are
    // deliberately *not* matched here: pairing them needs a rate, and
    // inventing one is forbidden (ADR-009). They stay visible as spend and
    // as a review item rather than being netted on a guessed rate.
    //
    // **KHA-80:** the "as a review item" half of that sentence was a promise
    // this file did not keep until P3b-2 — a cross-currency near-match fell
    // through to ordinary spend with no flag at all. [_findUnpairable] is the
    // implementation, and `TransferReviewReason.crossCurrencyNearMatch` is
    // what it produces for exactly this branch.
    if (out.amount != inbound.amount) {
      return null;
    }
    final Duration gap = out.occurredAt!.difference(inbound.occurredAt!).abs();
    if (gap > window) {
      return null;
    }

    final String? outRef = _normalizeReference(out.referenceNumber);
    final String? inRef = _normalizeReference(inbound.referenceNumber);
    if (outRef != null && inRef != null && outRef == inRef) {
      return InternalTransferEvidence.referenceMatch;
    }
    return InternalTransferEvidence.amountAndTime;
  }

  /// Reference numbers are compared case-insensitively with surrounding
  /// whitespace removed — the two legs come from two separately-formatted
  /// templates, and `d360-trf-556231` and `D360-TRF-556231` are the same
  /// reference. Nothing more aggressive: stripping punctuation would start
  /// matching references that merely look similar.
  static String? _normalizeReference(String? raw) {
    final String trimmed = (raw ?? '').trim();
    return trimmed.isEmpty ? null : trimmed.toUpperCase();
  }
}

final class _Candidate {
  final LedgerTransaction out;
  final LedgerTransaction inbound;
  final InternalTransferEvidence evidence;

  const _Candidate(this.out, this.inbound, this.evidence);
}
