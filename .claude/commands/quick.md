---
description: Fast lane for small changes — one engineer, smoke check, merge. No PRD/design cycle.
---

Small change requested:

$ARGUMENTS

1. **manager** -> sanity-size it. If this actually changes product behaviour,
   data model, or security, STOP and say it needs /kickoff instead. Otherwise
   pick the one owning engineer and define the "done" check. One Linear issue,
   no milestones/blocking ceremony.
2. Owning engineer -> implement on a branch with the relevant test updated,
   self-review, open PR.
3. **qa-tester** -> smoke-check ONLY the affected journey (run it, screenshot if
   UI). Verdict `QA: PASS/FAIL`.
4. **code-reviewer** -> merge on green CI + QA PASS.

Whole lane targets a single round. If it bounces twice, escalate to the human —
it wasn't a quick change.
