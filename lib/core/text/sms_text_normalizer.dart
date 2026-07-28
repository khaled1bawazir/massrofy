/// Step 1 of `docs/architecture.md` ADR-007's evaluation order: put a raw
/// SMS body into **one canonical shape** before any rule regex is applied to
/// it.
///
/// ## Why normalisation has to happen, and has to happen exactly once
///
/// A Saudi bank SMS is a hostile input for a regex:
///
///  - It mixes **three digit families** — ASCII `0-9`, Arabic-Indic `٠-٩`
///    (U+0660–0669) and Extended/Persian `۰-۹` (U+06F0–06F9) — sometimes
///    inside the same message (an Arabic sentence quoting a Latin merchant
///    name that carries ASCII store digits).
///  - It is **bidirectional text**, so the wire form is littered with
///    invisible bidi controls (LRM/RLM/ALM, the isolate and embedding marks)
///    that a human never sees but a regex absolutely does. `\s` does not
///    match them; `.` does. A rule that works when pasted into a test and
///    fails on the real wire form is almost always this.
///  - Arabic display text may carry **tatweel** (ـ, U+0640), a pure
///    typographic stretch character with no semantic value, which splits a
///    keyword like `شراء` into something no literal match can find.
///  - Whitespace is inconsistent: NBSP, narrow NBSP, tabs, doubled spaces,
///    and newlines all appear where a single space is meant.
///
/// If each rule tried to defend against all of that itself, every rule in
/// every rule pack would need the same defensive noise, and the *first* rule
/// author to forget one would ship a silent miss. So the pipeline normalises
/// **once**, up front, and every rule (and, per ADR-008, the merchant-key
/// pipeline later) matches against the normalised form only.
///
/// ## What this deliberately does NOT do
///
/// ADR-007 step 1 says "Unicode NFKC". **Dart's core library ships no
/// Unicode normalisation**, and pulling a full NFKC table in would add a
/// sizeable dependency to a no-network app for a case that barely occurs in
/// SMS (Arabic *presentation forms*, U+FB50–FDFF / U+FE70–FEFF, are produced
/// by legacy rendering stacks, not by modern carriers). Rather than claim
/// NFKC and not do it, this file implements the **specific, enumerated**
/// compatibility folds that matter for this input domain and says so out
/// loud:
///
///  - the three digit families → ASCII,
///  - Arabic decimal/thousands separators → ASCII equivalents,
///  - bidi controls, tatweel, and Arabic diacritics → removed,
///  - all whitespace runs → a single ASCII space.
///
/// Anything beyond that is an honest gap, recorded here rather than in a
/// comment nobody reads. See `docs/architecture.md` §8 — this is the kind of
/// deviation the ADR asks to be surfaced, not silently absorbed.
///
/// ## A note for readers new to Dart
///
/// This file exposes only top-level `const` data and one class of `static`
/// methods. There is no instance state, so there is nothing to construct —
/// `abstract final class` is the modern Dart way to say "this type is a
/// namespace for functions; you may not extend it and you may not
/// instantiate it".
library;

/// Canonicalises raw SMS text for rule matching (ADR-007 step 1).
abstract final class SmsTextNormalizer {
  // --- Invisible characters -------------------------------------------------
  //
  // Bidi formatting controls. The first three (LRM/RLM/ALM) are already
  // handled by `normalizeNumerals` in core/money for the narrow numeral
  // case; the isolate/embedding/override family (U+202A–U+202E, U+2066–
  // U+2069) is what actually appears around Latin merchant names embedded
  // in an Arabic sentence, and is the set that most often breaks a rule
  // that looked fine in a test file.
  static const Set<int> _invisibleCodePoints = <int>{
    0x200B, // ZERO WIDTH SPACE
    0x200C, // ZERO WIDTH NON-JOINER
    0x200D, // ZERO WIDTH JOINER
    0x200E, // LEFT-TO-RIGHT MARK
    0x200F, // RIGHT-TO-LEFT MARK
    0x061C, // ARABIC LETTER MARK
    0x202A, // LEFT-TO-RIGHT EMBEDDING
    0x202B, // RIGHT-TO-LEFT EMBEDDING
    0x202C, // POP DIRECTIONAL FORMATTING
    0x202D, // LEFT-TO-RIGHT OVERRIDE
    0x202E, // RIGHT-TO-LEFT OVERRIDE
    0x2066, // LEFT-TO-RIGHT ISOLATE
    0x2067, // RIGHT-TO-LEFT ISOLATE
    0x2068, // FIRST STRONG ISOLATE
    0x2069, // POP DIRECTIONAL ISOLATE
    0xFEFF, // ZERO WIDTH NO-BREAK SPACE / BOM
    0x0640, // ARABIC TATWEEL — typographic stretch, zero semantic value
  };

