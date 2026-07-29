/// **ADR-008's merchant-key pipeline** — `merchantRaw` → `merchantKey`.
///
/// ```
/// Unicode NFKC → strip bidi controls and tatweel → remove Arabic diacritics
///   → fold Arabic letter variants → case-fold Latin to upper
///   → strip trailing store/terminal/reference digit runs
///   → strip a configurable noise-token list
///   → collapse whitespace
/// ```
///
/// The first five steps are `CanonicalText.fold` (shared with category names —
/// see that file for the honest statement about NFKC in Dart). The last three
/// are here, because they are specific to *merchants*: a number at the end of
/// a merchant string is a till, a branch or a reference, whereas a number at
/// the end of a category name is part of the name.
///
/// ## What this pipeline is for, in one sentence
///
/// PRD §3.4 shows the same shop arriving as `PANDA STORE 1234`, `Panda` and —
/// inside an otherwise Arabic message — a Latin transliteration. KHA-31's
/// promise is *"correct it once per merchant and it stays right"*, and that is
/// only true if all three produce the same key.
///
/// ## Where this pipeline deliberately stops
///
/// It does **not** try to transliterate between scripts. ADR-008 is explicit:
/// *"Arabic and Latin renderings of the same merchant cannot be reliably
/// transliterated. **We do not try.**"* Cross-script linking is a `MerchantAlias`
/// the user creates in one action. A transliterator would be a machine deciding
/// that two strings are the same shop, which is exactly the silent merge
/// AC-D2.3 forbids.
///
/// ## NFR-M3
///
/// Every string in the noise list below is a generic English/Arabic word or a
/// major-city name. **No merchant string from any real user's SMS appears in
/// this repository**, here or in the test corpus.
library;

import '../../core/text/canonical_text.dart';

/// Which script a merchant string is written in — `merchant_alias.script`.
enum MerchantScript {
  arabic('arabic'),
  latin('latin'),
  mixed('mixed');

  const MerchantScript(this.key);
  final String key;
}

/// Produces and inspects ADR-008 merchant keys.
abstract final class MerchantKey {
  /// Tokens that carry no identity and appear beside real merchant names.
  ///
  /// **Stored already folded** (upper-case Latin, folded Arabic
  /// orthography), because they are compared against tokens that have already
  /// been through [CanonicalText.fold]. `merchant_key_test.dart` asserts
  /// `fold(token) == token` for every entry, so an entry added in the wrong
  /// form fails a test instead of silently never matching.
  ///
  /// The city names are the deliberate part: ADR-008 lists them, and their
  /// effect is that `PANDA RIYADH` and `PANDA JEDDAH` are one merchant. That
  /// is the intent — a chain's branches are the chain — and it is the reason
  /// the list is short and consists only of names that cannot plausibly *be*
  /// a merchant on their own.
  static const Set<String> noiseTokens = <String>{
    // Branch / outlet vocabulary.
    'BRANCH',
    'STORE',
    'STORES',
    'BR',
    'FRC', // franchise marker seen in acquirer strings
    'TERMINAL',
    'TERM',
    'POS',
    'CO',
    'LLC',
    'LTD',
    // Arabic equivalents, in folded form (see the note above: ة → ه).
    'فرع',
    'محل',
    'شركه',
    // "مؤسسة" folded: ة → ه *and* ؤ → و. Written in the folded form, not the
    // dictionary form — the test below is what caught this one.
    'موسسه',
    // Major Saudi cities, folded.
    'RIYADH',
    'JEDDAH',
    'DAMMAM',
    'KHOBAR',
    'MAKKAH',
    'MADINAH',
    'الرياض',
    'جده',
    'الدمام',
    'الخبر',
    'مكه',
    'المدينه',
  };

  /// Splits on whitespace **and** on the punctuation acquirers use as
  /// separators, so `PANDA-1234` and `PANDA 1234` tokenise identically.
  static final RegExp _separators = RegExp(r'''[\s\-_/\\*#,.:;|()\[\]"'@+]+''');

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  /// U+0600–U+06FF, the Arabic block. The range is written as literal
  /// characters here (unlike `sms_sanitizer.dart`'s `\uXXXX` style) because
  /// it is a single contiguous block whose endpoints are documented on this
  /// line — there is no per-character list for a reviewer to check by eye.
  static final RegExp _arabicLetter = RegExp(r'[؀-ۿ]');
  static final RegExp _latinLetter = RegExp(r'[A-Za-z]');

  /// Returns the canonical key for [raw], or null when [raw] is null/blank.
  ///
  /// Null in, null out: a transaction with no merchant text (a transfer, an
  /// ATM withdrawal) has no merchant *key*, and inventing an empty-string key
  /// would make every such transaction "the same merchant" — one rule would
  /// then categorise every ATM withdrawal in the ledger. That is the single
  /// most damaging silent merge available in this design, so the type refuses
  /// to represent it.
  static String? ofOrNull(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final String key = of(raw);
    return key.isEmpty ? null : key;
  }

  /// Returns the canonical key for [raw].
  ///
  /// Idempotent — `of(of(x)) == of(x)` — which matters because a key is
  /// computed when a merchant is created and recomputed on every later
  /// message. A pipeline that changed its own output on a second pass would
  /// stop matching the very rows it wrote.
  static String of(String raw) {
    final String folded = CanonicalText.fold(raw);

    final List<String> tokens = <String>[
      for (final String token in folded.split(_separators))
        if (token.isNotEmpty) token,
    ];

    // Step 6 — trailing store/terminal/reference digit runs. Only *trailing*,
    // per ADR-008, and the restraint is deliberate: stripping digit tokens
    // anywhere would turn `7 ELEVEN` into `ELEVEN`, inventing a different
    // merchant out of a real name.
    while (tokens.isNotEmpty && _digitsOnly.hasMatch(tokens.last)) {
      tokens.removeLast();
    }

    // Step 7 — the noise list.
    tokens.removeWhere(noiseTokens.contains);

    // Step 8 — collapse. (`fold` already collapsed whitespace runs; joining
    // tokens with a single space is what makes `PANDA-1234` and `PANDA 1234`
    // produce the same key.)
    if (tokens.isEmpty) {
      // Everything was noise or digits — e.g. a merchant genuinely called
      // "Riyadh Store". Falling back to the folded string keeps a usable
      // identity instead of collapsing every such merchant into one empty key
      // (the silent merge described on [ofOrNull]).
      return folded;
    }
    return tokens.join(' ');
  }

  /// The tokens of a key, for the token-set tier (T3).
  static Set<String> tokensOf(String key) => <String>{
    for (final String token in key.split(_separators))
      if (token.isNotEmpty) token,
  };

  /// Which script [value] is written in — recorded on an alias so a review
  /// screen can explain why two spellings were linked.
  static MerchantScript scriptOf(String value) {
    final bool hasArabic = _arabicLetter.hasMatch(value);
    final bool hasLatin = _latinLetter.hasMatch(value);
    if (hasArabic && hasLatin) {
      return MerchantScript.mixed;
    }
    return hasArabic ? MerchantScript.arabic : MerchantScript.latin;
  }
}
