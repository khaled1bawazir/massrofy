// QA probe: does an invisible bidi/format mark in the SMS sender id defeat
// `_resolveBank`'s `sender.trim()` + shipped `senderPatterns`?
//
// Run with: dart run docs/evidence/qa-pr44-regate/bidi_sender_probe.dart
//
// `ignore_for_file` rather than a rewrite, deliberately, and only in this
// evidence script:
//  - `text_direction_code_point_in_literal` — the LITERAL marks are the
//    experiment. Rewriting them as `‏` escapes would test a different
//    string from the one a carrier actually delivers, which is the whole
//    question. (The permanent guard in `test/qa/pr44_p5b_qa_probes_test.dart`
//    does use `String.fromCharCode`, because there the marks are an input to
//    an assertion rather than the object of study.)
//  - `avoid_print` — this is a standalone CLI probe, not production code, and
//    stdout is its only output channel.
//
// Without these, `flutter analyze --fatal-infos` fails on a file that lives
// under `docs/` purely as evidence.
// ignore_for_file: text_direction_code_point_in_literal, avoid_print
void main() {
  final RegExp jazira = RegExp(r'^Jazira\s*Bank$', caseSensitive: false);
  final RegExp d360 = RegExp(r'^D360\s*Bank$', caseSensitive: false);

  final Map<String, String> cases = <String, String>{
    'clean control': 'Jazira Bank',
    'RLM prefix (U+200F)': '‏Jazira Bank',
    'RLM suffix (U+200F)': 'Jazira Bank‏',
    'LRM prefix (U+200E)': '‎Jazira Bank',
    'RLE/PDF wrap': '‫Jazira Bank‬',
    'BOM/ZWNBSP prefix (U+FEFF)': '﻿Jazira Bank',
    'ZWSP prefix (U+200B)': '​D360 Bank',
  };

  cases.forEach((String label, String s) {
    final String trimmed = s.trim();
    final bool matched = jazira.hasMatch(trimmed) || d360.hasMatch(trimmed);
    print(
      '${matched ? "MATCH  " : "DISCARD"}  trimLen=${trimmed.length}  '
      'rawLen=${s.length}  $label',
    );
  });
}
