// QA probe for PR #37 / KHA-108 — THROWAWAY, deleted with this branch.
//
// This file is written exactly as `dart format` emits it and contains exactly
// ONE defect: an unused import. So if `.github/workflows/qa-pr-lint.yml`
// really runs `flutter analyze --fatal-infos`, this PR must go RED on
// `unused_import`. A green check would mean the workflow's lint steps are
// being skipped and the check is green because it checked nothing.
import 'dart:convert';

String qaPr37TriggerProbe() {
  return 'qa-pr-lint has teeth';
}
