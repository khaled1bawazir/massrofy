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
  // --- What counts as a "digit" here -------------------------------------
  //
  // Dart's `\d` in a RegExp is **ASCII-only** (`[0-9]`) — it does NOT match
  // Eastern Arabic-Indic numerals (٠١٢٣٤٥٦٧٨٩, U+0660–U+0669) or the
  // Extended/Persian forms (۰۱۲۳۴۵۶۷۸۹, U+06F0–U+06F9). That matters for an
  // Arabic-first product: a `\d`-based OTP pattern would silently fail to
  // redact "١٢٣٤٥٦ هو رمز التحقق" and write a live one-time code into the
  // database in cleartext.
  //
  // Which digit form actually arrives in real SMS is genuinely unknown to
  // us: `docs/PRD.md` §3.4 deliberately does **not** reproduce the sample
  // bank messages (NFR-M3 forbids committing real bank SMS), and
  // `docs/brand.md` §"Numerals" mandates Western digits only for what the
  // *UI renders* — a display rule, which says nothing about what a bank
  // puts on the wire. So rather than guess, we match all three digit
  // families. Over-redacting is the safe failure mode for a banking app
  // (the same principle ADR-017 applies elsewhere); under-redacting leaks a
  // secret permanently.
  //
  // This is a character-class *body*, interpolated into the patterns below
  // (and negated as `[^$_digitChars]`) so every pattern in this file agrees
  // on what a digit is — the previous mix of `\d` and `[^\d]` was where the
  // inconsistency could creep back in.
  //
  // Written as `\uXXXX` escapes rather than literal ٠-٩ / ۰-۹ glyphs on
  // purpose: the two Arabic-Indic families are visually near-identical
  // (compare ٤ and ۴), so a literal range is genuinely unreviewable by eye
  // and a mistyped endpoint would silently narrow what gets redacted. The
  // escapes are also immune to any re-encoding of this source file. Dart's
  // RegExp understands `\uXXXX` inside a character class, and in a raw
  // string (`r'...'`) the backslash reaches the regex engine intact.
  static const String _digitChars =
      r'0-9' // ASCII 0-9
      r'\u0660-\u0669' // Arabic-Indic ٠١٢٣٤٥٦٧٨٩
      r'\u06F0-\u06F9'; // Extended/Persian Arabic-Indic ۰۱۲۳۴۵۶۷۸۹

  // Matches a Saudi IBAN: "SA" followed by exactly 22 digits (2 check
  // digits + 20 BBAN digits, per the Saudi IBAN standard). Case-insensitive
  // so a lower-case "sa" prefix (unlikely, but cheap to cover) is caught too.
  static final RegExp _saudiIbanPattern = RegExp(
    'SA[$_digitChars]{22}',
    caseSensitive: false,
  );

  // Any maximal run of digits. We later filter to the 13-19 length window
  // ADR-013 specifies for PAN candidates and Luhn-check each candidate,
  // rather than trying to write one clever-but-fragile regex that both
  // finds digit runs *and* validates Luhn in one step.
  static final RegExp _digitRunPattern = RegExp('[$_digitChars]+');

  // The secret-bearing keywords, English and Arabic, shared by both of the
  // OTP patterns below so the two directions can never drift apart. Covers
  // common OTP synonyms beyond the original CVV/PIN/OTP set —
  // "verification code"/"one-time password"/"access code" in English, and
  // "رمز الدخول"/"رمز التفعيل" in Arabic — since real bank OTP messages
  // phrase the same concept many ways, and under-redacting any of them is
  // exactly the failure mode this class exists to prevent.
  static const String _secretKeywords =
      r'CVV|CVC|PIN|OTP|one[- ]time password|verification code|access code|'
      r'رمز التحقق|رمز الدخول|رمز التفعيل|رمز|الرقم السري|كلمة المرور';

  // A secret-bearing keyword, followed — somewhere in the next few
  // characters — by the secret digits themselves. Three capture groups:
  // (1) the keyword, (2) the connecting gap, (3) the digit run.
  //
  // ## Why the digit run is `{3,}` and NOT `{3,8}`
  // A bounded upper limit leaks. With `(\d{3,8})`, the input
  // "OTP: 123456789 is your code" matched only the first EIGHT digits and
  // produced "OTP: [REDACTED]9" — publishing the tail of a live code. OTP
  // lengths genuinely vary between banks (4, 5, 6, 8... ), so raising the
  // bound just moves the leak rather than closing it. An unbounded `{3,}`
  // is greedy, so it consumes the **entire contiguous digit run**, leaving
  // no remainder at either end. See the 9-digit regression tests in
  // test/core/text/sms_sanitizer_test.dart.
  //
  // The gap is `[^$_digitChars]{0,20}` — generous enough for a short
  // connecting phrase ("is", "هو", a colon, a space) while, crucially,
  // being unable to match a digit. That is what guarantees the digit run
  // this pattern finds is genuinely adjacent to the keyword, and it also
  // keeps the quantifier bounded, so there is no catastrophic-backtracking
  // risk.
  static final RegExp _keywordBeforeDigitsPattern = RegExp(
    '($_secretKeywords)'
    '([^$_digitChars]{0,20})'
    '([$_digitChars]{3,})',
    caseSensitive: false,
  );

  // The mirror image of [_keywordBeforeDigitsPattern]: the digits appear
  // *first*, then the keyword — the ordinary phrasing of a very common
  // Arabic OTP message shape, e.g. "١٢٣٤٥٦ هو رمز التحقق الخاص بك" ("123456
  // is your verification code"). A pattern that only ever looks for
  // "keyword, then digits" never matches this at all, which is precisely
  // the OTP-under-redaction gap this closes: without this second pattern, a
  // 6-digit OTP phrased this (extremely common) way would sail through
  // [sanitize] completely unredacted, unless it also happened to be a
  // Luhn-valid 13-19 digit PAN candidate (it almost never is — OTPs are
  // typically 4-6 digits).
  //
  // The same unbounded-`{3,}` reasoning applies here, and this direction is
  // where a bounded quantifier leaked from the *front*: "123456789 is your
  // OTP" used to produce "1[REDACTED] is your OTP", because the engine gave
  // up on matching 8 digits at offset 0 and simply restarted one character
  // later. Greedy-and-unbounded matches the whole run from its true start.
  // Groups: (1) the digit run, (2) the gap, (3) the keyword.
  static final RegExp _digitsBeforeKeywordPattern = RegExp(
    '([$_digitChars]{3,})'
    '([^$_digitChars]{0,20})'
    '($_secretKeywords)',
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
    // (English or Arabic) appears — in **either** order relative to the
    // digits, since real bank messages use both ("Your OTP is 123456" and
    // "123456 هو رمز التحقق"). Running both directions is what actually
    // closes the OTP-under-redaction gap; a single direction silently
    // missed a whole common phrasing (see the pattern doc comments above).
    //
    // Both patterns capture the connecting gap as its own group, so the
    // replacement is a straight reassembly of "everything except the digit
    // run". (An earlier version recomputed the gap with `substring` index
    // arithmetic over group lengths — correct, but fragile enough that it
    // was worth removing now that the quantifiers are variable-length.)
    // Group 3 / group 1 respectively — the digit run — is simply dropped
    // and replaced wholesale, so no digit of it can survive.
    text = text.replaceAllMapped(_keywordBeforeDigitsPattern, (Match match) {
      return '${match.group(1)}${match.group(2)}[REDACTED]';
    });
    text = text.replaceAllMapped(_digitsBeforeKeywordPattern, (Match match) {
      return '[REDACTED]${match.group(2)}${match.group(3)}';
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

  /// The numeric value 0-9 of a single digit character, in any of the three
  /// digit families [_digitChars] accepts (ASCII, Arabic-Indic,
  /// Extended/Persian Arabic-Indic).
  ///
  /// Needed because the old `codeUnit - 0x30` trick only works for ASCII:
  /// applied to '٥' (U+0665) it yields 1589, which would silently corrupt
  /// the Luhn sum below into meaningless arithmetic rather than failing
  /// loudly. Each family is a contiguous, in-order block, so subtracting
  /// the block's base is all that's required.
  ///
  /// Returns `null` for anything that isn't a digit — callers treat that as
  /// "not a PAN candidate" rather than guessing.
  static int? _digitValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
    if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
      return codeUnit - 0x0660; // ٠-٩
    }
    if (codeUnit >= 0x06F0 && codeUnit <= 0x06F9) {
      return codeUnit - 0x06F0; // ۰-۹
    }
    return null;
  }

  /// Standard Luhn checksum (ISO/IEC 7812-1), used to tell a real card-like
  /// number apart from an ordinary long digit string (a reference number, a
  /// phone number run into an amount, etc.) so we redact precisely rather
  /// than indiscriminately.
  ///
  /// Script-agnostic: a PAN written in Arabic-Indic numerals checksums
  /// exactly like the same PAN in ASCII, so a card number does not escape
  /// redaction merely by arriving in a different digit family.
  static bool _isLuhnValid(String digits) {
    int sum = 0;
    bool doubleThisDigit = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      final int? digitValue = _digitValue(digits.codeUnitAt(i));
      if (digitValue == null) return false; // not a digit run we understand
      int digit = digitValue;
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
