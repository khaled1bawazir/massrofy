/// **ADR-008's normalisation pipeline, as a table** — KHA-31, R-5.
///
/// The whole corpus here is **synthetic** (NFR-M3): generic chain-shaped
/// names and invented store numbers. No merchant string from any real user's
/// SMS is in this repository.
library;

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
      const List<String> variants = <String>[
        'PANDA FOODS',
        'panda foods',
        '  Panda   Foods  ',
        'PANDA FOODS 1420',
        'PANDA-FOODS-1420',
        'PANDA FOODS STORE 1420',
        'PANDA FOODS BRANCH',
        'PANDA FOODS RIYADH',
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

    test('a merchant made entirely of noise words keeps a usable key', () {
      // "Riyadh Store" is a plausible shop name. Falling through to the folded
      // string keeps it distinct instead of collapsing every such merchant
      // into one empty key — the worst silent merge available in this design.
      expect(MerchantKey.of('RIYADH STORE'), isNotEmpty);
      expect(
        MerchantKey.of('RIYADH STORE'),
        isNot(MerchantKey.of('JEDDAH STORE')),
      );
    });

    test('null and blank merchant text produce no key at all', () {
      // A transfer or an ATM withdrawal names no merchant. An empty-string key
      // would make every one of them "the same merchant", and a single rule
      // would then categorise the lot.
      expect(MerchantKey.ofOrNull(null), isNull);
      expect(MerchantKey.ofOrNull(''), isNull);
      expect(MerchantKey.ofOrNull('   '), isNull);
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
