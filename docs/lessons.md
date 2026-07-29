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

- **[2026-07-29] [process]** Human feedback, worth carrying forward as-is: **the phase order
  (P1 foundation -> P2 ingestion -> P3 domain model -> ... -> P5 UI) is architecturally correct
  — each phase genuinely needs the one before it — but it is strictly horizontal (one layer,
  fully, before the next), so nothing a human can actually see or use exists until P5. By the
  end of P3b, the team had shipped real money math, multi-currency, refunds, entity resolution,
  two real-device security fixes, and 800+ passing tests — and the app still only ever showed a
  lock screen and a literal placeholder screen, because nothing had wired a UI to any of it yet.
  The work was real; it did not *feel* real, and the only way to check progress was reading
  build-log/test-plan rather than using the thing. **-> For the next product built this way,
  plan one thin end-to-end vertical slice early (e.g. right after P1's foundation: one screen,
  one real data path, deliberately minimal) alongside the horizontal phases, purely so there is
  something a human can open and see working before the *entire* domain model is done. This is
  a planning/sequencing change for `docs/build-plan.md`'s next `/kickoff`, not a P3b-2 change —
  P3b-2 keeps building on the existing plan. Revisit when scoping the next project's phase 0.**

- **[2026-07-29] [process]** A gate result is only evidence for the exact tree it was measured
  on, twice now. First, a CI-timing claim was derived from summed background-`sleep` durations
  instead of measured elapsed time, and reopened an Urgent issue on a hang that never happened
  (PR #16). Second, `QA: PASS 20`'s "format clean (181 files, 0 changed)" was true of PR #20's
  branch and was then read as if it also covered PR #22's branch, which added two files the
  claim never saw — CI caught it, but only because it re-runs the gate; a human skimming the
  verdict would not have. **-> Any pass/fail claim (test count, format-clean, "N files changed")
  must name the commit SHA it was measured on, and a reviewer must re-run the gate on the
  CURRENT head rather than citing an earlier verdict — a stale-but-true-when-written claim is
  indistinguishable from a fabricated one to whoever reads it later.**

- **[2026-07-29] [process] The conditional merge gate is a genuinely good invention — give it a
  home outside the merge commit.** Shipping PR #20 with two known High defects was the right call
  and code-reviewer defended it properly: it verified that *no shipped code path can reach them*
  (the app shell routes only to `HomePlaceholderScreen`) and wrote an explicit condition —
  "KHA-87/88 are merge-blocking for any PR that routes `NeedsReviewScreen`,
  `RecentlyDeletedScreen` or `TransactionDetailScreen`, and for any build that reaches a device."
  That is better than either shipping silently or blocking on an unreachable bug. **But the gate
  lived only in a merge-commit message**, where nothing enforces it and nobody re-reads it — and
  it turned out to bisect the very next phase, because P4's AC-C2.2 and AC-C4.1/4.2 cannot be met
  without routing two of the three named screens. **-> When a reviewer ships a known defect under
  a condition, the condition must become a `blocks` link in the tracker on the issues it gates, in
  the same action as the merge. A gate that exists only in prose is a gate that depends on the
  next person having read the right commit.** (Generalises: "unreachable today" is a claim about
  *navigation*, not about code — it expires the moment someone adds a route, silently.)

- **[2026-07-29] [qa] Four QA artifact PRs in a row have needed manual rebase/cherry-pick rescue,
  and the cause is the branch topology, not carelessness.** PR #12 was opened and closed unused;
  #15 needed its own pass; #19 needed conflict resolution in `docs/defects.md`; **#21 was orphaned
  outright** — it was retargeted to `main` when PR #20 squash-merged and deleted its base branch,
  and had to be replaced by #22 with a cherry-pick. Each rescue was ad-hoc orchestrator cleanup.
  The root cause: QA's artifacts are authored *against the code branch* (the probes must compile
  against the code under test) but the PR is opened *against `main`*, so a squash-merge of the
  code PR deletes the ground the QA PR was standing on. **-> Open the QA artifact PR with the
  CODE BRANCH as its base, and merge it into that branch before the code PR merges.** One base
  that still exists, one final merge to `main`, no orphan. The "zero production diff" property QA
  rightly insists on is preserved as a *commit* boundary instead of a *PR* boundary — still fully
  verifiable by tree hash, which is how QA has been proving it anyway.

- **[2026-07-29] [process] The "issue born in review has no milestone" lesson recurred within 24
  hours of being written — so the reminder is not the fix.** KHA-87 and KHA-88 were created during
  PR #20's QA gate with owner, labels, severity and superb reproductions, and **no milestone** —
  exactly the 2026-07-28 finding about KHA-69/70/74. They were High, `security-sensitive`, and
  gating the next phase, and they were invisible to the phase plan. A rule that a busy agent must
  remember mid-gate has now failed twice. **-> Stop treating it as an authoring rule and make it a
  standing reconciliation step: at every supervision turn, the manager queries Linear for issues
  with no milestone and files them before doing anything else. Authoring discipline is still
  requested, but the manager is the backstop and should assume the rule was missed.**
