/// The closed vocabulary of `Transaction.transactionType`
/// (`docs/architecture.md` §4.2), in one place.
///
/// ## Why constants and not a Dart `enum`
///
/// These exact spellings are three things at once: what a rule pack writes in
/// its `messageType` field, what the `transaction_type` column stores, and
/// what `SpendClassification` switches on. An `enum` would need a mapping
/// layer at each boundary, and a mapping layer is somewhere for the three to
/// drift apart. One spelling, checked in one place.
///
/// ## Unknown types are expected, not exceptional
///
/// ADR-007's §5.2 forward-compatibility rule allows a *newer imported pack*
/// to introduce a type this build has never heard of. Nothing here throws on
/// one: [isKnown] answers the question honestly and callers degrade
/// gracefully — the transaction is still recorded, still listed, and excluded
/// from spend totals until something can classify it (NFR-A7: nothing is
/// silently dropped, but nothing is silently counted either).
library;

abstract final class TransactionType {
  // --- Spending ------------------------------------------------------------

  /// Card present at a merchant.
  static const String posPurchase = 'pos_purchase';

  /// Card-not-present. The template PRD §3.4 observed carrying a foreign
  /// currency, an inline conversion and an FX fee.
  static const String onlinePurchase = 'online_purchase';

  /// A utility/telecom bill paid from an account (biller code + invoice).
  static const String billPayment = 'bill_payment';

  /// A standalone fee or VAT debit.
  static const String fee = 'fee';

  /// A loan/finance installment deduction, which PRD §3.4 notes also reports
  /// a remaining balance.
  static const String installment = 'installment';

  /// The bare "debited from account" template — almost no other detail.
  static const String accountDebit = 'account_debit';

  /// Money leaving an account toward a named counterparty. **Spend only when
  /// the counterparty is a third party** — see `internal_transfer.dart`.
  static const String transferOut = 'transfer_out';

  // --- Money in ------------------------------------------------------------

  /// A refund, reversal or merchant credit. Nets against spend (US-B7).
  static const String refund = 'refund';

  /// Money arriving from a named counterparty. Income when the counterparty
  /// is a third party; an internal transfer when it is the user themselves.
  static const String transferIn = 'transfer_in';

  /// A salary/payroll credit specifically (AC-B10.1). Distinguished from
  /// [transferIn] so the income view can name it, and so a future budget can
  /// treat recurring income differently from a one-off inbound transfer.
  static const String salaryIncome = 'salary_income';

  // --- Neither spend nor income -------------------------------------------

  /// Cash taken out at an ATM (AC-B10.2). **Not spend**: the money still
  /// belongs to the user, it has merely stopped being traceable. It becomes
  /// spend only when the user records what the cash was used for, via manual
  /// entry (US-B4).
  static const String withdrawal = 'withdrawal';

  /// A credit-card repayment from a linked account. **Not spend**: it settles
  /// purchases that were already counted when the card was used, and counting
  /// it again is architecture §4.2's named "single easiest way to make every
  /// total wrong".
  static const String cardRepayment = 'card_repayment';

  /// A correction the user or an importer applied. Reserved; no rule produces
  /// it yet.
  static const String adjustment = 'adjustment';

  /// The parser matched a rule that declared no type, or a row predates the
  /// column. Excluded from spend until something classifies it.
  static const String unknown = 'unknown';

  static const Set<String> all = <String>{
    posPurchase,
    onlinePurchase,
    billPayment,
    fee,
    installment,
    accountDebit,
    transferOut,
    refund,
    transferIn,
    salaryIncome,
    withdrawal,
    cardRepayment,
    adjustment,
    unknown,
  };

  static bool isKnown(String value) => all.contains(value);

  /// The two transfer types, which are the only ones an internal-transfer
  /// pair can be made of (`internal_transfer.dart`).
  static const Set<String> transferTypes = <String>{transferOut, transferIn};

  /// Types that a **data-entry form** should record with `affectsSpend:
  /// false` (US-B10/B11).
  ///
  /// ## This is the form's default, not the classifier's answer
  ///
  /// `SpendClassification` is what actually decides whether a movement counts
  /// toward spend, and it derives that from the type and direction rather than
  /// trusting the stored boolean — a rule pack may say "this is not spend" and
  /// be believed, but may not say "this internal transfer *is* spend". This
  /// set exists only so a form writing a new row starts it out with a sensible
  /// `affects_spend` value instead of asking the person a question that has an
  /// objective answer.
  ///
  /// **[transferOut] is deliberately absent**, and it was wrongly present in
  /// P3a's S-19 form. A transfer moves the user's own money only when it is
  /// *internal*, and whether it is internal is a property of the **pair**,
  /// which a form filling in one leg cannot possibly know (AC-B11.2, risk
  /// R-7). Including it meant every hand-entered outgoing transfer — including
  /// a genuine payment to a third party — was silently dropped from spend.
  static const Set<String> nonSpendTypes = <String>{
    cardRepayment,
    transferIn,
    salaryIncome,
    // AC-B10.2 — cash out is not spend until the user records what it bought.
    withdrawal,
  };

  /// The types whose natural direction is money *arriving* (US-B7, AC-B10.1).
  ///
  /// A form uses this to set the direction control alongside the type, because
  /// direction is the only place the sign lives and getting it wrong is
  /// getting the total wrong (`lib/core/money/sign_convention.dart`).
  static const Set<String> creditTypes = <String>{
    refund,
    transferIn,
    salaryIncome,
  };
}
