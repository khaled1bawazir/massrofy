# Massrofy — Build Plan

**Version:** 2.0 (2026-07-29) — **right-sized to `TIER: personal`.**
**Owner:** manager. **Source of truth for issue state: Linear.** This file is the plan only.

> **v2.0 is a deliberate trim, not a rewrite.** v1.6 had grown to 1,125 lines of
> client-grade ceremony (full risk register, per-phase banking-domain essays, the gate-2
> open-question checklist) on a single-user personal tool. `docs/PRD.md` now declares
> `TIER: personal`, which caps this file at ~150 lines. Cut at the P4/P5 boundary because
> nothing in flight referenced the removed sections. **The history is not lost** — v1.6 is
> in git (`137418c`), and the narrative lives in `docs/build-log.md`.

---

## 1. What this is

A single-user, offline-first Android app (Flutter) that turns bank SMS into a trustworthy
picture of personal spending. No backend, no network permission — ADR-001, CI-enforced by
`check_no_network_permission.sh`.

## 2. Who builds it

**Needed:** mobile-engineer (~85% of all work), devops-engineer, qa-tester, code-reviewer,
solution-architect (decisions only), manager.

**Permanently NOT needed:** backend-engineer and frontend-engineer. ADR-001 chose no
backend and there is no web surface — this is architecture, not scheduling. The
`owner-backend-engineer-CONDITIONAL` label is dead.

---

## 3. Completed phases

| Phase | Content | Landed |
|---|---|---|
| P0 | Gate 2 — architecture ADR + brand + design, human-approved | docs |
| P1 | Foundation: CI, money type, encrypted storage, audit trail, app lock | PR #1 |
| P2 | SMS ingestion + parsing (Epic A) | PR #2 |
| P3a | Domain spine: bank/instrument hierarchy, transaction record (Epic B) | PR #11 |
| P3b-1 | Multi-currency, refunds/credits, income/ATM/internal transfers | PR #18 |
| P3b-2 | Mutation surface: edit/delete/restore, enrichment merge, audit chain | PR #20 |
| P3b-3 | Merge/undo debt paid (retired risk R-15) | PR #24 |
| P4a | Categorization engine + merchant rule store (Epics C, D) | PR #27 |
| P4a-1 | Eleven defects + ADR-008 v1.3 merchant corroboration | PR #30 |
| P4b | Categorization UI + ADR-008 v1.4 code fix | **PR #34 → `4177199`** |

**P4 is closed.** KHA-32, 33, 34, 97, 106, 107 all verified `Done` in Linear.
`QA: PASS 34` (7,290-string differential corpus, zero collision-class violations).

---

## 4. P5 — UI, reporting and privacy controls (Epics E, F) — ACTIVE

**Owner:** mobile-engineer. 8 issues. Split into three PRs — P3 (9 issues, one PR) and P4
(split) both showed that a single large PR buys extra review rounds.

| Sub-phase | Issues | Done check |
|---|---|---|
| **P5a — shell** | KHA-35 home dashboard, KHA-36 transaction list + bank/instrument screens | Displayed month total equals a from-scratch recomputation over the period's rows (equality, not approximate). Empty state renders at zero transactions. |
| **P5b — analysis** | KHA-37 reports (category/card/month-over-month), KHA-38 search + filter | Every displayed total traceable to its constituent transactions (NFR-A6). Mixed currencies never summed without a stated conversion (NFR-A5). |
| **P5c — privacy & history** | KHA-39 privacy/export/erase-everything, KHA-40 change-history view, KHA-86 AC-B8.3 proof, KHA-41 a11y + RTL pass | Erase-everything leaves Recently Deleted empty and unrecoverable (KHA-86). Every screen renders in Arabic RTL and English LTR at the largest OS font size with no truncation. |

**Sequencing:** P5a → P5b → P5c. KHA-41 runs last by construction — it audits the others.
**KHA-36 is unblocked:** its only blocker, KHA-101, closed with PR #30.

**Banking-domain watch items for P5 review:**
- No cached totals that can drift from the ledger (NFR-A6). If caching is needed for
  performance, invalidation must be provably correct plus a recompute-from-scratch test.
