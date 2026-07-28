# Team lessons (compounding memory)

The manager appends a short entry after every /build retrospective. Agents read
this file at the start of their work. Keep entries short and actionable; prune
stale ones occasionally.

Format per entry:
- [date] [area: backend/frontend/mobile/qa/design/process] lesson -> what to do differently

---

- **[2026-07-28] [process]** A phase exit check that only names *documents* lets non-document
  work in that phase slip silently. P0 required both gate-2 docs APPROVED **and** the KHA-7
  device spike ("not optional"), but only the doc half was enforceable, so P0 "closed" with
  the spike unrun — and P1 and P2 then both shipped on its unverified assumptions (now risk
  R-12). **-> Every phase exit check must enumerate all its artifacts, and any item that
  needs a human or physical device must be escalated the moment its phase closes without it,
  not discovered three phases later.**

- **[2026-07-28] [process]** Work deferred inside a PR body does not exist. PR #2 clearly
  disclosed that S-19/AC-A4.2 and ADR-017 D2 were shipped as callbacks for P3 to implement,
  and PR #4's review said mobile-engineer owed an AC-A4.3 test "before P3 closes" — none of
  it had a Linear issue, so P3 was planned without it and would have closed with Epic A
  half-functional. Caught at supervision; became KHA-64 and KHA-66. **-> An engineer
  deferring work, or a reviewer naming a follow-up, must create the Linear issue in the same
  action. "Documented in the PR" is not tracking.** (code-reviewer already does this well —
  KHA-58 was split out for exactly this reason. Make it universal.)

- **[2026-07-28] [qa]** A closed issue can hide unshipped acceptance criteria when the
  issue's done-check is narrower than the ACs it claims to cover. KHA-22 is `Done` and its
  own done-check genuinely passes, but AC-A4.2 within it is not implemented. **-> QA should
  verify closure against the PRD's ACs, not against the issue's own done-check, and the
  traceability matrix is the tool that catches this.**

- **[2026-07-28] [mobile]** Large single-phase PRs are expensive to review: P2 took four
  rounds and five blockers, one security-relevant. **-> Split a phase into a "spine" PR
  (the entities everything else blocks on) and a "behaviours" PR. Being trialled on P3.**
