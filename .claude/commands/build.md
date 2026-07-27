---
description: Build the approved feature — implementation through staging. Autonomous. Run AFTER /design is approved.
---

Preconditions (check ALL, stop if any fails):
1. `docs/PRD.md` reads `APPROVED`.
2. `docs/architecture.md` reads `APPROVED`.
3. `docs/brand.md` reads `APPROVED` (skip if design is `N/A - no UI`).
4. `docs/design.md` reads `APPROVED` (or `N/A - no UI in this feature`).
If architecture, brand, or design is still `DRAFT`, STOP and tell the human to
approve them first (run `/design`, then approve the files).

With both gates passed, run the team autonomously in order:

1. **devops-engineer** -> create the CI pipeline (`.github/workflows/ci.yml`) and
   document branch protection FIRST, so PRs have a green-CI gate to pass.
2. Implementation (parallel where the plan allows), building against the APPROVED `docs/architecture.md`, `docs/brand.md`,
   `docs/design.md`, `docs/mockups/*.html`, and `docs/api.md`:
   - **backend-engineer** -> API + tests, `docs/api.md`, open PR.
   - **frontend-engineer** -> React UI + tests, open PR.
   - **mobile-engineer** -> Flutter UI + tests, open PR (skip if not in scope).
3. **qa-tester** -> `docs/test-plan.md`, automated tests, run them; file any defect
   as a Linear issue linked to its story.
4. **code-reviewer** -> for each open PR: verify CI is green, review, then merge or
   send back. Loop until all PRs are merged or blocked on a human decision.
5. **devops-engineer** -> deploy the merged result to staging.

Report a final summary: what shipped, what merged, what's blocked. Only stop for
the human on a genuine product decision or a production deploy approval.
