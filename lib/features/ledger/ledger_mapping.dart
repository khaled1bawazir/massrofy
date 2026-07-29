/// Maps stored rows onto the ledger's value types.
///
/// ## Why this is one file, and why it lives here
///
/// The storage shape and the domain shape genuinely differ (see
/// `ledger_transaction.dart`), so *something* has to reassemble the money
/// triples and resolve the instrument. Doing it in one place means there is
/// exactly one piece of code that can get "amount column without its currency
/// column" wrong, and it has tests. Doing it in each screen means every screen
/// can get it wrong independently.
///
/// It sits in `features/ledger` rather than `data/` because the *target*
/// types are the ledger's. `features` depending on `data` row types matches
/// what P2 already does (`features/ingestion` imports the DAOs); the rule
/// architecture §3 actually forbids is the reverse direction and
/// feature-to-feature coupling.
///
/// ## The one subtle thing here
///
/// Money is read from the **authoritative `_amount` TEXT column**, never from
/// the `_minor` integer (ADR-002). `Money.tryParse` returns null rather than
/// throwing on a malformed value, so a row whose amount will not parse cannot
/// be turned into a [LedgerTransaction] at all.
///
/// ## KHA-74 — what happens to that row, and why the old answer was wrong
///
/// It used to be dropped, silently. The reasoning at the time was defensible
/// as far as it went — *"a zero-amount row in a list is invisible and wrong;
/// an absent row is at least honestly absent"* — and both halves of that are
/// true. What it missed is that **an absent row is not honestly absent to the
/// person reading the total.** The row vanished from every list and every
/// figure with no error, no flag and no count. A user whose ledger contained
/// one would be shown a smaller number than their real spending and would have
/// no way to discover it.
///
/// That is the failure mode this product exists to *not* have. `docs/PRD.md`'s
/// whole proposition is "trust the numbers", and NFR-A6 requires every derived
/// figure to trace back to its constituent transactions — a total that quietly
/// excludes one of its constituents does not trace to them, it traces to *most
/// of* them. A visibly broken total beats an invisibly wrong one.
///
/// So mapping now returns a [LedgerMappingOutcome]: the transactions it could
/// read, **and** a list of the rows it could not, as [UnreadableTransaction]
/// records carrying the row id and the reason. The presentation layer surfaces
/// them in the Needs Review inbox (design.md S-18) as a data-integrity item.
/// The underlying row is still untouched — nothing here repairs or deletes
/// anything, because guessing at what a corrupted amount was meant to say
/// would be inventing money.
///
/// **How reachable is this?** Today, only by editing the database outside the
/// app: every write path stores `Money.toCanonicalString()`, and P3b-2 adds
/// `checkMovementAmount` to the last unguarded one (KHA-79). The gap is closed
/// now precisely *because* this phase adds write paths — manual entry, the
/// enrichment merge, transfer confirmation — and because P7's statement import
/// will add more. A silent-drop behaviour is cheap to fix while it is
/// unreachable and expensive to discover once it is not.
library;

import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import 'ledger_transaction.dart';
import 'bank_tree.dart';

/// A stored transaction the app **cannot read**, surfaced rather than dropped.
///
/// Deliberately carries no amount text: the value is unparseable, so quoting
/// it back would put an arbitrary string from the database onto a screen and
/// into an accessibility tree, and NFR-S4 does not make an exception for
/// strings that happen to be broken.
final class UnreadableTransaction {
  /// `transactions.id`. Enough for the user to be told *"transaction #41 could
  /// not be read"* and for a future repair tool to find it, and nothing more.
  final int transactionId;

  /// Which part of the money triple failed. A closed vocabulary so the UI
  /// renders localised copy rather than an English diagnostic string.
  final UnreadableReason reason;

  const UnreadableTransaction({
    required this.transactionId,
    required this.reason,
  });

  @override
  String toString() => 'UnreadableTransaction(#$transactionId, ${reason.name})';
}

