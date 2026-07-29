/// **ADR-008's merchant-key pipeline** — `merchantRaw` → `merchantKey`.
///
/// ```
/// Unicode NFKC → strip bidi controls and tatweel → remove Arabic diacritics
///   → fold Arabic letter variants → case-fold Latin to upper
///   → strip ONE digit run — the last one that is trailing *modulo structural
///     noise* — and only when a structural marker sits immediately on either
///     side of it (ADR-008 v1.4)
///   → strip the structural noise-token list
///   → collapse whitespace  (no tokens left ⇒ NO KEY, not a fallback)
/// ```
///
/// **Step 6 must run before step 7 and that ordering is load-bearing**, not an
/// accident: the digit strip *consumes the noise tokens as its evidence*. Strip
/// the noise first and `PANDA STORE 1234` loses the only thing that says `1234`
/// is an outlet number, so it would key as `PANDA 1234` and PRD §3.4's
/// motivating case would break. ADR-008 v1.4 rejects the swap explicitly.
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
/// ## **Corroboration is evidence in the string; never a prior about digits**
///
/// ADR-008 **v1.4** (the KHA-106/KHA-107 decision, 2026-07-29) had to amend
/// v1.3's own digit rule, because v1.3 stated the rule above and then violated
/// it three paragraphs later. Its corroboration signal (ii) — *"strip a
/// trailing run of ≥4 digits, no other corroboration required"* — merged
/// `QAMART 1000` and `QAMART 2000` into one `merchant` row at tier T1,
/// confidence 1.00 (KHA-106). **That signal is withdrawn, and the general
/// argument for why matters more than the specific fix:**
///
/// > A length-only signal decides strippability **from the digit run alone**,
/// > and the residue it leaves is **the prefix**. So for *any* threshold N, two
/// > strings that share a prefix and carry different qualifying runs reduce to
/// > the same key. Sibling collapse is not a bad choice of N — it is what a
/// > length signal **is**. Raising N only changes *which* siblings collide.
///
/// `CategorizationConfig.referenceDigitRunMinLength` was therefore **deleted,
/// not retuned**: O-1's posture ("the value is tuning, the bar is not") cannot
/// protect a constant whose mere *existence* is the bar. **Adjacency to a
/// structural marker is now the only corroborator**, because a marker word
/// beside the run is *the string itself stating that the run is not part of the
/// name* — decidable from the token pair alone, so condition 1 (purity) holds.
/// A bare digit run makes no such statement, and a machine that strips it is
/// guessing which of the two kinds of number it is looking at.
///
/// The cost, disclosed rather than discovered: **`PANDA 1234` no longer equals
/// `PANDA`.** It is flagged for the user, not merged — the same direction as
/// the city-name cost below, for the same reason.
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

