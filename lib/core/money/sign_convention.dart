/// **THE SIGN CONVENTION.** Read this before writing any code that stores,
/// aggregates or displays a money movement — KHA-28, US-B7, AC-B7.1/B7.2,
/// NFR-A6, and the settled contract for KHA-26's manual-entry validation
/// (defect O-QA-2).
///
/// ---
///
/// ## The decision, in one sentence
///
/// > **An amount is always a non-negative magnitude. The sign lives in
/// > [MovementDirection], and nowhere else.**
///
/// A purchase of 152.75 SAR and a refund of 152.75 SAR are stored with the
/// *same* `amount` (`152.75`) and different `direction`s (`debit` vs
/// `credit`). There is no negative number anywhere in the transaction table,
/// no `isCredit` boolean alongside a signed amount, and no "negative means
/// refund" convention in any form field.
///
/// ## Why this convention and not the alternatives
///
/// Three candidates were on the table. The decision matters because KHA-28
/// requires refunds to net against spend, and a convention that is applied
/// inconsistently across storage, aggregation and display produces totals
/// that cannot be reconciled at all (NFR-A6, and the Linear issue says so
/// explicitly).
///
/// | Candidate | Why not |
/// |---|---|
/// | **Signed `amount`** (a refund is `-152.75`) | Every aggregation site then has to decide whether to negate, and half of them will get it wrong once. Worse, it makes "negative" a *legal* value, which is exactly how defect **O-QA-2** happens: a user types `-50` into the S-19 completion form and silently inverts the movement direction, producing a refund the bank never issued. If negative is never legal, that class of bug cannot be typed in. |
/// | **Signed `amount` + a redundant `direction` column** | Two sources of truth for one fact. The day they disagree — an import, a migration, a hand-edited row — nothing in the system can say which one is right. |
/// | **Magnitude + `direction` (chosen)** | One source of truth. The sign is applied at exactly one place in the aggregation path ([signedForSpend]) and at exactly one place in the display path (`formatSignedAmount`). A negative amount is then unambiguously *invalid input*, which is a checkable precondition rather than a silent semantic. |
///
/// The database already leans this way — `transaction_table.dart` says a
/// refund "is never stored as a negative debit" — but leaning is not a
/// contract. This file makes it one, with a validator ([violationForAmount])
/// that callers can enforce and tests can pin.
///
/// ## The contract KHA-26 (P3b-2) must build against
///
/// The manual-entry and completion forms (S-19, S-14) must:
///
///  1. **Reject a negative amount outright**, with the message
///     `AppLocalizations.amountMustBePositive` — do *not* silently take the
///     absolute value, and do *not* interpret the minus sign as "make this a
///     credit". Both are guesses about intent.
///  2. **Offer direction as an explicit control** (a debit/credit segmented
///     control), never as a sign the user types. The S-19 form already has
///     one ("Money in" / "Money out"); the amount field must not become a
///     second, contradictory way of saying the same thing.
///  3. **Accept zero.** This is settled the other way, deliberately, and it
///     is the point most likely to be "fixed" by mistake: KHA-25 requires
///     *"'unknown' to be distinguishable from 'zero' in the data model"*, a
///     bank can genuinely post a zero-value authorisation, and there is a
///     test in `unparsed_completion_test.dart` that pins it. Zero is a
///     magnitude like any other; only a negative one is a sign in disguise.
///
/// ## Where the sign is actually applied
///
///  - **Aggregation:** [signedForSpend], called only from
///    `period_totals.dart`.
///  - **Display:** `formatSignedAmount` in `presentation/widgets/
///    ledger_widgets.dart`, which prefixes `−` or `+` (and pairs it with an
///    icon and a word, per NFR-U4 — the sign never travels by colour alone).
///
/// Two call sites, both named here, both tested. That is the whole surface.
library;

import 'money.dart';

/// The closed vocabulary of movement directions (architecture §4.2
/// `Transaction.direction`).
///
/// Constants rather than a Dart `enum` because these exact spellings are what
/// the `direction` column stores and what a rule pack's `sign` field produces
/// — one vocabulary, one place, no mapping layer that could drift.
abstract final class MovementDirection {
  /// Money leaving the instrument: a purchase, a fee, an outgoing transfer.
  static const String debit = 'debit';

  /// Money arriving at the instrument: a refund, income, an incoming
  /// transfer. A credit **reduces** period spend (US-B7, AC-B7.1) — it never
  /// increases it, and it is never stored as a negative debit.
  static const String credit = 'credit';

  static const Set<String> all = <String>{debit, credit};

  /// True when [value] is a direction this app understands.
  ///
  /// An imported rule pack (ADR-007's answer to R-11) could name a third
  /// direction. Callers treat an unknown direction as `debit` for storage but
  /// must **not** silently include it in a total — see
  /// `SpendClassification.of`, which routes an unknown direction to
  /// `needsReview` rather than to an assumption.
  static bool isKnown(String value) => all.contains(value);
}

/// Why an amount is not a valid movement magnitude.
///
/// A closed set rather than free text, so the presentation layer maps it to a
/// localised message and the domain layer never carries a user-facing string
/// (which would be untranslatable and, worse, would tempt someone to
/// interpolate the amount into it — NFR-S4).
/// A one-value enum today, on purpose: it is the shape a *set* of rules takes,
/// and the next rule (say, "more fractional digits than the currency has minor
/// units") should join it rather than become a second boolean somewhere else.
enum AmountViolation {
  /// The amount is strictly less than zero. See the O-QA-2 note above: this
  /// is rejected, never absolute-valued and never reinterpreted as a credit.
  negative,
}

/// Returns the reason [amount] cannot be a movement magnitude, or `null` when
/// it is valid.
///
/// **Zero is valid** — see point 3 of the contract above before changing that.
///
/// Deliberately a *query*, not an assertion that throws: the ingestion
/// pipeline must route a bad value to the review queue (NFR-A7) rather than
/// crash the batch (NFR-R5), and a form must show a field error rather than
/// blow up. Callers that genuinely want the hard failure use
/// [checkMovementAmount].
AmountViolation? violationForAmount(Money amount) =>
    amount.isNegative ? AmountViolation.negative : null;

/// Throws [ArgumentError] when [amount] is not a valid movement magnitude.
///
/// For write paths that have already validated their input and want the
/// invariant enforced at the boundary — a defence in depth, so a future
/// caller that forgets [violationForAmount] fails loudly at the DAO rather
/// than quietly in a total three screens away.
void checkMovementAmount(Money amount, {required String context}) {
  final AmountViolation? violation = violationForAmount(amount);
  if (violation == null) {
    return;
  }
  // The message names the violation and the call site, never the figure
  // (NFR-S4: an exception message is a log line waiting to happen).
  throw ArgumentError(
    'Invalid movement amount in $context: ${violation.name}. '
    'Amounts are non-negative magnitudes; the sign lives in `direction` '
    '(see lib/core/money/sign_convention.dart).',
  );
}

/// The amount as it contributes to a **spend** total: positive for a debit,
/// negative for a credit.
///
/// This is the single place in the app where the convention is turned into
/// arithmetic. `Money`'s unary minus keeps the subtraction in exact decimal
/// arithmetic (ADR-002) instead of branching on sign at every call site.
///
/// An unrecognised [direction] is treated as a debit here — but callers are
/// expected to have excluded such a transaction from the total already (see
/// `SpendClassification.of`). Treating it as a debit is the conservative
/// direction to be wrong in: it over-states spend visibly rather than
/// under-stating it invisibly.
Money signedForSpend(Money amount, {required String direction}) =>
    direction == MovementDirection.credit ? -amount : amount;
