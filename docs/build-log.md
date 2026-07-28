# Massrofy — Build Log

Append-only status log. The **manager** writes one block per supervision turn during
`/build`: what was verified from evidence, what changed in `docs/build-plan.md`, the next
dispatch, and a cost note so the human can learn this product's per-feature economics.

Plan lives in `docs/build-plan.md`. Issue state lives in Linear. This file is the narrative
of what actually happened, including the parts that went sideways.

---

## 2026-07-28 — Phase P3 entry (first supervision turn under team v2)

**Supervisor:** manager (opus). **`main` at time of check:** `6a835f8`.

### What I verified from evidence, not memory

| Claim | Verified how | Result |
|---|---|---|
| P1 merged | GitHub PR #1 → `9d1487c` | ✅ merged 2026-07-27 23:03 after 3 review rounds |
| P2 merged | GitHub PR #2 → `67f1dfd` | ✅ merged 2026-07-28 13:23 after **4** review rounds, 5 blockers incl. security-relevant B5 (dedup HMAC key reused the audit-chain root key with no domain separation) |
| P3 blockers closed | Linear KHA-19, KHA-14 | ✅ both `Done` — P3 is genuinely unblocked |
| P3 issues ready | Linear KHA-23…29 | ✅ all `Backlog`, milestone P3, `owner-mobile-engineer`, `epic-B` |
| Nothing else in flight that P3 conflicts with | GitHub PRs, all states | ⚠️ **PR #6 is open** — but docs-only (`README.md`, 1 file), zero overlap with `lib/`. No conflict. |
| Build plan still matches reality | `docs/build-plan.md` vs. above | ❌ **diverged in six places** — corrected, see below |

### What the briefing said vs. what I found

The briefing described PRs #1, #2 and #4. Reality has **eight** PRs: #3 closed unmerged
(superseded), #5 merged team-v2 process, #7 and #8 merged CI fixes for emulator flakiness
(KHA-62), and **#6 still open**. The build has been busier than the plan recorded.

### Findings that changed the plan

1. **P3 was missing two inherited work items — the significant find.** PR #2 shipped
   S-19 / AC-A4.2 (complete an unparsed SMS) and ADR-017 D2's enrichment merge as
   **callbacks with no implementation**, deferring both to P3 because they must write a full
   `Transaction`. Neither was in KHA-23…29. As written, P3 would have closed with Epic A's
   review queue half-functional. Created **KHA-64** (blocked by KHA-23, KHA-25).
   Note honestly: **KHA-22 is `Done` while AC-A4.2 is not actually shipped.** The closure is
   defensible on KHA-22's own done-check, but the gap was living only in a PR body.
2. **An agreed follow-up had no ticket.** Code-reviewer's merge commit for PR #4 says
   mobile-engineer owes an AC-A4.3 DAO-level regression test "before P3 closes". It existed
   nowhere in Linear. Created **KHA-66**.
3. **§2.1's backend question is settled** and the plan still called it open. ADR-001 chose
   no backend, CI-enforced by `check_no_network_permission.sh` against a real release
   manifest. backend-engineer and frontend-engineer are **permanently** out of scope on this
   product, P8 included. Recorded as resolved; the `owner-backend-engineer-CONDITIONAL`
   label is now dead.
4. **The issue index was stale** — it claimed KHA-5…53 / 49 issues. Review, QA and CI have
   since created KHA-54, 55, 58, 62, 64, 66. Linear is now stated as the source of truth.
5. **The team-v2 QA merge gate wasn't in the plan.** QA now returns `QA: PASS`/`QA: FAIL` and
   code-reviewer refuses to merge without it. Every P3+ PR routes
   engineer → qa → code-reviewer. Also recorded: `docs/test-plan.md` covers Epic 0 + A only,
   so **P3's QA pass owes Epic B traceability rows**.
6. **New risk R-12 — the P0 device spike (KHA-7) was never run.** See escalation below.

### Escalation to the human (not blocking P3)

**KHA-7, the background-SMS latency spike, is still in Backlog with no recorded outcome.**
§P0 called it "not optional" and P0's exit check only enforced the doc approvals, so it slipped
through. P1 and P2 both shipped on its unverified assumptions, and PR #2's own "Honest limits"
section says so plainly. **It is the one task no agent can do** — it needs the user's real
phone and real OEM.

Bounded, not alarming: if the broadcast is suppressed on the target device, ADR-006's fix is a
*default* change (Layer 3 becomes default-on), not a redesign. And ADR-018 has already
renegotiated NFR-R1 downward for an unrelated reason (the app lock), flagged as H-13. But it
compounds — every phase adds code above an unverified assumption. Logged as **R-12**, routed
to close at P10 at the latest. **KHA-58** (`ingest.skipped.locked`) is a partial substitute
and worth doing regardless.

### Decision

**Dispatch mobile-engineer for P3, split across two PRs**, rather than one.

P3 is now 9 issues / ~40 points — the largest single-agent phase in the build. P2 went to four
review rounds as one large PR. R-9 (single-implementer bottleneck) says keep PRs small so
review doesn't become a queue, and repeating P2's shape at greater size is a predictable
mistake.

- **P3a — the spine:** KHA-23 (bank/instrument hierarchy) + KHA-25 (transaction record).
  Everything in Epic B blocks on these two, and P4/P5 build against them.
- **P3b — behaviours:** KHA-24, 26, 27, 28, 29, 64, 66.

No parallel engineer this phase. ADR-001 means there is no backend and no web surface, so
frontend-engineer and backend-engineer are correctly not dispatched — this is a single-lane
phase by architecture, not by scheduling.

**Banking-domain watch items for P3a/P3b review:** KHA-64's enrichment merge is the only
operation in the product where two records become one (R-8 — never auto-remove, keep it
user-confirmed, stay traceable to both source messages); every mutation in KHA-26 must write
an append-only audit entry including restore (NFR-A2); KHA-27 must make summing mixed
currencies without a stated conversion impossible rather than merely discouraged (NFR-A5);
KHA-23's entity resolution must work on **masked** identifiers, since NFR-S2 means last-4 is
all that is stored.

### Cost note — this phase

| Agent | Model tier | Ran |
|---|---|---|
| manager (this turn) | **opus** | Supervision only: read 2 docs, ~12 Linear queries, ~6 GitHub queries; wrote 2 docs, created 2 Linear issues. No code. |

Cheap turn — no engineering agent ran. For context on where this build's cost actually goes:
P1 and P2 were each **one opus code-reviewer pass per round × 3 and 4 rounds**, which has
been the dominant recurring cost, not the authoring. Both were written by engineers on
**sonnet**; all engineers moved to **opus** in PR #5 after review caught a security-relevant
defect (B5) in engineer-authored code, so P3 is the **first phase authored on opus**. The
split-PR recommendation should be watched for its effect here: two smaller PRs may cost fewer
total review rounds than one large one, or may cost more in fixed per-PR overhead. P3 is the
experiment that tells us which.

### Next dispatch

**mobile-engineer (opus) → P3a: KHA-23 + KHA-25**, branch off `main` @ `6a835f8`, one PR.
Then qa-tester for a `QA: PASS`/`FAIL` verdict incl. Epic B traceability rows, then
code-reviewer to merge on green CI + `QA: PASS`. P3b follows on the merged spine.

*(Separately, and not part of the P3 dispatch: **PR #6 is open and unmerged**. Its CI was
blocked by the emulator flakiness that PR #8 has since fixed — the emulator job now
path-filters out on a docs-only diff and passed in 15s on the 15:04 re-run. It needs
code-reviewer, not an engineer. Manager does not merge.)*

---
