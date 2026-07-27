/// Thrown whenever an operation would combine two [Money] values (see
/// `money.dart`) that carry different ISO 4217 currency codes, without going
/// through an explicit, stated conversion.
///
/// ## Why this exists (ADR-002 / NFR-A5)
/// `docs/architecture.md` ADR-002 requires that "amounts in different
/// currencies must never be summed without a stated conversion" to be true
/// *at runtime, in every code path* — not just something engineers remember.
/// Extending `Error` (rather than `Exception`) is a deliberate choice: in
/// Dart, an `Error` signals a programming mistake that should never be
/// caught-and-ignored in normal control flow (contrast this with
/// `FormatException`, which callers are expected to catch when parsing
/// untrusted input). Adding SAR to USD without a rate is exactly that kind
/// of mistake, and this type makes it loud and unmistakable.
class CurrencyMismatchError extends Error {
  /// The operation attempted, e.g. `'add'`, `'subtract'`, `'compare'`.
  final String operation;

  /// The currency code of the left-hand operand.
  final String left;

  /// The currency code of the right-hand operand.
  final String right;

  CurrencyMismatchError(this.operation, this.left, this.right);

  @override
  String toString() =>
      'CurrencyMismatchError: cannot $operation Money($left) and Money($right) '
      'directly. Cross-currency arithmetic requires an explicit ExchangeRate '
      'via MoneyConverter.convert() — see docs/architecture.md ADR-002/ADR-009.';
}
