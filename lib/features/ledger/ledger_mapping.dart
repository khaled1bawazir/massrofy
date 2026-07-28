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
/// throwing on a malformed value, and a transaction whose amount will not
/// parse is skipped by [toLedgerTransactionOrNull] rather than rendered as
/// zero — a zero-amount row in a list is invisible and wrong; an absent row is
/// at least honestly absent, and the underlying data is untouched.
library;

import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import 'ledger_transaction.dart';
import 'bank_tree.dart';

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
    convertedAmount: _moneyOrNull(
      row.convertedAmountAmount,
      row.convertedAmountCurrency,
    ),
    feeAmount: _moneyOrNull(row.feeAmountAmount, row.feeAmountCurrency),
    fxRate: row.fxRate,
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

/// Maps a whole list, dropping only rows whose amount will not parse.
List<LedgerTransaction> toLedgerTransactions(
  Iterable<TransactionRow> rows, {
  Map<int, LedgerInstrument> instrumentsById = const <int, LedgerInstrument>{},
}) => <LedgerTransaction>[
  for (final TransactionRow row in rows)
    ?toLedgerTransactionOrNull(row, instrumentsById: instrumentsById),
];

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
