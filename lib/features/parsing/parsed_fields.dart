/// The structured output of a successful parse: everything the rule engine
/// could read out of one bank SMS, and **nothing it guessed**.
///
/// ## Why every field is nullable, and why that is the point
///
/// AC-B1.3 requires that a field absent from the source message be recorded
/// as **explicitly unknown** — never blank, never zero, never inferred. A
/// `null` here means "the message did not say", and the UI renders that as
/// the literal text *"Not stated in message"* (design.md S-11), not as an
/// empty row the user has to interpret.
///
/// The alternative — defaulting `merchant` to `''` or `feeAmount` to zero —
/// is how a spending tracker quietly tells someone a foreign-currency
/// purchase cost them nothing in fees. In a banking app the difference
/// between "zero" and "unknown" is not a nicety.
///
/// ## Scope note: this is not the `Transaction` entity
///
/// `docs/architecture.md` §4.2 defines the full `Transaction` (bank and
/// instrument foreign keys, categorisation confidence, soft-delete
/// lifecycle, internal-transfer links). That is **P3** work. This class is
/// the parser's half of the contract: flat, foreign-key-free, and derived
/// purely from message text. P3 maps it onto the domain model; it does not
/// replace it.
library;

import '../../core/money/money.dart';

/// Which instrument a message named, in the masked form we are allowed to
/// keep (NFR-S2 — there is no field anywhere in this app able to hold a full
/// PAN).
final class InstrumentReference {
  /// `card` or `account`. Comes from the matched rule's declared
  /// `instrumentKind`, never from a guess about how many digits were
  /// printed (AC-B13.1/2).
  final String kind;

  /// Already reduced to its storable form, e.g. `****4821`.
  final String maskedIdentifier;

  /// `visa` | `mada` | `mastercard`, or `null` when the message did not say.
  /// PRD §3.4 notes that the *same* bank prints a network for cards and
  /// nothing at all for bare account numbers.
  final String? network;

  /// `credit` | `debit` | `prepaid`, or `null` when unstated.
  final String? cardType;

  const InstrumentReference({
    required this.kind,
    required this.maskedIdentifier,
    this.network,
    this.cardType,
  });

  @override
  bool operator ==(Object other) =>
      other is InstrumentReference &&
      other.kind == kind &&
      other.maskedIdentifier == maskedIdentifier &&
      other.network == network &&
      other.cardType == cardType;

  @override
  int get hashCode => Object.hash(kind, maskedIdentifier, network, cardType);

  /// Safe to log and to show: the identifier is masked by construction, and
  /// this type can never hold anything but a masked form.
  @override
  String toString() =>
      'InstrumentReference($kind $maskedIdentifier'
      '${network == null ? '' : ' $network'}'
      '${cardType == null ? '' : ' $cardType'})';
}

/// Everything one message yielded.
final class ParsedFields {
  /// The transaction amount in the currency the message stated.
  ///
  /// This is the **native** amount (NFR-A5). For a foreign-currency purchase
  /// this is the foreign amount, and [convertedAmount] carries the inline
  /// SAR figure the bank printed alongside it.
  final Money? amount;

  /// The SAR (or base-currency) figure the message itself supplied, where it
  /// did. ADR-009 prefers the bank's own conversion over any rate we could
  /// derive — the bank's number is what actually hit the account.
  final Money? convertedAmount;

  /// The FX / international-transaction fee, as its **own** field.
  ///
  /// PRD §3.4 and Linear KHA-19 are explicit that this must not be folded
  /// into [amount]. Folding it in overstates what the purchase cost and
  /// makes the fee invisible to the "where does my money go" question that
  /// is the entire product.
  final Money? feeAmount;

  /// Exchange rate as an exact decimal **string** — deliberately not a
  /// `double`, and deliberately not `Money` (a rate is not an amount of
  /// money). Stored as text per architecture §4.2 `Transaction.fxRate`.
  final String? exchangeRate;

  /// The account/loan balance a message reported after the movement — PRD
  /// §3.4 notes the installment template does this. Informational only; it
  /// is never treated as spend.
  final Money? remainingBalance;

  /// The merchant/payee exactly as the message printed it, after the rule's
  /// declared transforms. ADR-008's normalisation into a `merchantKey`
  /// happens later, in categorisation (P4) — the parser deliberately keeps
  /// the raw-ish text so a normalisation change can never silently rewrite
  /// what the bank actually said.
  final String? merchantRawText;

  final InstrumentReference? instrument;

  /// The *second* instrument some templates name — specifically the
  /// settlement/source account in a credit-card repayment message. This is
  /// the only automatic source of `Instrument.settlementAccountId`
  /// (AC-B14.1); everywhere else the link stays null and is shown as
  /// "not linked", never inferred (AC-B14.3).
  final InstrumentReference? settlementInstrument;

  /// Wall-clock reading from the message, already interpreted as
  /// `Asia/Riyadh` and converted to UTC. Pair with [timeSource].
  final DateTime? occurredAtUtc;

  /// `sms_explicit` | `sms_local_assumed` | `received_at_fallback`
  /// (architecture §4.2). Recorded so an odd-looking timestamp is
  /// explainable rather than mysterious.
  final String? timeSource;

  /// Present on transfers and some bill payments (PRD §3.4). Where present
  /// this is the **reliable** duplicate key (ADR-017 D2); where absent,
  /// dedup falls back to the heuristic tier.
  final String? referenceNumber;

  final String? counterpartyName;
  final String? counterpartyBankName;
  final String? billerCode;
  final String? invoiceNumber;

  const ParsedFields({
    this.amount,
    this.convertedAmount,
    this.feeAmount,
    this.exchangeRate,
    this.remainingBalance,
    this.merchantRawText,
    this.instrument,
    this.settlementInstrument,
    this.occurredAtUtc,
    this.timeSource,
    this.referenceNumber,
    this.counterpartyName,
    this.counterpartyBankName,
    this.billerCode,
    this.invoiceNumber,
  });

  /// Which of the engine's known field names actually produced a value.
  ///
  /// Used for the `requiredFields` check. Kept next to the fields themselves
  /// so adding a field to this class and forgetting to make it requirable is
  /// a one-file mistake rather than a silent one.
  Set<String> get presentFieldNames => <String>{
    if (amount != null) 'amount',
    if (convertedAmount != null) 'convertedAmount',
    if (feeAmount != null) 'feeAmount',
    if (exchangeRate != null) 'exchangeRate',
    if (remainingBalance != null) 'remainingBalance',
    if (merchantRawText != null) 'merchant',
    if (instrument != null) 'instrumentRef',
    if (settlementInstrument != null) 'settlementRef',
    if (occurredAtUtc != null) 'occurredAt',
    if (referenceNumber != null) 'referenceNumber',
    if (counterpartyName != null) 'counterpartyName',
    if (counterpartyBankName != null) 'counterpartyBankName',
    if (billerCode != null) 'billerCode',
    if (invoiceNumber != null) 'invoiceNumber',
  };

  /// **Deliberately does not include amounts, merchants, counterparties, or
  /// any identifier** (NFR-S4, ADR-015). `toString()` is the single most
  /// common accidental leak in a Dart codebase — an object interpolated into
  /// a log line — so this one reports shape only.
  @override
  String toString() => 'ParsedFields(fields: ${presentFieldNames.length})';
}
