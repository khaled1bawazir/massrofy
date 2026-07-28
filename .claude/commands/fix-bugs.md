---
description: Maintenance loop — pick up open bug issues from Linear and fix them autonomously.
---

This is the phase-2 maintenance loop. Run it whenever bugs are raised.

1. Query Linear for open issues labelled `bug` (or the label $ARGUMENTS if given)
   that are not already in progress.
2. For each bug, in priority order:
   - Reproduce it from the issue's steps. If you cannot reproduce, comment on the
     issue asking for more detail and move on.
   - Route the fix to the right specialist by area: **backend-engineer**,
     **frontend-engineer**, or **mobile-engineer**. They fix on a branch, add a
     regression test that fails before and passes after, and open a PR.
   - **qa-tester** verifies the fix, confirms the regression test covers it, and
     posts the same `QA: PASS <PR#>` / `QA: FAIL <PR#> - <defects>` verdict
     required by `/build`. No verdict, no merge — code-reviewer's rule applies
     here too.
   - **code-reviewer** checks CI is green AND the QA verdict is PASS, reviews,
     and merges. Then move the Linear issue to Done.
3. Report which bugs were fixed and merged, which need human input, and which
   couldn't be reproduced.

Guardrail: if a fix would touch security, authorization, or money-handling logic,
the code-reviewer must be extra strict and flag it in the PR summary. Never merge
a red pipeline.
