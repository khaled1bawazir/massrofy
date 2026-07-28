---
description: Build the approved feature — implementation through staging, conducted by the manager. Autonomous. Run AFTER /design is approved.
---

Preconditions (check ALL, stop if any fails):
1. `docs/PRD.md` reads `APPROVED`.
2. `docs/architecture.md` reads `APPROVED`.
3. `docs/brand.md` reads `APPROVED` (skip if design is `N/A - no UI`).
4. `docs/design.md` reads `APPROVED` (or `N/A - no UI in this feature`).
If any is still `DRAFT`, STOP and tell the human to approve first.

This build is CONDUCTED BY THE MANAGER. Between every phase, dispatch the
**manager** in supervise mode: it reads actual state (docs, PRs, CI, Linear),
updates `docs/build-plan.md` if reality diverged, resolves conflicts (especially
`docs/api.md` drift), logs status+cost to `docs/build-log.md`, and names the next
dispatch. If a previous run died mid-way, the manager resumes from evidence — do
not restart from scratch.

The phase sequence the manager conducts:
1. **devops-engineer** -> CI pipeline (`.github/workflows/ci.yml`) + branch
   protection documented FIRST.
2. Implementation (parallel where the plan allows), against the APPROVED
   `docs/architecture.md`, `docs/brand.md`, `docs/design.md`, `docs/mockups/`,
   and `docs/api.md`:
   - **backend-engineer** -> API + tests, flesh out `docs/api.md`, open PR.
   - **frontend-engineer** -> React UI + tests, open PR.
   - **mobile-engineer** -> Flutter UI + tests, open PR (skip if not in scope).
3. **qa-tester** -> per PR: run the test plan, the contract/integration stage
   (real backend), and the adversarial security pass. Verdict `QA: PASS/FAIL`
   per PR. File defects in Linear.
4. **code-reviewer** -> per PR: merge ONLY when CI is green AND QA passed.
   Otherwise send back with comments; the owning engineer fixes; QA re-verifies.
   (manager supervises this loop and breaks deadlocks.)
5. **devops-engineer** -> deploy the merged result to staging.
6. **manager** -> retrospective: append lessons learned this build (what broke,
   what was re-planned, what to do differently) to `docs/lessons.md`, and write
   the final summary: shipped, merged, blocked, open issues, approximate cost by
   phase/model.

Only stop for the human on a genuine product decision or a production deploy.
