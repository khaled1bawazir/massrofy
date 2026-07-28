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

## 2026-07-28 — Phase P3a → P3b boundary (second supervision turn)

**Supervisor:** manager (opus). **`main` at time of check:** `fd8b309` (PR #15).
**Open PRs: none.** Clean tree, nothing in review.

### What I verified from evidence, not memory

| Claim | Verified how | Result |
|---|---|---|
| P3a merged | GitHub `8e549d8` (PR #11) | ✅ KHA-23, KHA-25 landed; schema v3 adds `bank` + `instrument` |
| KHA-24 status | Read `ledger_entity_resolver.dart` + `instrument_detail_screen.dart` **on `main`**, cross-checked against QA's matrix | ❌ **Linear was stale — the work is fully shipped.** Closed as Done. See below |
| KHA-64 status | PR #11 merge commit vs. Linear | ❌ **Linear was wrong in the other direction — auto-closed.** Reopened. See below |
| KHA-26/27/28/29 | Linear | ✅ all still `Backlog`, milestone P3, correctly scoped per v1.2 |
| KHA-69 decision made? | Linear + `docs/architecture.md` | ❌ **Not made.** Still `Backlog`, still blocking KHA-53 |
| QA's Epic B pass | `docs/test-plan.md` on `main` | ✅ 20 AC rows, 17 PASS / 3 partial / **0 FAIL**; 18/18 adversarial attacks repelled |
| Issues born in review are tracked | Linear | ⚠️ **Partly.** KHA-69, KHA-70, KHA-74 existed but had **no milestone** — invisible to the phase plan. Fixed |

**A process note on my own method.** My first instinct was to answer the KHA-24 question from
the local working tree. That tree is checked out on `feature/p2-sms-ingestion-parsing` and is
two phases stale — `lib/data/db/tables/` there has no `bank_table.dart` or `instrument_table.dart`
at all, which would have produced the confident and completely wrong answer *"KHA-24 is not
implemented; neither is KHA-23."* Every code claim in this block is read from `main` via the
GitHub API instead. A stale checkout is a worse evidence source than no evidence, because it
looks authoritative.

### The two tracking corrections — opposite failure modes, same root cause

1. **KHA-24 was Done but tracked as Backlog.** All three ACs verified on `main`:
   `linkSettlementAccount` is called only when both sides resolve *and* the primary is a card
   and the settlement side is an account (AC-B14.1); the detail screen renders the linked
   account (AC-B14.2) and a deliberately neutral "not linked" (AC-B14.3). QA marks all three
   **PASS** with verbatim test names, including the `and nothing else does` corpus assertion —
   which is the half that actually prevents a guessed link, and exactly the banking-domain
   property KHA-24 was written to protect. Closed. **P3b is one issue smaller than planned.**

2. **KHA-64 was In Progress but tracked as Done.** PR #11's merge commit states outright that
   the D2 enrichment merge *"stays open for P3b, so KHA-64 remains In Progress"* — and the
   Linear/GitHub integration auto-closed it anyway, two seconds after the merge, because the PR
   was linked to it. There is no enrichment-merge implementation under `lib/features/ledger/`.
   Reopened to In Progress.

Both are the same failure at bottom: **issue state drifted from reality in whichever direction
nobody was looking.** The second one is the more dangerous, because an automation silently
overrode an explicit human decision recorded in the merge commit — and KHA-64's D2 half is the
single highest-correctness-risk item in P3 (R-8, the only place two records become one). Had
this not been caught, P3 would have closed with it unbuilt and nothing in Linear disagreeing.
New lesson recorded.

### Decision: P3b as two PRs, grouped by coupling

**The v1.2 spine-split experiment paid off, with specific evidence.** P2 as one large PR:
four review rounds, five blockers, one security-relevant. P3a as a spine PR: **zero FAIL, zero
merge-blocking defects**, and the three items QA raised were all correctly non-blocking
follow-ups rather than rework. So: keep splitting — but **two PRs, not three**, because the
per-PR opus QA pass plus opus review pass is this build's dominant recurring cost, and
fragmenting further buys review comfort at a rising price.

The seam is chosen by **what shares code**:

- **P3b-1 — "what a period total means":** KHA-27 (+KHA-70), KHA-28, KHA-29. All three rewrite
  the same function. Split apart, `period_totals.dart` is rewritten and re-QA'd three times,
  each time certifying a number that is still semantically incomplete.
- **P3b-2 — "the mutation surface":** KHA-26 (+O-QA-2), KHA-64's D2 half, KHA-66, KHA-74,
  KHA-69. Every one writes an append-only audit entry, and KHA-69 *is* the audit chain — one
  coherent `security-sensitive` review surface instead of the same invariants re-derived twice.

**Order is load-bearing, and this is the part I'd defend hardest: P3b-1 first.** KHA-26's
manual-entry form must be able to express every valid transaction — a credit, a foreign-currency
amount with rate and date, an income or internal-transfer classification. Build the form before
the type space is closed and the form and its tests get rebuilt. Concretely, O-QA-2 (a negative
amount on S-19 silently inverts direction) is routed to KHA-26's validation and **cannot be
answered correctly until KHA-28 fixes the sign convention**. Sequencing also keeps schema
versions honest: v4 in P3b-1, v5 in P3b-2, instead of two branches both claiming v4.

### The KHA-69 window — decide it now, while it is free

KHA-69 asks for a written, dated decision and offers three options in ascending honesty cost.
**Option (a) is provably correct today, and the reasoning is not the one the issue records.**
The issue guessed option (a) was "plausible" because P10 has not happened. The real argument is
stronger: KHA-75 establishes that **nobody has ever unlocked this app on real hardware**, and
the database key is provisioned *behind* that gate. No unlock → no encrypted database → no
audit rows. There is nothing on any real install to migrate.

This is worth taking now because **the window closes**: it stays true only until someone
unlocks a pre-P3a build. Recommended: record option (a), dated, in the v3 migration comment
next to ADR-010, with the standing condition that the P10 staging APK goes onto a clean install.

### Banking-domain watch items for P3b review

- **P3b-1:** NFR-A5 — summing mixed currencies without a stated conversion must be
  *unrepresentable*, not merely discouraged. AC-B9.3 — a rate must never render without a rate
  date or an explicit "date unknown" (KHA-70). KHA-28's sign convention must be identical across
  storage, aggregation and display, or totals stop reconciling (NFR-A6). R-7 — internal-transfer
  detection bootstraps from incomplete knowledge and must flag for review, never guess (AC-B11.2).
- **P3b-2:** R-8 — the D2 merge is user-confirmed only, never automatic, never removes, and the
  result stays traceable to both source messages (NFR-A6). Every mutation **including restore**
  writes an audit entry (NFR-A2). KHA-74 — a row that cannot be read must surface somewhere
  rather than vanish from totals; money silently absent is worse than money visibly wrong.

### Cost note — this phase

| Agent | Model tier | Ran |
|---|---|---|
| mobile-engineer | **opus** | P3a authoring (KHA-23, KHA-25, KHA-64 first half) → PR #11 |
| qa-tester | **opus** | P3a QA gate + Epic B traceability + 18-attack adversarial suite → PR #15 |
| code-reviewer | **opus** | PR #11, #13, #14, #15 merges |
| devops-engineer | **opus** | KHA-67 emulator deadlines → PR #14 |
| mobile-engineer *(second instance)* | **opus** | KHA-71 fix → PR #13; **KHA-75 emulator repro in flight now** |
| manager (this turn) | **opus** | Supervision only: 3 docs, ~10 Linear queries, ~10 GitHub reads. No code |

**The experiment's first result is in, and it is favourable but not free.** P3a cost one
authoring pass + one QA pass + one review round and produced zero blockers — against P2's four
review rounds on one PR. The saving is real. The cost that split PRs *add* is also now visible:
P3a needed a second QA PR (#15) of its own, and PR #12 was opened and closed before it. Net,
still clearly ahead. Worth re-measuring after P3b-1, when the comparison is two similar-sized
behaviour PRs rather than spine-vs-monolith.

Separately: **five of the last six merged PRs were CI, process or real-device bug fixes, not
product code.** That is the honest shape of this phase.

### Next dispatch

**mobile-engineer (opus) → P3b-1: KHA-27 (+KHA-70), KHA-28, KHA-29**, branched off `main` @
`fd8b309`, one PR, landing schema **v4**. Then qa-tester for an explicit `QA: PASS`/`FAIL`
including Epic B rows for AC-B7.x, AC-B9.x, AC-B10.x and AC-B11.x, then code-reviewer to merge
on green CI + `QA: PASS`. P3b-2 follows on the merged result.

This runs **in parallel with the KHA-75 diagnosis** already in flight. The two are file-disjoint
— KHA-75 lives in `lib/features/security/`, `DbMasterKeyStore` and `KeystoreChannel.kt`, while
P3b-1 lives in `lib/features/ledger/` and `lib/data/` — so this is one of the few genuine
parallel windows in a build that R-9 says is otherwise single-lane. **KHA-75 keeps priority
if the two ever contend:** P3b builds domain model above a gate no human has passed (R-14).

---
