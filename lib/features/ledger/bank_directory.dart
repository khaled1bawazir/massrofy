/// Bank **entity resolution** — KHA-23, US-B12, AC-B12.1, AC-B12.3.
///
/// ## The acceptance criterion this file exists for
///
/// AC-B12.3: *"two SMS reference the same bank using different naming (e.g.
/// Arabic name in one message, an abbreviation in another) … resolve to the
/// same bank entity, not two."*
///
/// There are two distinct ways a bank gets named, and both must land on one
/// key:
///
/// 1. **By sender id.** `BAJ` and `Aljazira` are different originating
///    addresses for one bank. The parser already collapses these — a bank's
///    `senderPatterns` all map to its single `bankId` (ADR-007) — so this half
///    is solved upstream, and the ledger simply must not undo it by keying on
///    anything else.
/// 2. **By name in the text.** "بنك الجزيرة" in one message, "BAJ" in
///    another. That is what [BankDirectory.resolveByName] handles, using the
///    pack's own alias and display-name sets.
///
/// The rule the whole thing rests on: **identity is the canonical key; the
/// display string is only ever an input.**
///
/// ## Why this type exists instead of reading the rule pack directly
///
/// Architecture §3's dependency rule: a feature never imports another
/// feature's internals. `features/ledger` must not know what a `RulePack`
/// looks like, or a rule-schema change would become a ledger change. So the
/// ledger declares the small shape it needs — [BankProfile] — and something
/// that already depends on both (the presentation layer's providers) adapts
/// the pack into it.
library;

/// The facts the ledger needs about one bank, independent of where they came
/// from (a bundled pack, an imported pack, or the user typing them in).
final class BankProfile {
  /// Stable identity. For a pack-derived profile this is the pack's `bankId`.
  final String canonicalKey;

  final String displayNameAr;
  final String displayNameEn;

  /// Alternative spellings — abbreviations, Latin transliterations, the
  /// Arabic short form. Matched case- and whitespace-insensitively.
  final List<String> aliases;

  const BankProfile({
    required this.canonicalKey,
    required this.displayNameAr,
    required this.displayNameEn,
    this.aliases = const <String>[],
  });

  @override
  String toString() => 'BankProfile($canonicalKey)';
}

/// An index over [BankProfile]s that answers "which bank is this?".
final class BankDirectory {
  final List<BankProfile> profiles;

  /// Normalised name/alias → canonical key. Built once at construction: a
  /// directory is read on every ingested message, and rebuilding the index
  /// per lookup would be a per-message cost for a per-pack fact.
  final Map<String, String> _byNormalizedName;

  BankDirectory(this.profiles)
    : _byNormalizedName = <String, String>{
        for (final BankProfile profile in profiles) ...<String, String>{
          for (final String name in <String>[
            profile.canonicalKey,
            profile.displayNameAr,
            profile.displayNameEn,
            ...profile.aliases,
          ])
            if (normalizeBankName(name).isNotEmpty)
              normalizeBankName(name): profile.canonicalKey,
        },
      };

  const BankDirectory.empty()
    : profiles = const <BankProfile>[],
      _byNormalizedName = const <String, String>{};

  /// The profile for [canonicalKey], or `null` if no active pack declares it.
  ///
  /// Null is a real case rather than an error: a pack can be replaced while
  /// the banks it created still hold transactions, and those transactions
  /// must keep working. Callers fall back to the stored `bank` row, which is
  /// why the display names are persisted (see `bank_table.dart`).
  BankProfile? byCanonicalKey(String canonicalKey) {
    for (final BankProfile profile in profiles) {
      if (profile.canonicalKey == canonicalKey) {
        return profile;
      }
    }
    return null;
  }

  /// **AC-B12.3.** Resolves a bank *named in text* — in either script, as a
  /// display name, an alias, or an abbreviation — to its canonical key.
  ///
  /// Returns `null` when the name matches nothing, which the caller treats as
  /// "unknown bank", never as "a new bank called whatever this string is".
  /// Creating a bank from an unrecognised string is how a typo becomes a
  /// permanent second entity in the tree.
  String? resolveByName(String name) =>
      _byNormalizedName[normalizeBankName(name)];
}

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _arabicDiacritics = RegExp('[ً-ْـ]');

/// Folds a bank name to a comparison key.
///
/// Deliberately narrow — case, whitespace, Arabic diacritics/tatweel, and the
/// alef/ya/ta-marbuta spelling variants that make "الجزيرة" and "الجزيره" the
/// same word to a reader and different strings to a computer. It does **not**
/// do fuzzy matching: two banks with similar names must stay two banks, and
/// an edit-distance match here would eventually merge them.
String normalizeBankName(String value) {
  String result = value.trim().toLowerCase();
  result = result.replaceAll(_arabicDiacritics, '');
  result = result
      .replaceAll('أ', 'ا') // أ → ا
      .replaceAll('إ', 'ا') // إ → ا
      .replaceAll('آ', 'ا') // آ → ا
      .replaceAll('ى', 'ي') // ى → ي
      .replaceAll('ة', 'ه'); // ة → ه
  result = result.replaceAll(_whitespaceRun, ' ');
  // Hyphens and underscores are punctuation in bank branding, not meaning:
  // `D-360`, `D360` and `d 360` are one bank.
  result = result.replaceAll(RegExp(r'[-_]'), '');
  return result.replaceAll(_whitespaceRun, '');
}
