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

- **[2026-07-28] [process] RESULT of the split experiment above: it worked.** P2 as one PR =
  4 review rounds, 5 blockers. P3a as a spine PR = **0 FAIL, 0 merge-blocking defects**, 17/20
  ACs at full PASS; the three items QA raised were all correctly non-blocking follow-ups, not
  rework. The cost it adds is real but smaller: a separate QA PR per code PR, plus one PR
  opened and closed unused. **-> Keep splitting phases. But split by what shares code, not by
  issue count or theme — issues that rewrite the same function (e.g. the period total: currency
  conversion + credit netting + transfer exclusion) belong in ONE PR, or QA certifies a number
  three times that is wrong until the last one lands. And cap it at two PRs per phase: the
  per-PR opus QA pass + opus review pass is this build's dominant recurring cost.**

- **[2026-07-28] [process]** **The Linear/GitHub integration auto-closed KHA-64 as `Done` two
  seconds after PR #11 merged — overriding that same PR's merge commit, which said explicitly
  "KHA-64 remains In Progress" because half of it was deliberately deferred.** Nothing in Linear
  disagreed, so P3 would have closed with the ADR-017 D2 enrichment merge — the single
  highest-risk operation in the phase (R-8, the only place two records become one) — unbuilt and
  untracked. This is the KHA-22 lesson recurring through a different mechanism: last time a
  done-check was narrower than its ACs, this time an automation overwrote a human decision.
  **-> When a PR closes only PART of an issue, do not let the PR reference auto-close it: say so
  in the PR body AND re-open/re-state the issue in the same action. At every supervision turn,
  reconcile Linear state against the merge commits themselves, not against Linear alone —
  drift happens in both directions (KHA-24 was the opposite case: shipped, but still in Backlog).**

- **[2026-07-28] [process]** A manager supervision turn nearly answered "is KHA-24 built?" from
  the local working tree, which was checked out on a two-phase-old branch where the relevant
  tables do not exist at all — the confident, authoritative-looking, completely wrong answer
  would have been "not implemented". **-> Establish code state from the remote default branch
  (GitHub API) during supervision, never from the local checkout. A stale checkout is worse
  evidence than none, because it does not announce that it is stale.**

- **[2026-07-28] [qa]** Issues created *during* a QA gate or a code review (KHA-69, KHA-70,
  KHA-74) were filed correctly but with **no milestone**, so they existed in Linear and were
  invisible to the phase plan — the same "tracked nowhere" failure the PR-body lesson above was
  written to stop, one level up. **-> An issue born in review must get its milestone/phase set
  at creation, not just its owner and labels. "It has a ticket" is not the same as "it is in a
  phase".**