- Periods are **calendar months**, not statement cycles (OQ-12).
- KHA-39 is **security-sensitive**: export writes plaintext financial history to disk.
  Erase-everything must be irreversible and must not leave audit rows behind.

---

## 5. Remaining phases

| Phase | Content | Notes |
|---|---|---|
| P6 | Budgets + threshold alerts (Epic G) — KHA-42, 43 | After P5. Parallel with P7. |
| P7 | Statement reconciliation (Epic H) — KHA-44, 45 | CSV must-have; **PDF is best-effort and deferrable to v1.1**. |
| P8 | Encrypted backup + restore (Epic I) — KHA-46, 47 | Restore must work **without the original device present**, else the feature fails at the moment it exists for. |
| P9 | QA hardening + acceptance — KHA-49, 50, 51, 52 | KHA-48 done. |
| P10 | Staging release — KHA-53 | Signed APK on real hardware + human acceptance. **Carries the R-17 window (§6).** |

---

## 6. Live constraints

Only constraints that are still load-bearing. Retired risks removed (see git for the rest).

1. **The merchant-identity re-key window is still open, and expires silently.**
   No install anywhere carries a `merchant` / `merchant_alias` / `merchant_rule` row, so
   `MerchantKey.of` is still free to change with a no-op migration. It expires the moment a
   **Massrofy build ingests one SMS while unlocked** — no screen, no user action needed.
   That is **KHA-53 (P10)**, and it is *not* KHA-7 (whose harness has no database).
   **KHA-109 is open and is another candidate change to `MerchantKey.of`** — the architect
   asked for it to be probed before this window closes.
   *An emulator AVD is disposable and does not spend the window. A side-load onto the real
   phone with ingestion live does.*

2. **KHA-7 (background-SMS latency spike) has never been run.** Confirmed from Linear state
   history: single `Backlog` entry, never started. P1–P4 all shipped above its unverified
   assumptions. Bounded — if the broadcast is suppressed on the target OEM the fix is a
   *default* change (ADR-006 Layer 3 default-on), not a redesign. Must close by P10.
   Safe to run now as a throwaway harness. **Owner: human (device) + mobile-engineer.**

3. **No branch protection on this repo** (KHA-55, GitHub free plan). "Green CI + strict
   reviewer" is convention, not server-enforced. Compensating: code-reviewer is the only
   agent permitted to merge; manager is explicitly forbidden from merging.

4. **Runtime verification gap — being closed now, see §7.** The app lock *has* been passed
   on real hardware (KHA-71, KHA-75, both fixed and device-verified on an Honor Magic V5).
   What has never happened is a journey walk **past** the lock, because until PR #34 there
   were no screens past `HomePlaceholderScreen`.

---

## 7. Open follow-ups not owned by a phase

| Issue | Pri | Owner | Note |
|---|---|---|---|
| KHA-108 | Med | devops | CI never runs on a QA-artifact PR based on a code branch. Has now cost two QA rounds (PR #28, #35 showed zero checks). |
| KHA-85 | High | devops | Linear PR linkback silently closes **future** work when a QA-artifact PR merges. |
| KHA-109 | Med | architect | All-digit merchant strings key on their leading digit run. Inside the §6.1 window. |
| KHA-110 | Low | mobile | Category picker "Recent" row renders but nothing supplies it. |
| KHA-111 | Low | architect | ADR-008 v1.4's disclosed-cost description understates its scope. Doc-only; behaviour is correct. |
| KHA-58, 77, 84, 81, 68, 92, 93, 95 | Low–Med | mobile | Carried residuals. Batch into a cleanup pass, not individual dispatches. |

**KHA-67 is `Done`** (2026-07-28) — it is no longer part of the devops sweep.

---

## 8. Process

- **Linear is the source of truth for issue state.** This file does not maintain an index.
- Every code PR routes **engineer → qa-tester (`QA: PASS`/`FAIL`) → code-reviewer (merges)**.
- QA opens its artifact PR **based on the code branch**, not `main` (standing rule).
- `TIER: personal`: one review round, ~5–10 QA probes not 30+, batch small fixes into one
  round, no blocking-link choreography in Linear.