  /// Arabic diacritics (harakat) and the superscript alef, U+064B–U+0652 and
  /// U+0670. Banks generally do not vowel their SMS text, but a rule that
  /// matched `شِراء` and not `شراء` would be a maddening intermittent bug, so
  /// they are stripped unconditionally. This mirrors ADR-008's merchant
  /// normalisation pipeline deliberately: the parser and the merchant matcher
  /// must agree on what "the same string" means, or a merchant learned from
  /// one message will not match the next.
  static bool _isArabicDiacritic(int codePoint) =>
      (codePoint >= 0x064B && codePoint <= 0x0652) || codePoint == 0x0670;

  // --- Digit families -------------------------------------------------------

  /// Arabic-Indic (U+0660–0669) and Extended/Persian (U+06F0–06F9) digits.
  /// Returns the ASCII digit, or `null` when [codePoint] is not one of them.
  ///
  /// Kept as arithmetic on contiguous blocks rather than a 20-entry map
  /// because the two families are visually near-identical (compare ٤ and ۴)
  /// and a hand-written map is genuinely unreviewable by eye — the same
  /// argument `sms_sanitizer.dart` makes for using `\uXXXX` escapes.
  static String? _asciiDigitOrNull(int codePoint) {
    if (codePoint >= 0x0660 && codePoint <= 0x0669) {
      return String.fromCharCode(0x30 + (codePoint - 0x0660));
    }
    if (codePoint >= 0x06F0 && codePoint <= 0x06F9) {
      return String.fromCharCode(0x30 + (codePoint - 0x06F0));
    }
    return null;
  }

  static const int _arabicDecimalSeparator = 0x066B; // ٫
  static const int _arabicThousandsSeparator = 0x066C; // ٬
  static const int _arabicPercentSign = 0x066A; // ٪

  /// Any run of whitespace — ASCII or Unicode — collapses to one space.
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Returns [raw] in the canonical form every rule-pack regex is written
  /// against.
  ///
  /// Idempotent by construction: `normalize(normalize(x)) == normalize(x)`,
  /// which matters because the ingestion pipeline normalises for the dedup
  /// HMAC (ADR-017 D1) *and* for rule matching (ADR-007), and those two must
  /// never disagree about what "the same message" is. There is a test that
  /// asserts this property directly.
  ///
  /// **Length-preserving it is not** — characters are removed. Never use an
  /// index taken from normalised text against the raw string.
  static String normalize(String raw) {
    final StringBuffer buffer = StringBuffer();

    for (final int codePoint in raw.runes) {
      if (_invisibleCodePoints.contains(codePoint) ||
          _isArabicDiacritic(codePoint)) {
        continue;
      }

      final String? asciiDigit = _asciiDigitOrNull(codePoint);
      if (asciiDigit != null) {
        buffer.write(asciiDigit);
        continue;
      }

      switch (codePoint) {
        case _arabicDecimalSeparator:
          buffer.write('.');
        case _arabicThousandsSeparator:
          buffer.write(',');
        case _arabicPercentSign:
          buffer.write('%');
        // A non-breaking space is whitespace semantically but is not matched
        // by every `\s` implementation people expect; map it explicitly so
        // the collapse below is guaranteed to catch it.
        case 0x00A0:
        case 0x202F:
        case 0x2007:
          buffer.write(' ');
        default:
          buffer.writeCharCode(codePoint);
      }
    }

    return buffer.toString().replaceAll(_whitespaceRun, ' ').trim();
  }
}
