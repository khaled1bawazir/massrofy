---
description: Build the approved feature — implementation through staging, conducted by the manager. Autonomous. Run AFTER /design is approved.
---

Preconditions (check ALL, stop if any fails):
1. `docs/PRD.md` reads `APPROVED`.
2. `docs/architecture.md` reads `APPROVED`.
3. `docs/brand.md` reads `APPROVED` (skip if design is `N/A - no UI`).
4. `docs/design.md` reads `APPROVED` (or `N/A - no UI in this feature`).
If any is still `DRAFT`, STOP and tell the human to approve first.

Read the TIER from `docs/PRD.md` first — it calibrates everything below
(personal: short docs, ~5-10 QA probes, one review round, minimal Linear
ceremony, short build-log entries).

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
3. THE FEATURE LOOP — run this for EVERY feature/story, in the same session:
   a. **qa-tester** -> test the feature properly: automated tests, the
      contract/integration stage (real backend), the security pass, AND actually
      run the feature like a user. File EVERY problem found as a Linear issue
      labelled `bug` with repro steps, expected vs actual, and severity. Verdict
      `QA: PASS/FAIL` per PR.
   b. If issues were raised: **manager** -> triage each issue and ASSIGN it to
      the owning engineer (backend/frontend/mobile) in Linear, with priority
      order. Note the assignment in `docs/build-log.md`.
   c. Assigned engineer(s) -> fix on the same branch/PR with a regression test
      per fix. Move the issue to In Review.
   d. **qa-tester** -> re-verify each fixed issue (run it again, not just read
      the code). Close verified issues; reopen failed ones.
   e. Repeat b-d until QA passes, MAX 3 ROUNDS. If issues survive 3 rounds,
      STOP that feature and escalate to the human with a summary of what's
      stuck and why.
4. **code-reviewer** -> per PR: merge ONLY when CI is green AND QA's verdict is
   PASS with no open bug issues on the feature. Otherwise back to the loop.
   (manager supervises and breaks deadlocks.)
5. **qa-tester** -> RUNTIME JOURNEY VERIFICATION on the integrated build: boot
   the real stack and walk every PRD journey as a user (first screen renders,
   core flows work, no boot errors). Verdict `QA: RUNTIME PASS/FAIL`. On FAIL,
   file the defects and route back to the owning engineer via the manager — do
   NOT proceed to staging.
6. **product-owner** -> PRODUCT VALIDATION (UAT): use the verified build against
   the PRD's problem statement with realistic scenarios (see its Mode 2).
   Business gaps -> `business-gap` Linear issues -> manager triages: spec fixes
   go back through the loop; genuine scope changes escalate to the human.
   Verdict `PO: VALIDATED` required before release.
7. **devops-engineer** -> deploy to staging, then run the post-deploy smoke
   check against live staging.
8. **qa-tester** -> produce `docs/release-report.md` (see /release-report):
   journey table with evidence, fresh first-screen screenshots in
   `docs/evidence/`, open issues, what was NOT tested, and the verdict
   `READY FOR HUMAN USE` or `NOT READY`. The build is not "done" without it.
9. **manager** -> retrospective: append lessons learned this build (what broke,
   what was re-planned, what to do differently) to `docs/lessons.md`, and write
   the final summary: shipped, merged, blocked, open issues, approximate cost by
   phase/model.

Only stop for the human on a genuine product decision or a production deploy.
