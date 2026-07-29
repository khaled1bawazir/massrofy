/// **ADR-008's normalisation pipeline, as a table** — KHA-31, R-5.
///
/// The whole corpus here is **synthetic** (NFR-M3): generic chain-shaped
/// names and invented store numbers. No merchant string from any real user's
/// SMS is in this repository.
library;

// `CategorizationConfig` is no longer imported: ADR-008 v1.4 deleted
// `referenceDigitRunMinLength`, and nothing else in this file's subject matter
// is configurable. Merchant identity is decided by the rules in
// `merchant_key.dart` alone (KHA-106).
import 'package:flutter_test/flutter_test.dart';
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
      //
      // **Three rows left this list at ADR-008 v1.4 (KHA-106)** for the same
      // shape of reason: `PANDA FOODS 1420`, `PANDA-FOODS-1420` and
      // `PANDA*FOODS#0042` were absorbed only by the *length* corroboration
      // signal, which is withdrawn because no threshold can be residue-safe.
      // They are pinned as the disclosed cost in the KHA-106 test below rather
      // than deleted. What still absorbs a store number is a marker word beside
      // it — `PANDA FOODS STORE 1420` — which is PRD §3.4's observed shape and
      // the case the product actually needs.
      const List<String> variants = <String>[
        'PANDA FOODS',
        'panda foods',
        '  Panda   Foods  ',
        'PANDA FOODS STORE 1420',
        'PANDA FOODS 1420 STORE', // KHA-107: the same three tokens, reordered
        'PANDA-FOODS-STORE-1420',
        'PANDA FOODS BRANCH',
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

    test('KHA-99/106/107 — a digit run is stripped only when a structural '
        'marker sits beside it, and at most one of them', () {
      // **ADR-008 v1.4's worked-example table, verbatim.** The architect calls
      // that table "the regression suite", so it is transcribed rather than
      // paraphrased, and every row carries the reason from the ADR.
      const Map<String, String> workedExamples = <String, String>{
        // Marker BEFORE the run — PRD §3.4's observed shape, unchanged since
        // v1.3.
        'PANDA STORE 1234': 'PANDA',
        'PANDA BRANCH 7': 'PANDA',
        // Marker AFTER the run. KHA-107 closed: the run is trailing once
        // structural noise is disregarded, so the two orderings are one shop.
        'PANDA 1234 STORE': 'PANDA',
        // No marker anywhere. **The disclosed cost of KHA-106** — pinned as
        // its own case below too, because it is a cost we chose, not a bug.
        'PANDA 1234': 'PANDA 1234',
        'QANDA-9021': 'QANDA 9021',
        // KHA-106 closed: two numbered outlets are two identities.
        'QAMART 1000': 'QAMART 1000',
        'QAMART 2000': 'QAMART 2000',
        // …and the accepted collapse, disclosed rather than hidden: with a
        // marker beside them, both DO collapse. Reordering changes this shape.
        'QAMART 1000 STORE': 'QAMART',
        'QAMART 2000 STORE': 'QAMART',
        // KHA-99, still closed at three digits.
        'QAMART 100': 'QAMART 100',
        'QAMART 200': 'QAMART 200',
        // Rule 2 — at most one run; two in a row are not a reference.
        'QAMART 100 200 300': 'QAMART 100 200 300',
        // Rule 3 — a bare number keeps whatever identity it has.
        '4321': '4321',
        // Rule 5 — leading digits are protected BY RULE 1: `ELEVEN` is not a
        // noise token, so `7` is never a candidate.
        '7 ELEVEN': '7 ELEVEN',
        '7 ELEVEN STORE': '7 ELEVEN',
        '7 ELEVEN 1234': '7 ELEVEN 1234',
      };
      workedExamples.forEach((String input, String expected) {
        expect(MerchantKey.of(input), expected, reason: 'of("$input")');
      });

      // The KHA-102 rows of the same table: the strip fires, and what is left
      // is all noise, so there is no merchant identity at all.
      expect(MerchantKey.ofOrNull('STORE 7'), isNull);
      expect(
        MerchantKey.ofOrNull('1234 STORE'),
        isNull,
        reason:
            'ADR-008 v1.4: the candidate strips and the remainder is '
            'all-noise — more conservative than v1.3, and correct',
      );

      // Two numbered outlets must stay two identities, stated as the
      // inequality the defect was about rather than only as two equalities.
      expect(
        MerchantKey.of('QAMART 1000'),
        isNot(MerchantKey.of('QAMART 2000')),
        reason: 'KHA-106: the 4-digit sibling collision is closed',
      );
      expect(MerchantKey.of('QAMART 100'), isNot(MerchantKey.of('QAMART 200')));
      expect(MerchantKey.of('CAFE 1'), isNot(MerchantKey.of('CAFE 2')));
    });

    test('KHA-107 — the strip is ORDER-INSENSITIVE: a marker before the run '
        'and a marker after it produce one key', () {
      // The defect PROBE M1 reported: the same three tokens in two orders were
      // two merchant identities, against PRD §3.4's promise that all renderings
      // of one shop reach one key.
      expect(
        MerchantKey.of('PANDA 1234 STORE'),
        MerchantKey.of('PANDA STORE 1234'),
      );
      expect(MerchantKey.of('PANDA 1234 STORE'), 'PANDA');

      // Swept over every reference marker, not only `STORE`, and in both
      // orders — a fix that worked for one marker word and not the rest would
      // pass a single-case test.
      for (final String marker in MerchantKey.referenceMarkerTokens) {
        expect(
          MerchantKey.of('QANDA $marker 4821'),
          MerchantKey.of('QANDA 4821 $marker'),
          reason: 'marker "$marker" must corroborate from either side',
        );
        expect(MerchantKey.of('QANDA 4821 $marker'), 'QANDA');
      }
    });

    test('KHA-106 — the DISCLOSED COSTS are pinned as tests, so a future '
        '"improvement" that reintroduces length stripping fails CI', () {
      // ADR-008 v1.4 accepted two consequences explicitly. Neither is a bug,
      // and both are exactly the kind of thing a later reader would "fix".
      // Asserting them is what turns "we decided this" into something the build
      // enforces.

      // Cost 1 — a bare digit run is no longer absorbed into the chain key.
      // The pair falls to T4 ("did you mean…"), which can never auto-apply, so
      // the app ASKS rather than merging. That direction is the whole point.
      expect(
        MerchantKey.of('PANDA 1234'),
        isNot(MerchantKey.of('PANDA')),
        reason:
            'EXPECTED, not a defect: with the length signal withdrawn there '
            'is nothing in "PANDA 1234" that says 1234 is not part of the '
            'name. Restoring this equality means restoring KHA-106.',
      );

      // Cost 2 — with a marker beside them, sibling outlets DO still collapse.
      // This is signal (i) working as designed, and v1.4 discloses that
      // reordering makes it reachable for a shape v1.3 did not reach.
      expect(
        MerchantKey.of('QAMART 1000 STORE'),
        MerchantKey.of('QAMART 2000 STORE'),
        reason:
            'EXPECTED: `STORE` is the string stating that the run is not part '
            'of the name. The repair for a wrong marker claim is the '
            'alias-split affordance (ADR-008 settled answer 6 / H-15), not a '
            'narrower strip.',
      );
      expect(MerchantKey.of('QAMART 1000 STORE'), 'QAMART');
    });

    test('KHA-106/107 — `of` is idempotent over the whole synthetic corpus, '
        'and the invariant holds BY CONSTRUCTION', () {
      // ADR-008 v1.4 requires this table-driven rather than as one case,
      // because the previous single-case test (`PANDA STORE 1420`) passed
      // while `PANDA 1234 STORE` was broken.
      //
      // The proof the code claims: every corroborator is itself a noise token,
      // so no OUTPUT of `of` can contain one, so a second pass strips nothing.
      // The corpus below is deliberately biased toward the shapes that make
      // that argument load-bearing — markers on both sides, digits everywhere,
      // all-noise strings, mixed scripts.
      const List<String> corpus = <String>[
        'PANDA 1234 STORE',
        'PANDA STORE 1234',
        'PANDA 1234',
        'PANDA',
        'QAMART 1000',
        'QAMART 1000 STORE',
        'QAMART 100 200 300',
        '7 ELEVEN',
        '7 ELEVEN STORE',
        '7 ELEVEN 1234',
        'STORE 7',
        '1234 STORE',
        '1234 STORE 5678',
        'STORE 1234 BRANCH',
        'QANDA BRANCH STORE 42',
        'فرع QANDA 1234',
        'مطعم البيك فرع الرياض',
        'PANDA-FOODS-1420',
        'PANDA*FOODS#0042',
        '***',
        'STORE',
        '4321',
        'RIYADH STORE',
        'MAKKAH BAKERY',
      ];
      for (final String input in corpus) {
        final String once = MerchantKey.of(input);
        expect(
          MerchantKey.of(once),
          once,
          reason: 'of(of("$input")) != of("$input") — the invariant is broken',
        );
        // …and a third pass, because "stable after two" and "a fixed point"
        // are not the same claim.
        expect(MerchantKey.of(MerchantKey.of(once)), once, reason: input);
      }
    });

    test('KHA-106/107 — the proof\'s premises, asserted directly rather than '
        'trusted', () {
      // The idempotence argument rests on exactly two facts. If either stops
      // holding, the invariant above becomes luck, so both are pinned here
      // where a reader can see them beside the claim.

      // Premise 1: every corroborator is itself stripped by step 7.
      expect(
        MerchantKey.referenceMarkerTokens.difference(MerchantKey.noiseTokens),
        isEmpty,
        reason:
            'a corroborator that survives step 7 could appear in `of`\'s '
            'output and corroborate a strip on the second pass',
      );

      // Premise 2: `CanonicalText.fold` is itself idempotent — steps 1-5 of
      // the pipeline. ADR-008 v1.4 asks for this explicitly, since the proof
      // rests on it.
      for (final String input in <String>[
        'PANDA STORE 1234',
        'مطـــعم البيك',
        'Panda-1420',
        'ﺍﻟﺴﻼﻡ',
        '  spaced   out  ',
      ]) {
        final String once = CanonicalText.fold(input);
        expect(CanonicalText.fold(once), once, reason: 'fold("$input")');
      }
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

    test('a LEADING number is part of the name and is never a candidate', () {
      // Stripping digit tokens anywhere would turn `7 ELEVEN` into `ELEVEN`,
      // inventing a different merchant out of a real name.
      //
      // At ADR-008 v1.4 this is no longer a special case for "leading": the
      // candidate scan walks back from the end and stops at the first token
      // that is neither a digit run nor noise, so `ELEVEN` shields the `7`.
      expect(MerchantKey.of('7 ELEVEN'), '7 ELEVEN');
      expect(MerchantKey.of('7 ELEVEN STORE'), '7 ELEVEN');
      expect(MerchantKey.of('7 ELEVEN 1234'), '7 ELEVEN 1234');
      expect(MerchantKey.of('7 ELEVEN 1234 STORE'), '7 ELEVEN');
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
