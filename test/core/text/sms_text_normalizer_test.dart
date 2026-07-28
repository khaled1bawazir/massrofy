/// ADR-007 step 1. Each group below corresponds to one class of real-world
/// SMS noise that would otherwise have to be defended against inside every
/// single rule in every rule pack — where the first author to forget one
/// would ship a silent miss.
///
/// ## Why the invisible characters are built, not typed
///
/// Bidi controls reorder how the **source line containing them** renders in
/// an editor and in a code-review diff. A literal fixture built from them is
/// therefore unreviewable by eye, and a stray extra one is undetectable. The
/// Dart analyzer flags them for exactly this reason
/// (`text_direction_code_point_in_literal`), and it is right to.
///
/// So they are constructed from their code points below. This is the same
/// argument `sms_sanitizer.dart` makes for writing its Arabic-Indic digit
/// ranges as `\uXXXX` escapes rather than as literal glyphs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';

/// LEFT-TO-RIGHT ISOLATE (U+2066) — wraps a Latin run inside Arabic text.
final String lri = String.fromCharCode(0x2066);

/// POP DIRECTIONAL ISOLATE (U+2069) — closes it.
final String pdi = String.fromCharCode(0x2069);

/// LEFT-TO-RIGHT MARK, RIGHT-TO-LEFT MARK, ARABIC LETTER MARK.
final String lrm = String.fromCharCode(0x200E);
final String rlm = String.fromCharCode(0x200F);
final String alm = String.fromCharCode(0x061C);

/// ARABIC TATWEEL (U+0640) — a pure typographic stretch with no meaning.
final String tatweel = String.fromCharCode(0x0640);

/// NO-BREAK SPACE and NARROW NO-BREAK SPACE.
final String nbsp = String.fromCharCode(0x00A0);
final String nnbsp = String.fromCharCode(0x202F);

void main() {
  group('digit families', () {
    test('Arabic-Indic digits become ASCII', () {
      expect(SmsTextNormalizer.normalize('مبلغ:١٥٢٫٧٥'), 'مبلغ:152.75');
    });

    test('Extended/Persian Arabic-Indic digits become ASCII', () {
      expect(SmsTextNormalizer.normalize('۱۲۳۴۵'), '12345');
    });

    test('the three families mix inside one message', () {
      // Genuinely happens: an Arabic sentence quoting a Latin merchant name
      // that carries its own ASCII store number.
      expect(
        SmsTextNormalizer.normalize('شراء ١٥٢ لدى EXTRA 0042 رقم ۷۷'),
        'شراء 152 لدى EXTRA 0042 رقم 77',
      );
    });

    test('the Arabic decimal and thousands separators map to ASCII', () {
      expect(SmsTextNormalizer.normalize('١٬٥٠٠٫٥٠'), '1,500.50');
    });
  });

  group('invisible characters', () {
    test('bidi isolates around an embedded Latin run are stripped', () {
      // This is the single most common reason a rule that works when pasted
      // into a test fails against the real wire form: `\s` does not match
      // these characters, but `.` does.
      expect(
        SmsTextNormalizer.normalize('لدى ${lri}EXTRA MART$pdi اليوم'),
        'لدى EXTRA MART اليوم',
      );
    });

    test('LRM / RLM / ALM are stripped', () {
      expect(SmsTextNormalizer.normalize('a${lrm}b${rlm}c${alm}d'), 'abcd');
    });

    test('tatweel is stripped so a stretched keyword still matches', () {
      // "شـــراء" renders identically to "شراء" but no literal match finds it.
      expect(SmsTextNormalizer.normalize('ش$tatweel$tatweel راء'), 'ش راء');
      expect(SmsTextNormalizer.normalize('شرا$tatweel ء'), 'شرا ء');
    });

    test('Arabic diacritics are stripped', () {
      // A vowelled keyword must not become an intermittent parser bug.
      expect(SmsTextNormalizer.normalize('شِراء'), 'شراء');
    });
  });

  group('whitespace', () {
    test('newlines, tabs and doubled spaces collapse to one space', () {
      // This is what lets a multi-line bank template be matched by one flat
      // regex — see `assets/rule_packs/sa-core.json`.
      expect(
        SmsTextNormalizer.normalize('شراء\nبطاقة:\t\tمدى   -  ****4821'),
        'شراء بطاقة: مدى - ****4821',
      );
    });

    test('non-breaking and narrow no-break spaces collapse too', () {
      expect(SmsTextNormalizer.normalize('a${nbsp}b${nnbsp}c'), 'a b c');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(SmsTextNormalizer.normalize('  hello  '), 'hello');
    });
  });

  group('idempotence — the property the dedup HMAC depends on', () {
    // The pipeline normalises once and uses the result for BOTH rule matching
    // and the ADR-017 D1 content HMAC. If normalising twice could produce a
    // different string, the same message could hash differently on two runs
    // and duplicate suppression would silently stop working.
    final List<String> samples = <String>[
      'شراء\nبطاقة:مدى-****4821\nمبلغ:١٥٢٫٧٥ SAR',
      'D360: Purchase of SAR 89.00  at  BALAD',
      'لدى ${lri}EXTRA MART$pdi اليوم',
      '',
      '   ',
      '۱۲۳٤٥٦',
    ];

    for (int i = 0; i < samples.length; i++) {
      test('normalize(normalize(x)) == normalize(x) for sample $i', () {
        final String once = SmsTextNormalizer.normalize(samples[i]);
        expect(SmsTextNormalizer.normalize(once), once);
      });
    }
  });

  group('what it deliberately does NOT do', () {
    test('letters, case and punctuation are left alone', () {
      // Normalisation is about representation, never about meaning. Folding
      // case here would make rule regexes ambiguous about what they match,
      // and the loader already compiles them case-insensitively.
      expect(
        SmsTextNormalizer.normalize('Purchase of SAR 89.00 at BALAD.'),
        'Purchase of SAR 89.00 at BALAD.',
      );
    });
  });
}
