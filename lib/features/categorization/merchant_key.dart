/// **ADR-008's merchant-key pipeline** — `merchantRaw` → `merchantKey`.
///
/// ```
/// Unicode NFKC → strip bidi controls and tatweel → remove Arabic diacritics
///   → fold Arabic letter variants → case-fold Latin to upper
///   → strip ONE trailing digit run, only when corroborated as a reference
///   → strip the structural noise-token list
///   → collapse whitespace  (no tokens left ⇒ NO KEY, not a fallback)
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
/// ## **The corroboration rule** — read this before adding anything below
///
/// ADR-008 v1.3 (the KHA-98 decision, 2026-07-29) replaced the v1.0 *list* with
/// a *rule*, because a list cannot be reviewed — you cannot tell whether the
/// next entry someone adds is safe. Quoted verbatim, because it is the thing
/// that must outlive every specific line in this file:
///
/// > **A token may be removed from a merchant string only if it is incapable,
/// > by its kind, of distinguishing one business from another.**
/// >
/// > 1. **Type-level, not instance-level.** Whether a token is strippable must
/// >    be decidable from the token alone. [MerchantKey.of] stays a **pure,
/// >    deterministic, database-free** function.
/// > 2. **Structural, not proper.** A strippable token names *what kind of
/// >    thing* a merchant is — an outlet, legal-form or terminal word
/// >    (`BRANCH`, `STORE`, `FRC`, `LLC`, `فرع`). A **proper noun** — a city, a
/// >    district, a mall, a person — names *which* one, and is never
/// >    strippable.
/// > 3. **Residue-safe.** Stripping must never be able to reduce two strings
/// >    that differ only in a proper noun, or only in a number that is part of
/// >    a name, to the same key.
///
/// This replaces the sentence that used to sit on [noiseTokens] — *"a chain's
/// branches are the chain"* — which read as intentional to three consecutive
/// reviewers and was the direct cause of a **High-severity identity merge at
/// confidence 1.00** (KHA-98): `MAKKAH BAKERY` and `MADINAH BAKERY` both keyed
/// as `BAKERY`, `merchant.merchant_key` is `UNIQUE`, so two unrelated bakeries
/// became one row and categorising one auto-applied to the other at tier T1.
/// No confidence threshold could have caught it: the collision is manufactured
/// by normalisation, **upstream of every tier**.
///
/// The cost of the fix is real and is the *right* cost: two branches of one
/// chain (`PANDA RIYADH` / `PANDA JEDDAH`) now key differently and are flagged
/// rather than merged. Two rows that should be one is recoverable in a single
/// user action (a `MerchantAlias` link); one row that should be two destroys
/// the identity. AC-D2.3 already chose between them — *"never silently merge
/// unrelated merchants"*.
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
/// Every string in the noise list below is a generic English/Arabic outlet,
/// legal-form or terminal word. **No merchant string from any real user's SMS
/// appears in this repository**, here or in the test corpus.
library;

