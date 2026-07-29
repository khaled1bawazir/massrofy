STATUS: LIVE — gate 2 passed, build in progress
# Massrofy — Build Plan

**Version:** 1.4
**Date:** 2026-07-27 (v1.0) · last supervised 2026-07-29 (v1.4)
**Author:** manager agent (v1.0 planning; v1.1+ build supervision)
**Source of truth:** `docs/PRD.md` v0.3, STATUS: Approved
**Linear project:** [Massrofy — Personal Spending Tracker from Bank SMS](https://linear.app/khaledbawazir/project/massrofy-personal-spending-tracker-from-bank-sms-1c491affcc87) (team `KHA`)

> This document plans **who builds what, in what order**. It deliberately makes **no
> architecture decisions** — those belong to `docs/architecture.md` (solution-architect)
> and `docs/design.md` (ui-ux-designer), both of which are human gate 2. Where planning
> surfaced a decision that must be made, it is recorded in §7 as a flag, not answered here.

> **This is now a living document.** Under team v2 the manager re-reads real state
> (docs, PRs, CI, Linear) between build phases and updates this plan where reality
> diverged. Per-phase status and dispatch history live in `docs/build-log.md`.

## Revision history

| Ver | Date | Change |
|---|---|---|
| 1.0 | 2026-07-27 | Original plan, written before gate 2. |
| 1.1 | 2026-07-28 | Gate 2 closed; P1 and P2 merged. |
| 1.2 | 2026-07-28 | **P3 supervision.** §2.1 backend question closed by ADR-001. P3 scope corrected — two work items inherited from P2 were missing (KHA-64, KHA-66) and P3 is now recommended as two PRs. §8 issue index refreshed (issues now run past KHA-53). §9 records the team-v2 QA merge gate. R-1 restated as unpaid P0 debt. |
| 1.4 | 2026-07-29 | **P3→P4 supervision. P3 is complete** (P3b-1 = PR #18, P3b-2 = PR #20, both through engineer → QA → reviewer; KHA-69 recorded as option (a), dated). **P4 split into two PRs, and the seam is forced rather than chosen** — code-reviewer's PR #20 gate makes KHA-87/KHA-88 merge-blocking for any PR that routes `NeedsReviewScreen`, `RecentlyDeletedScreen` or `TransactionDetailScreen`, and P4's own ACs (AC-C2.2, AC-C4.1/4.2) cannot be met without routing two of those three. New **P3b-3** fix PR inserted ahead of P4. New **R-15** (defects held safe only by absent navigation). KHA-32's `needs-architecture-decision` label removed — ADR-008 answers A-7 with a named constant. KHA-87/88 had **no milestone**, the same failure as the v1.3 lesson, now filed under P4. |
| 1.3 | 2026-07-28 | **P3a→P3b supervision.** P3a merged (PR #11). **KHA-24 found already shipped inside P3a** and closed — P3b is one issue smaller than v1.2 planned. **KHA-64 found wrongly auto-closed by the Linear/GitHub integration** and reopened; its D2 half is genuinely unbuilt. Three QA/review-born issues (KHA-69, KHA-70, KHA-74) had no milestone and are now in P3b. P3b re-split into **two PRs by coupling, not by issue count** — totals-semantics first, mutation-surface second, with reasoning recorded. New **R-14**: no human has ever unlocked this app on real hardware (KHA-75), which both raises device risk and, today, makes KHA-69's option (a) provably correct. |

---

## 1. Scope summary

Massrofy is a **single-user Android application built in Flutter**, installed by side-load
(no app store — OQ-3/OQ-4). It reads the bank transaction SMS the user already receives
in Saudi Arabia (Arabic and English, right-to-left), and turns them into a trustworthy,
always-current picture of personal spending.

What gets built:

| Capability | PRD epic |
|---|---|
| Read incoming and recent SMS, tell financial messages from OTP/marketing noise, never silently drop one | A |
| Parse each message into a structured transaction (amount, currency, merchant, instrument, date-time, type) using per-bank, per-message-type rules | A, B |
| Model the real hierarchy: **bank → account / card**, auto-created on first mention, with card↔settlement-account linkage | B |
| Full transaction lifecycle: manual entry, edit, soft delete + restore, refunds/credits, multi-currency, income/ATM/internal-transfer classification | B |
| Categorization with a merchant-learning loop — correct once per merchant, then it stays right | C, D |
| Reporting: current-month total, by category, by card, month-over-month, search and filter | E |
| Privacy and trust: biometric app lock, export, erase-all, transparency screen, append-only change history | F |
| Monthly budgets per category and overall, with threshold alerts | G |
| PDF/CSV statement import and reconciliation against SMS-derived data | H |
| Encrypted cloud backup and restore onto a new device | I |

What is **not** built (PRD §3.2): any payment initiation, any bank API integration, any
multi-user or sharing feature, email/push ingestion, receipt OCR, forecasting, analytics
or telemetry SDKs, or app-store publication.

**The single most important product constraint** (CON-2): the app is *read-only with
respect to money*. It observes. It never moves a riyal. Every design and code review must
hold that line.

---

## 2. Which specialists this feature actually needs

The roster is not applied wholesale. Here is the call, with reasoning.

| Specialist | Needed? | Why |
|---|---|---|
| **solution-architect** | **Done at gate 2** | Settled on-device vs. server (ADR-001), storage/crypto, background SMS strategy, parser rule model, backup key recovery. Re-engaged only when a build phase surfaces a new decision — as happened with ADR-018. |
| **ui-ux-designer** | **Done at gate 2** | ~12 screens, Arabic-first RTL, and the correction flow (NFR-U7). Re-engaged only via `/revise-design`. |
| **devops-engineer** | **Yes** | Flutter CI, signed-APK build, side-load staging channel. Note: **branch protection is unavailable on this repo's GitHub free plan (KHA-55)** — merge discipline is convention-only, not server-enforced, which raises the stakes on the QA + code-reviewer gate. |
| **mobile-engineer** (Flutter) | **Yes — primary implementer** | Owns essentially all product code: ingestion, parsing, domain model, learning loop, every screen, budgets, statements, backup client. |
| **frontend-engineer** (React web) | **NO — never dispatch** | **There is no web surface in this product at all.** No admin console, no companion web app, no browser-based anything. The PRD's only client is the Android/Flutter app. Dispatching a React engineer would produce a deliverable nobody asked for and a second codebase to secure. |
| **backend-engineer** (Java/Spring) | **NO — never dispatch (settled 2026-07-28)** | §2.1 is closed: **ADR-001 chose no backend**, CI-enforced. Applies to Epic I too. |
| **qa-tester** | **Yes** | 132 acceptance criteria across 9 epics need a traceability matrix; the parser corpus needs automated regression (NFR-M2); security/privacy claims (AC-F4.2) need active verification, not assertion. |
| **code-reviewer** | **Yes** | Merge gate on every PR. Extra scrutiny mandated on anything labelled `security-sensitive`. |
| **production-support** | **Yes, but reduced** | There are no server logs to triage. Its remit here is on-device crash/diagnostic triage and raising bugs — and it is constrained by NFR-S4/S6 (no sensitive values in logs, no telemetry SDK). See flag A-14. |

### 2.1 The backend question — ANSWERED (2026-07-28): there is no backend

> **Resolved.** `docs/architecture.md` **ADR-001** decides it: Massrofy is on-device only,
> with **no backend and no network permission at all**. This is not merely documented, it is
> mechanically enforced — CI runs `.github/scripts/check_no_network_permission.sh`, which
> fails the build if `INTERNET`/`ACCESS_NETWORK_STATE` appears in the **merged release
> manifest across every plugin**, verified against a real release build in PR #1.
>
> Consequences, now settled rather than conditional:
> - **backend-engineer is never dispatched on this product.** Not for Epic I either.
> - **frontend-engineer is never dispatched.** Confirmed: there is no web surface.
> - **P8 (Epic I) is mobile-engineer work**, and the `(or backend-engineer …)` caveat on
>   that phase below is void.
> - The `owner-backend-engineer-CONDITIONAL` Linear label is now dead and should not be
>   applied to anything new.
>
> The team for this product is, finally: **devops + mobile + qa + code-reviewer**, plus
> production-support post-release. Three of the eleven roster agents are permanently out of
> scope here (backend, frontend, and — after gate 2 — the designers, barring `/revise-design`).
>
> The original reasoning is kept below because it is the argument the ADR had to answer.

<details>
<summary><b>Original v1.0 reasoning — the backend question as it stood before ADR-001 (superseded, kept for the record)</b></summary>

This project's default team shape assumes a Java/Spring backend served to clients. **Massrofy
probably does not have one.** The PRD points hard the other way:

- NFR-P2/P3: parsing and categorization run **on-device by default**; moving *processing*
  off-device would require an explicit, opt-in, documented change.
- NFR-R4: the app must **function fully offline** for viewing and categorizing.
- CON-1: single user, **no account system, no server-side identity**.
- AC-F4.2: under network monitoring during normal use, **no financial data may leave the device**.

That leaves exactly one candidate for server-side work: **Epic I, encrypted cloud backup**
(C16). And even that may need no custom service — an end-to-end-encrypted blob in the
user's own cloud storage would satisfy US-I1/I2/I3 with zero backend code and a strictly
better privacy posture (the operator can't read what they can't decrypt).

**Decision owner: solution-architect. This must be stated explicitly in the ADR.** Until
it is:

- Do **not** dispatch backend-engineer at `/build`.
- If — and only if — the ADR chooses a custom sync service, backend-engineer is activated
  for **Epic I only**, and the ADR must simultaneously explain how a server-side component
  is reconciled with NFR-P2, NFR-R4 and AC-F4.2.
- If the ADR chooses managed/E2EE storage (the expected outcome), Epic I is **mobile-engineer
  work** and the team for this feature is: devops + mobile + qa + reviewer.

Issues that would belong to a backend are pre-labelled `owner-backend-engineer-CONDITIONAL`
in Linear so this stays visible rather than being assumed either way.

</details>

---

## 3. Phases, ownership and sequencing

Phases map to Linear **milestones** `P0`–`P10`. Each phase has an **exit check** — an
observable condition, not a feeling — recorded on the milestone in Linear.

### P0 — Gate 2: Architecture + Design *(blocking, runs first)*
**Owners:** solution-architect, ui-ux-designer (in parallel), plus one mobile-engineer spike.

| Work | Owner |
|---|---|
| `docs/architecture.md` (ADR) answering every flag in §7.1 | solution-architect |
| Penpot frames + `docs/design.md` answering every flag in §7.2 | ui-ux-designer |
| **Feasibility spike:** background SMS receipt on the user's actual Android version/OEM | mobile-engineer |

The spike is not optional. NFR-R1 promises "seconds from SMS arrival to visible in-app",
and OQ-3 records that on-device SMS behaviour is **not yet verified**. If the target device's
OEM aggressively kills background receivers, that promise changes and the architecture
changes with it. Run the spike **during** P0 so its result lands in the ADR, not after it.

**Exit check:** the human marks **both** `docs/architecture.md` and `docs/design.md`
`APPROVED`. `/build` refuses to start otherwise.

> **Retrospective (2026-07-28): this exit check was wrong, and it cost us.** It names only the
> two documents, so P0 closed cleanly while the spike above — declared "not optional" one
> paragraph earlier — was never run. KHA-7 is still in Backlog with no recorded outcome, and
> P1 and P2 have both since shipped on its unverified assumptions. See **R-12**. An exit check
> must enumerate *every* artifact of its phase, or the ones it omits become invisible.

---

### P1 — Foundation: CI, secure storage, money, audit
**Owner:** devops-engineer (CI) + mobile-engineer (everything else). Sequential after P0.

| Work | Owner | Done check |
|---|---|---|
| Flutter CI: analyze, format, unit + widget tests, debug APK artifact; branch protection requiring `ci`; secret scanning | devops | A PR with a failing test cannot be merged |
| Signed release-APK build + staging side-load distribution channel | devops | A tagged build produces an installable signed APK |
| App scaffold: layering, DI, `ar`/`en` localization, RTL bootstrap | mobile | App launches in Arabic RTL and English LTR from the OS locale |
| **Money value type** — exact decimal, currency-tagged, no floating point (NFR-A4/A5) | mobile | Property test: no `double` in any money path; summing mixed currencies without a stated conversion is a compile-time or runtime error |
| Encrypted local datastore + schema + migrations (NFR-S1) | mobile | The DB file on disk is unreadable without the key; a migration test runs forward from an empty install |
| Masking + redaction utilities; log scrubber (NFR-S2/S4) | mobile | A test asserts a full PAN-like string is never persisted or logged; identifiers render masked everywhere |
| Append-only audit trail infrastructure (NFR-A2/A3) | mobile | Any transaction mutation writes an immutable history entry with actor, timestamp, before and after; an update/delete against history fails |
| App lock: biometric/passcode + app-switcher obscuring (NFR-S3/S8) | mobile | App resumes locked; the switcher snapshot shows no figures |

Everything downstream depends on these. Do not let ingestion work start before the money
type and audit trail exist — retrofitting exact-decimal arithmetic and provenance after
the fact is how banking apps get silently wrong numbers.

---

### P2 — SMS ingestion and parsing (Epic A)
**Owner:** mobile-engineer. Sequential after P1.

Permission flow and priming; background receiver and processing pipeline; financial-vs-noise
classification; the **parser rule engine** (per bank, per message type — PRD §3.4 shows the
two sample banks produce structurally different messages for 9 transaction types, so a single
generic template will not work); historical import from the start of the current calendar
month, resumable; duplicate suppression; the unparsed review queue.

Internal parallelism: once the rule-engine *interface* is agreed, the classifier, the
importer, the dedup logic and the review queue can be built alongside individual bank rule
sets. The engine interface itself is the sequencing bottleneck — do it first.

**Exit check:** the synthetic fixture corpus covering both banks and all nine observed message
types parses to expected output in automated tests; no fixture is silently discarded (NFR-A7);
a real SMS on a physical device reaches the data layer within seconds.

> **Status (2026-07-28): met in part. P2 merged as PR #2 with the third clause open.** The
> corpus and no-silent-discard halves are genuinely proved (the latter structurally —
> `ParseOutcome` is a sealed type with no `dropped` case and the pipeline's `switch` has no
> `default:`). **The physical-device clause was never verified** and PR #2 says so in its own
> "Honest limits". Two things changed underneath it: ADR-018 makes background ingestion an
> unconditional no-op while locked, so the Layer 2 foreground sweep does the work and NFR-R1
> is renegotiated to "seconds while unlocked; seconds from unlock, nothing lost, while locked"
> (flagged to the human as H-13); and KHA-7 remains unrun (**R-12**). Carried to P10.

> **Test data rule, non-negotiable (NFR-M3):** the user's genuine bank SMS must never be
> committed to a repository or pasted into any tool. The corpus is realistic-but-**synthetic**,
> authored from the structural patterns in PRD §3.4. QA owns enforcing this.

---

### P3 — Domain model: banks, instruments, transactions (Epic B)
**Owner:** mobile-engineer. Sequential after P2 (needs real parsed output to model against).

> **STATUS (2026-07-29): P3 IS COMPLETE — with two High defects deliberately left open.**
> P3a = PR #11, P3b-1 = PR #18 (schema v4, KHA-27/28/29/70), P3b-2 = PR #20 (schema v5,
> KHA-26/64/66/74/78/79/80). Each went engineer → QA (with a real adversarial probe suite:
> 18 attacks on P3a, 11 probes on P3b-1, 37 merge-focused probes on P3b-2) → code-reviewer.
> **KHA-69 is recorded** in `docs/architecture.md` as option (a), dated 2026-07-29, closing the
> last non-code artifact in the P3b exit check. The two open defects — **KHA-87** and
> **KHA-88** — are carried into P3b-3 below, and they now gate P4. See **R-15**.

**Historical (2026-07-28): P3a merged; P3b was the remaining work, re-split into two PRs — see below.**
PR #11 (`8e549d8`) landed the domain spine: KHA-23, KHA-25, KHA-24 and KHA-64's first half.
QA verified it at 17/20 full PASS, 3 partial, **0 FAIL**, with an 18-attack adversarial pass
(PR #15) in which every attack was repelled or detected.

Bank/account/card hierarchy with auto-creation on first mention and entity resolution
(the same bank named in Arabic in one message and abbreviated in another must resolve to
**one** bank — AC-B12.3); friendly names that survive re-parsing; card↔settlement-account
linkage; the transaction record with provenance; manual entry, edit, soft delete and restore;
refunds and credits netting against spend; multi-currency with the FX-fee component kept as
its own field (PRD §3.4); income, ATM withdrawal and internal-transfer classification.

#### Scope correction — two items inherited from P2 (added 2026-07-28)

P2 shipped two things as **callbacks with no implementation behind them**, deferring them
here because both must write a full `Transaction` and the domain model did not exist yet.
Neither was covered by KHA-23..29, so P3 as originally written would have closed while Epic A
was still half-functional. Both are now tracked:

| Issue | Inherited work | Why it was deferred |
|---|---|---|
| **KHA-64** | **S-19 / AC-A4.2** — completing an unparsed SMS into a real transaction, and **ADR-017 D2's enrichment merge** | PR #2 items 9 and 5: both write a full `Transaction` over P3 fields |
| **KHA-66** | **AC-A4.3 regression test** — a dismissed message stays dismissed across a full re-scan | QA-found gap (PR #4); code-reviewer set "before P3 closes" as the deadline |

Note honestly: **KHA-22 is closed `Done` while AC-A4.2 is not actually shipped.** The closure
is defensible — KHA-22's own done-check was about the *queue* (nothing silently dropped,
dismissal survives re-scan) and that is genuinely delivered — but the completion action is
outstanding, and KHA-64 is the record of that. This is the kind of gap that disappears if only
PR bodies remember it.

**KHA-64 carries the highest correctness risk in P3.** The enrichment merge is the only place
in the entire product where two records become one, and R-8 is explicit that silently deleting
a real transaction is worse than an inflated total. Merge must stay user-confirmed and
never automatic, and the result must remain traceable to both source messages (NFR-A6).

#### Two tracking corrections found at the P3a→P3b boundary (2026-07-28)

**1. KHA-24 was already shipped inside P3a and is now closed `Done`.** It was still sitting in
Backlog, milestoned into P3b. Verified at AC level against `main`, not against the PR body:
`lib/features/ledger/ledger_entity_resolver.dart` calls `instrumentDao.linkSettlementAccount`
only when both sides resolved *and* the primary side is a card and the settlement side is an
account (AC-B14.1); `lib/presentation/screens/instrument_detail_screen.dart` renders
`instrumentLinkedTo(...)` (AC-B14.2) and a deliberately neutral `instrumentNotLinked`
(AC-B14.3). QA's matrix independently marks all three ACs **PASS** with verbatim test names,
including the `and nothing else does` corpus assertion that is what actually stops a guessed
link. P3b is therefore one issue smaller than v1.2 assumed.

**2. KHA-64 was wrongly flipped to `Done` and has been reopened.** PR #11's own merge commit
says plainly: *"its second half — ADR-017 D2's enrichment merge — stays open for P3b, so
KHA-64 remains In Progress."* The Linear/GitHub integration auto-closed it on merge anyway
(completed 19:00:35, two seconds after the merge). There is no enrichment-merge implementation
anywhere under `lib/features/ledger/`. **This is `docs/lessons.md`'s KHA-22 lesson repeating
through a different mechanism** — last time a human-written done-check was narrower than its
ACs; this time an automation overrode an explicit human decision. See the new lesson.

**3. Three QA/review-born issues had no milestone at all** — KHA-69, KHA-70 and KHA-74 were
created during the PR #11 QA gate and the PR #15 review, and were tracked nowhere in the phase
plan. All three are now in P3b, below.

#### Re-split: P3b as two PRs, grouped by coupling rather than by issue count

**The v1.2 spine-split experiment paid off, and the evidence is specific.** P2 as one large PR
took **four review rounds and five blockers**, one security-relevant. P3a as a spine PR merged
with **zero FAIL and zero merge-blocking defects**, 17/20 ACs at full PASS, and the three items
QA did raise (KHA-69, KHA-70, O-QA-1/2) were all correctly judged non-blocking follow-ups
rather than rework. Continue splitting — but **two PRs, not three or five**: the build-log's
cost note identifies the per-PR opus QA pass plus opus review pass as the dominant recurring
cost, so fragmenting further buys review comfort at a real and rising price.

The seam is chosen by **what shares code**, not by what sounds thematically tidy:

| PR | Issues | Why these belong together |
|---|---|---|
| **P3b-1 — what a period total *means*** | KHA-27 (+KHA-70), KHA-28, KHA-29 | All three rewrite the **same function**. A period total must convert currencies (KHA-27), net credits against debits (KHA-28), and exclude internal transfers and income from spend (KHA-29). Split apart, `period_totals.dart` gets rewritten and re-QA'd three times, each time against a total that is still semantically wrong until the last one lands — three QA passes certifying a number nobody should trust yet. |
| **P3b-2 — the mutation surface** | KHA-26 (+O-QA-2), KHA-64's D2 enrichment merge, KHA-66, KHA-74, KHA-69 | Every one of these is a path by which a record is created, edited, merged, soft-deleted or restored — and every one must write an append-only audit entry (NFR-A2). KHA-69 *is* the audit chain. That makes them one coherent surface for a single `security-sensitive` reviewer pass, instead of the same reviewer re-deriving the audit invariants twice. |

**Order is load-bearing: P3b-1 must land before P3b-2.** KHA-26's manual-entry form has to be
able to express every *valid* transaction — a credit (KHA-28's sign convention), a
foreign-currency amount with its rate and rate date (KHA-27 + KHA-70's schema), an income or
internal-transfer classification (KHA-29). Building that form before the type space is closed
guarantees rework of the form and of its tests. Concretely: **O-QA-2** (a negative amount typed
on S-19 is accepted and silently inverts the movement direction) is routed to KHA-26's
validation, and it cannot be answered correctly until KHA-28 has fixed the sign convention —
otherwise KHA-26 is guessing what "negative" is supposed to mean. Sequencing also keeps the
schema versions honest: KHA-27 + KHA-70 land **v4** in P3b-1, and anything KHA-26/KHA-74 need
lands **v5** in P3b-2, rather than two branches both claiming v4 and the loser renumbering.

**Exit check (P3b, and therefore P3):** fixtures produce the correct bank tree; category totals
sum to the period total (AC-C1.3); per-card totals sum to the period total (AC-E3.2); internal
transfers are excluded from spend; every stored amount carries a currency; a review-queue item
can be completed into a transaction and leaves the queue (AC-A4.2 — **met by P3a**); a dismissed
item stays dismissed across a re-scan (AC-A4.3 — KHA-66); **a D2-flagged pair can be merged by
explicit user action into one transaction traceable to both source messages, and no code path
merges or removes a transaction without user confirmation (KHA-64)**; **a rate is never
displayed without either a rate date or an explicit "date unknown" (KHA-70)**; **the KHA-69
audit-chain decision is written and dated next to ADR-010**.

Per the v1.1 lesson, this exit check deliberately enumerates *every* artifact of the phase,
including the ones that are decisions rather than code.

---

### P3b-3 — Pay the merge/undo debt *(added 2026-07-29; runs before P4a)*
**Owner:** mobile-engineer. One PR. Issues: **KHA-87, KHA-88, KHA-89** — plus **KHA-90's O-QA-5**
(make `mergeDuplicatePair`'s `actor` a required argument) and **O-QA-7** (one over-claiming
sentence in `ledger_mapping.dart`). Leave KHA-90's O-QA-6 and O-QA-9 alone.

**KHA-89 was added to this PR on evidence, not tidiness.** It lives in the same two files
(`transaction_merge.dart`'s `MergePlan.between` and `transaction_dao.dart`'s
`mergeDuplicatePair`) and its D-QA-10 is the *third* instance of the same root cause as KHA-87:
`MergePlan.between`'s refusal set covers amount, currency, direction and type, and nothing else —
so money columns are dropped (KHA-87) **and** a user's correction on the losing row is discarded
for the parser's value (D-QA-10). One fix to the refusal set answers both. Splitting them means
two engineers' passes and two QA passes over one function. D-QA-11 (a copied user value arrives
without its protected status) is in `mergeDuplicatePair`, which KHA-88 is already opening.

**O-QA-8 is deliberately NOT here — it is a P4b requirement, listed below.** `NeedsReviewScreen`
fires `onMerge!(item)` on a **single tap**, while soft delete has a real `AlertDialog`
(`transaction_detail_screen.dart:166`, AC-B6.2). The riskiest operation in the product is one tap
and the safer one is two. That is harmless while nothing routes the screen, and it becomes an R-8
problem the moment KHA-32 does.

This is not new feature work. It is P3b-2's known debt, and it is scheduled here — ahead of P4
rather than at P5 — for four reasons, in descending weight:

1. **It gates P4b.** See R-15 and the P4 section below. P4b cannot start until this is paid.
2. **`transaction_dao.dart` is quiet right now.** KHA-88 lives at `restore()` (lines ~263–325)
   and `mergeDuplicatePair` (~1009–1140). P4a will touch the same DAO for AC-C3.3's
   delete-with-reassign and for writing `categoryId`/`categoryConfidence`/`needsReview`. Fixing
   the DAO before P4a means the fix is not rebased over a categorization rewrite of the same file.
3. **Schema numbering stays uncontended.** KHA-88's done-check leaves open whether
   `merged_from_transaction_id` becomes a set (needs a table, hence **v6**) or a second merge
   into the same survivor is refused (needs nothing). Running it alone lets it take v6 *if it
   needs it* and lets P4a take the next number unconditionally, instead of two branches both
   claiming v6 and the loser renumbering. **P4a claims v7 regardless** — a gap in the sequence is
   cheaper than a collision.
4. **The QA pass is cheap here.** Both issues' done-checks say *invert* the existing probes
   (A1/A2, B2/B3/B4/B6, F6) rather than delete them. QA re-runs a suite it already authored; it
   does not have to design a new adversarial surface. This is the least expensive opus QA pass
   available in the whole build, and it is the one that unblocks the most.

**Watch item for the reviewer:** KHA-87 offers three defensible fixes and explicitly names (b) —
add the money-bearing columns to `MergePlan.between`'s refusal set — as the cheapest and most
conservative, because it matches that file's own stated principle verbatim: *"Two records that
disagree about a value are not a merge candidate; they are a question for the user."* Prefer (b)
unless the engineer argues otherwise on evidence. It is the option that cannot lose money, only
decline to merge.

**Exit check:** probes A1/A2 and B2/B3/B4/B6/F6 are **inverted and passing**; a merge either
carries or refuses every money-bearing column, with a test that pins the comparison set so the
next column added to `transactions` cannot silently join the "neither compared nor carried" set;
`restore()` clears the survivor's pointer **only when it names the row being restored** and
appends an audit entry against the survivor (NFR-A2); the chain/enrichment-reversal decisions are
written down and the doc comments and test names match whichever way they went.

---

### P4 — Categorization and learning loop (Epics C, D)
**Owner:** mobile-engineer. Sequential after P3 **and after P3b-3**.

Category model with a default starter list (OQ-18 — the list is proposed by the designer in
P0, not invented in code); the categorization engine with a confidence notion and needs-review
flagging; the merchant→category rule store with normalization and matching that works across
Arabic and Latin script (merchant names appear transliterated in Latin even inside Arabic
messages — PRD §3.4); user-correction-always-wins precedence; the correction flow with the
"this one only / this and future" scope choice; bulk categorize with undo; the learned-rules
management screen.

#### Nothing here is blocked on a decision — both inputs already exist (verified 2026-07-29)

Checked before planning, because P4's two issues most likely to stall both looked blocked and
neither is:

- **KHA-30 was "blocked on the design's default category list".** `docs/design.md` **§4**
  resolves OQ-18/D-2: **13 categories** (10 spending + 3 money-movement, including *Loan &
  Installments* and *Fees & Charges* as their own categories per PRD §3.4's hint), with
  *Uncategorized* as a system category that always exists and can be neither deleted nor renamed.
  Seed that list. Do not invent one, and do not "improve" it in code.
- **KHA-32 carried `needs-architecture-decision`. It is stale and the label is removed.**
  **ADR-008** answers A-7 in full — the normalisation pipeline, the `MerchantAlias` table, and a
  four-tier match table (T1 user rule 1.00 · T2 seed rule 0.90 · T3 token-set Jaccard ≥ 0.80 →
  0.60–0.85 · T4 Damerau-Levenshtein ≥ 0.90 → ≤ 0.60, **never** auto-apply · no match → 0.00 +
  `needsReview`). The threshold is `autoApplyThreshold`, **a single named constant in
  `CategorizationConfig`, initial value 0.85**, and the ADR states in its own words that the
  *value* is "a build-phase tuning parameter to be set against the corpus in P4, not a product
  commitment". So it is the engineer's to tune, with the tuning evidence recorded in the PR — not
  an escalation.

#### Split: two PRs, and this time the seam is *forced*, not chosen

P3's evidence is now unambiguous — P2 monolithic = 4 review rounds / 5 blockers; P3a spine = 0
blockers; P3b-1 and P3b-2 split by coupling = also clean. So P4 splits. What is different is
that P4's seam was not a judgement call: **code-reviewer's PR #20 gate draws it.**

> "KHA-87 and KHA-88 are merge-blocking for any PR that routes `NeedsReviewScreen`,
> `RecentlyDeletedScreen` or `TransactionDetailScreen`, and for any build that reaches a device."

That is binding, and P4 walks straight into it. All three screens **already exist on `main`**
(`lib/presentation/screens/needs_review_screen.dart`, `recently_deleted_screen.dart`,
`transaction_detail_screen.dart`); the app shell simply routes to `HomePlaceholderScreen` and
never reaches them. And P4's own acceptance criteria cannot be met without reaching two of them:

- **AC-C2.2** requires the correction to complete "without leaving the transaction context, in no
  more than two screens", and `docs/design.md` §6 implements it as a chip tap on **S-11
  Transaction Detail** opening the `CategoryPicker` sheet (S-12/13) — 2 taps, 0 screen changes.
  There is no way to satisfy "without leaving the transaction context" without a transaction
  context. **KHA-33 routes `TransactionDetailScreen`.**
- **AC-C4.1/4.2** put the needs-review indicator and count in front of the user, and design.md
  §S-18 lands them as the **Low-confidence tab of the Needs Review Inbox**, alongside the
  existing Unparsed tab. **KHA-32 routes `NeedsReviewScreen`.**

So the gate does not merely "affect" P4 — it bisects it, and the bisection line falls exactly
where a spine/behaviours split would have fallen anyway. That is the useful finding: the seam is
over-determined, so take it with confidence.

| PR | Issues | Schema | Inside the KHA-87/88 gate? | Why these belong together |
|---|---|---|---|---|
| **P4a — the categorization spine** | **KHA-30** (category model, seeded 13-item list, custom categories, delete-with-reassign) · **KHA-31** (merchant normalisation, `Merchant`/`MerchantAlias`/`MerchantRule`, tiered matching, user-wins precedence) | **v7** | **NO** | Pure data + domain. New tables, a new `features/categorization/` module, zero navigation changes, no screen routed. KHA-31 is `blockedBy` KHA-30 in Linear and every other P4 issue is `blockedBy` KHA-31 — this is the literal bottleneck, and it is also the part with the real intellectual risk (R-5, cross-script matching). It deserves a QA pass whose whole attention is on matching correctness, uncontaminated by UI. |
| **P4b — the learning loop's user surface** | **KHA-32** (confidence, needs-review flag + count) · **KHA-33** (correction flow, scope choice, bulk + undo) · **KHA-34** (learned-rules screen, re-apply to history) | v7 (no new schema expected) | **YES — routes `NeedsReviewScreen` and `TransactionDetailScreen`** | All three are the same surface over the P4a store, and all three write audit entries — KHA-33's corrections and undos, KHA-34's bulk historical re-apply (one entry *per affected transaction*, AC-D4.4). One `security-sensitive` reviewer pass over one audit surface, exactly as P3b-2 was grouped. Splitting KHA-34 off would mean a third opus QA + review pass for a screen that shares its store and its audit invariants with KHA-33. |

Three PRs are in flight for this phase area (P3b-3, P4a, P4b), but **P4 itself is still two** —
the cap from the v1.3 lesson holds. P3b-3 is P3's debt being paid, not P4 fragmenting.

**Order is load-bearing: P3b-3 → P4a → P4b.** P4a can technically start before P3b-3 lands
(file-disjoint, and it is not gated), but there is only one mobile-engineer lane (R-9), so
"parallel" here is fiction — sequence it and take the clean DAO and the uncontended schema number.

#### Banking-domain watch items for P4 review

- **AC-C1.3 is a reconciliation guarantee, not a display detail.** Category totals *including
  Uncategorized* must sum to the period total, and P3b-1 has already made that sum currency-aware
  (unconverted rows are excluded from base totals and reported separately). Any category
  operation — create, rename, delete-with-reassign, delete-with-uncategorize — that can break the
  invariant is a defect, and the done-check requires a test after **each** of those four.
- **Every automatic categorization writes an audit entry attributed to the SYSTEM, naming the
  rule that fired** (NFR-A2, AC-F5.2). The user must always be able to answer "why is this in
  this category?". A bulk historical re-apply that writes no history is a defect (AC-D4.4).
- **AC-D3.1/D3.2 — user correction always wins.** No automatic re-learning may silently overwrite
  an explicit user choice, and per ADR-008 an automatic match must **never** create or mutate a
  rule; only explicit user action does.
- **AC-D2.4 — a never-seen merchant must never be confidently categorized by coincidence.** T4
  exists precisely to be surfaced as "did you mean…" rather than applied. The observable bar is
  *match, or flag; never silently miscategorize.*
- **AC-C5.2 — bulk undo restores each transaction's own prior category**, not a default. And undo
  is a new event that writes its own audit entries, never an erasure of the previous ones
  (NFR-A3). This is the same property KHA-88 just failed on the merge path; do not re-fail it here.
- **P4b inherits O-QA-8 (KHA-90) as a hard requirement, not an observation.** The moment KHA-32
  routes `NeedsReviewScreen`, that screen's single-tap `onMerge!(item)` becomes a live one-tap
  merge — the operation this plan itself calls the highest-risk in P3, with no confirmation, while
  the strictly safer soft delete requires a dialog. R-8's "user-confirmed, never automatic"
  guarantee currently rests on a caller that does not exist yet; KHA-32 is that caller.
  **P4b must ship the merge confirmation before or with the route.** Same for
  `onKeepBothDuplicates` and `onTransferVerdict`, and for the four P3b-2 providers O-QA-9 lists as
  constructed-but-never-watched — those are the loose ends whoever wires navigation picks up.
- **NFR-M3 still applies to the tuning corpus.** `autoApplyThreshold` is tuned against
  *synthetic* merchant strings. No real merchant string from the user's SMS enters the repository,
  a test fixture, or a PR body.

**Exit check:** the electric-bill case (AC-D2.1) passes end to end; a correction updates the
rule and the next matching transaction arrives pre-categorized without user action; a
never-seen merchant is never assigned a confident category by coincidence (AC-D2.4); the
category-sum invariant (AC-C1.3) holds after create, rename, delete-with-reassign and
delete-with-uncategorize; a one-off correction does **not** become a rule and the previously
learned rule still applies to the next transaction (AC-D5.2); a rules-screen edit with
"re-apply to history" writes **one audit entry per affected transaction**; and — the artifact
this phase must not lose — **KHA-87 and KHA-88 are closed before P4b merges**, since P4b is the
PR that routes the screens the gate names.

---

### P5 — UI, reporting and privacy controls (Epics E, F)
**Owner:** mobile-engineer. Starts after P3; **partially parallel with P4**.

Screens (home dashboard with current-month total and review count; transaction list and
detail; search and filter; bank and instrument pages; category, card and month-over-month
reports; privacy and data-control settings with export, erase-all and the transparency
screen; the change-history view) plus a dedicated accessibility and RTL conformance pass
across NFR-U1..U8.

**Parallelism note:** presentation work for Epics B and E can begin as soon as the P3 domain
model is stable, while the P4 learning loop is still being built — *except* the correction
flow and the rules screen, which belong to P4 and depend on the rule store.

**Exit check:** every screen in `docs/design.md` is implemented and renders correctly in
Arabic RTL and English LTR at the largest OS font size with no truncation; every displayed
total is traceable to its constituent transactions (NFR-A6).

---

### P6 — Budgets and alerts (Epic G)
**Owner:** mobile-engineer. After P3 (needs correct spend totals) and P5 (needs the reporting surface). Can run parallel with P7.

Per-category and overall monthly budgets on calendar months (OQ-12); progress display;
threshold alerts via local notifications, opt-in per budget.

**Exit check:** crossing 100% fires exactly one alert per budget per period; no alert fires
for a category with no budget (AC-G3.2); budget progress excludes income and internal
transfers (per US-B10/B11).

---

### P7 — Statement reconciliation (Epic H)
**Owner:** mobile-engineer. After P4 (reconciliation-added transactions must train the same learning loop). Can run parallel with P6.

CSV import (must-have), PDF import (**at risk — see R-6**), the matching engine, and a
reconciliation report showing matched / newly-added / unmatched counts.

**Exit check:** every statement line ends as matched, added, or explicitly flagged unmatched
— never silently dropped; a reconciliation-added transaction trains the learning loop
identically to an SMS-derived one (AC-H3.1).

---

### P8 — Encrypted backup and restore (Epic I)
**Owner:** mobile-engineer. ~~*(or backend-engineer, only if the ADR chooses a custom service)*~~ — **void: ADR-001 chose no backend, see §2.1.** After P3; ideally last among feature phases so the schema has settled.

Encrypted backup, key management and **key recovery**, restore onto a new device.

**Exit check:** the backup blob is unreadable to whoever holds the cloud account; a second
or wiped device restores transactions, instruments, categories, learned rules and budgets in
full (AC-I3.1); and critically, **the restore works without the original device present** —
otherwise the feature does not solve the problem it exists for (see R-2).

---

### P9 — QA hardening and acceptance
**Owner:** qa-tester. Runs *continuously alongside* P2–P8, then a dedicated hardening pass.

| Work | Done check |
|---|---|
| `docs/test-plan.md` — AC traceability matrix | Every AC in PRD §5 has a test case ID |
| Parser regression corpus automation (NFR-M2) | Corpus runs in CI; a rule change that breaks a previously-passing message fails the build |
| Security and privacy verification | Network monitoring during normal use shows zero financial data leaving the device (AC-F4.2); logs contain no amounts, merchants or identifiers; the at-rest DB is unreadable without the key; masking holds in every view |
| Accessibility and RTL audit | Arabic RTL and English LTR both pass; TalkBack reads amounts, categories and card names correctly; contrast ≥4.5:1; debit/credit and needs-review are distinguishable without colour |
| End-to-end acceptance run + `docs/defects.md` | Every AC has a recorded pass / fail / blocked result |

QA should be writing the traceability matrix **during P0**, not waiting for code. It is the
one artifact that can be produced entirely from the approved PRD.

---

> **Process change — team v2 (2026-07-28).** QA is no longer only a parallel authoring track:
> it is now a **merge gate**. qa-tester (now opus) must return an explicit `QA: PASS` /
> `QA: FAIL` verdict on each PR, including a contract/integration stage and an adversarial
> security pass (injection, authz bypass, money-math edge cases, replay, mass-assignment), and
> **code-reviewer refuses to merge without `QA: PASS`** in addition to green CI. This applies
> to `/fix-bugs` as well as `/build`.
>
> Two consequences for the phases above: every feature PR from P3 onward routes
> **engineer → qa → code-reviewer**, never engineer → code-reviewer; and `docs/test-plan.md`
> is a living document that gains its epic's traceability rows as part of that phase's QA
> gate, rather than waiting for a P9 catch-up (it currently covers Epic 0 and Epic A only, so
> **P3's QA pass owes Epic B rows**).

---

### P10 — Review, merge and staging release
**Owners:** code-reviewer (merge on green CI **and** `QA: PASS`), devops-engineer (signed staging APK), production-support (thereafter).

**Exit check:** a signed APK is installed on the user's real device, ingests real SMS, and the
human confirms the current-month total matches reality. That last confirmation is the only
acceptance test that actually matters for this product.

---

## 4. Dependency order at a glance

```
P0  Architecture + Design  ── HUMAN GATE 2 ──┐   (spike: background SMS runs inside P0)
                                             v
P1  CI · secure storage · money · audit  (devops ∥ mobile)
                                             v
P2  SMS ingestion + parsing (Epic A)
                                             v
P3  Domain model: banks/instruments/transactions (Epic B)
                    │
        ┌───────────┴────────────┐
        v                        v
P4  Categorization +         P5  UI + reporting + privacy
    learning (C, D)              (E, F)   [partially parallel]
        │                        │
        └───────────┬────────────┘
                    v
        ┌───────────┼────────────┐
        v           v            v
P6 Budgets     P7 Statements   P8 Backup/restore     [all three parallel]
   (G)            (H)             (I)
                    v
P9  QA hardening  (runs continuously from P2; dedicated pass here)
                    v
P10 Review · merge · staging APK
```

### Strictly sequential (do not overlap)
- P0 → P1: nothing is built before both gate-2 docs are APPROVED.
- P1 → P2: the money type and audit trail must exist before any transaction is written.
- P2 → P3: model the domain against real parser output, not against guesses.
- P3 → P4: the learning loop needs a stable merchant field to key on.
- **P3b-3 → P4b** *(added 2026-07-29)*: KHA-87/88 must close before any PR routes
  `NeedsReviewScreen`, `RecentlyDeletedScreen` or `TransactionDetailScreen` — which P4b does by
  necessity, not by choice (AC-C2.2 and AC-C4.1/4.2). See **R-15**. Sequenced as
  **P3b-3 → P4a → P4b**; P4a is not gated but shares the lane, so it runs second, not concurrently.
- P4 → P7: reconciliation must reuse the learning loop, not fork it.

### Safe to run in parallel
- P0: architect and designer, simultaneously (both read only the PRD).
- P0: the background-SMS spike, alongside both.
- P1: devops CI work ∥ mobile foundation work — no shared files.
- P2 internally: classifier ∥ importer ∥ dedup ∥ review queue, once the rule-engine interface is fixed.
- P4 ∥ P5: learning loop ∥ presentation/reporting, after P3 lands.
- P6 ∥ P7 ∥ P8: three independent feature areas over a settled domain model.
- P9: QA authoring runs continuously from P0 and never blocks engineering.

### The critical path
`P0 → P1 → P2 → P3 → P4 → P7 → P9 → P10`. Everything that can slip without moving the end
date is off it. **P2 (parsing) is the highest-variance item on the path** — parser quality
determines whether this product works at all, and it is bounded by SMS content the team
does not control (CON-3).

---

## 5. Banking-domain implications called out per phase

Per the team's standing rule, security, auditability and data-privacy consequences are
stated explicitly rather than assumed.

### Security
- **P1 is where security is won or lost.** Encryption at rest (NFR-S1), masking (NFR-S2),
  log scrubbing (NFR-S4) and app lock (NFR-S3/S8) are foundation work, not a hardening
  sprint at the end. A design that stores plaintext first and encrypts later will leak
  through backups, logs and crash dumps.
- **The app must handle SMS that contain things it must refuse to store.** NFR-S2 requires
  redaction *before* storage if a message ever carries a full PAN or credential. That is a
  parser-layer responsibility in P2, not a display-layer one in P5.
- **Raw SMS text is retained** (AC-B1.2 lets the user verify a parse). It is therefore
  encrypted, masked-on-display, excluded from logs, and covered by erase-all (AC-F3.1).
- **Key recovery is the sharpest edge in the whole build** — see R-2. A device-bound key
  makes the backup unrestorable; a weak user passphrase makes it decryptable. This is an
  architecture decision, and it is security-critical.
- `security-sensitive` in Linear marks the issues where code-reviewer must do an explicit
  security review rather than a functional one.

### Auditability
- NFR-A2/A3 require an **append-only** history of every mutation with actor (user vs. system
  rule), timestamp, and before/after values — and it must not be editable from the UI. Note
  honestly: on a device the user fully controls, "append-only" is enforceable at the
  application layer, not against a determined owner with a database editor. The architect
  should state the enforcement boundary rather than over-claim it.
- NFR-A1 provenance: every transaction knows whether it came from SMS (with a reference to
  the source message), manual entry, or statement reconciliation. P7 must not create a
  fourth, untracked path.
- NFR-A6: no derived figure may exist that cannot be traced back to its constituent
  transactions. This constrains P5 and P6 — no cached totals that can drift from the ledger.
- NFR-A4: exact decimal arithmetic. Dart has no built-in decimal type; **this is a P1
  decision with consequences in every later phase** (see R-3).

### Data privacy
- AC-F4.2 is a **testable** privacy claim, not marketing copy: under network monitoring, no
  financial data leaves the device. QA must actually run that test (P9). It also means no
  analytics SDK, no crash reporter that ships message content, no third-party font or map
  call that carries a payload (NFR-S6, X13).
- NFR-P4: non-financial SMS must not be indexed or retained beyond the instant needed to
  reject them. The classifier in P2 must discard, not archive.
- NFR-M3: real bank SMS never enter the repository. This is a hard rule for every agent,
  including when reporting a defect — a defect report quoting a real SMS violates it. QA
  and production-support must reproduce with synthetic equivalents.
- Epic I is the **only** intentional egress of financial data in the product. It must be
  encrypted such that the storage provider and the cloud account holder cannot read it
  (AC-I2.1), and the transparency screen (US-F4) must describe it accurately.
- The manual export (US-F2) is deliberately **unencrypted** (OQ-13/NFR-S7). That is an
  accepted trade-off, but the warning in AC-F2.3 is therefore a required control, not a nicety.

---

## 6. Risks

| ID | Risk | Impact | Mitigation / owner |
|---|---|---|---|
| **R-1** | **Background SMS reception is unreliable on modern Android.** Restricted permissions, Doze, and OEM battery managers can kill a background receiver. NFR-R1 promises single-digit seconds. | Core promise of the product degrades to "updates when you open the app". | **PARTLY REALISED, AND THE MITIGATION WAS NEVER RUN — see R-12.** The P0 spike (KHA-7) is still in Backlog with no recorded outcome, so P1 and P2 both shipped on unverified assumptions. ADR-018 has meanwhile already renegotiated NFR-R1 downward on *different* grounds (the app lock), flagged to the human as H-13. **Owner: mobile-engineer + solution-architect.** |
| **R-2** | **Backup key recovery.** If the encryption key lives only in the Android Keystore it is device-bound, and a lost device means an unrestorable backup — defeating US-I3 entirely. If it's derived from a user passphrase, a weak passphrase weakens AC-I2.1. | Epic I silently fails at the exact moment it's needed. | Architect must specify key derivation, escrow and recovery explicitly in the ADR, and QA must test restore **on a device that has never seen the original key**. |
| **R-3** | **Exact decimal money in Dart.** There is no native decimal type; a `double` creeping into one aggregation path silently corrupts totals and violates NFR-A4. | Wrong numbers, undetectably. | P1 decision, enforced by a lint/CI rule banning `double` in money paths plus property-based tests. **Owner: solution-architect (choice), mobile-engineer (enforcement).** |
| **R-4** | **Parser brittleness.** Bank SMS formats change without notice (NFR-M1), and coverage is bounded by what the SMS actually says (CON-3). Only two banks and nine message types are sampled. | Transactions land in the unparsed queue; the user loses trust. | Data-driven rule sets, updatable without redesign; the review queue (US-A4) is the safety net so nothing is lost; corpus regression in CI. Collect more real samples over time (residual OQ-2) — via synthetic transcription only. |
| **R-5** | **Merchant matching across Arabic and Latin script**, with store numbers, spacing and reference codes attached (AC-D2.3). Too loose merges unrelated merchants; too strict makes the user re-tag forever. | The learning loop — the product's core value — underperforms. | Normalization strategy is an architecture decision; the observable bar is "match or flag, never silently miscategorize". Tune against the corpus, not against intuition. |
| **R-6** | **On-device PDF statement parsing is hard.** Bank PDF layouts vary, may be image-based, and may be password-protected. | P7 overruns or ships something unreliable. | **Recommend to the human: ship CSV first as the must-have, treat PDF as best-effort within P7 and deferrable to v1.1 without harming the release.** Architect to assess feasibility in the ADR. |
| **R-7** | **Internal-transfer detection bootstraps from incomplete knowledge.** The app only knows which accounts are "the user's own" after it has seen them (US-B11, AC-B11.2). | Early transfers get misclassified as spending, inflating totals. | AC-B11.2 already requires flagging-for-review rather than guessing. Designer must give that flag a first-class place in the UI, not a corner. |
| **R-8** | **Auth-alert vs. posting-alert duplicates** (AC-A5.2) and genuine same-merchant same-amount same-day purchases (AC-A5.3) pull dedup in opposite directions. | Either inflated totals or silently deleted real transactions — the second is worse. | Bias hard toward flagging over auto-merging. Never auto-remove. Transaction reference numbers, where present (§3.4), are the reliable key. |
| **R-9** | **Single-implementer bottleneck.** mobile-engineer owns ~85% of the work; P2–P8 are mostly one lane. | Little real parallelism after P1; slippage compounds. | Sequence to maximize the genuine parallel windows (P4∥P5, P6∥P7∥P8), keep QA off the critical path, and keep PRs small so review never becomes a queue. |
| **R-10** | **No telemetry, by design** (NFR-S6, X13) — and no app store, so no store crash reporting either. | production-support has almost nothing to triage with; field bugs surface only as the user describing them. | Accept it: it is the correct privacy posture. Compensate with a local, user-visible, redaction-safe diagnostic log the user can share deliberately. **Flag A-14 for the architect.** |
| **R-11** | **Side-load distribution means no update channel.** Every fix requires the user to install an APK manually (OQ-4/X16). | Slow fix propagation; parser rule updates can't be pushed. | devops should make the staging APK trivially installable; architect should consider whether parser rules can be updated as data without a full reinstall (NFR-M1). |
| **R-12** *(added 2026-07-28)* | **The P0 device spike (KHA-7) was never run, and it is the one task no agent can do.** It needs the user's real phone. P0's exit check was written as "the human marks both gate-2 docs APPROVED", which the build satisfied — but §P0 also called the spike "not optional", and that half was never enforced. Two phases of ingestion code now rest on its unverified assumptions, and PR #2's own "Honest limits" says so plainly. | If the broadcast turns out to be suppressed on the target OEM, the fix is a *default* change (ADR-006 Layer 3 becomes default-on), not a redesign — so the blast radius is bounded. But it stays unknown until someone runs it, and it is compounding: every phase adds code above it. | **Escalate to the human now, not at P10.** It does not block P3 (domain modelling is pure logic over already-parsed output). It *should* block the P10 staging sign-off. KHA-58's `ingest.skipped.locked` diagnostic is a partial substitute — it makes "locked, working as designed" distinguishable from "broadcast never arrived" from the outside. **Owner: human (device) + mobile-engineer (harness).** |
| **R-14** *(added 2026-07-28)* | **Nobody has ever successfully unlocked this app on real hardware.** Two consecutive real-device blockers on first run: KHA-71 (the app lock could never show a prompt — fixed, PR #13) and now **KHA-75, Urgent and open** (a correct fingerprint *and* a correct device PIN both report "auth failed", most likely first-run Keystore key provisioning throwing and being swallowed by a `catch (_)`). Nine merged PRs of product code have never been executed end-to-end by a human. | Every device-facing assumption in the build is unverified at once — not just SMS latency (R-12) but the app lock, the Keystore, and SQLCipher key provisioning on this OEM's TEE. The pattern is that each real-device session finds a new first-run blocker, which suggests more remain. | KHA-75 is being diagnosed on an emulator repro now. **Do not treat P3b progress as progress toward a usable product** — the domain model is being built above a gate no user has passed. One upside, recorded because it is load-bearing elsewhere: since the DB key is provisioned *behind* that gate, no encrypted database and therefore **no audit rows can exist on any real install**, which is what makes KHA-69's option (a) provably correct today rather than merely plausible. **Owner: mobile-engineer (KHA-75) + human (device).** |
| **R-13** *(added 2026-07-28)* | **No branch protection on this repo (KHA-55)** — GitHub free plan. The `/build` design leans on "green CI + strict reviewer" as the merge gate, but nothing *server-side* enforces it: a green `ci` check is a convention, not a requirement. | An agent could in principle merge a red or unreviewed PR, and the design's central safety claim would not hold. | Accepted risk, recorded in the user's notes. Compensating controls: code-reviewer is the only agent permitted to merge, the team-v2 `QA: PASS` gate adds a second independent verdict, and **manager is explicitly forbidden from merging** even when told to break deadlocks. Revisit if the repo ever moves to a paid plan. |
| **R-15** *(added 2026-07-29)* | **Two High-severity money/audit defects are live in `main` and are held harmless by nothing but the absence of a navigation route.** KHA-87: resolving a duplicate silently drops the absorbed row's FX fee and converted amount out of the reported figures. KHA-88: `restore()` clears the survivor's merge pointer without checking which row it names, and appends no audit entry against the survivor — an NFR-A2 gap on **every** merge undo. Both shipped in PR #20 with QA and code-reviewer's explicit, correct agreement that no shipped code path can reach them today: the app shell routes only to `HomePlaceholderScreen`. | The mitigation is one line of routing code away from evaporating, and it evaporates **silently** — nothing fails, nothing warns; a total just becomes wrong. The failure mode is KHA-74's ("money absent from a total with no signal") through a new write path, which is the class of defect this product can least afford. | **This is not an accepted risk, it is a scheduled one.** code-reviewer recorded a binding gate at PR #20: KHA-87/88 block any PR routing `NeedsReviewScreen`, `RecentlyDeletedScreen` or `TransactionDetailScreen`, **and any build reaching a device**. That gate is honoured here as **P3b-3**, sequenced ahead of P4a, and both issues are now blocking-linked in Linear to KHA-32 and KHA-33. Note the second clause too: **R-12's device spike and R-14's real-device runs are also inside this gate** — no APK goes to hardware until it is paid. **Owner: mobile-engineer.** |

---

## 7. Open questions the plan surfaced — for gate 2

These are **flags, not answers**. Planning is not the place to decide them.

> **Status: gate 2 closed — A-1…A-15 and D-1…D-12 are answered** in `docs/architecture.md`
> (ADR-001…ADR-018) and `docs/design.md`, both APPROVED. Kept here as the record of what
> planning demanded be decided, and as the checklist to re-run if the PRD ever changes.
> Answers have since moved on in one place: **ADR-018** (background ingestion vs. the
> cryptographic app lock) was raised *during* P2, not at gate 2, and it renegotiated NFR-R1
> — flagged to the human as **H-13**. A-2's answer remains provisional on the unrun KHA-7
> spike (**R-12**).

### 7.1 For the solution-architect (`docs/architecture.md`)

| # | Question |
|---|---|
| **A-1** | **Is there a backend at all?** State it explicitly. If yes, justify it against NFR-P2, NFR-R4, CON-1 and AC-F4.2. If no, say so plainly so `/build` never dispatches a backend-engineer by habit. See §2.1. |
| **A-2** | Background SMS strategy on the target Android version and OEM, and the **honest** achievable latency against NFR-R1. Informed by the P0 spike. |
| **A-3** | Encryption at rest: whole-database vs. field-level, key storage, key rotation, and what happens on device credential change. |
| **A-4** | **Backup key derivation, escrow and recovery** — the mechanism that makes AC-I3.1 actually work from a lost device. Highest-stakes decision in the ADR (R-2). |
| **A-5** | The exact-decimal money representation (minor-unit integers vs. a decimal package) and how it is enforced in CI (R-3). |
| **A-6** | The parser rule model: how per-bank, per-message-type rules are expressed, and how they are updated without a redesign (NFR-M1) — and, given side-loading, whether rules can update as data (R-11). |
| **A-7** | Merchant normalization and matching strategy across Arabic/Latin script, and where the confidence threshold for "needs review" lives (residual OQ-14, AC-C4.1). |
| **A-8** | Duplicate-detection strategy: reference-number-keyed where available, heuristic fallback otherwise, and the auth-vs-posting case (R-8). |
| **A-9** | FX handling: prefer the SMS-supplied converted amount and rate; what happens when a foreign-currency message carries no conversion, given the offline requirement (NFR-R4, AC-B9.3). |
| **A-10** | Audit-trail enforcement boundary — where append-only is genuinely enforced vs. where it is an application-layer convention (NFR-A2/A3). Do not over-claim. |
| **A-11** | Statement PDF feasibility on-device, and whether PDF should be descoped from v1 (R-6). |
| **A-12** | How "erase everything" (AC-F3.1/F3.3) reaches *every* copy — local DB, cached SMS, audit history, exports and **the cloud backup**. A hard delete that leaves an encrypted cloud copy is not a hard delete. |
| **A-13** | Redaction-before-storage: where in the pipeline a credential-bearing SMS is scrubbed (NFR-S2, NFR-C2). |
| **A-14** | Diagnostics with no telemetry: what production-support can actually work from, given NFR-S4/S6 (R-10). |
| **A-15** | `FLAG_SECURE` / snapshot obscuring (NFR-S8) vs. QA's need for screenshots — how the two coexist without shipping a bypass. |

### 7.2 For the ui-ux-designer (`docs/design.md`)

| # | Question |
|---|---|
| **D-1** | **Arabic-first RTL** end to end (NFR-U8): mirrored layouts, and an explicit decision on Eastern-Arabic vs. Western digit rendering for amounts. |
| **D-2** | The **default starting category list** (OQ-18), including whether "loan/finance installment" is its own category as PRD §3.4 suggests. |
| **D-3** | The **correction flow** — the highest-frequency interaction in the product (NFR-U7, AC-C2.2 ≤ 2 screens) — including how the US-D5 scope choice ("this only" vs. "this and future") is offered without adding friction. Get this wrong and the learning loop never trains. |
| **D-4** | Non-colour indicators for debit vs. credit and for needs-review (NFR-U4). |
| **D-5** | The information architecture for **bank → account/card**, keeping account activity and card activity visibly distinct (AC-B13.3). |
| **D-6** | Masked identifiers everywhere, and how an auto-created, not-yet-renamed instrument presents itself (AC-B15.2). |
| **D-7** | The unparsed / needs-review queue, including showing raw SMS text and the "not a transaction" dismissal (US-A4). |
| **D-8** | All the unhappy states: permission never granted, permission revoked mid-life (AC-A1.3), import in progress, no data yet, filter returns nothing, not enough history to compare (AC-E4.2). |
| **D-9** | Permission priming before the SMS request — the app is unusable if the user declines. |
| **D-10** | The transparency screen (US-F4) — plain-language, accurate, and it must be updated if the ADR introduces any egress. |
| **D-11** | Large-font/no-truncation behaviour for long Arabic merchant names alongside amounts (NFR-U3). |
| **D-12** | Budget progress and alert presentation (US-G3/G4). |

### 7.3 For the human

| # | Question | Status (2026-07-28) |
|---|---|---|
| 1 | **Confirm the no-web-frontend call** in §2 — this plan dispatches no React work at all. | ✅ Settled by ADR-001. No web surface exists or will. |
| 2 | **Confirm the backend posture** in §2.1 once the ADR lands. | ✅ Settled: ADR-001 chose no backend, CI-enforced. |
| 3 | **Decide on PDF statement import** (R-6): must-have for v1, or CSV-first with PDF in v1.1? | ⬜ **STILL OPEN.** Not yet needed — P7 is several phases away — but it should be answered before P7 is planned, not during it. |
| 4 | More real SMS samples are still welcome (residual OQ-2) — other banks, and edge cases like declines and partial refunds. Share the *structure*, never the raw text (NFR-M3). | ⬜ Standing invitation. Directly reduces R-4. |
| 5 | **Run the KHA-7 background-SMS spike on your real device** (**R-12**, added 2026-07-28). | 🔴 **STILL NEEDED — no agent can do this.** Three phases of code now rest on assumptions it was meant to verify. It does not block P4. **Note the new constraint (R-15): the gate code-reviewer set at PR #20 blocks "any build that reaches a device" until KHA-87/88 are fixed — so this spike should wait for P3b-3 to land, then run.** That is a sequencing improvement, not a further delay: it means when you do run it, you are running a build whose merge/undo paths are sound. |
| 6 | **NFR-R1 has been renegotiated downward** since you approved the PRD: ADR-018 (H-13) changes the promise to "seconds while unlocked; seconds from unlock, with nothing lost, while locked." | ⬜ **Please confirm you accept this**, since it alters a promise in an approved document. |
| 7 | **KHA-75 blocks all real-device use** (R-14) — no one has unlocked the app on hardware yet. | ✅ **FIXED (PR #17).** Root cause was ours, not the OEM's: `KeystoreChannel.intListArg` read byte arguments as `List<Integer>` while Flutter encodes a Dart `Uint8List` as typed data that Kotlin decodes as `byte[]`, so every wrap/unwrap threw `ClassCastException` on **every** Android device. QA verified all four unlock journeys on a real API-35 device with PIN and fingerprint enrolled. R-14's premise is retired; R-15 now carries the "don't ship to a device yet" constraint for a different reason. |
| 9 | **Nothing is asked of you for P4.** Recorded explicitly so the absence is deliberate: both of P4's apparent blockers turned out to be already answered (design.md §4's category list; ADR-008's `autoApplyThreshold = 0.85`), and every remaining P4 choice is an engineering one. The build proceeds without you until P7's PDF question (#3) or a real-device run (#5). | ⬜ No action needed. |
| 8 | **KHA-69's decision should be taken now, while it is free.** The audit-chain fix is forward-only, so pre-P3a audit rows would stay permanently unverifiable. Option (a) — "confirm no install carrying pre-P3a audit rows exists" — is **provably true today**, because the database key is provisioned behind the app-lock gate that KHA-75 shows nobody has ever passed: no unlock, no database, no audit rows. | ✅ **DONE — option (a) taken, recorded and dated 2026-07-29** in `docs/architecture.md` next to ADR-010, with the standing condition that the P10 staging APK goes onto a **clean install**. Taken inside the window; it closed on the same day PR #17 made the first successful hardware unlock possible. KHA-53/P10 is unblocked. |

---

## 8. Linear organization

Project: **Massrofy — Personal Spending Tracker from Bank SMS** (team `KhaledBawazir` / `KHA`).

- **Milestones `P0`–`P10`** are the phases above, each carrying its exit check. They encode
  the dependency order — do not start a milestone before its predecessor's exit check is met.
- **Epic labels** `epic-A-sms-ingestion` … `epic-I-backup-sync` map 1:1 to PRD epics A–I.
  `epic-0-foundation` covers cross-cutting work that has no PRD epic (CI, storage, money,
  audit, app lock).
- **Owner labels** `owner-solution-architect`, `owner-ui-ux-designer`, `owner-devops-engineer`,
  `owner-mobile-engineer`, `owner-qa-tester` route work at `/build`.
  `owner-backend-engineer-CONDITIONAL` marks the issues that exist **only if** the ADR chooses
  a custom backend (§2.1).
- **`security-sensitive`** requires an explicit security review from code-reviewer, not just
  a functional one.
- **`needs-architecture-decision`** means the issue cannot start until the ADR answers a
  named question from §7.1.

Every issue carries its PRD story and AC references, and a "Done check" that QA can verify.

### Issue index (KHA-5 … KHA-53 as planned, plus follow-ups born in review)

> **The original index is no longer the whole set.** Review, QA and CI have since created
> real work above KHA-53 — KHA-54, KHA-55, KHA-58, KHA-62, KHA-64, KHA-66 and others. Treat
> **Linear as the source of truth for issue state**; this table is the planned skeleton, not
> a census. Follow-ups are listed against the phase that must close them.

| Milestone | Issues | Owner(s) |
|---|---|---|
| P0 — Gate 2 | KHA-5 ADR ✅ · KHA-6 UI design ✅ · **KHA-7 background-SMS spike — STILL IN BACKLOG, NEVER RUN (R-12)** | architect, designer, mobile |
| P1 — Foundation | KHA-8 CI · KHA-9 signed APK · KHA-10 scaffold/RTL · KHA-11 money type · KHA-12 encrypted store · KHA-13 masking/redaction · KHA-14 audit trail · KHA-15 app lock — **all ✅ merged (PR #1)** | devops, mobile |
| P2 — Ingestion (A) | KHA-16 permissions · KHA-17 background receiver · KHA-18 classifier · KHA-19 parser engine · KHA-20 historical import · KHA-21 dedup · KHA-22 review queue — **all ✅ merged (PR #2)**; +KHA-54 sanitizer gaps ✅ · KHA-58 `ingest.skipped.locked` diagnostic ⬜ | mobile |
| P3a — Domain spine (B) | KHA-23 bank/instrument hierarchy ✅ · KHA-24 card↔account link ✅ *(shipped inside P3a; was stale in Backlog until 2026-07-28)* · KHA-25 transaction record ✅ · KHA-64 first half (S-19 / AC-A4.2) ✅ — **merged PR #11** | mobile |
| P3b-1 — What a total means (B) | KHA-27 multi-currency (owns **KHA-70**) · KHA-28 refunds/credits · KHA-29 income/ATM/internal transfers — **all ✅ merged (PR #18, schema v4)**; follow-ups KHA-79 ✅, KHA-80 ✅, KHA-81 ⬜ | mobile |
| P3b-2 — Mutation surface (B) | KHA-26 ✅ · **KHA-64 second half — ADR-017 D2 enrichment merge** ✅ · KHA-66 ✅ · KHA-74 ✅ · **KHA-69** audit-chain decision ✅ *(option (a), recorded and dated 2026-07-29 in `docs/architecture.md`; unblocks KHA-53/P10)* · KHA-78/79/80 ✅ — **all merged (PR #20, schema v5)** | mobile |
| **P3b-3 — Merge/undo debt** *(new, 2026-07-29)* | **KHA-87** merge drops the FX fee + converted amount *(High, `security-sensitive`)* · **KHA-88** `restore()` corrupts the survivor's merge link and audits nothing against it *(High, `security-sensitive`)* · **KHA-89** user intent lost on the merge's losing side *(Medium — same two files, same root cause as KHA-87)* · **KHA-90** O-QA-5 + O-QA-7 only. All ⬜ Backlog. **KHA-87/88 block P4b — see R-15.** KHA-90's **O-QA-8** is a P4b requirement, not P3b-3 work | mobile |
| P4a — Categorization spine (C, D) | KHA-30 category model + seeded 13-item list (design.md §4) · KHA-31 merchant rule store, normalisation, alias table, tiered matching (ADR-008) — ⬜ Backlog. **Schema v7.** Not gated | mobile |
| P4b — Learning-loop surface (C, D) | KHA-32 confidence/flagging *(`needs-architecture-decision` removed — ADR-008 answers A-7)* · KHA-33 correction flow + scope choice + bulk/undo · KHA-34 rules screen + re-apply to history — ⬜ Backlog. **Gated: routes `NeedsReviewScreen` + `TransactionDetailScreen`, so KHA-87/88 must close first** | mobile |
| P5 — UI (E, F) | KHA-35 dashboard · KHA-36 list/bank screens · KHA-37 reports · KHA-38 search/filter · KHA-39 privacy controls · KHA-40 change history · KHA-41 a11y/RTL pass | mobile |
| P6 — Budgets (G) | KHA-42 budgets · KHA-43 alerts | mobile |
| P7 — Statements (H) | KHA-44 CSV/PDF import · KHA-45 reconciliation | mobile |
| P8 — Backup (I) | KHA-46 encrypted backup · KHA-47 restore | mobile *(ADR-001: no backend, §2.1)* |
| P9 — QA | KHA-48 test plan ✅ (Epic 0 + A + the P3a slice of Epic B) · KHA-49 parser corpus · KHA-50 security/privacy verification · KHA-51 a11y audit · KHA-52 E2E acceptance | qa |
| P10 — Release | KHA-53 staging release, **blocked by KHA-69** · **KHA-7 device spike must close here at the latest (R-12)** | reviewer, devops |
| Real-device bugs (R-14) | KHA-71 app lock never showed a prompt ✅ (PR #13) · **KHA-75 correct fingerprint/PIN both report "auth failed" — Urgent, open, being diagnosed now** · KHA-72 swallowed platform errors · KHA-73 pre-API-28 biometric theming | mobile |
| Cross-cutting | KHA-55 no branch protection (GitHub free plan — merge safety is convention-only, accepted risk) · KHA-62 emulator CI flakiness ✅ (PR #7, #8) · KHA-65 job timeouts ✅ (PR #9) · KHA-67 emulator deadlines (PR #14, still In Progress by devops' own scoping — two jobs' historical hangs were never fully explained) | devops |

Blocking relations are set in Linear on the issues where the dependency is load-bearing
(e.g. KHA-19 parser blocks KHA-20/21/22/23; KHA-31 rule store blocks KHA-32/33/34;
KHA-46 backup blocks KHA-47 restore). The milestone order carries the rest.

Two issues could be started **before** gate 2 closed, because they needed only the approved
PRD: **KHA-7** (the background-SMS spike, whose result was to feed the ADR) and **KHA-48**
(the QA traceability matrix). In the event, KHA-48 was done late (retroactively, in PR #4)
and **KHA-7 was never done at all** — the lesson is recorded in `docs/lessons.md`.

Also note the `owner-backend-engineer-CONDITIONAL` label described above is now **dead** —
ADR-001 settled §2.1 against a backend, so nothing should ever carry it.

---

*End of build plan. Gate 2 is closed: `docs/architecture.md`, `docs/brand.md` and
`docs/design.md` are APPROVED and product code is being written against them. This document
is no longer a pre-build plan but a live one — the manager updates it between phases as
reality diverged, and `docs/build-log.md` records each phase's actual dispatch and outcome.*
