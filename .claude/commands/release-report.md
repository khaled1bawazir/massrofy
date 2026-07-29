---
description: Produce the evidence-based release report — proof the build is verified and ready for human use.
---

Dispatch **qa-tester** to produce `docs/release-report.md` for the current build.
This is the no-surprises document: every claim backed by evidence, gaps stated
honestly. It must contain:

1. **What was verified, with evidence**
   - Journey table: every user journey -> RUNTIME-VERIFIED / FAILED / NOT TESTED,
     with the evidence for each (Playwright screenshot path in
     `docs/evidence/`, test log, emulator run output).
   - First-screen screenshot of web (and mobile if emulator available) embedded
     or linked. A release report without a screenshot of the running app is
     incomplete.
2. **Test results summary** — unit / contract / security-attack / E2E counts,
   pass rates, and links to CI runs.
3. **Open issues** — every unresolved Linear bug with severity. If any HIGH is
   open, the verdict below cannot be READY.
4. **What was NOT tested and why** — the honest section. Anything skipped
   (e.g. no emulator on this machine, iOS build-only) is listed explicitly.
5. **Product validation** — the product-owner UAT verdict (`PO: VALIDATED` or the open business gaps).
6. **Verdict** — `READY FOR HUMAN USE` or `NOT READY - <reasons>`. Requires PO validation and no open HIGH or business-gap issues.

Rules: no claim without evidence; screenshots are taken fresh from THIS build,
not reused. If evidence can't be produced (tool missing), say so — never fake it.
