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
/// One redaction to apply: destroy `[start, end)` and put `replacement`
/// there.
///
/// A **record type** (Dart 3), which is a lightweight anonymous tuple with
/// named fields — no class declaration, no constructor, and structural
/// equality for free. Declared at library level because Dart does not allow
/// a `typedef` inside a class body.
///
/// Every generic redaction rule in [SmsSanitizer] produces a list of these
/// rather than rewriting the string itself. That is what lets three
/// independent rules agree on one consistent view of the text: each reports
/// *what it found and where*, and a single function applies them all in one
/// pass with the offsets still valid.
typedef _Redaction = ({int start, int end, String replacement});

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

  // --- §13.3 — the group separator set -----------------------------------
  //
  // Exactly five characters, ratified in ADR-013 §13.3. Written as escapes
  // for the same reason as [_digitChars]: three of the five are invisible
  // whitespace variants that no reviewer can tell apart by eye.
  //
  // What is **excluded** matters as much as what is included, and §13.3
  // records the reasons so nobody re-adds them on a hunch:
  //
  //  - **the full stop `.`** is the decimal separator in amounts. Including
  //    it would trade a real risk of destroying a transaction amount for
  //    coverage of a PAN format issuers do not use.
  //  - **newline** separates *fields* in a bank SMS. Joining across one
  //    fuses two unrelated numbers, and Luhn only filters 9 of those 10.
  //  - **runs of two or more separators**, for the same fusing reason. Note
  //    the patterns below therefore allow exactly *one* separator between
  //    groups, never `+`.
  // Three of the five are invisible whitespace variants that no reviewer
  // can tell apart by eye, and a literal `-` inside a character class would
  // start a *range*. So every one is written as a `\uXXXX` escape, in a raw
  // string so the backslash reaches the regex engine intact â€” the same
  // reasoning, and the same defence against a re-encoded source file, as
  // [_digitChars] above.
  static const String _separatorChars =
      r'\u0020' // SPACE
      r'\u00A0' // NO-BREAK SPACE
      r'\u202F' // NARROW NO-BREAK SPACE
      r'\u002D' // HYPHEN-MINUS (escaped: a literal - would open a range)
      r'\u2013'; // EN DASH

  /// True for the five §13.3 separators. Kept as a predicate as well as a
  /// character class so the hand-written IBAN scan and the regex-driven PAN
  /// scan cannot drift apart on what a separator is.
  static bool _isSeparator(int codeUnit) =>
      codeUnit == 0x0020 ||
      codeUnit == 0x00A0 ||
      codeUnit == 0x202F ||
      codeUnit == 0x002D ||
      codeUnit == 0x2013;

  /// §13.2 — characters removed from the **matching view** of the text.
  ///
  /// ## Why this is load-bearing and not tidiness
  ///
  /// Sanitisation runs on the **raw** SMS body, before `SmsTextNormalizer`
  /// (ADR-013 requires redaction at the ingestion boundary, and the
  /// normaliser runs afterwards on the already-safe text). So this file
  /// cannot assume bidi controls have been stripped — it has to strip them
  /// itself.
  ///
  /// An Arabic RTL bank template routinely wraps a Latin-script number in
  /// directional marks. A single `U+200F` sitting between two groups of a
  /// card number splits the digit-group sequence in two, and every rule
  /// below that reasons about "groups joined by a separator" then sees two
  /// short numbers instead of one PAN — and lets the PAN through in full.
  ///
  /// These characters are removed from the *matching view* only. The
  /// returned text keeps its original formatting everywhere outside a
  /// replaced span, because AC-B1.2 asks the user to verify a parse against
  /// something that looks like what their bank actually sent.
  static bool _isIgnorable(int codeUnit) =>
      codeUnit == 0x200E || // LEFT-TO-RIGHT MARK
      codeUnit == 0x200F || // RIGHT-TO-LEFT MARK
      codeUnit == 0x061C || // ARABIC LETTER MARK
      (codeUnit >= 0x202A && codeUnit <= 0x202E) || // LRE/RLE/PDF/LRO/RLO
      (codeUnit >= 0x2066 && codeUnit <= 0x2069) || // LRI/RLI/FSI/PDI
      codeUnit == 0x00AD; // SOFT HYPHEN

  // Any maximal run of digits, used to split a digit-group sequence back
  // into its groups. Length filtering and the Luhn check happen in Dart
  // rather than in the pattern — one clever regex that both found runs and
  // validated Luhn would be unreviewable and, per §13.4, wrong.
  static final RegExp _digitRunPattern = RegExp('[$_digitChars]+');

  /// §13.4's **digit-group sequence**: `g1 sep g2 sep … sep gn`, where each
  /// `gi` is a maximal run of two or more digits and each `sep` is a single
  /// separator. The trailing `*` (not `+`) is what makes `n = 1` — the
  /// ordinary contiguous run — the same case as every other, handled by the
  /// same code.
  ///
  /// Groups are `{2,}` rather than exactly 4 so that non-standard groupings
  /// (Amex 4-6-5, or 4-4-4-4-3 for a 19-digit PAN) are covered.
  ///
  /// This pattern only *locates* candidates. Deciding which slice of a
  /// sequence is a PAN is [_findPanSpans]' job, and that distinction is the
  /// whole of §13.4 — see the comment there.
  static final RegExp _digitGroupSequencePattern = RegExp(
    '[$_digitChars]{2,}(?:[$_separatorChars][$_digitChars]{2,})*',
  );

  /// The `SA` prefix of a Saudi IBAN. Case-insensitive so a lower-case
  /// prefix is caught too. Everything after it is scanned by hand in
  /// [_findIbanSpans], because "22 digits, tolerating single separators
  /// between groups, counted across group boundaries" is not something a
  /// regex expresses without becoming unreadable.
  static final RegExp _saudiIbanPrefixPattern = RegExp(
    'SA',
    caseSensitive: false,
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

    // Every generic pass runs over the §13.2 **matching view** — the text
    // with bidi controls and soft hyphens removed — and writes its results
    // back into the original string by mapped offsets. See
    // [_redactOnMatchingView].

    // 1) IBANs first (§13.5).
    //
    // Ordering is not arbitrary any more. A Saudi IBAN is 22 digits, and a
    // 13-19 digit window *inside* those 22 can be Luhn-valid by coincidence
    // — Luhn passes one in ten strings at random. Running the PAN pass first
    // would then rewrite part of an IBAN as `****nnnn` and leave the rest of
    // the account number sitting in the text. Longest, most specific rule
    // first.
    text = _redactOnMatchingView(text, _findIbanSpans);

    // 2) PAN candidates (§13.4), contiguous and group-separated alike.
    //
    // Luhn is what makes this precise rather than a blunt "redact every long
    // number" rule — the latter would eat transaction reference numbers and
    // defeat duplicate detection (ADR-017 D2), a correctness regression
    // bought for no security gain.
    final List<_Redaction> panSpans = _redactionsOnMatchingView(
      text,
      _findPanSpans,
    );
    if (panSpans.isNotEmpty) {
      panRedacted = true;
      text = _applyRedactions(text, panSpans);
    }

    // 3) CVV / PIN / OTP / password-shaped secrets (§13.6).
    //
    // See [_findSecretSpans] for why this is a proximity sweep over *every*
    // nearby digit run rather than the two single-shot "keyword then digits"
    // / "digits then keyword" regexes it replaced (Linear KHA-54, gaps 1
    // and 2).
    text = _redactOnMatchingView(text, _findSecretSpans);

    // 4) Per-bank patterns from a rule pack (ADR-007), applied **last**
    //    (§13.7).
    //
    // Per §13.7: replace the named `(?<secret>…)` group if the pattern
    // declares one, otherwise the whole match.
    //
    // ## Why honouring a group from an untrusted pack is safe here
    //
    // This deserves stating, because "let untrusted input tell the sanitiser
    // to redact *less*" is normally exactly the wrong shape. It is safe for
    // one specific structural reason: the generic passes above have already
    // run, independently, and a rule pack cannot switch them off. §13.7 says
    // it outright — a per-bank pattern is *never a substitute* for the
    // generic path. So the narrowest thing a hostile pack can achieve is to
    // under-redact **the extra coverage it invented itself**, which is the
    // coverage that would not exist at all if the pack had said nothing. It
    // cannot reach a PAN, an IBAN or a keyword-adjacent code; those are
    // already gone.
    //
    // What the group buys is precision where the bank knows its own
    // template: "in this message the code is the third field" lets the pack
    // redact the code without also destroying the amount next to it, and a
    // destroyed amount is a real transaction pushed into the review queue.
    //
    // Two conservative details, both deliberate:
    //  - a group that is absent, empty, or ambiguous (its text occurs more
    //    than once inside the match, so we cannot tell which occurrence the
    //    engine captured) falls back to redacting the **whole** match;
    //  - the replacement is `[REDACTED]` with no last-4 retained. Unlike a
    //    PAN, no part of a secret has downstream value.
    for (final RegExp pattern in extraRedactPatterns) {
      text = text.replaceAllMapped(pattern, _replaceSecretGroupOrWholeMatch);
    }

    return SanitizedSmsText._(text, panRedacted);
  }

  /// The rule-pack convention for naming the secret inside a `redact[]`
  /// pattern (§13.7): `(?<secret>\d{3,8})`.
  static const String _rulePackSecretGroup = 'secret';

  /// §13.7's replacement: the named group if it is present and unambiguous,
  /// the whole match otherwise.
  static String _replaceSecretGroupOrWholeMatch(Match match) {
    const String redacted = '[REDACTED]';
    final String whole = match.group(0)!;
    if (match is! RegExpMatch ||
        !match.groupNames.contains(_rulePackSecretGroup)) {
      return redacted;
    }

    final String? secret = match.namedGroup(_rulePackSecretGroup);
    if (secret == null || secret.isEmpty) {
      return redacted;
    }

    // Dart exposes a named group's *text* but not its offsets, so locate it
    // inside the match. If the same text appears more than once we cannot
    // know which occurrence was captured — redacting the wrong one would
    // leave the real secret in place, so fall back to the whole match. This
    // is the one branch where guessing would cost a live secret.
    final int index = whole.indexOf(secret);
    if (index < 0 || index != whole.lastIndexOf(secret)) {
      return redacted;
    }
    return whole.replaceRange(index, index + secret.length, redacted);
  }

  /// All the digit characters of [text], with separators and anything else
  /// discarded — so the length window and the Luhn check see the number the
  /// way the issuer wrote it, not the way the bank's template printed it.
  static String _digitsOnly(String text) {
    final StringBuffer digits = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final int unit = text.codeUnitAt(i);
      if (_digitValue(unit) != null) {
        digits.writeCharCode(unit);
      }
    }
    return digits.toString();
  }

  /// §13.4's PAN test, in one place so no two callers can disagree about
  /// what "PAN-shaped" means.
  ///
  /// The 13-19 window is kept and 12-digit Maestro is **out of scope,
  /// explicitly** (§13.4). Lowering the floor to 12 materially increases
  /// collisions with reference numbers and account suffixes, and the wider
  /// context is that by CON-3/NFR-S2 a full PAN in a bank's own SMS is
  /// already anomalous — the messages we expect carry a masked last-4. This
  /// whole rule is a **backstop**, and a backstop should be calibrated for
  /// precision against the numbers that legitimately appear.
  static bool _isPanShaped(String digits) =>
      digits.length >= 13 && digits.length <= 19 && _isLuhnValid(digits);

  // --- §13.2's matching view, and how spans get back to the real text -----

  /// The text with §13.2's ignorable characters removed, plus a map from
  /// each view offset back to its offset in the original string.
  ///
  /// This is the mechanism that lets a bidi mark sit in the middle of a card
  /// number without defeating the rules, while still returning text that
  /// looks like what the bank sent everywhere a redaction did not happen.
  static ({String text, List<int> sourceIndex}) _matchingView(String original) {
    final StringBuffer buffer = StringBuffer();
    final List<int> sourceIndex = <int>[];
    for (int i = 0; i < original.length; i++) {
      final int unit = original.codeUnitAt(i);
      if (_isIgnorable(unit)) {
        continue;
      }
      buffer.writeCharCode(unit);
      sourceIndex.add(i);
    }
    return (text: buffer.toString(), sourceIndex: sourceIndex);
  }

  /// Runs [find] over the matching view of [text] and translates the spans it
  /// returns back into original-string offsets.
  static List<_Redaction> _redactionsOnMatchingView(
    String text,
    List<_Redaction> Function(String view) find,
  ) {
    final ({String text, List<int> sourceIndex}) view = _matchingView(text);
    final List<_Redaction> found = find(view.text);
    return <_Redaction>[
      for (final _Redaction span in found)
        (
          start: view.sourceIndex[span.start],
          // The end maps from the *last* character in the span rather than
          // from the exclusive end, so ignorable characters sitting just
          // after the span survive in the output instead of being swallowed
          // by it.
          end: view.sourceIndex[span.end - 1] + 1,
          replacement: span.replacement,
        ),
    ];
  }

  static String _redactOnMatchingView(
    String text,
    List<_Redaction> Function(String view) find,
  ) => _applyRedactions(text, _redactionsOnMatchingView(text, find));

  /// Rebuilds [text] with every span in [redactions] replaced.
  ///
  /// [redactions] must be sorted by `start`. Iterating forwards with a
  /// cursor keeps every offset valid — mutating in place while indices shift
  /// underneath is the classic way this kind of code starts leaving stray
  /// digits behind.
  static String _applyRedactions(String text, List<_Redaction> redactions) {
    if (redactions.isEmpty) {
      return text;
    }
    final StringBuffer out = StringBuffer();
    int cursor = 0;
    for (final _Redaction span in redactions) {
      if (span.start < cursor) {
        continue; // overlaps an earlier redaction; that one already won
      }
      out.write(text.substring(cursor, span.start));
      out.write(span.replacement);
      cursor = span.end;
    }
    out.write(text.substring(cursor));
    return out.toString();
  }

  // --- §13.4 — PAN detection ---------------------------------------------

  /// Finds every PAN in the matching view, using §13.4's **longest window
  /// first, then backtrack** scan.
  ///
  /// ## Why the naive version is a full-cleartext-PAN bug
  ///
  /// The obvious implementation — and the one that shipped in the first cut
  /// of this file — tests only the *maximal* separator-joined sequence:
  /// concatenate all of it, check 13-19 and Luhn, give up if it fails. That
  /// leaves a real PAN in cleartext whenever a bank template puts another
  /// grouped number immediately after the card number:
  ///
  /// ```text
  /// purchase 4111 1111 1111 1111 45
  ///   → one 18-digit sequence → fails Luhn → returned untouched,
  ///     PAN and all, with panRedacted = false
  /// ```
  ///
  /// That is byte-for-byte the KHA-54 gap-3 failure mode, and the KHA-54
  /// corpus missed it only because every fixture happened to put a non-digit
  /// token (`SAR`) immediately after the PAN. One trailing number is all it
  /// took.
  ///
  /// So instead: enumerate the contiguous windows `gi..gj` of each sequence,
  /// **longest first, then leftmost**. Take the first window that is 13-19
  /// digits and Luhn-valid, redact the whole span *including its internal
  /// separators*, and resume after it. Longest-first matters — a 16-digit
  /// PAN must be found as a PAN, not as some shorter Luhn-valid slice of
  /// itself.
  static List<_Redaction> _findPanSpans(String view) {
    final List<_Redaction> spans = <_Redaction>[];

    for (final Match sequence in _digitGroupSequencePattern.allMatches(view)) {
      final String text = sequence.group(0)!;
      final List<Match> groups = _digitRunPattern.allMatches(text).toList();

      // Cumulative digit counts, so "how many digits are in window gi..gj?"
      // is one subtraction instead of a substring plus a scan.
      //
      // This is not premature optimisation — it is a bound on adversarial
      // input. The window enumeration is O(groups²), and a 1600-character
      // SMS of nothing but two-digit groups produces ~530 groups, so ~140k
      // windows. Building and scanning a string for each took **675 ms for
      // one message** when measured; a batch of a hundred would blow through
      // ADR-006's ~10-second background budget on its own. With the prefix
      // sums, all but the handful of windows that are actually 13-19 digits
      // long are rejected by integer arithmetic, and the same message
      // sanitises in single-digit milliseconds.
      final List<int> digitsBefore = List<int>.filled(groups.length + 1, 0);
      for (int g = 0; g < groups.length; g++) {
        digitsBefore[g + 1] =
            digitsBefore[g] + (groups[g].end - groups[g].start);
      }

      int from = 0; // first group still available to match
      while (from < groups.length) {
        _Redaction? hit;
        int nextFrom = from;

        // Longest window first, then leftmost — §13.4 step 1.
        for (
          int length = groups.length - from;
          length >= 1 && hit == null;
          length--
        ) {
          for (int i = from; i + length <= groups.length; i++) {
            final int j = i + length - 1;

            // The cheap test first. Note this counts *characters* in the
            // digit runs, which equals the digit count exactly because
            // `_digitRunPattern` matches nothing else.
            final int digitCount = digitsBefore[j + 1] - digitsBefore[i];
            if (digitCount < 13 || digitCount > 19) {
              continue;
            }

            final String candidate = text.substring(
              groups[i].start,
              groups[j].end,
            );
            final String digits = _digitsOnly(candidate);
            if (!_isPanShaped(digits)) {
              continue;
            }
            hit = (
              start: sequence.start + groups[i].start,
              end: sequence.start + groups[j].end,
              replacement: '****${digits.substring(digits.length - 4)}',
            );
            nextFrom = j + 1; // §13.4 step 3: resume after the window
            break;
          }
        }

        if (hit == null) {
          break;
        }
        spans.add(hit);
        from = nextFrom;
      }
    }

    return spans;
  }

  // --- §13.5 — Saudi IBAN detection --------------------------------------

  /// Finds `SA` + 22 digits, **tolerating a single separator between
  /// groups**, and replaces it with `SA**…<last4>`.
  ///
  /// The conventional print form of a Saudi IBAN is
  /// `SA03 8000 0000 6080 1016 7519`. The contiguous-only `SA[digits]{22}`
  /// pattern this replaces did not match that at all, so the grouped form —
  /// which is the form a human actually types and a bank actually prints —
  /// survived in full. Same defect class as the grouped PAN above.
  ///
  /// Written as a hand scan rather than a regex because the rule counts
  /// digits *across* group boundaries (22 in total, however they are
  /// grouped), and a regex that expresses that is unreadable enough to be a
  /// liability in a file like this one.
  static List<_Redaction> _findIbanSpans(String view) {
    const int ibanDigits = 22; // 2 check digits + 20 BBAN digits
    final List<_Redaction> spans = <_Redaction>[];

    for (final Match prefix in _saudiIbanPrefixPattern.allMatches(view)) {
      final StringBuffer digits = StringBuffer();
      int count = 0;
      int cursor = prefix.end;
      int end = -1;

      while (cursor < view.length && count < ibanDigits) {
        final int unit = view.codeUnitAt(cursor);

        if (_digitValue(unit) != null) {
          digits.writeCharCode(unit);
          count++;
          cursor++;
          if (count == ibanDigits) {
            end = cursor;
          }
          continue;
        }

        // A single separator is allowed, but only *between* digits — a
        // trailing one is just the space after the number. This is also what
        // stops "SAR 45.00" being read as an IBAN prefix: the character
        // after `SA` is `R`, which is neither.
        if (_isSeparator(unit) &&
            cursor + 1 < view.length &&
            _digitValue(view.codeUnitAt(cursor + 1)) != null) {
          cursor++;
          continue;
        }

        break;
      }

      if (count == ibanDigits) {
        final String all = digits.toString();
        spans.add((
          start: prefix.start,
          end: end,
          // "SA**…<last4>" per ADR-013 §13.5 and §4.2's `Instrument`.
          replacement: 'SA**…${all.substring(all.length - 4)}',
        ));
      }
    }

    return spans;
  }

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
  /// There is deliberately **no upper bound** on the run length (§13.6
  /// withdrew v1.0's "3-8 digits"). A 9-digit code is still a secret; an
  /// upper bound is an under-redaction bug wearing a specificity costume.
  static List<_Redaction> _findSecretSpans(String view) {
    final List<Match> keywords = _secretKeywordPattern
        .allMatches(view)
        .toList();
    if (keywords.isEmpty) {
      return const <_Redaction>[];
    }

    // Collect the [start, end) span of every digit run to destroy. The
    // counts here are tiny (an SMS is <= 1600 chars), so the nested scan
    // costs nothing worth optimising away.
    final List<_Redaction> spans = <_Redaction>[];

    for (final Match digitRun in _secretDigitRunPattern.allMatches(view)) {
      final bool nearAnyKeyword = keywords.any(
        (Match keyword) => _isWithinProximity(
          view,
          keywordStart: keyword.start,
          keywordEnd: keyword.end,
          runStart: digitRun.start,
          runEnd: digitRun.end,
        ),
      );
      if (nearAnyKeyword) {
        // The whole run, and no last-4 retained: unlike a PAN, no part of a
        // secret has any downstream value (§13.6).
        spans.add((
          start: digitRun.start,
          end: digitRun.end,
          replacement: '[REDACTED]',
        ));
      }
    }

    return spans;
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