import '../../core/config/categorization_config.dart';
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
  /// **Structural** tokens — words that name *what kind of thing* a merchant
  /// is, never *which one*. Condition 2 of the corroboration rule.
  ///
  /// **Stored already folded** (upper-case Latin, folded Arabic
  /// orthography), because they are compared against tokens that have already
  /// been through [CanonicalText.fold]. `merchant_key_test.dart` asserts
  /// `fold(token) == token` for every entry, so an entry added in the wrong
  /// form fails a test instead of silently never matching.
  ///
  /// **No proper noun may ever be added here.** A city, a district, a mall or a
  /// person names *which* business, so removing it can reduce two unrelated
  /// shops to one key — which is exactly the KHA-98 defect. That is not left to
  /// a reviewer noticing: `merchant_key_test.dart` pins this set against an
  /// explicit allow-list of structural words, so a "helpful" addition fails CI
  /// rather than silently merging two shops.
  ///
  /// **The twelve city entries ADR-008 v1.0 listed are gone** (`RIYADH`,
  /// `JEDDAH`, `DAMMAM`, `KHOBAR`, `MAKKAH`, `MADINAH` and their folded Arabic
  /// forms). See this library's corroboration-rule note for why, and for what
  /// that costs.
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
  };

  /// The subset of [noiseTokens] whose presence immediately *before* a trailing
  /// digit run corroborates that run as a store/terminal/reference number
  /// (KHA-99, corroboration signal (i)).
  ///
  /// `PANDA STORE 1234` is PRD §3.4's actual observed shape: the word `STORE`
  /// is what tells us `1234` is an outlet number rather than part of a name.
  /// A legal-form word (`LLC`, `شركه`) is deliberately **not** here — "Qandaco
  /// LLC 5" is not a recognised reference shape, and guessing would be exactly
  /// the unbounded strip this rule replaces.
  static const Set<String> referenceMarkerTokens = <String>{
    'BRANCH',
    'STORE',
    'STORES',
    'BR',
    'FRC',
    'TERMINAL',
    'TERM',
    'POS',
    'فرع',
    'محل',
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

  /// Returns the canonical key for [raw], or null when [raw] has no merchant
  /// identity in it.
  ///
  /// Null in, null out: a transaction with no merchant text (a transfer, an
  /// ATM withdrawal) has no merchant *key*, and inventing an empty-string key
  /// would make every such transaction "the same merchant" — one rule would
  /// then categorise every ATM withdrawal in the ledger. That is the single
  /// most damaging silent merge available in this design, so the type refuses
  /// to represent it.
  ///
  /// ## KHA-102 — "no tokens survived" is also "no merchant"
  ///
  /// This guard used to be defeated by its own implementation. [of] fell back
  /// to the *folded string* when every token was stripped, and a string made
  /// only of separators (`'***'`, `'-*-'` — acquirers routinely send a
  /// placeholder where the merchant name was masked) tokenises to nothing while
  /// folding to itself. So the fallback key was non-empty, the `isEmpty` test
  /// missed it, and one rule categorised every masked-merchant message from
  /// every bank.
  ///
  /// The fallback is **gone** (ADR-008 v1.3, settled answer 3), and removal
  /// rather than patching is the point: *an all-noise string is by construction
  /// made only of tokens we have just declared incapable of distinguishing two
  /// businesses, so a key built from it is by construction incapable of
  /// distinguishing two businesses.* Requiring "at least one letter or digit"
  /// would have closed `'***'` and left `'STORE'` and `'محل'` open.
  ///
  /// **Nothing is lost or hidden.** The transaction is still written, still
  /// carries its `merchantRawText`, still appears in every total and still
  /// audits — it lands in `CategorizationResult.skippedNoMerchant`, exactly
  /// like a transaction that carried no merchant text at all. We decline to
  /// *identify*; we never discard.
  static String? ofOrNull(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final String key = of(raw);
    return key.isEmpty ? null : key;
  }

  /// Returns the canonical key for [raw], or the **empty string** when nothing
  /// in [raw] can distinguish one business from another.
  ///
  /// Idempotent — `of(of(x)) == of(x)` — which matters because a key is
  /// computed when a merchant is created and recomputed on every later
  /// message. A pipeline that changed its own output on a second pass would
  /// stop matching the very rows it wrote.
  ///
  /// Most callers want [ofOrNull], which turns the empty string into `null`.
  static String of(String raw) {
    final String folded = CanonicalText.fold(raw);

    final List<String> tokens = <String>[
      for (final String token in folded.split(_separators))
        if (token.isNotEmpty) token,
    ];

    // Step 6 — ONE trailing reference digit run, and only when corroborated.
    _stripCorroboratedTrailingDigitRun(tokens);

    // Step 7 — the structural noise list.
    tokens.removeWhere(noiseTokens.contains);

    // Step 8 — collapse. (`fold` already collapsed whitespace runs; joining
    // tokens with a single space is what makes `PANDA-1234` and `PANDA 1234`
    // produce the same key.)
    //
    // KHA-102: no tokens survived ⇒ **no key**. There is deliberately no
    // fallback to `folded` here; see [ofOrNull] for the full argument.
    return tokens.join(' ');
  }

  /// **KHA-99 — the bounded, corroborated trailing-digit strip.**
  ///
  /// ADR-008 v1.0 shipped this as a `while` loop with no bound, so `QAMART 100`
  /// and `QAMART 200` both keyed as `QAMART` and two numbered outlets — often
  /// separately owned franchises — became one identity at confidence 1.00. That
  /// is the KHA-98 defect in a second guise. But unlike a city name, a digit run
  /// *does* have a recognisable reference shape, so the answer is not "drop it";
  /// it is "corroborate it".
  ///
  /// Mutates [tokens] in place, removing **at most one** trailing token. All
  /// four rules are required (ADR-008 v1.3, settled answer 2):
  ///
  ///  1. **At most one** trailing all-digit token is removed. Two digit runs in
  ///     a row are not a reference; they are part of a name or a garbled string,
  ///     and collapsing them is a guess. (`QAMART 100 200 300` keeps all three.)
  ///  2. Removed **only if a non-digit token remains** afterwards — otherwise
  ///     the "merchant" is a bare number and stripping it leaves nothing.
  ///  3. Removed **only if corroborated** as a reference, by either signal:
  ///     **(i) adjacency** — the preceding token is a [referenceMarkerTokens]
  ///     word this pipeline is also stripping (`PANDA STORE 1234`); or
  ///     **(ii) length** — the run is at least
  ///     [CategorizationConfig.referenceDigitRunMinLength] digits, which is a
  ///     till/terminal/reference id, not a branch number a human says out loud.
  ///  4. **Leading digits keep their existing protection.** `7 ELEVEN` must
  ///     survive; only the *last* token is ever a candidate. That asymmetry was
  ///     always deliberate and it stands unchanged.
  static void _stripCorroboratedTrailingDigitRun(List<String> tokens) {
    if (tokens.length < 2) {
      // Rule 2, in its cheapest form: a single token is either the whole
      // identity or a bare number, and neither is strippable.
      return;
    }
    final String last = tokens.last;
    if (!_digitsOnly.hasMatch(last)) {
      return;
    }

    final String previous = tokens[tokens.length - 2];

    // Rule 1 — two digit runs in a row are not a reference.
    if (_digitsOnly.hasMatch(previous)) {
      return;
    }

    // Rule 2 — at least one non-digit token must survive. `previous` is already
    // known to be a non-digit, so this holds; asserted through the whole list
    // anyway so the rule is enforced by the code rather than by that inference
    // staying true if the checks above are ever reordered.
    final bool nonDigitSurvives = tokens
        .take(tokens.length - 1)
        .any((String token) => !_digitsOnly.hasMatch(token));
    if (!nonDigitSurvives) {
      return;
    }

    // Rule 3 — corroboration, either signal.
    final bool corroborated =
        referenceMarkerTokens.contains(previous) ||
        last.length >= CategorizationConfig.referenceDigitRunMinLength;
    if (!corroborated) {
      return;
    }

    tokens.removeLast();
  }

  /// The tokens of a key as a **multiset** — how many times each token occurs.
  ///
  /// T3 compares multisets, not sets (KHA-100). No step in this pipeline
  /// produces or removes a *repeated* token, so a duplicated token is a genuine
  /// difference between two strings, and collapsing it would be the machine
  /// asserting identity on a guess. Over sets, `QAFE QAFE` reached Jaccard 1.0
  /// against `QAFE` and auto-applied another brand's rule at exactly the
  /// threshold; over multisets it is 1/2 = 0.5, which falls to T4 and can never
  /// auto-apply.
  static Map<String, int> tokenMultisetOf(String key) {
    final Map<String, int> counts = <String, int>{};
    for (final String token in key.split(_separators)) {
      if (token.isEmpty) {
        continue;
      }
      counts[token] = (counts[token] ?? 0) + 1;
    }
    return counts;
  }

  /// The distinct tokens of a key.
  ///
  /// Kept for callers that genuinely want set semantics (a display chip list, a
  /// containment check). **The matcher does not use this** — see
  /// [tokenMultisetOf] and KHA-100 for why.
  static Set<String> tokensOf(String key) => tokenMultisetOf(key).keys.toSet();

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
