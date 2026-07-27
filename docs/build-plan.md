STATUS: DRAFT
# Massrofy — Build Plan

**Version:** 1.0
**Date:** 2026-07-27
**Author:** manager agent (phase 2 — planning)
**Source of truth:** `docs/PRD.md` v0.3, STATUS: Approved
**Linear project:** [Massrofy — Personal Spending Tracker from Bank SMS](https://linear.app/khaledbawazir/project/massrofy-personal-spending-tracker-from-bank-sms-1c491affcc87) (team `KHA`)

> This document plans **who builds what, in what order**. It deliberately makes **no
> architecture decisions** — those belong to `docs/architecture.md` (solution-architect)
> and `docs/design.md` (ui-ux-designer), both of which are human gate 2. Where planning
> surfaced a decision that must be made, it is recorded in §7 as a flag, not answered here.

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
| **solution-architect** | **Yes — next, blocking** | Gate 2. Must settle on-device vs. server, storage/crypto, background SMS strategy, parser rule model, backup key recovery. See §7. |
| **ui-ux-designer** | **Yes — next, blocking** | Gate 2. This is a UI-heavy product: ~12 screens, Arabic-first RTL, and the correction flow (NFR-U7) is the interaction the whole learning loop depends on. |
| **devops-engineer** | **Yes** | Flutter CI, branch protection (the merge safety net), signed-APK build, side-load staging channel. Small but genuinely required. |
| **mobile-engineer** (Flutter) | **Yes — primary implementer** | Owns essentially all product code: ingestion, parsing, domain model, learning loop, every screen, budgets, statements, backup client. |
| **frontend-engineer** (React web) | **NO — do not dispatch** | **There is no web surface in this product at all.** No admin console, no companion web app, no browser-based anything. The PRD's only client is the Android/Flutter app. Dispatching a React engineer would produce a deliverable nobody asked for and a second codebase to secure. |
| **backend-engineer** (Java/Spring) | **CONDITIONAL — do not dispatch yet** | See §2.1. There is very likely **no traditional backend** in this product. |
| **qa-tester** | **Yes** | 132 acceptance criteria across 9 epics need a traceability matrix; the parser corpus needs automated regression (NFR-M2); security/privacy claims (AC-F4.2) need active verification, not assertion. |
| **code-reviewer** | **Yes** | Merge gate on every PR. Extra scrutiny mandated on anything labelled `security-sensitive`. |
| **production-support** | **Yes, but reduced** | There are no server logs to triage. Its remit here is on-device crash/diagnostic triage and raising bugs — and it is constrained by NFR-S4/S6 (no sensitive values in logs, no telemetry SDK). See flag A-14. |

### 2.1 The backend question — flagged, not decided

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

> **Test data rule, non-negotiable (NFR-M3):** the user's genuine bank SMS must never be
> committed to a repository or pasted into any tool. The corpus is realistic-but-**synthetic**,
> authored from the structural patterns in PRD §3.4. QA owns enforcing this.

---

### P3 — Domain model: banks, instruments, transactions (Epic B)
**Owner:** mobile-engineer. Sequential after P2 (needs real parsed output to model against).

Bank/account/card hierarchy with auto-creation on first mention and entity resolution
(the same bank named in Arabic in one message and abbreviated in another must resolve to
**one** bank — AC-B12.3); friendly names that survive re-parsing; card↔settlement-account
linkage; the transaction record with provenance; manual entry, edit, soft delete and restore;
refunds and credits netting against spend; multi-currency with the FX-fee component kept as
its own field (PRD §3.4); income, ATM withdrawal and internal-transfer classification.

**Exit check:** fixtures produce the correct bank tree; category totals sum to the period
total (AC-C1.3); per-card totals sum to the period total (AC-E3.2); internal transfers are
excluded from spend; every stored amount carries a currency.

---

### P4 — Categorization and learning loop (Epics C, D)
**Owner:** mobile-engineer. Sequential after P3.

Category model with a default starter list (OQ-18 — the list is proposed by the designer in
P0, not invented in code); the categorization engine with a confidence notion and needs-review
flagging; the merchant→category rule store with normalization and matching that works across
Arabic and Latin script (merchant names appear transliterated in Latin even inside Arabic
messages — PRD §3.4); user-correction-always-wins precedence; the correction flow with the
"this one only / this and future" scope choice; bulk categorize with undo; the learned-rules
management screen.

**Exit check:** the electric-bill case (AC-D2.1) passes end to end; a correction updates the
rule and the next matching transaction arrives pre-categorized without user action; a
never-seen merchant is never assigned a confident category by coincidence (AC-D2.4).

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
**Owner:** mobile-engineer *(or backend-engineer, only if the ADR chooses a custom service — §2.1)*. After P3; ideally last among feature phases so the schema has settled.

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

### P10 — Review, merge and staging release
**Owners:** code-reviewer (merge on green CI), devops-engineer (signed staging APK), production-support (thereafter).

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
| **R-1** | **Background SMS reception is unreliable on modern Android.** Restricted permissions, Doze, and OEM battery managers can kill a background receiver. NFR-R1 promises single-digit seconds. | Core promise of the product degrades to "updates when you open the app". | P0 spike on the user's real device *before* the ADR is written. If it fails, the ADR must state the achievable latency and the PRD's NFR-R1 needs revisiting with the human. **Owner: mobile-engineer + solution-architect.** |
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

---

## 7. Open questions the plan surfaced — for gate 2

These are **flags, not answers**. Planning is not the place to decide them.

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
1. **Confirm the no-web-frontend call** in §2 — this plan dispatches no React work at all.
2. **Confirm the backend posture** in §2.1 once the ADR lands.
3. **Decide on PDF statement import** (R-6): must-have for v1, or CSV-first with PDF in v1.1?
4. More real SMS samples are still welcome (residual OQ-2) — other banks, and edge cases like
   declines and partial refunds. Share the *structure*, never the raw text (NFR-M3).

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

### Issue index (KHA-5 … KHA-53, 49 issues)

| Milestone | Issues | Owner(s) |
|---|---|---|
| P0 — Gate 2 | KHA-5 ADR · KHA-6 UI design · KHA-7 background-SMS spike | architect, designer, mobile |
| P1 — Foundation | KHA-8 CI · KHA-9 signed APK · KHA-10 scaffold/RTL · KHA-11 money type · KHA-12 encrypted store · KHA-13 masking/redaction · KHA-14 audit trail · KHA-15 app lock | devops, mobile |
| P2 — Ingestion (A) | KHA-16 permissions · KHA-17 background receiver · KHA-18 classifier · KHA-19 parser engine · KHA-20 historical import · KHA-21 dedup · KHA-22 review queue | mobile |
| P3 — Domain (B) | KHA-23 bank/instrument hierarchy · KHA-24 card↔account link · KHA-25 transaction record · KHA-26 manual/edit/soft-delete · KHA-27 multi-currency · KHA-28 refunds · KHA-29 income/transfers | mobile |
| P4 — Learning (C, D) | KHA-30 categories · KHA-31 merchant rule store · KHA-32 confidence/flagging · KHA-33 correction flow · KHA-34 rules screen | mobile |
| P5 — UI (E, F) | KHA-35 dashboard · KHA-36 list/bank screens · KHA-37 reports · KHA-38 search/filter · KHA-39 privacy controls · KHA-40 change history · KHA-41 a11y/RTL pass | mobile |
| P6 — Budgets (G) | KHA-42 budgets · KHA-43 alerts | mobile |
| P7 — Statements (H) | KHA-44 CSV/PDF import · KHA-45 reconciliation | mobile |
| P8 — Backup (I) | KHA-46 encrypted backup · KHA-47 restore | mobile *(backend only if ADR says so)* |
| P9 — QA | KHA-48 test plan · KHA-49 parser corpus · KHA-50 security/privacy verification · KHA-51 a11y audit · KHA-52 E2E acceptance | qa |
| P10 — Release | KHA-53 staging release | reviewer, devops |

Blocking relations are set in Linear on the issues where the dependency is load-bearing
(e.g. KHA-19 parser blocks KHA-20/21/22/23; KHA-31 rule store blocks KHA-32/33/34;
KHA-46 backup blocks KHA-47 restore). The milestone order carries the rest.

Two issues can be started **before** gate 2 closes, because they need only the approved PRD:
**KHA-7** (the background-SMS spike, whose result must feed the ADR) and **KHA-48** (the QA
traceability matrix). Everything else waits for both gate-2 documents to be APPROVED.

---

*End of build plan. This document is a plan, not an approval. Gate 2 — `docs/architecture.md`
and `docs/design.md` both marked APPROVED by the human — still stands between here and any
line of product code.*
