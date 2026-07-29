// QA probe for PR #37 / KHA-108 — THROWAWAY, deleted with this branch.
//
// Round 2: identical formatting, but 'dart:convert' is now USED. The previous
// commit's only defect was the unused import and the job went red; if this
// commit goes green, the red is attributable to `flutter analyze
// --fatal-infos` catching `unused_import` and nothing else.
import 'dart:convert';

String qaPr37TriggerProbe() {
  return jsonEncode(<String, String>{'probe': 'qa-pr-lint has teeth'});
}
