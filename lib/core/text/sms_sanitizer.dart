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

  // A PAN candidate that may be **group-separated**: two or more digit
  // groups joined by a single space or hyphen, e.g. "4111 1111 1111 1111"
  // or "4111-1111-1111-1111", as well as the plain contiguous run.
  //
  // ## Why this exists (Linear KHA-54, gap 3 — the highest-severity one)
  //
  // [_digitRunPattern] only ever matches a *maximal contiguous* run, so the
  // single most common real-world way of writing a card number — in groups
  // of four — never even reached the 13-19 length window, let alone the
  // Luhn check. A grouped PAN therefore survived `sanitize` completely
  // intact **and** `panRedacted` reported `false`, so the schema flag
  // actively recorded the absence of a PAN that was sitting in the row in
  // cleartext. That is precisely the outcome NFR-S2/NFR-C2 exist to make
  // structurally impossible.
  //
  // Note this is a **widening of ADR-013's literal wording** ("Luhn-valid
  // 13-19 digit runs"). It is recorded as an ADR amendment request rather
  // than a silent divergence — see the PR description for this phase.
  //
  // Group size is `{2,}` rather than exactly 4 so that non-standard
  // groupings (4-6-5 Amex-style, or 4-4-4-4-3 for a 19-digit PAN) are
  // covered too. The separator class is deliberately *single* space/hyphen
  // only: allowing runs of separators would let the pattern swallow two
  // unrelated numbers that merely sit near each other in the sentence.
  static final RegExp _groupedDigitRunPattern = RegExp(
    '[$_digitChars]{2,}(?:[ -][$_digitChars]{2,})+',
  );

  // A run of digits long enough to plausibly be a secret. Used by the
  // proximity sweep below, which redacts **every** such run inside a
  // keyword's window rather than only the nearest one.
  static final RegExp _secretDigitRunPattern = RegExp('[$_digitChars]{3,}');

  // Just the keywords, with no digits attached — the proximity sweep locates
  // the keyword first and then decides which digit runs are "near" it,
  // instead of trying to express both in one pattern (which is what made the
  // old single-shot patterns miss whenever a decoy number sat in between).
  static final RegExp _secretKeywordPattern = RegExp(
    '(?:$_secretKeywords)',
    caseSensitive: false,
  );

  /// How far, in **words**, a digit run may sit from a secret-bearing
  /// keyword and still be treated as the secret.
  ///
  /// KHA-54 gap 2 was caused by measuring this in *characters*: with a
  /// 20-character bound, `"Your verification code, valid for 5 minutes, is
  /// 903212"` redacted nothing at all — the `5` in "5 minutes" blocked the
  /// old no-digits-allowed gap class, and the remaining distance to the live
  /// code exceeded 20 characters. Counting words instead is stable against
  /// exactly that kind of ordinary connecting phrase, in both English and
  /// Arabic, and does not silently change meaning when a bank adds two words
  /// to its template.
  ///
  /// Set to 12 rather than something tighter after measuring against the
  /// longest realistic phrasings: `Your one-time password to complete your
  /// purchase at MERCHANT is CODE` and `Your verification code, valid for 5
  /// minutes, is CODE` both fall comfortably inside it, and a bank adding two
  /// words to a template must not silently reopen the leak.
  ///
  /// The cost of the generous bound is over-redaction, and it is bounded in
  /// turn: it can only fire in a message that contains a secret keyword at
  /// all, and such a message is almost always classified `intent: ignore`
  /// (OTP/marketing), whose body is discarded entirely anyway. The worst
  /// realistic case is a transaction message that mentions a code, which is
  /// then routed to the review queue where the user can see it — visible and
  /// recoverable, versus a leaked live code, which is neither.
  static const int _secretProximityWords = 12;

  /// A hard character ceiling on the same window, so that a message with no
  /// spaces at all (or a pathological one-word block) cannot turn the word
  /// bound into "the entire message".
  static const int _secretProximityMaxChars = 120;

  // The secret-bearing keywords, English and Arabic. Covers
  // common OTP synonyms beyond the original CVV/PIN/OTP set —
  // "verification code"/"one-time password"/"access code" in English, and
  // "رمز الدخول"/"رمز التفعيل" in Arabic — since real bank OTP messages
  // phrase the same concept many ways, and under-redacting any of them is
  // exactly the failure mode this class exists to prevent.
  static const String _secretKeywords =
      r'CVV|CVC|PIN|OTP|one[- ]time password|verification code|access code|'
      r'رمز التحقق|رمز الدخول|رمز التفعيل|رمز|الرقم السري|كلمة المرور';

  /// Redacts [rawBody] and returns a [SanitizedSmsText]. This is the **only**
  /// place in the app that is allowed to see genuinely raw SMS text and turn
  /// it into something persistable.
  ///
  /// [extraRedactPatterns] lets a per-bank rule pack (ADR-007's `redact[]`
  /// list) contribute additional regexes without this class needing to know
  /// about rule packs. The P2 ingestion pipeline
  /// (`lib/features/ingestion/ingestion_pipeline.dart`) now passes the
  /// matched bank's patterns here for real; the generic path below is the
  /// fallback for any sender whose rule pack has no `redact[]` list, and is
  /// never a *substitute* for it.
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

    // 2) PAN candidates, **including group-separated ones**.
    //
    // Two passes, longest-form first: the grouped pattern is tried before
    // the contiguous one so that "4111 1111 1111 1111" is consumed as a
    // single 16-digit candidate rather than as four unrelated 4-digit runs
    // that individually fail the length window. (KHA-54 gap 3.)
    //
    // Luhn is what makes this specific rather than a blunt "redact every
    // long number" rule — the latter would eat transaction reference
    // numbers and defeat duplicate detection (ADR-017 D2), which is a
    // correctness regression traded for no security gain.
    text = text.replaceAllMapped(_groupedDigitRunPattern, (Match match) {
      final String candidate = match.group(0)!;
      final String digits = _stripGroupSeparators(candidate);
      if (!_isPanShaped(digits)) {
        return candidate; // leave untouched — not PAN-shaped
      }
      panRedacted = true;
      return '****${digits.substring(digits.length - 4)}';
    });

    text = text.replaceAllMapped(_digitRunPattern, (Match match) {
      final String digits = match.group(0)!;
      if (!_isPanShaped(digits)) {
        return digits;
      }
      panRedacted = true;
      return '****${digits.substring(digits.length - 4)}';
    });

    // 3) CVV / PIN / OTP / password-shaped secrets.
    //
    // See [_redactSecretsNearKeywords] for why this is a proximity sweep
    // over *every* nearby digit run rather than the two single-shot
    // "keyword then digits" / "digits then keyword" regexes it replaced
    // (Linear KHA-54, gaps 1 and 2).
    text = _redactSecretsNearKeywords(text);

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

  /// Removes the single space/hyphen separators inside a grouped digit
  /// candidate so the length window and Luhn check see the number the way
  /// the issuer wrote it, not the way the bank's template printed it.
  static String _stripGroupSeparators(String candidate) =>
      candidate.replaceAll(' ', '').replaceAll('-', '');

  /// ADR-013's PAN test, in one place so the contiguous and grouped passes
  /// can never disagree about what "PAN-shaped" means.
  static bool _isPanShaped(String digits) =>
      digits.length >= 13 && digits.length <= 19 && _isLuhnValid(digits);

  /// Destroys **every** digit run of 3+ digits that sits within
  /// [_secretProximityWords] words of a secret-bearing keyword, in either
  /// direction.
  ///
  /// ## Why a sweep, and not the two regexes this replaced
  ///
  /// The previous implementation used one pattern for "keyword, gap, digits"
  /// and a mirrored one for "digits, gap, keyword". Both matched **the
  /// nearest** digit run only, and both defined "gap" as up to 20 characters
  /// containing *no digits*. Linear KHA-54 reproduced two consequences of
  /// that, and both leaked a live secret in cleartext:
  ///
  /// 1. **A decoy wins.** `"Your OTP for account 1234 is 567890"` redacted
  ///    the account suffix `1234` — because it was nearest — and left the
  ///    actual code `567890` untouched. The redaction marker in the output
  ///    made the message *look* handled.
  /// 2. **A decoy plus distance redacts nothing.** `"Your verification code,
  ///    valid for 5 minutes, is 903212"` matched neither direction: the `5`
  ///    in "5 minutes" broke the no-digits gap class, and the distance from
  ///    the keyword to the code exceeded the 20-character bound.
  ///
  /// The fix is to stop trying to identify *which* run is the secret — that
  /// is not knowable from the text — and instead destroy all of them inside
  /// the window. **Over-redaction is the correct failure mode here.** The
  /// worst case is that a message becomes unparseable and therefore lands in
  /// the review queue (US-A4), where the user sees it and can act; the
  /// alternative failure mode is a live one-time code sitting in the database
  /// forever, which is silent and unrecoverable. That is the same asymmetry
  /// ADR-017 reasons from when it biases toward flagging over auto-removal.
  ///
  /// Note the deliberate consequence: an OTP/marketing message from a known
  /// bank is classified `intent: ignore` by ADR-007 and stored **with no body
  /// at all**, so aggressive redaction of exactly those messages costs the
  /// product nothing. The messages this could over-redact are transaction
  /// messages that happen to contain a secret keyword — and those are
  /// precisely the ones where a secret would otherwise be persisted.
  static String _redactSecretsNearKeywords(String text) {
    final List<Match> keywords = _secretKeywordPattern
        .allMatches(text)
        .toList();
    if (keywords.isEmpty) {
      return text;
    }

    // Collect the [start, end) span of every digit run to destroy. A Set
    // keyed by start offset would be enough, but a list of spans reads more
    // obviously and the counts here are tiny (an SMS is <= 1600 chars).
    final List<({int start, int end})> spans = <({int start, int end})>[];

    for (final Match digitRun in _secretDigitRunPattern.allMatches(text)) {
      final bool nearAnyKeyword = keywords.any(
        (Match keyword) => _isWithinProximity(
          text,
          keywordStart: keyword.start,
          keywordEnd: keyword.end,
          runStart: digitRun.start,
          runEnd: digitRun.end,
        ),
      );
      if (nearAnyKeyword) {
        spans.add((start: digitRun.start, end: digitRun.end));
      }
    }

    if (spans.isEmpty) {
      return text;
    }

    // Rebuild the string, replacing each span wholesale. Iterating forwards
    // and tracking a cursor keeps every offset valid — mutating in place
    // while indices shift underneath is the classic way this kind of code
    // starts leaving stray digits behind.
    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (final ({int start, int end}) span in spans) {
      out.write(text.substring(cursor, span.start));
      out.write('[REDACTED]');
      cursor = span.end;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }

  /// True when the digit run at `[runStart, runEnd)` is close enough to the
  /// keyword at `[keywordStart, keywordEnd)` to be treated as its secret.
  ///
  /// "Close enough" is **word count first, character count as a ceiling** —
  /// see [_secretProximityWords] for why measuring in characters alone was
  /// the bug.
  static bool _isWithinProximity(
    String text, {
    required int keywordStart,
    required int keywordEnd,
    required int runStart,
    required int runEnd,
  }) {
    // The text strictly between the two spans, whichever order they occur in.
    final int gapStart = runEnd <= keywordStart ? runEnd : keywordEnd;
    final int gapEnd = runEnd <= keywordStart ? keywordStart : runStart;
    if (gapEnd < gapStart) {
      return true; // overlapping — e.g. "PIN1234" with no separator at all
    }

    final String gap = text.substring(gapStart, gapEnd);
    if (gap.length > _secretProximityMaxChars) {
      return false;
    }
    // `trim().split(whitespace)` on an empty/blank gap yields [''], i.e. a
    // length of 1, which is why the blank case is short-circuited: an
    // adjacent run must never be pushed over the bound by counting a
    // phantom word.
    final String trimmed = gap.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    final int words = trimmed.split(RegExp(r'\s+')).length;
    return words <= _secretProximityWords;
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
