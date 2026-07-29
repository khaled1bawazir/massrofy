/// **The shared script-folding step** — ADR-008's normalisation pipeline,
/// steps 1 to 3, factored out so two different consumers cannot disagree
/// about what "the same string" means.
///
/// ## Who uses this, and why it is not inside the merchant matcher
///
/// Two callers, with genuinely different needs after this point:
///
///  - **`features/categorization/merchant_key.dart`** — continues on to strip
///    trailing store numbers and noise tokens, because `PANDA STORE 1234` and
///    `Panda` are the same shop (AC-D2.3).
///  - **`data/dao/category_dao.dart`** — stops here, because a *category*
///    name's digits and words are all meaningful. "Bills 2026" is not the same
///    category as "Bills", and folding them together would reject a legitimate
///    name as a duplicate (AC-C3.2 must reject *duplicates*, not merely
///    similar names).
///
/// Sharing the fold and not the rest is the whole point: the case-, spacing-
/// and Arabic-orthography-insensitivity is identical for both, and that is the
/// part it would be a silent bug to implement twice.
///
/// ## What "fold" means here, stated honestly
///
/// ADR-008 opens with "Unicode NFKC". Dart's core library ships no Unicode
/// normalisation, and `lib/core/text/sms_text_normalizer.dart` already
/// explains at length why this codebase implements the specific, enumerated
/// compatibility folds that matter for Saudi bank SMS instead of pulling in a
/// full NFKC table for a no-network app. The same reasoning applies verbatim
/// here, and this file reuses that decision rather than re-litigating it:
/// [fold] *starts* by calling [SmsTextNormalizer.normalize].
///
/// The additional steps here are the ones ADR-008 names that the parser's
/// normaliser deliberately does not do (the parser must not fold `ة` into `ه`
/// inside a keyword it is matching literally):
///
///  - **Arabic letter-variant folding** — `أ إ آ ٱ → ا`, `ة → ه`, `ى → ي`,
///    `ؤ → و`, `ئ → ي`. Saudi SMS spells the same merchant both ways
///    routinely, and a user should never have to teach the app twice.
///  - **Latin case folding to upper.** Upper rather than lower purely so the
///    stored keys are visually obvious as keys in a debugger; either direction
///    is correct as long as it is only done in one place, which is here.
///
/// ## Not for display, ever
///
/// A folded string is a **match key**. It has lost `ة`/`ه` distinctions and
/// letter case, so showing one to a user would show them a misspelling of
/// their own merchant. Every entity in this codebase that carries a key also
/// carries the original text for display (`Merchant.canonicalName`,
/// `Category.nameAr`/`nameEn`) for exactly that reason.
library;

import 'sms_text_normalizer.dart';

/// Script-insensitive folding, shared by merchant keys and category names.
abstract final class CanonicalText {
  /// Arabic orthographic variants that must not create two of anything.
  ///
  /// Written as a literal map of single characters rather than a regex with
  /// character classes, because a reviewer has to be able to check each pair
  /// by eye — several of these differ only by a dot or a hamza seat.
  static const Map<String, String> _arabicLetterFolds = <String, String>{
    'أ': 'ا', // alef with hamza above
    'إ': 'ا', // alef with hamza below
    'آ': 'ا', // alef with madda
    'ٱ': 'ا', // alef wasla
    'ة': 'ه', // teh marbuta → heh
    'ى': 'ي', // alef maksura → yeh
    'ؤ': 'و', // waw with hamza
    'ئ': 'ي', // yeh with hamza
  };

  /// Returns the canonical match form of [raw].
  ///
  /// Idempotent: `fold(fold(x)) == fold(x)`. That property is asserted by a
  /// test, and it matters because a key is computed at write time and again at
  /// read time by different code paths — if folding were not idempotent, a key
  /// stored once and recomputed later could stop matching itself.
  static String fold(String raw) {
    // Step 1 — the shared SMS-domain normalisation: bidi controls, tatweel,
    // Arabic diacritics, three digit families, whitespace runs.
    final String normalized = SmsTextNormalizer.normalize(raw);

    // Step 2 — Arabic letter variants.
    final StringBuffer buffer = StringBuffer();
    for (final int rune in normalized.runes) {
      final String character = String.fromCharCode(rune);
      buffer.write(_arabicLetterFolds[character] ?? character);
    }

    // Step 3 — Latin case. `toUpperCase()` leaves Arabic untouched (it is
    // caseless), so this is safe to apply to a mixed-script string, which is
    // the normal case per PRD §3.4: a Latin merchant name inside an Arabic
    // message.
    return buffer.toString().toUpperCase();
  }
}