// `CategorizationConfig` is deliberately NOT imported here any more. Until
// ADR-008 v1.4 this file read `referenceDigitRunMinLength` from it; that
// constant is deleted, and with it the last way a config edit could change what
// this pipeline considers one business (KHA-106). Merchant identity is now
// decided entirely by the rules written in this file.
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

  /// The subset of [noiseTokens] whose presence immediately **before or after**
  /// a digit run corroborates that run as a store/terminal/reference number.
  ///
  /// Since ADR-008 v1.4 (KHA-106) this is the **only** corroboration signal
  /// there is — see the library note. Since v1.4 (KHA-107) it is read on
  /// **either side** of the run rather than only before it, so
  /// `PANDA STORE 1234` and `PANDA 1234 STORE` are one shop with one key. The
  /// marker's *position* is an accident of how one acquirer orders its tokens
  /// and carries no information about the number; order-insensitivity is simply
  /// what PRD §3.4's *"all renderings of one shop → one key"* means when two
  /// renderings are permutations of each other.
  ///
  /// `PANDA STORE 1234` is PRD §3.4's actual observed shape: the word `STORE`
  /// is what tells us `1234` is an outlet number rather than part of a name.
  /// A legal-form word (`LLC`, `شركه`) is deliberately **not** here — "Qandaco
  /// LLC 5" is not a recognised reference shape, and guessing would be exactly
  /// the unbounded strip this rule replaces.
  ///
  /// **This set must stay a subset of [noiseTokens]**, and that is not a
  /// stylistic preference: it is what makes [of] idempotent (see [of]'s own
  /// doc comment) *and* what makes the allow-list test over `noiseTokens` cover
  /// this set too. A corroborator that was not itself noise could be a proper
  /// noun, and it would survive step 7 into the output.
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
  /// **Idempotent — `of(of(x)) == of(x)`** — which matters because a key is
  /// computed when a merchant is created and recomputed on every later
  /// message. A pipeline that changed its own output on a second pass would
  /// stop matching the very rows it wrote.
  ///
  /// ## Why that claim is TRUE, and how a future edit could quietly break it
  ///
  /// Until ADR-008 v1.4 this sentence was a claim the code did not honour:
  /// `PANDA 1234 STORE` keyed as `PANDA 1234` on the first pass and `PANDA` on
  /// the second, because step 7 removed `STORE` and thereby *made* the digit
  /// run trailing (KHA-107). v1.4 does not weaken the claim — it earns it, and
  /// the proof is one line, so it belongs here rather than in a document:
  ///
  /// > Step 7 removes every [noiseTokens] word, and
  /// > `referenceMarkerTokens ⊆ noiseTokens`. With the length signal withdrawn
  /// > (KHA-106), **marker adjacency is the only corroborator**. Therefore no
  /// > output of [of] can ever *contain* a corroborator, so step 6 is a no-op on
  /// > a second pass — and so is step 7. Hence `of(of(x)) == of(x)`.
  ///
  /// ⚠️ **The invariant rests entirely on "every corroborator is itself a noise
  /// token".** Any future corroboration signal that is *not* also stripped by
  /// step 7 breaks idempotence silently — a length threshold, a "digits
  /// following a letter" heuristic, a regex over the raw string, a corroborator
  /// word deliberately kept out of [noiseTokens]. None of those would fail a
  /// type check or a review-by-eye. If you are adding a signal, add it to
  /// [noiseTokens] too, or do not add it.
  /// `merchant_key_test.dart` pins the invariant table-driven over the whole
  /// synthetic corpus so a breakage fails CI rather than passing quietly.
  ///
  /// Most callers want [ofOrNull], which turns the empty string into `null`.
  static String of(String raw) {
    final String folded = CanonicalText.fold(raw);

    final List<String> tokens = <String>[
      for (final String token in folded.split(_separators))
        if (token.isNotEmpty) token,
    ];

    // Step 6 — ONE reference digit run, and only when corroborated. Must run
    // BEFORE step 7: it reads the noise tokens as its evidence.
    _stripCorroboratedReferenceDigitRun(tokens);

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

  /// **The bounded, corroborated reference-digit strip** — KHA-99, amended by
  /// KHA-106 and KHA-107 (ADR-008 v1.4, settled answers 7 and 8).
  ///
  /// ADR-008 v1.0 shipped this as a `while` loop with no bound, so `QAMART 100`
  /// and `QAMART 200` both keyed as `QAMART` and two numbered outlets — often
  /// separately owned franchises — became one identity at confidence 1.00. That
  /// is the KHA-98 defect in a second guise. But unlike a city name, a digit run
  /// *does* have a recognisable reference shape, so the answer is not "drop it";
  /// it is "corroborate it".
  ///
  /// **Renamed from `_stripCorroboratedTrailingDigitRun` at v1.4**, because
  /// "trailing" stopped being true: the candidate is now the last digit run
  /// that is trailing *modulo structural noise*, so in `PANDA 1234 STORE` the
  /// run at index 1 is a candidate even though it is not last. ADR-008 v1.4
  /// leaves the rename to the implementer's judgement; a name that describes
  /// the old rule is worse than no name.
  ///
  /// Mutates [tokens] in place, removing **at most one** token. Five rules,
  /// all required, and only rule 3 changed at v1.4:
  ///
  ///  1. **Candidate selection (v1.4).** The candidate is the **last all-digit
  ///     token such that every token after it is a [noiseTokens] word** — the
  ///     run is trailing once structural noise is disregarded. If there is no
  ///     such token, nothing is stripped.
  ///  2. **At most one** token is removed, ever — the candidate. Two digit runs
  ///     in a row are not a reference; they are part of a name or a garbled
  ///     string, and collapsing them is a guess. Enforced by refusing when the
  ///     token immediately *before* the candidate is itself all-digit.
  ///     (`QAMART 100 200 300` keeps all three.)
  ///  3. Removed **only if a non-digit token remains** afterwards — otherwise
  ///     the "merchant" is a bare number and stripping it leaves nothing.
  ///     Note this deliberately counts a *noise* token as a survivor, so
  ///     `STORE 7` strips to `STORE` and then yields **no key** via KHA-102,
  ///     rather than the junk key `7`.
  ///  4. **Corroboration (v1.4): adjacency on EITHER side, and nothing else.**
  ///     The token immediately before **or** immediately after the candidate,
  ///     in the pre-strip token list, must be a [referenceMarkerTokens] word.
  ///     v1.3's length signal is **withdrawn** — see the library note for the
  ///     general argument that no threshold can be made residue-safe.
  ///  5. **Leading digits keep their existing protection.** `7 ELEVEN` and
  ///     `7 ELEVEN STORE` both survive intact, and they do so *by rule 1*
  ///     rather than by a special case: `ELEVEN` is not a noise token, so `7`
  ///     is never a candidate in the first place.
  static void _stripCorroboratedReferenceDigitRun(List<String> tokens) {
    if (tokens.length < 2) {
      // Rule 3, in its cheapest form: a single token is either the whole
      // identity or a bare number, and neither is strippable.
      return;
    }

    final int candidate = _referenceDigitRunIndex(tokens);
    if (candidate < 0) {
      return;
    }

    // Rule 2 — two digit runs in a row are not a reference.
    if (candidate > 0 && _digitsOnly.hasMatch(tokens[candidate - 1])) {
      return;
    }

    // Rule 3 — at least one non-digit token must survive. Checked over the
    // whole list minus the candidate rather than inferred from the neighbour,
    // so the rule is enforced by the code and survives a future reordering of
    // the checks above.
    bool nonDigitSurvives = false;
    for (int i = 0; i < tokens.length; i++) {
      if (i != candidate && !_digitsOnly.hasMatch(tokens[i])) {
        nonDigitSurvives = true;
        break;
      }
    }
    if (!nonDigitSurvives) {
      return;
    }

    // Rule 4 — corroboration by adjacency, read on BOTH sides (KHA-107).
    final bool corroborated =
        (candidate > 0 &&
            referenceMarkerTokens.contains(tokens[candidate - 1])) ||
        (candidate < tokens.length - 1 &&
            referenceMarkerTokens.contains(tokens[candidate + 1]));
    if (!corroborated) {
      return;
    }

    tokens.removeAt(candidate);
  }

  /// Rule 1's candidate: the index of the last all-digit token with **only
  /// noise tokens after it**, or `-1` when there is none.
  ///
  /// Scanning from the end and stopping at the first non-noise, non-digit token
  /// is what bounds this to a single run and keeps `7 ELEVEN 1234`'s leading
  /// `7` unreachable: the scan meets `ELEVEN`, which is neither a digit run nor
  /// noise, and stops there.
  static int _referenceDigitRunIndex(List<String> tokens) {
    for (int i = tokens.length - 1; i >= 0; i--) {
      final String token = tokens[i];
      if (_digitsOnly.hasMatch(token)) {
        return i;
      }
      if (!noiseTokens.contains(token)) {
        // A real word sits between here and the end, so nothing before it is
        // "trailing modulo noise".
        return -1;
      }
    }
    return -1;
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
