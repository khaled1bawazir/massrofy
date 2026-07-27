/// Redaction-at-the-ingestion-boundary, enforced by a type.
///
/// ## Why this file holds two classes together (a note for Dart newcomers)
/// `docs/architecture.md` ADR-013 requires: *"`SanitizedSmsText` has a
/// private constructor and can be produced **only** by `SmsSanitizer`. A
/// developer cannot write an unsanitised `String` into the message table
/// because the code will not compile."*
///
/// In Dart, a name starting with `_` (like `SanitizedSmsText._`) is private
/// to the **file** it's declared in (Dart calls a file a "library"), not
/// merely to its class. That means [SmsSanitizer] must live in this same
/// file to be allowed to call `SanitizedSmsText._(...)` — if it lived in a
/// separate file, it would be just as locked out as any other caller, and
/// the whole point of this design would be defeated. So: one file, two
/// tightly-coupled classes, on purpose.
library;

/// A block of SMS body text that has already been through [SmsSanitizer]
/// and is therefore safe to persist (ADR-013) — any full PAN, CVV, PIN, or
/// IBAN it might have contained has already been destroyed, not merely
/// hidden.
///
/// There is no `SanitizedSmsText(String)` constructor. Anywhere in this
/// codebase you see a `SanitizedSmsText`, you know — by construction, not by
/// convention — that it went through [SmsSanitizer.sanitize] first. This is
/// the type the raw-message DAO's `insert` method requires (see
/// `lib/data/dao/raw_message_dao.dart`): it cannot accept a plain `String`.
class SanitizedSmsText {
  /// The redacted text. Safe to store, log (via [SafeLogger]-style redaction
  /// rules elsewhere), and display for user verification of a parse
  /// (AC-B1.2).
  final String value;

  /// True if a Luhn-valid PAN-shaped digit run was found and redacted in
  /// this message (`RawMessage.panRedacted` in the schema, ADR-013/ADR-004).
  final bool panRedacted;

  const SanitizedSmsText._(this.value, this.panRedacted);
}

/// Redacts sensitive-authentication-data patterns out of raw SMS text
/// **before** anything is persisted — the ingestion-boundary enforcement
/// ADR-013 requires, and the mechanism NFR-C2 relies on ("avoid handling
/// cardholder data entirely, rather than attempt to secure it").
///
/// This class has no state — every method is effectively a pure function of
/// its input — so a single shared instance (or, as here, `static` methods)
/// is all that's needed; there is nothing to construct.
abstract final class SmsSanitizer {
  // Matches a Saudi IBAN: "SA" followed by exactly 22 digits (2 check
  // digits + 20 BBAN digits, per the Saudi IBAN standard). Case-insensitive
  // so a lower-case "sa" prefix (unlikely, but cheap to cover) is caught too.
  static final RegExp _saudiIbanPattern = RegExp(
    r'SA\d{22}',
    caseSensitive: false,
  );

  // Any maximal run of digits. We later filter to the 13-19 length window
  // ADR-013 specifies for PAN candidates and Luhn-check each candidate,
  // rather than trying to write one clever-but-fragile regex that both
  // finds digit runs *and* validates Luhn in one step.
  static final RegExp _digitRunPattern = RegExp(r'\d+');

  // A secret-bearing keyword (English or Arabic), followed — somewhere in
  // the next few characters — by the 3-8 digit secret itself. The bounded
  // `{0,20}` gap is generous enough for a short connecting phrase ("is",
  // "هو", a colon, a space) without risking runaway backtracking (the
  // quantifier is bounded, not unbounded, so there is no catastrophic
  // backtracking risk here).
  static final RegExp _secretKeywordPattern = RegExp(
    r'(CVV|CVC|PIN|OTP|رمز التحقق|رمز|الرقم السري|كلمة المرور)[^\d]{0,20}(\d{3,8})',
    caseSensitive: false,
  );

  /// Redacts [rawBody] and returns a [SanitizedSmsText]. This is the **only**
  /// place in the app that is allowed to see genuinely raw SMS text and turn
  /// it into something persistable.
  ///
  /// [extraRedactPatterns] lets a per-bank rule pack (ADR-007's `redact[]`
  /// list) contribute additional regexes without this class needing to know
  /// about rule packs — parsing (P2) is not built yet in this P1 foundation,
  /// so this parameter defaults to empty and is here so the call site
  /// contract is already stable for when ADR-007 lands.
  static SanitizedSmsText sanitize(
    String rawBody, {
    List<RegExp> extraRedactPatterns = const <RegExp>[],
  }) {
    String text = rawBody;
    bool panRedacted = false;

    // 1) IBANs first. A Saudi IBAN's 22-digit run is always longer than the
    // 13-19 digit PAN window below, so the two patterns never actually
    // compete for the same characters — this ordering is for readability,
    // not correctness.
    text = text.replaceAllMapped(_saudiIbanPattern, (Match match) {
      final String digits = match.group(0)!;
      final String last4 = digits.substring(digits.length - 4);
      return 'SA**…$last4'; // "SA**…<last4>" per ADR-013
    });

    // 2) PAN candidates: maximal digit runs of length 13-19 that pass the
    // Luhn checksum. Luhn is exactly what makes this specific, not a blunt
    // "redact every long number" rule that would eat transaction reference
    // numbers and defeat duplicate-detection (ADR-017).
    text = text.replaceAllMapped(_digitRunPattern, (Match match) {
      final String digits = match.group(0)!;
      if (digits.length < 13 || digits.length > 19 || !_isLuhnValid(digits)) {
        return digits; // leave untouched — not PAN-shaped
      }
      panRedacted = true;
      final String last4 = digits.substring(digits.length - 4);
      return '****$last4';
    });

    // 3) CVV / PIN / OTP / password-shaped secrets, wherever the keyword
    // (English or Arabic) appears.
    text = text.replaceAllMapped(_secretKeywordPattern, (Match match) {
      final String keyword = match.group(1)!;
      final String between = match
          .group(0)!
          .substring(
            keyword.length,
            match.group(0)!.length - match.group(2)!.length,
          );
      return '$keyword$between[REDACTED]';
    });

    // 4) Per-bank additional patterns from a rule pack (ADR-007), if any.
    // Each is expected to have exactly one capture group naming the secret,
    // matching the rule-pack schema's `redact[]` convention
    // (`(?<secret>\d{3,8})`); we redact the whole match conservatively if no
    // named group is present, since over-redacting is always the safer
    // failure mode for a banking app (ADR-017's "bias hard toward the safe
    // side" principle applies here too).
    for (final RegExp pattern in extraRedactPatterns) {
      text = text.replaceAll(pattern, '[REDACTED]');
    }

    return SanitizedSmsText._(text, panRedacted);
  }

  /// Standard Luhn checksum (ISO/IEC 7812-1), used to tell a real card-like
  /// number apart from an ordinary long digit string (a reference number, a
  /// phone number run into an amount, etc.) so we redact precisely rather
  /// than indiscriminately.
  static bool _isLuhnValid(String digits) {
    int sum = 0;
    bool doubleThisDigit = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int digit = digits.codeUnitAt(i) - 0x30;
      if (doubleThisDigit) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      sum += digit;
      doubleThisDigit = !doubleThisDigit;
    }
    return sum % 10 == 0;
  }
}