/// Why a stored row could not become a [LedgerTransaction].
enum UnreadableReason {
  /// The authoritative `amount_amount` column is not a valid exact decimal, so
  /// there is no honest [Money] to be had from the row.
  ///
  /// **O-QA-7 (KHA-90) — this used to also claim "or `amount_currency` is not
  /// a currency code this build understands", and that was never true.**
  /// [Money] performs no currency-code validation: it stores whatever string
  /// the write path handed it, so a row holding `ZZZ` maps perfectly well and
  /// never reaches here.
  ///
  /// The sentence was corrected rather than the code, because the current
  /// behaviour is the one KHA-74 actually asked for. An unrecognised currency
  /// lands in its own currency bucket, is excluded from the base-currency
  /// total, and is counted on the explicit "not converted" line — so the user
  /// is *told* the figure is incomplete. Declaring such a row unreadable would
  /// hide a real transaction behind an error banner to protect a total that is
  /// already protected. Rejecting an unknown code belongs at the **write**
  /// boundary, where the message that produced it can still be shown.
  unparsableAmount,
}

/// The result of mapping a set of stored rows: what could be read, and what
/// could not.
///
/// A dedicated type rather than a `(List, List)` record so callers must name
/// what they are ignoring. A caller that only wants [transactions] says so out
/// loud, which is a much better failure mode than a second return value nobody
/// notices — the shape of the KHA-74 bug in the first place.
final class LedgerMappingOutcome {
  final List<LedgerTransaction> transactions;

  /// Empty in every normal install. Non-empty means the ledger on disk holds
  /// something this build cannot represent, and the user must be told.
  final List<UnreadableTransaction> unreadable;

  const LedgerMappingOutcome({
    required this.transactions,
    required this.unreadable,
  });

  static const LedgerMappingOutcome empty = LedgerMappingOutcome(
    transactions: <LedgerTransaction>[],
    unreadable: <UnreadableTransaction>[],
  );

  bool get hasUnreadable => unreadable.isNotEmpty;
}

LedgerBank toLedgerBank(BankRow row) => LedgerBank(
  id: row.id,
  canonicalKey: row.canonicalKey,
  displayNameAr: row.displayNameAr,
  displayNameEn: row.displayNameEn,
);

LedgerInstrument toLedgerInstrument(InstrumentRow row) => LedgerInstrument(
  id: row.id,
  bankId: row.bankId,
  kind: row.kind,
  maskedIdentifier: row.maskedIdentifier,
  friendlyName: row.friendlyName,
  network: row.network,
  cardType: row.cardType,
  settlementAccountId: row.settlementAccountId,
);

