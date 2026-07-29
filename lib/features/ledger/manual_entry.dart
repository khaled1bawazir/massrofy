/// **US-B4 — adding a transaction by hand.** KHA-26, AC-B4.1, AC-B4.2,
/// AC-B4.3, and defect O-QA-2's validation contract.
///
/// ---
///
/// ## Cash is a first-class citizen here, not a fallback
///
/// OQ-19 settled this and the wording matters: cash spending is *"first-class,
/// not a fallback"*. A tracker built from bank SMS knows about card and
/// account movements and is structurally blind to the notes in someone's
/// pocket. If entering cash feels like using an escape hatch, the user stops
/// doing it, and the monthly total quietly drifts away from what they actually
/// spent — while still looking authoritative. So "no instrument" is a normal,
/// unremarkable choice on this form, rendered as *"Cash"*, not as an error
/// state and not as a missing field.
///
/// ## Validation names the field (AC-B4.2)
///
/// > *"A missing required field blocks saving with a message NAMING the
/// > missing field."*
///
/// [ManualEntryRejected] therefore carries a list of [ManualEntryField]
/// constants, not a boolean and not a sentence. The form maps each one to a
/// localised message under the right input. "Invalid input" would satisfy a
/// literal reading of "blocks saving" and fail the point of the criterion,
/// which is that the user can act on what they are told (brand.md voice
/// principle 4).
///
/// ## The sign convention, restated because this is where it gets typed
///
/// `lib/core/money/sign_convention.dart` is the contract, and this form is the
/// caller it was written for. Three rules, all enforced below:
///
///  1. A negative amount is **rejected outright** ([ManualEntryField.amount]
///     with [AmountProblem.negative]). It is not absolute-valued, and the
///     minus sign is emphatically not read as "make this a refund" — both
///     would be guesses about intent, and the second one silently invents a
///     refund the bank never issued (defect O-QA-2).
///  2. Direction is an **explicit control** (Money in / Money out), never a
///     sign the user types.
///  3. **Zero is accepted.** This is settled the other way on purpose and is
///     the point most likely to be "fixed" by mistake — KHA-25 requires
///     unknown and zero to stay distinguishable, and a bank can post a
///     zero-value authorisation. Only a *negative* magnitude is a sign in
///     disguise.
library;

import '../../core/money/money.dart';
import '../../core/money/sign_convention.dart';
import '../../data/dao/transaction_dao.dart';
import 'transaction_types.dart';

/// The field names the manual-entry form can report as missing or invalid.
///
/// Constants rather than free text: the UI maps them to localised labels, and
/// an English string here would be untranslatable in an Arabic-first app.
/// Mirrors `CompletionField` in `unparsed_completion.dart` deliberately — the
/// two forms are the same form per design.md S-20, so their error vocabularies
/// should not diverge.
abstract final class ManualEntryField {
  static const String amount = 'amount';
  static const String currency = 'currency';
  static const String occurredAt = 'occurredAt';
  static const String transactionType = 'transactionType';
  static const String direction = 'direction';
}

/// Why an amount was refused, when the field was filled in but wrong.
///
/// Separate from "missing" because the two need different sentences: an empty
/// field needs *"enter an amount"*, a negative one needs an explanation of the
/// direction control (`amountMustBePositive`).
enum AmountProblem {
  /// Nothing was typed.
  missing,

  /// Typed, but not a valid exact decimal — or a valid decimal in a currency
  /// code this build does not recognise.
  unparsable,

  /// Negative. See the sign-convention notes above.
  negative,
}

/// What the user typed. Every field is stated; nothing here is inferred.
final class ManualTransactionDraft {
  /// Exact decimal text, as typed. Parsed once, in [ManualEntryService], via
  /// [Money.tryParse] — which also accepts Arabic-Indic digits, as an
  /// Arabic-first app must (and as a hand-rolled check in a widget would not).
  final String amountText;

  /// ISO 4217 code. Defaulted by the form to the base currency but always
  /// explicit in the data: NFR-A5 allows no amount without one.
  final String currencyCode;

  final DateTime? occurredAt;

  /// One of `transaction_types.dart`'s values.
  final String? transactionType;

  /// `debit` | `credit`, from the segmented control.
  final String direction;

  final String? merchantRawText;

  /// The account or card this hit, or **null for cash** — the first-class
  /// choice described above, not an omission.
  final int? instrumentId;

  final String? categoryId;
  final String? referenceNumber;
  final String? counterpartyName;

  const ManualTransactionDraft({
    required this.amountText,
    required this.currencyCode,
    this.occurredAt,
    this.transactionType,
    this.direction = MovementDirection.debit,
    this.merchantRawText,
    this.instrumentId,
    this.categoryId,
    this.referenceNumber,
    this.counterpartyName,
  });

