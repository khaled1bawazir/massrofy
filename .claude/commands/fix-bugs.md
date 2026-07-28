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
   - **qa-tester** verifies the fix and confirms the regression test covers it.
   - **code-reviewer** merges ONLY with green CI AND an explicit `QA: PASS`
     verdict for the fix. No verdict, or a FAIL -> no merge; back to the
     engineer. Then move the Linear issue to Done.
3. Bound the loop: if a bug survives 3 fix->verify rounds, stop and escalate it
   to the human instead of thrashing.
4. Report which bugs were fixed and merged, which need human input, and which
   couldn't be reproduced.

Guardrail: if a fix touches security or authorization logic, the code-reviewer
must be extra strict and flag it in the PR summary. Never merge a red pipeline.
