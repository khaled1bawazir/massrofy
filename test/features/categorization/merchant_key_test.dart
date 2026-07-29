/// **ADR-008's normalisation pipeline, as a table** — KHA-31, R-5.
///
/// The whole corpus here is **synthetic** (NFR-M3): generic chain-shaped
/// names and invented store numbers. No merchant string from any real user's
/// SMS is in this repository.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/config/categorization_config.dart';
import 'package:massrofy/core/text/canonical_text.dart';
import 'package:massrofy/features/categorization/merchant_key.dart';

void main() {
  group('CanonicalText.fold — the shared script fold', () {
    test('is idempotent', () {
      // A key is computed when a merchant is created and recomputed on every
      // later message, by different code paths. A fold that changed its own
      // output on a second pass would stop matching the rows it wrote.
      for (final String input in <String>[
        'Panda Foods',
        'مطعم البيك',
        'CAFÉ  ROYAL',
        'شركة الكهرباء',
      ]) {
        final String once = CanonicalText.fold(input);
        expect(CanonicalText.fold(once), once, reason: input);
      }
    });

    test(
      'folds Arabic letter variants so one spelling is not two merchants',
      () {
        // أ إ آ ٱ → ا, ة → ه, ى → ي — the variants Saudi SMS uses
        // interchangeably for the same name.
        expect(CanonicalText.fold('أحمد'), CanonicalText.fold('احمد'));
        expect(CanonicalText.fold('مكتبة'), CanonicalText.fold('مكتبه'));
        expect(CanonicalText.fold('مصطفى'), CanonicalText.fold('مصطفي'));
      },
    );

    test('case-folds Latin and collapses whitespace', () {
      expect(CanonicalText.fold('  Panda   foods '), 'PANDA FOODS');
    });

    test('strips bidi controls and tatweel, which the wire form is full of', () {
      // U+202B RLE ... U+202C PDF around a Latin name inside an Arabic
      // message, and a tatweel stretching an Arabic word. The bidi controls
      // are written as escapes, not as literals: a literal here would reorder
      // this source line in every editor and reviewer's browser, which is the
      // one place misleading text is genuinely dangerous (the analyzer refuses
      // them for exactly this reason).
      const String rightToLeftEmbedding = '\u202B';
      const String popDirectionalFormatting = '\u202C';
      expect(
        CanonicalText.fold(
          '${rightToLeftEmbedding}PANDA$popDirectionalFormatting',
        ),
        'PANDA',
      );
      expect(CanonicalText.fold('مطـــعم'), CanonicalText.fold('مطعم'));
    });

    test(
      'keeps digits, because a category name may legitimately contain one',
      () {
        // The merchant pipeline strips trailing digit runs; the shared fold must
        // not, or "Bills 2026" and "Bills" would collide as category names
        // (AC-C3.2 must reject duplicates, not merely similar names).
        expect(CanonicalText.fold('Bills 2026'), 'BILLS 2026');
      },
    );
  });

  group('MerchantKey.of — the merchant-specific steps', () {
    test('is idempotent', () {
      for (final String input in <String>[
        'PANDA STORE 1420',
        'Panda-1420',
        'مطعم البيك فرع الرياض',
      ]) {
        final String once = MerchantKey.of(input);
        expect(MerchantKey.of(once), once, reason: input);
      }
    });

    test('the cosmetic-variant corpus all produces one key (AC-D2.3)', () {
      // Every row here is the same shop as far as the user is concerned:
      // spacing, case, punctuation, a till number and a branch word.
      //
      // **`PANDA FOODS RIYADH` left this list at ADR-008 v1.3 (KHA-98).** A
      // city name is a proper noun: it can be the *distinguishing* token of two
      // unrelated businesses, so removing it is not absorbing cosmetic variance
      // — it is the machine asserting that two shops are one. The cost is that
      // a chain's branches key separately and the user links them once with a
      // `MerchantAlias`; the alternative was `MAKKAH BAKERY` and
      // `MADINAH BAKERY` becoming a single merchant row at confidence 1.00.
      // Pinned as its own case below.
      const List<String> variants = <String>[
        'PANDA FOODS',
        'panda foods',
        '  Panda   Foods  ',
        'PANDA FOODS 1420',
        'PANDA-FOODS-1420',
        'PANDA FOODS STORE 1420',
        'PANDA FOODS BRANCH',
        'PANDA*FOODS#0042',
      ];
      final Set<String> keys = variants.map(MerchantKey.of).toSet();
      expect(
        keys,
        hasLength(1),
        reason: 'produced ${keys.toList()} — every variant must key the same',
      );
      expect(keys.single, 'PANDA FOODS');
    });

    test('KHA-98 — a city name is a proper noun and is never stripped', () {
      // The regression table from ADR-008 v1.3's KHA-98 subsection, verbatim.
      // Two unrelated local businesses whose only distinguishing token is a
      // city name must not become one identity.
      expect(
        MerchantKey.of('MAKKAH BAKERY'),
        isNot(MerchantKey.of('MADINAH BAKERY')),
      );
      expect(MerchantKey.of('MAKKAH BAKERY'), 'MAKKAH BAKERY');

      // Two branches of one chain now key separately too. That is the stated
      // cost, and it is the recoverable direction: one `MerchantAlias` link
      // fixes it, whereas one row that should have been two cannot be unpicked
      // without re-attributing history.
      expect(
        MerchantKey.of('PANDA RIYADH'),
        isNot(MerchantKey.of('PANDA JEDDAH')),
      );

      // Arabic city names went with them.
      expect(MerchantKey.of('فرع QANDA الرياض'), 'QANDA الرياض');
    });

    test('KHA-98 — the noise list contains only STRUCTURAL words, enforced '
        'against an explicit allow-list', () {
      // ADR-008 v1.3: *"no proper noun may ever be added to it. A test must pin
      // that: the noise list is asserted against an explicit allow-list of
      // structural words, so a future 'helpful' addition fails CI rather than
      // silently merging two shops."*
      //
      // This is the forcing function, and it is deliberately a *equality*
      // check rather than a subset check: adding a word to `noiseTokens`
      // without adding it here fails, and so does removing one, so both
      // directions of drift are caught. Every entry below names a kind of
      // business (an outlet, a legal form, a terminal) and none names a
      // particular one.
      const Set<String> structuralAllowList = <String>{
        // Outlet / branch vocabulary.
        'BRANCH', 'STORE', 'STORES', 'BR', 'FRC', 'TERMINAL', 'TERM', 'POS',
        // Legal-form vocabulary.
        'CO', 'LLC', 'LTD',
        // The Arabic equivalents, in folded form.
        'فرع', 'محل', 'شركه', 'موسسه',
      };
      expect(
        MerchantKey.noiseTokens,
        structuralAllowList,
        reason:
            'the noise list has drifted from the structural allow-list. If an '
            'entry here is a PROPER NOUN — a city, a district, a mall, a '
            'person — it can be the distinguishing token of two unrelated '
            'businesses, and stripping it merges them at confidence 1.00 '
            '(KHA-98). Read the corroboration rule in merchant_key.dart first.',
      );

      // The reference markers are a subset of the noise list by construction:
      // adjacency corroboration only makes sense for a word this pipeline is
      // also removing.
      expect(
        MerchantKey.referenceMarkerTokens.difference(MerchantKey.noiseTokens),
        isEmpty,
      );
    });

    test('KHA-99 — a trailing digit run is stripped only when CORROBORATED, '
        'and at most one of them', () {
      // ADR-008 v1.3 settled answer 2, as a table.

      // Corroborated by ADJACENCY to a structural marker — PRD §3.4's own
      // observed shape. Preserved exactly as before.
      expect(MerchantKey.of('PANDA STORE 1234'), 'PANDA');
      expect(MerchantKey.of('PANDA BRANCH 7'), 'PANDA');

      // Corroborated by LENGTH: four or more digits is a till/terminal/
      // reference id, not a branch number a human says out loud.
      expect(MerchantKey.of('PANDA 1234'), 'PANDA');
      expect(MerchantKey.of('QANDA-9021'), 'QANDA');

      // NOT corroborated: a short bare number is part of the name, so two
      // numbered outlets stay two identities. This is the KHA-99 defect.
      expect(MerchantKey.of('QAMART 100'), 'QAMART 100');
      expect(MerchantKey.of('QAMART 200'), 'QAMART 200');
      expect(MerchantKey.of('QAMART 100'), isNot(MerchantKey.of('QAMART 200')));
      expect(MerchantKey.of('CAFE 1'), isNot(MerchantKey.of('CAFE 2')));

      // Rule 1 — at most ONE run. Two digit runs in a row are not a reference.
      expect(MerchantKey.of('QAMART 100 200 300'), 'QAMART 100 200 300');

      // Rule 2 — never strip the last non-digit-bearing thing. A bare number
      // keeps whatever identity it has rather than becoming no merchant.
      expect(MerchantKey.of('4321'), '4321');

      // Rule 4 — leading digits keep their existing protection, unchanged.
      expect(MerchantKey.of('7 ELEVEN'), '7 ELEVEN');
      expect(MerchantKey.of('7 ELEVEN 1234'), '7 ELEVEN');

      // The tunable is the length, not the bar.
      expect(CategorizationConfig.referenceDigitRunMinLength, 4);
    });

    test(
      'unrelated merchants keep different keys (AC-D2.3, the other half)',
      () {
        final Set<String> keys = <String>{
          MerchantKey.of('PANDA FOODS'),
          MerchantKey.of('PANDA EXPRESS'),
          MerchantKey.of('TAMIMI MARKETS'),
          MerchantKey.of('SEC-KAHRABA'),
        };
        expect(keys, hasLength(4));
      },
    );

    test('only TRAILING digit runs are stripped — a leading number is part of '
        'the name', () {
      // Stripping digit tokens anywhere would turn `7 ELEVEN` into `ELEVEN`,
      // inventing a different merchant out of a real name.
      expect(MerchantKey.of('7 ELEVEN'), '7 ELEVEN');
      expect(MerchantKey.of('7 ELEVEN 1234'), '7 ELEVEN');
    });

    test('a merchant with a real name beside a noise word keeps a usable key', () {
      // "Riyadh Store" is a plausible shop name, and after KHA-98 it keeps a
      // *genuine* key rather than a fallback one: `RIYADH` is a proper noun, so
      // it is no longer stripped and survives as the identity. Two such shops
      // stay two merchants, which is what the old fallback was reaching for and
      // could not reliably deliver.
      expect(MerchantKey.of('RIYADH STORE'), 'RIYADH');
      expect(
        MerchantKey.of('RIYADH STORE'),
        isNot(MerchantKey.of('JEDDAH STORE')),
      );
    });

    test('KHA-102 — a string with NO surviving token yields no key at all', () {
      // A transfer or an ATM withdrawal names no merchant. An empty-string key
      // would make every one of them "the same merchant", and a single rule
      // would then categorise the lot.
      expect(MerchantKey.ofOrNull(null), isNull);
      expect(MerchantKey.ofOrNull(''), isNull);
      expect(MerchantKey.ofOrNull('   '), isNull);

      // The guard used to be defeated by its own implementation: `of` fell back
      // to the folded string when every token was stripped, and a
      // punctuation-only string (acquirers send these where the merchant name
      // was masked) tokenises to nothing while folding to itself. Non-empty, so
      // the `isEmpty` test missed it, and one rule then categorised every
      // masked-merchant message from every bank.
      expect(MerchantKey.ofOrNull('***'), isNull);
      expect(MerchantKey.ofOrNull('-*-'), isNull);

      // And the general form, which is why the fallback was REMOVED rather than
      // patched to "require a letter or digit": a string made only of tokens we
      // have declared incapable of distinguishing two businesses cannot
      // distinguish two businesses.
      expect(MerchantKey.ofOrNull('STORE'), isNull);
      expect(MerchantKey.ofOrNull('محل'), isNull);
      expect(MerchantKey.ofOrNull('BRANCH STORE'), isNull);

      // Still idempotent across the new empty answer.
      expect(MerchantKey.of(MerchantKey.of('***')), MerchantKey.of('***'));
    });

    test('every noise token is stored in already-folded form', () {
      // The list is compared against tokens that have already been folded, so
      // an entry in the wrong form would silently never match. This is the
      // check that turns that into a test failure instead.
      for (final String token in MerchantKey.noiseTokens) {
        expect(
          CanonicalText.fold(token),
          token,
          reason: '"$token" is not in folded form and will never match',
        );
      }
    });

    test('Arabic and Latin renderings are NOT merged by the pipeline (ADR-008 '
        'declines to transliterate)', () {
      // The architecture is explicit: "Arabic and Latin renderings of the same
      // merchant cannot be reliably transliterated. We do not try." Linking
      // them is a user action (`MerchantAlias`), never an inference. If this
      // test ever starts passing as "equal", someone has added a
      // transliterator and the silent-merge guarantee is gone.
      expect(MerchantKey.of('البيك'), isNot(MerchantKey.of('AL BAIK')));
    });

    test('scriptOf classifies the three cases', () {
      expect(MerchantKey.scriptOf('PANDA'), MerchantScript.latin);
      expect(MerchantKey.scriptOf('بنده'), MerchantScript.arabic);
      expect(MerchantKey.scriptOf('بنده PANDA'), MerchantScript.mixed);
    });
  });
}