/// Reassembles one transaction. Returns null when the authoritative amount
/// column cannot be parsed — see the library note above.
///
/// [instrumentsById] supplies the already-loaded instruments; passing the map
/// avoids a query per row when mapping a whole list.
LedgerTransaction? toLedgerTransactionOrNull(
  TransactionRow row, {
  Map<int, LedgerInstrument> instrumentsById = const <int, LedgerInstrument>{},
}) {
  final Money? amount = Money.tryParse(
    row.amountAmount,
    currency: row.amountCurrency,
  );
  if (amount == null) {
    return null;
  }

  return LedgerTransaction(
    id: row.id,
    amount: amount,
    direction: row.direction,
    transactionType: row.transactionType,
    affectsSpend: row.affectsSpend,
    occurredAt: row.occurredAt,
    timeSource: row.timeSource,
    merchantRawText: row.merchantRawText,
    counterpartyName: row.counterpartyName,
    counterpartyBankName: row.counterpartyBankName,
    referenceNumber: row.referenceNumber,
    // Schema v7 (KHA-30, KHA-31). Passed straight through, nulls included: a
    // null `categoryId` here means "uncategorized", which `CategoryResolver`
    // turns into the explicit category at display time — mapping must not
    // substitute a default, or the two representations this schema went out of
    // its way to avoid would reappear one layer up.
    categoryId: row.categoryId,
    categorySource: row.categorySource,
    categoryConfidence: row.categoryConfidence,
    categoryRuleId: row.categoryRuleId,
    merchantId: row.merchantId,
    convertedAmount: _moneyOrNull(
      row.convertedAmountAmount,
      row.convertedAmountCurrency,
    ),
    feeAmount: _moneyOrNull(row.feeAmountAmount, row.feeAmountCurrency),
    fxRate: row.fxRate,
    // Schema v4 (KHA-27, KHA-70, KHA-29). Passed straight through: every one
    // of these is nullable in exactly the way the domain type expects, and a
    // null here genuinely means "not recorded", not "not mapped".
    fxRateDate: row.fxRateDate,
    fxRateSource: row.fxRateSource,
    conversionPending: row.conversionPending,
    internalTransferGroupId: row.internalTransferGroupId,
    internalTransferState: row.internalTransferState,
    remainingBalance: _moneyOrNull(
      row.remainingBalanceAmount,
      row.remainingBalanceCurrency,
    ),
    instrument: row.instrumentId == null
        ? null
        : instrumentsById[row.instrumentId!],
    instrumentMaskedRefFromMessage: row.instrumentMaskedRef,
    provenance: row.provenance,
    provenanceDetail: row.provenanceDetail,
    sourceMessageId: row.sourceMessageId,
    rulePackId: row.rulePackId,
    rulePackVersion: row.rulePackVersion,
    ruleId: row.ruleId,
    needsReview: row.needsReview,
    reviewReason: row.reviewReason,
    possibleDuplicateOfId: row.possibleDuplicateOfId,
    isDeleted: row.isDeleted,
    deletedAt: row.deletedAt,
  );
}

/// Maps a whole list, **reporting** rather than discarding the rows whose
/// amount will not parse (KHA-74).
///
/// This is the mapping entry point new code should use. [toLedgerTransactions]
/// remains for the many call sites that legitimately only want the readable
/// transactions — a period total cannot include a row it cannot read — but
/// those call sites are now *choosing* to ignore the defect list rather than
/// being unaware one exists.
LedgerMappingOutcome mapLedgerTransactions(
  Iterable<TransactionRow> rows, {
  Map<int, LedgerInstrument> instrumentsById = const <int, LedgerInstrument>{},
}) {
  final List<LedgerTransaction> mapped = <LedgerTransaction>[];
  final List<UnreadableTransaction> unreadable = <UnreadableTransaction>[];

  for (final TransactionRow row in rows) {
    final LedgerTransaction? transaction = toLedgerTransactionOrNull(
      row,
      instrumentsById: instrumentsById,
    );
    if (transaction == null) {
      unreadable.add(
        UnreadableTransaction(
          transactionId: row.id,
          reason: UnreadableReason.unparsableAmount,
        ),
      );
      continue;
    }
    mapped.add(transaction);
  }

  return LedgerMappingOutcome(transactions: mapped, unreadable: unreadable);
}

/// Maps a whole list, keeping only the rows that could be read.
///
/// Use [mapLedgerTransactions] when the caller can surface a data problem;
/// this shorthand is for the arithmetic paths, which genuinely have nothing
/// they can do with an unreadable row except leave it out.
List<LedgerTransaction> toLedgerTransactions(
  Iterable<TransactionRow> rows, {
  Map<int, LedgerInstrument> instrumentsById = const <int, LedgerInstrument>{},
}) =>
    mapLedgerTransactions(rows, instrumentsById: instrumentsById).transactions;

/// Both halves of a money triple must be present, or the value is unknown.
///
/// An amount without a currency is not a smaller problem than no amount at
/// all — NFR-A5 requires every stored amount to carry its currency, and a
/// figure rendered without one is exactly the ambiguity this app exists to
/// remove.
Money? _moneyOrNull(String? amount, String? currency) {
  if (amount == null || currency == null) {
    return null;
  }
  return Money.tryParse(amount, currency: currency);
}
