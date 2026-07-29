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

## 2026-07-29 — Phase P4 entry (P3 closed; P3b-3 inserted ahead of it)

**Supervisor:** manager (opus). **`main` at time of check:** `4f49513`.

**Note on this file:** the P3b-1 → P3b-2 turn was never logged here — the previous entry is the
P3a→P3b turn and the next thing that happened was two merged PRs. This entry covers both
outcomes so the narrative has no hole. That gap is itself a small process finding: a supervision
turn that dispatches without appending leaves the log claiming an older reality than Linear does.

### What I verified from evidence, not memory

| Claim | Verified how | Result |
|---|---|---|
| P3b-1 merged | GitHub `main` history → `ad9d95a` (PR #18) | ✅ schema v4; KHA-27/28/29/70; CI 6/6; `QA: PASS 18` at `3ba320d` |
| P3b-2 merged | GitHub `main` history → `c7be7a0` (PR #20) | ✅ schema v5; KHA-26/64/66/69/74/78/79/80; CI 6/6 incl. emulator; `QA: PASS 20` |
| KHA-75 actually fixed | `56e9cbe` (PR #17) merge commit | ✅ root cause was a Kotlin/Flutter byte-encoding mismatch in `KeystoreChannel`, **not** an OEM/TEE fault. Four unlock journeys verified on real API-35 hardware. **R-14's premise is retired.** |
| KHA-69 recorded | build-plan §7.3 row 8 + architecture.md | ✅ option (a), dated 2026-07-29. Last non-code artifact of the P3b exit check. KHA-53/P10 unblocked |
| KHA-87/88 state | Linear `get_issue` | ⚠️ Backlog, High, `security-sensitive` — **and no milestone at all** |
| Other issues born in the same gate | Linear `get_issue` KHA-89, KHA-90 | ⚠️ **also milestone-less — 4 of 4 from the PR #20 gate.** And KHA-89 shares KHA-87's root cause in the same two files, so it joins P3b-3; KHA-90's O-QA-8 (one-tap merge, no dialog) turns out to be a P4b requirement |
| The three gated screens exist | GitHub `lib/presentation/screens/` @ `4f49513` | ⚠️ **all three are already on `main`** — `needs_review_screen.dart` (23.9 KB), `recently_deleted_screen.dart` (6.7 KB), `transaction_detail_screen.dart` (27.3 KB). Only the *route* is missing |
| KHA-30 blocked on design | `docs/design.md` §4 | ✅ **not blocked** — 13 categories resolved (OQ-18/D-2), incl. Loan & Installments and Fees & Charges |
| KHA-32 blocked on the architect | `docs/architecture.md` ADR-008 | ✅ **not blocked** — A-7 answered; `autoApplyThreshold` is a named constant, initial 0.85, and the ADR says the value is a build-phase tuning parameter. Label removed |

### The finding that shaped this phase: the gate bisects P4, and P4's own ACs walk into it

code-reviewer's PR #20 merge commit records a binding gate: *"KHA-87 and KHA-88 are
merge-blocking for any PR that routes `NeedsReviewScreen`, `RecentlyDeletedScreen` or
`TransactionDetailScreen`, and for any build that reaches a device."*

The briefing asked whether that touches P4, on the reasoning that P4 is categorization, not those
screens. **It does, and not marginally — it cuts P4 in half.** Two independent ACs force it:

- **AC-C2.2** requires the correction to complete "without leaving the transaction context, in no
  more than two screens". design.md §6 implements exactly that as a chip tap on **S-11 Transaction
  Detail** opening the `CategoryPicker` sheet — 2 taps, 0 screen changes. You cannot satisfy
  "without leaving the transaction context" without a transaction context. **KHA-33 routes
  `TransactionDetailScreen`.**
- **AC-C4.1/4.2** put the needs-review indicator and count in front of the user; design.md §S-18
  lands them as the **Low-confidence tab** of the existing Needs Review Inbox. **KHA-32 routes
  `NeedsReviewScreen`.**

Worth stating plainly because it is the interesting part: the gate's line and a spine/behaviours
split line **fall in the same place**. KHA-30/31 are pure data and domain with no navigation;
KHA-32/33/34 are the surface. The seam is over-determined — two independent arguments pick it —
which is the strongest form of evidence a sequencing decision gets. Take it and stop deliberating.

KHA-87's own text agrees, in QA's words: *"It must not survive into P4, and it must be fixed
before any build reaches a device."*

### Decision: P3b-3 → P4a → P4b

**P3b-3 (new)** — KHA-87 + KHA-88, one small PR, P3's debt rather than P4 fragmenting. Scheduled
ahead of P4a, not after it, for four reasons in descending weight: (1) it gates P4b; (2)
`transaction_dao.dart` is quiet now and P4a will touch the same file for AC-C3.3's
delete-with-reassign — fix the DAO before a categorization rewrite lands on top of it; (3) schema
numbering: KHA-88's fix *may* need a table (if `merged_from_transaction_id` becomes a set), so let
it take v6 if it needs it and give **P4a v7 unconditionally** — a gap in the sequence is cheaper
than a collision and a renumber; (4) the QA pass is the cheapest in the build, because both
done-checks say *invert* the existing probes (A1/A2, B2/B3/B4/B6, F6) rather than author a new
adversarial surface. Cheapest gate, unblocks the most.

**P4a — the spine.** KHA-30 + KHA-31. Schema v7. Not gated, no navigation. KHA-31 is where the
genuine intellectual risk lives (R-5, cross-script matching), and it deserves a QA pass looking
only at matching correctness with no UI in the frame.

**P4b — the surface.** KHA-32 + KHA-33 + KHA-34. Gated. Grouped because all three write audit
entries over the same store — KHA-33's corrections and undos, KHA-34's bulk historical re-apply
(one entry *per affected transaction*, AC-D4.4) — so one `security-sensitive` reviewer pass covers
one audit surface, exactly as P3b-2 was grouped. Splitting KHA-34 out would buy a third opus
QA + review pass for a screen sharing both the store and the invariants.

**P4 is still two PRs.** The v1.3 cap holds; P3b-3 is P3 paying its debt.

Sequential, not parallel: P4a is file-disjoint from P3b-3 and ungated, but R-9's single
mobile-engineer lane makes "parallel" fiction here. Sequence it and take the clean DAO.

### Cross-engineer conflicts

None. There is one implementer lane and no open contract change since P3b-2 — `docs/api.md` does
not exist in this product (ADR-001: no backend, no API surface), so the usual frontend/mobile
contract-drift risk cannot arise here.

### What changed in the plan

`docs/build-plan.md` → **v1.4**: P3 marked complete with its two open defects named; **P3b-3**
inserted as a new phase section; P4 rewritten with the forced split, the two "already answered"
inputs, the gate analysis and six banking-domain watch items; **R-15** added (High defects held
safe only by absent navigation); §4 gains the `P3b-3 → P4b` sequential edge; §7.3 rows 5, 7 and 8
updated (KHA-7 should now wait for P3b-3 and then run; KHA-75 fixed; KHA-69 done) and a new row 9
recording that **nothing is asked of the human for P4**.

Linear: KHA-87 and KHA-88 given the **P4 milestone** (they had none) and blocking links to KHA-32
and KHA-33, so the gate is enforced by the tracker rather than by a merge commit nobody re-reads.
KHA-32's stale `needs-architecture-decision` label removed with a comment citing ADR-008's
threshold, so the engineer does not re-derive a confidence model.

### Cost note — this phase

| Agent | Model tier | Ran |
|---|---|---|
| mobile-engineer | **opus** | P3b-1 (PR #18) and P3b-2 (PR #20) authoring; KHA-75 fix (PR #17) |
| qa-tester | **opus** | Three gates: 11-probe suite on PR #18, **37-probe** merge-focused suite on PR #20 (PR #22), plus real-device runtime verification on PR #17 |
| code-reviewer | **opus** | PR #17, #18, #20, #22 merges; two rounds on #22 |
| manager (this turn) | **opus** | Supervision only: 4 docs read, 8 Linear calls, 4 GitHub reads, 1 docs PR. No code |

**Two economics observations.** First, the split is still paying: P3b-1 and P3b-2 each merged
without a rework round, against P2's four. Second, and newly visible — **QA is now the most
expensive agent in the build, not the engineer.** PR #20's gate produced 37 adversarial probes and
found both High defects that shape this entire phase; that is the pass earning its cost. But it
means P3b-3's *cheap* QA pass (invert existing probes) is a genuine saving worth sequencing for,
which is reason (4) above.

### Next dispatch

**mobile-engineer (opus) → P3b-3: KHA-87 + KHA-88 + KHA-89 + KHA-90's O-QA-5/O-QA-7**, branched
off `main` @ `4f49513`, one PR.

KHA-89 joined on evidence: its D-QA-10 is the same root cause as KHA-87 — `MergePlan.between`'s
refusal set covers amount, currency, direction and type and nothing else, which is why money
columns vanish (KHA-87) *and* why a user's correction on the losing row is discarded for the
parser's value (D-QA-10). One fix to that set answers both; splitting them buys two engineer
passes and two QA passes over one function. Applying the new milestone-sweep lesson is what
surfaced it — a good early return on that lesson.

Prefer KHA-87 fix option (b) — add the money-bearing columns to `MergePlan.between`'s refusal set
— unless the engineer argues otherwise on evidence; it matches that file's own stated principle
and it cannot lose money, only decline to merge. Invert the existing probes rather than delete
them. Take schema **v6 only if needed**; **P4a takes v7 regardless.** Then qa-tester for an
explicit `QA: PASS`/`FAIL`, then code-reviewer to merge on green CI + `QA: PASS`.

P4a (KHA-30 + KHA-31) follows on the merged result. **P4b does not start until KHA-87 and KHA-88
are closed** — that is now enforced by Linear blocking links, not just by a merge commit.

---

## 2026-07-29 — Phase P4a → P4b boundary (fourth supervision turn)

**Supervisor:** manager (opus). **`main` at time of check:** `ad5688a`. **Open PRs: none.**

**Working-tree warning, recorded because it nearly mattered.** The local checkout is on
`feature/p2-sms-ingestion-parsing`, two phases stale, and its `docs/defects.md` and `docs/lessons.md`
are missing the PR #27/#28/#29 content. Per the 2026-07-28 lesson, code and issue state were taken
from the GitHub API and Linear, never from the checkout. Before editing `docs/build-plan.md` and
`docs/build-log.md` I confirmed via `list_commits --path` that both files were last touched on
`main` by `a4791d4` (PR #23) — i.e. the local copies of *these two files specifically* are current
even though neighbouring files are not. That check is the only reason editing them here is safe.

### What I verified from evidence, not memory

| Claim | Verified how | Result |
|---|---|---|
| P3b-3 merged | GitHub `main` → `81b1147` (PR #24) | ✅ `QA: PASS 24`, CI 6/6, 1040 tests passing |
| P4a merged | GitHub `main` → `42db8ff` (PR #27) | ✅ schema v7, `QA: PASS 27`, CI re-run 6/6 on post-QA-merge head `c9715a5` |
| KHA-87 closed | Linear `stateHistory` | ✅ Done 07:52:44. QA re-verified by execution: `report.fees.base` stays `9.2`, `report.spend.base` stays `150` |
| KHA-88 closed | Linear `stateHistory` | ❌ **Open.** Done 07:52:44 → **Backlog 07:53:49**. Auto-closed by the merge, reopened 65 seconds later. The KHA-64 failure mode, caught in a minute instead of a phase |
| KHA-88's remaining scope | KHA-94 body + PR #24 merge commit | ⚠️ **Larger than PR #24 states**, and QA says so explicitly. The single-scalar link is now the **input to a safety guard** |
| KHA-94 state | Linear `get_issue` | ⬜ Backlog, **High**, `blocks` KHA-32 + KHA-33 |
| KHA-98 state | Linear `get_issue` | ⬜ Backlog, **High**, `needs-architecture-decision`, `owner-solution-architect`, `blocks` KHA-32/33/97 |
| KHA-98 needs an ADR, or is it engineer-fixable? | `docs/architecture.md` ADR-008 text quoted in the issue | 🔴 **Needs the ADR.** The noise list including **"city names"** is what ADR-008 mandates; QA's preferred fix is to delete it |
| A reviewer gate exists beyond Linear | PR #24 merge commit body | ⚠️ **Yes, and it was prose only:** *"KHA-94 and KHA-96's O-QA-11 must be closed BEFORE P4b code starts."* Now promoted to `blocks` links |
| Is any P4 work genuinely unblocked? | KHA-34 `blockedBy` | ⚠️ **KHA-34 was link-unblocked** — its only blocker, KHA-31, is closed. Substantively it is not. Corrected (see below) |
| Milestone sweep (standing rule) | Linear KHA-98…105, KHA-92…96 | ✅ **All clean.** Every one of the eight P4a QA issues carried the P4 milestone at creation — **the first gate where the manager did not have to backstop that rule** |

### The finding that shaped this phase: the gate grew, and one of its members is a defect in an approved ADR

v1.4 planned P4b behind a **two-issue** gate (KHA-87, KHA-88). It is now **seven**: KHA-88, KHA-94,
KHA-96, KHA-98, KHA-99, KHA-101, KHA-102. Only one of the original two has closed.

That is not plan decay — six of the seven were created *by the QA gates of the two PRs that merged
since*, which is the design working. What matters is the character of the newcomers.

**KHA-98 is the one that changes how this phase is staffed.** `MerchantKey.of('MAKKAH BAKERY')` and
`MerchantKey.of('MADINAH BAKERY')` both return `'BAKERY'`, and the resulting match lands at **T1,
confidence 1.00** — above every tier gate, above any value `autoApplyThreshold` could take. It is
unreachable by tuning because it is not a matching-confidence bug at all; it is a *deterministic key
collision manufactured by normalisation*. And the normalisation it is manufactured by is the one
ADR-008 mandates in its own words: strip *"a configurable noise-token list (`BRANCH`, `STORE`,
`FRC`, **city names**, terminal ids)"*.

So the engineer did what the approved architecture said, and the approved architecture was wrong for
an ordinary Saudi retail naming shape. **That is an ADR amendment, not a patch**, and it is why
KHA-98 already carries `needs-architecture-decision` + `owner-solution-architect` — I am confirming
that routing, not inventing it.

Two further reasons the architect goes first, both found this turn rather than inherited:

- **It is one question wearing three costumes.** KHA-98 (city tokens), KHA-99 (unbounded
  trailing-digit stripping — QA's own note: *"same family as KHA-98 — a decision on one should
  settle the other"*) and KHA-102 (`'***'` forming a usable key) all ask: **when may normalisation
  assert that two different raw strings are the same business?** ADR-008 answers "whenever the strip
  rules fire", with no corroboration requirement. Three engineer patches = three local answers and a
  fourth case next phase.
- **R-17, and it is time-boxed.** `merchant.merchant_key` is `UNIQUE` and *is* the identity, and P4a
  wired the categorizer into ingestion — so changing `MerchantKey` re-keys rows. Today **no install
  carries a `merchant` row**: R-15's gate blocks any device build while KHA-88 is open, and KHA-7 has
  never run. The architect can therefore take "no migration, clean install" **provably**, exactly as
  KHA-69's option (a) was taken on this same day. Miss the window and it becomes a migration that
  cannot be computed from the data it is migrating, because the correct grouping is precisely what
  was wrong.

### Decision: P4a-1 — one PR, architect first, engineer second

**Not P4b.** Six of seven gates are open, and two of them (KHA-98, KHA-94) are High.

**Not KHA-34 either, even though its links said yes.** The learned-rules screen was startable by
`blockedBy` alone — KHA-31 is closed and nothing else was linked. It must not start: it lists and
bulk-re-applies rules keyed on the identity KHA-98/99/102 are about to redefine, and AC-D4.4's
"re-apply to history" over a collapsed identity would rewrite categories across two unrelated
businesses **and write one audit entry per transaction attesting to it**. Building it now buys
rework of the screen, its tests, and its audit assertions. `blocks KHA-34` added from KHA-98, KHA-99,
KHA-102, KHA-94 and KHA-96 so the tracker says what the reasoning says.

**One PR, not two**, despite the two clusters being file-disjoint (identity: `merchant_key.dart`,
`categorization_service.dart` · merge/undo: `transaction_merge.dart`, `transaction_dao.dart`).
Splitting buys a second opus QA pass and a second opus review pass — which this log has now twice
identified as the dominant recurring cost — to separate two clusters no reviewer will confuse. Both
also need the *same cheap* verification: **invert probes already authored** (PROBE B/C/G2/U from
`qa_pr27_probe_test.dart`; J1/K1 from `qa_pr24_probe_test.dart`), not a new adversarial surface.
The two-PR cap holds: P4 is still P4a + P4b, and P4a-1 is P4a's debt exactly as P3b-3 was P3's.

**The genuine parallel window, and it is the first since gate 2.** The merge/undo cluster
(KHA-88/94/96) has no ADR dependency. R-9's "one mobile lane makes parallel a fiction" does not
apply to an architect-and-engineer pair, so the engineer may begin that cluster while the architect
writes. The identity cluster waits.

### Cross-engineer conflicts

None between engineers — still one implementer lane, and `docs/api.md` does not exist (ADR-001: no
backend, no contract to drift). **But this turn has the closest thing yet to a contract conflict:**
ADR-008 is a *contract between the architect and the engineer*, the engineer built to it correctly,
and it is now changing underneath already-merged code. That is the same shape as an API contract
moving after a client built against it, and it is handled the same way — the amendment lands first,
then a named follow-up task (P4a-1's identity cluster) carries the already-merged code to it. Worth
noting that this build's "no contract" property was true only until the architecture had to change.

### What changed in the plan

`docs/build-plan.md` → **v1.5**: P3b-3 and P4a marked merged with what each actually left open;
**P4a-1** inserted as a new phase with its cluster table, the four-reason argument for architect-first,
the architect's deliverable list, and its own exit check; **"The P4b gate, as it actually stands"**
table added (7 rows, each a Linear link, plus the three tracker corrections made this turn); P4's
exit check widened from two issues to seven, with a note that the AC-level clause *"a never-seen
merchant is never confidently categorized by coincidence"* is what caught KHA-98 — the 2026-07-28 QA
lesson paying out; **R-16** (identity asserted without corroboration) and **R-17** (the free re-key
window) added, R-15 updated to half-paid; §4 gains the `P4a-1 → P4b` edge and the
architect→engineer edge; §7.3 row 9 superseded and **row 10** added (ADR amendment FYI + the
`/revise-design` branch point); §8 index rows rewritten for P3b-3, P4a, P4a-1, P4b and KHA-36. Both
non-blocking corrections owed at v1.5 from PR #23's review are paid: the revision table and §7.3 are
now in order.

Linear, this turn: `blocks KHA-34` added from **KHA-98, KHA-99, KHA-102, KHA-94, KHA-96**;
`blocks KHA-32` added from **KHA-96** (its O-QA-11 half is precisely the needs-review inbox losing
items). Owner routing verified rather than changed — every gate issue already carries the correct
`owner-*` label, and since all agents act under one Linear account, the label *is* the routing.

### Cost note — this phase

| Agent | Model tier | Ran |
|---|---|---|
| mobile-engineer | **opus** | P3b-3 (PR #24) and P4a (PR #27) authoring |
| qa-tester | **opus** | Two gates: 17-probe second merge round (PR #26) and **35-probe** categorization round (PR #28), plus the §7d 27-AC traceability matrix |
| code-reviewer | **opus** | PR #24, #26, #27, #29 merges; re-ran CI on the post-QA-merge head rather than citing QA's SHA |
| manager (this turn) | **opus** | Supervision only: 3 docs read, 15 Linear calls, 5 GitHub calls, 5 Linear writes, 0 code |

**Three economics observations.** First, **QA is still the most expensive agent and still the one
earning its cost** — the 35-probe P4a round found the defect that reshaped this phase, and found it
in an *approved architecture document*, which no cheaper check would have reached. Second, the
QA-PR-based-on-the-code-branch change (lesson, 2026-07-29) **worked first try**: PR #28 merged into
the P4a branch and rode to `main` as one squash commit, ending a six-PR streak of manual rescues —
a real saving in orchestrator time, not just tidiness. Third, and less comfortable: **P4 has now
produced three fix PRs' worth of work (P3b-3, P4a-1) against two feature PRs.** That ratio is the
honest price of the adversarial QA posture on a money-handling product, and it is worth watching —
if P4a-1's gate produces a P4a-2, that is the signal to stop and re-scope rather than loop again.
Fix-loop count for this feature area: **round 2 of 3.**

### Next dispatch

**solution-architect (opus) → the ADR-008 merchant-identity amendment: KHA-98 (decision), settling
KHA-99, KHA-102 and KHA-100's tier claim with it.** Docs only — a dated amendment beside ADR-008 in
`docs/architecture.md`, not a rewrite. It must answer: the corroboration rule for collapsing two raw
strings into one identity (bar = AC-D2.3 "match, or flag — never silently miscategorize"); city
tokens, trailing digits, the non-alphanumeric fallback key, and whether T3 means *permutation* or
*same token set*; the R-17 migration posture with its premise stated as KHA-69's was, plus the
condition that the premise dies on first hardware install; and an explicit **yes/no on whether a
"these are two different shops" split affordance is required** — if yes, that screen is not in
`docs/design.md` and it triggers the first `/revise-design` round since gate 2. NFR-M3 applies:
synthetic merchant strings only.

Then **mobile-engineer (opus) → P4a-1**, one PR off `main` @ `ad5688a`: KHA-98/99/102/100 (identity,
after the ADR) · KHA-101 (correction-surface unification) · KHA-88/94/96 (merge/undo remainder, may
start immediately, no ADR dependency) · KHA-103/104/105 (cheap, same files). Schema **v8 only if the
architect requires a re-key**. Invert every named probe in place. Then qa-tester for an explicit
`QA: PASS`/`FAIL`, then code-reviewer to merge on green CI + `QA: PASS`.

**P4b (KHA-32 + KHA-33 + KHA-34) does not start until all seven gate issues are closed.**

---

## 2026-07-29 — Phase P4a-1 → P4b boundary (fifth supervision turn)

**Supervisor:** manager (opus). **`main` at time of check:** `c3c4cbf` (PR #30). **Open PRs: none.**

### The finding that had to come first: the fourth turn's docs never landed

The previous entry in this very file ends with a "Next dispatch" that was executed correctly — but the
**documents describing it were never merged.** Verified with `list_commits --path`, not assumed:

- `docs/build-plan.md` on `main`: last touched by **`a4791d4` (PR #23)** — the **v1.4** update.
- `docs/build-log.md` on `main`: last touched by **`a4791d4` (PR #23)** — the fourth turn is absent.

So `main`'s plan-of-record still described P4b as gated by **two** issues (KHA-87/88) while the real
gate was **seven**, and none of KHA-94/96/98/99/100/101/102 appeared anywhere in it. The code-reviewer
caught this at the PR #30 merge by reading `main` directly instead of trusting the previous turn's
summary. That is the right instinct and it was right.

**The irony worth recording: the fourth turn diagnosed the working-tree hazard correctly and still fell
into a different one.** Its own entry says it confirmed both files were current on `main` before editing
them — a careful check — and then the edits sat in a stale local checkout that nothing ever committed. It
guarded against editing a stale file. It did not guard against the edited file never leaving the machine.

**The build survived this only because of a v1.4 decision.** The seven-issue gate was also encoded as
`blocks` links in Linear, and Linear *did* persist. The engineer and reviewer worked from the links, not
from the plan file, so P4a-1 was scoped correctly anyway. That is the v1.4 lesson — *promote a reviewer's
prose gate into Linear links* — paying out against a failure it was not written for. Prose in a document
that may not land is not a control; a link is.

**Rule now explicit in `docs/build-plan.md` §Revision history:** a supervision turn is finished when its
docs are **merged to `main`**, not when they are written. The next turn's first evidence check is
`git log` on `docs/build-plan.md`.

### What I verified from evidence, not memory

- **`main` = `c3c4cbf`**, PR #30 merged 12:59:36Z, message enumerating the eleven closed issues, `QA: PASS
  30` on `3620388` (byte-identical `lib/` to the merged head), CI 6/6 green on `f906c94`.
- **No schema change.** The merge commit states the set-valued link was derived from the existing
  `merged_into_id` column via `TransactionDao.absorbedTransactionIds`. **v1.5 budgeted for a conditional
  schema v8 and a re-key; neither was needed.** Schema stays **v7** and R-17's free window is unspent.
- **KHA-106 and KHA-107 read in full in Linear.** KHA-106: `blocks` KHA-7 **and** KHA-53, `Backlog`,
  High, `needs-architecture-decision`. KHA-107: `Backlog`, Low, no blocks, related to KHA-106 and KHA-31.
- **KHA-7 read in full.** Still `Backlog`, Urgent, never run, `blockedBy` KHA-106 as of 12:30.
- **KHA-32 relations read.** Its `blockedBy` set is the full nine — the gate was real and bidirectional.
- **`ci.yml` lines 54-58 read directly:** `on: pull_request: branches: [main]` / `push: branches: [main]`.
  The QA-PR-on-a-code-branch gap is confirmed at the source, not inferred.
- **`.claude/agents/qa-tester.md` grepped:** no `flutter analyze` / `dart format` pre-PR instruction
  exists. The gap is real, not an agent ignoring its brief.
- **Could not read `docs/architecture.md` ADR-008 v1.3 directly.** The file is ~168 KB, over the GitHub
  tool's response cap, and the local copy is stale (it predates the amendment entirely). My reading of the
  corroboration rule and the migration posture therefore rests on **QA's verbatim citations** in KHA-106
  and KHA-107 — which quote condition 1 (purity/determinism), condition 3 (residue-safety) and the
  consequences list — plus PR #30's merge commit. Stated plainly rather than papered over: this is one
  step removed from the primary source, and the KHA-106 decision should be taken by the architect reading
  the ADR itself.

### The decision that mattered: KHA-106 vs. KHA-7, resolved by reading what KHA-7 actually is

The conflict as posed: KHA-106 `blocks` KHA-7, on the R-16 argument that running the device spike
populates a real `merchant` table and closes the clean-migration window that this entire fix round
existed to protect.

**The R-16 argument is correct. Its target is wrong.** KHA-7's own "Do" section specifies a *throwaway
spike app, not production code, not merged to main*, with a synthetic sender, and its done check ends
*spike code is deleted or kept out of the product repo*. A standalone receiver harness has **no SQLCipher
database, no `CategorizationService`, no `ensureMerchant` call and no `merchant` table.** It cannot write
the rows whose absence is the premise. The window closes on a **product** install that ingests one SMS
while unlocked — which is **KHA-53**, where the block is kept.

`KHA-106 blocks KHA-7` removed. `KHA-106 blocks KHA-53` retained.

**The genuine hazard was in my own document, not in the link.** `docs/build-plan.md` §7.3 row 5 told the
human the spike "should wait for P3b-3 to land, then run" — wording that invites side-loading the product
APK to satisfy KHA-7, which is precisely the action that spends the window. Rewritten in v1.6: KHA-7 is
harness-only, and the "no product build on hardware" constraint now sits on KHA-53 alone.

**Severity re-read, so nobody over-reacts to "High".** KHA-106's residual collides only strings sharing an
**identical non-numeric prefix** and differing solely by a trailing 4+ digit run. Two unrelated businesses
essentially never take that shape — that was KHA-98's case (`MAKKAH BAKERY` / `MADINAH BAKERY`), and it is
closed. What survives merges two numbered outlets **of one chain**, which the learning loop usually wants
merged. It is correctly filed as a **rule-integrity** defect: ADR-008 v1.3 states a normative
residue-safety condition its own implementation does not meet, and that species of silent disagreement is
exactly how KHA-98 got past three consecutive readers. It is not a money defect and it gates no feature.

**Net: nothing is waiting on KHA-106 any more.** It rides with P4b, as the issue itself proposes.

### Cross-engineer conflicts

None this phase, and the reason is structural rather than lucky: there is one mobile lane (R-9), no web or
backend surface (ADR-001), and the only genuinely two-agent edge — architect → engineer on merchant
identity — was sequenced in v1.5 and executed in that order. No `docs/api.md` exists to drift.

One near-conflict worth naming: **KHA-104 defends a writer that KHA-34 is about to add** (merchant rule
category ids validated on write, dropped on read). P4a-1 fixed it in the file it already had open, one
phase before the caller exists. That is the "cheap while the file is open" clustering paying off.

### Process gaps triaged this turn

1. **Linear batch-close — extended KHA-85, did not file a new issue, raised to High.** PR #30's title
   listed eleven `KHA-nnn` numbers; the integration closed one, and **10 of 11 were transitioned by hand**.
   This is the inverse of KHA-85's recorded failure (wrongful close of KHA-78) but the *same configuration
   decision*, and KHA-85's own preferred remedy — option 1, turn auto-close off and have the reviewer
   transition deliberately — resolves both directions at once. Splitting it into two tickets would invite
   two half-answers. Raised Medium → High because it has now cost reviewer time twice and multi-issue PRs
   are the normal shape here (P3b-3 closed 4, P4a-1 closed 11). Done check extended: *a PR that closes N
   issues closes all N or none.*
2. **QA-PR-has-no-CI — filed KHA-108 (Medium), did not dispatch devops.** Confirmed at source in
   `ci.yml`. The QA-PR-on-the-code-branch pattern should stay — it ended a six-PR streak of manual base
   rescues — so the fix is to widen the trigger (drop the `branches` filter on `pull_request`), checking
   the interaction with the path-filtered emulator job and the `ci` fan-in first. The cheaper complement,
   a pre-PR `flutter analyze` in `.claude/agents/qa-tester.md`, is an **agent-configuration change and
   therefore the human's call, not mine** — flagged in the issue, not actioned. Cost of the gap this
   round was one CI cycle plus a two-line commit, so it does not justify an opus devops dispatch on its
   own: **batched with KHA-85 and KHA-67 into one devops sweep after P4b.**

### What changed in the plan

`docs/build-plan.md` → **v1.6**: the P4b gate table rewritten from seven open rows to nine closed rows
with what actually fixed each, plus a new two-row table for KHA-106/107 and an explicit "read this
severity precisely" note; P4a-1 marked merged with an outcome block recording that the one-PR/two-cluster
bet paid and that schema v8 was never needed; **R-15 retired**, R-16 downgraded to Low-Medium residual,
R-17 updated to "window unspent, and here is the precise expiry condition"; §4 gains the
`KHA-106/107 → first P4b PR` edge and the explicit `KHA-7 is NOT sequenced behind KHA-106` correction;
**§7.3 row 5 rewritten** (the wording that was the hazard) and **row 11 added**; P4's exit check updated —
seven gate clauses discharged, replaced by the KHA-106/107 rider and O-QA-8's merge confirmation; §8 index
rows rewritten for P0, P4a-1, P4b, P10 and a new Process/infrastructure row. Plus the ⚠️ process note on
v1.5 never landing.

Linear this turn: `KHA-106 blocks KHA-7` **removed** (KHA-53 retained), with the reasoning recorded as
comments on both issues; `owner-solution-architect` added to KHA-106; KHA-85 commented and raised to High;
**KHA-108 created** (owner devops, P4 milestone — milestoned at creation, per the standing rule).

### Cost note — this phase

| Agent | Model tier | Ran |
|---|---|---|
| solution-architect | **opus** | ADR-008 **v1.3** corroboration-rule amendment (docs only) |
| mobile-engineer | **opus** | P4a-1 (PR #30) — eleven issues, two clusters, one PR |
| qa-tester | **opus** | Third adversarial round, 18 probes, `QA: PASS 30`; filed KHA-106/107 |
| code-reviewer | **opus** | PR #30 review + merge; caught the unlanded-plan divergence by reading `main` |
| manager (this turn) | **opus** | Supervision only: 4 docs/config reads, 8 Linear calls, 6 GitHub calls, 7 Linear writes, 0 code |

**Four economics observations.** First, **the architect-first routing was the cheapest good decision of
the phase** — one docs-only pass produced a general rule that closed four issues (KHA-98/99/100/102) and
pre-empted the fourth instance nobody had found yet. Compare three engineer patches inventing three local
answers. Second, **the one-PR/two-cluster bet paid exactly as argued**: eleven issues through **one** opus
QA pass and **one** opus review pass, against a v1.5 estimate of two of each if split. Third, **the fix
ratio improved and the stop condition was not hit** — v1.5 said that if P4a-1's gate produced a P4a-2,
that was the signal to stop and re-scope. It produced two *non-blocking* follow-ups instead, which is a
normal tail, not a loop. **Fix-loop count for this feature area: round 3 of 3 — and it terminated.**
Fourth, the cheapest defect-prevention in the whole build remains **inverting probes in place** rather
than authoring new adversarial surfaces; three consecutive rounds have now used it.

**One cost that is not an agent cost:** ten manual Linear transitions and one hand-authored fix commit by
the human orchestrator. That is the human doing integration work the tooling should do, and it is what
KHA-85 and KHA-108 exist to remove.

### Next dispatch

**mobile-engineer (opus) → P4b**, off `main` @ `c3c4cbf`, after a short **solution-architect (opus)**
docs-only pass settling **KHA-106 + KHA-107** as a dated ADR-008 **v1.4** amendment. The architect goes
first because KHA-106 carries `needs-architecture-decision` and two of its three options amend an APPROVED
gate-2 document — an engineer may not quietly contradict one. If the architect takes option 3 (accept and
document), both issues close with **zero code and zero QA cost**, and P4b proceeds unencumbered.

P4b = **KHA-32** (confidence + needs-review flag and count) · **KHA-33** (correction flow, scope choice,
bulk + undo) · **KHA-34** (learned-rules screen, re-apply to history) · **KHA-97** (category management:
S-14 list, S-15 reassignment dialog, inline "+ New category"). Hard requirements carried in: **O-QA-8's
merge confirmation ships before or with the route**; **one audit entry per affected transaction** on
KHA-34's bulk historical re-apply (AC-D4.4); **AC-C1.3's sum invariant** re-tested after all four category
operations. Then qa-tester for an explicit `QA: PASS`/`FAIL`, then code-reviewer to merge on green CI +
`QA: PASS`.

**In parallel, and costing no agent time: the human may now run KHA-7** — as a throwaway harness, never a
Massrofy APK. See build-plan §7.3 row 5.

**Deferred deliberately:** KHA-85 + KHA-108 + KHA-67 as one devops-engineer sweep after P4b.

---