  /// No amount, no merchant (NFR-S4).
  @override
  String toString() => 'ManualTransactionDraft(${transactionType ?? '?'})';
}

/// The outcome of a manual-entry attempt.
sealed class ManualEntryResult {
  const ManualEntryResult();
}

/// The transaction was written, with its audit entry, atomically.
final class ManualEntryAccepted extends ManualEntryResult {
  final int transactionId;
  const ManualEntryAccepted(this.transactionId);
}

/// Nothing was written.
///
/// [missingFields] holds [ManualEntryField] constants so the form can point at
/// each one (AC-B4.2). [amountProblem] refines the amount case when the field
/// was filled but unusable.
final class ManualEntryRejected extends ManualEntryResult {
  final List<String> missingFields;
  final AmountProblem? amountProblem;

  const ManualEntryRejected(this.missingFields, {this.amountProblem});
}

/// Writes a user-entered transaction (AC-B4.1) after validating it (AC-B4.2).
final class ManualEntryService {
  final TransactionDao transactionDao;

  const ManualEntryService({required this.transactionDao});

  /// Validates [draft] and, on success, writes the transaction and its audit
  /// entry in one database transaction.
  ///
  /// The validation here duplicates the form's own checks on purpose: the
  /// form's checks exist for the *person* (show every problem at once, in
  /// place), these exist for the *data* (nothing invalid reaches storage, no
  /// matter which caller). Neither trusts the other, and the DAO's
  /// `checkMovementAmount` is a third line behind both.
  Future<ManualEntryResult> add(
    ManualTransactionDraft draft, {
    DateTime? now,
  }) async {
    final String rawAmount = draft.amountText.trim();
    final Money? amount = Money.tryParse(
      rawAmount,
      currency: draft.currencyCode,
    );

    AmountProblem? amountProblem;
    if (rawAmount.isEmpty) {
      amountProblem = AmountProblem.missing;
    } else if (amount == null) {
      amountProblem = AmountProblem.unparsable;
    } else if (violationForAmount(amount) == AmountViolation.negative) {
      // O-QA-2. Rejected, never absolute-valued, never reinterpreted as a
      // credit — the direction control below is the only way to say "credit".
      amountProblem = AmountProblem.negative;
    }

    final List<String> missing = <String>[
      if (amountProblem != null) ManualEntryField.amount,
      // An unparsable amount can mean the *currency* is the unrecognised part,
      // so both fields are named. Pointing only at the amount would send the
      // user to correct a number that was already correct.
      if (amountProblem == AmountProblem.unparsable &&
          !_looksLikeCurrencyCode(draft.currencyCode))
        ManualEntryField.currency,
      if (draft.occurredAt == null) ManualEntryField.occurredAt,
      if ((draft.transactionType ?? '').trim().isEmpty)
        ManualEntryField.transactionType,
      if (!MovementDirection.isKnown(draft.direction))
        ManualEntryField.direction,
    ];

    if (missing.isNotEmpty) {
      return ManualEntryRejected(missing, amountProblem: amountProblem);
    }

    final String type = draft.transactionType!;
    final int id = await transactionDao.insertManual(
      amount: amount!,
      merchantRawText: _blankToNull(draft.merchantRawText),
      occurredAt: draft.occurredAt!,
      direction: draft.direction,
      transactionType: type,
      // Derived from the type rather than asked of the user: whether a
      // withdrawal counts as spend is a property of what a withdrawal *is*
      // (AC-B10.2), not a judgement the person entering it should have to
      // make. Note `transfer_out` is NOT in this set — whether a transfer is
      // internal is a property of the pair, which a form filling in one leg
      // cannot know (AC-B11.2, risk R-7). `internal_transfer.dart` decides it
      // from evidence and flags what it cannot prove.
      affectsSpend: !TransactionType.nonSpendTypes.contains(type),
      instrumentId: draft.instrumentId,
      categoryId: _blankToNull(draft.categoryId),
      referenceNumber: _blankToNull(draft.referenceNumber),
      counterpartyName: _blankToNull(draft.counterpartyName),
      now: now,
    );
    return ManualEntryAccepted(id);
  }

  /// A three-letter code is the shape ISO 4217 takes; anything else means the
  /// user mistyped the currency rather than the amount.
  static bool _looksLikeCurrencyCode(String value) => value.trim().length == 3;

  /// An empty text field means "the user did not state this" — AC-B1.3's
  /// unknown, not an empty-string value that would render as a blank row
  /// indistinguishable from a merchant literally called "".
  static String? _blankToNull(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
