STATUS: APPROVED

# Massrofy — Architecture Decision Record

**Version:** 1.8
**Date:** 2026-07-30 (v1.5: 2026-07-30; v1.4: 2026-07-29; v1.3: 2026-07-29; v1.2: 2026-07-29; v1.1: 2026-07-28; v1.0: 2026-07-27)
**Author:** solution-architect agent (phase 3 — architecture, human gate 2)
**Sources of truth:** `docs/PRD.md` v0.3 (STATUS: Approved), `docs/build-plan.md` v1.0
**Repository state at v1.0:** greenfield. **At v1.1:** P1 merged (`9d1487c`), P2 open as PR #2.
Every pattern in this document is established here, not inherited.

> **This document does not authorise itself.** The human reviews it and changes the status
> line above to `APPROVED`. `/build` refuses to start until this file and `docs/design.md`
> are both approved. Nothing in this document is a licence to write feature code.

> **v1.1 is an amendment to an already-approved document, not a re-opening of gate 2.** It
> resolves two escalations raised by mobile-engineer during the build (KHA-56, KHA-57) and
> changes nothing else. The status line stays `APPROVED`. **However, ADR-018 materially
> reduces what NFR-R1 commits to** (see H-13) — that reduction is a product-level fact the
> human should read even though it does not, in my judgement, require re-approving the whole
> architecture. If the human disagrees with H-13, ADR-018 is the one decision to re-open.

> **v1.3 is likewise an amendment, not a re-opening of gate 2.** It resolves four defects found
> by qa-tester during the PR #27 QA gate on the P4a categorization spine (**KHA-98** High,
> **KHA-99**, **KHA-100**, **KHA-102**), all four of which are facets of one policy question that
> ADR-008 v1.0 left implicit: *when may a machine decide that two raw merchant strings are the
> same business?* The answer is now written down as a rule rather than as a token list. Recorded
> as a dated subsection under ADR-008, in the same shape as ADR-010's KHA-69 decision. The status
> line stays `APPROVED`. **One consequence does need the human, and it is a process event, not a
> re-approval: this decision requires one new UI affordance that `docs/design.md` does not
> contain, so it triggers the project's first `/revise-design` round since gate 2 — see H-15.**

> **v1.4 is an amendment to v1.3's own amendment, and it exists because I got one clause wrong.**
> It resolves **KHA-106** (High) and **KHA-107** (Low), found by qa-tester at the PR #30 gate. v1.3
> stated a corroboration rule and then, three paragraphs later, shipped a corroboration *signal*
> that violates it: stripping a trailing run of four or more digits with nothing else to support it
> reduces `QAMART 1000` and `QAMART 2000` to one key at confidence 1.00 — the same High-severity
> shape v1.3 was written to close. That signal is **withdrawn**, and the digit strip is made
> order-insensitive in the same change. The status line stays `APPROVED`; no new human gate is
> triggered and H-15 is unaffected. **This amendment is documentation, but the decision it records
> requires a small code change that must land before any APK reaches a device — see R-16.**

> **v1.5 answers a question the human raised as existential to the product concept**, after
> KHA-127/KHA-128: *"the app should be smart enough… if this is not working it will be a breaker
> for the entire idea, since we will not be able to inject LLM to deal with these things inside
> the app."* My answer, in one line: **the concept does not depend on the app being smart. It
> depends on the app being honest about what it does not know, and on the correction being one
> tap.** KHA-128 was not a missing-intelligence failure — it was a **silence** failure. The
> pipeline already counts, on every run, the messages it skipped for an unrecognised sender
> (`IngestionStats.discardedNonFinancialSender`) and then throws that number away without ever
> showing it to anyone. ADR-007 gains a dated subsection recording the decision: **the sender gate
> stays hard, NFR-P4 stands unamended, and an on-device classifier is rejected for v1 with a
> stated re-open trigger.** New: **H-16** (needs the human) and **O-7**. The status line stays
> `APPROVED`; the user-facing deliverables this decision leans on are already gated behind **PRD
> Addendum A**, so this amendment adds no new approval gate of its own.

> **v1.6 is the first amendment whose new content ships as `DRAFT`.** It resolves **KHA-133**
> (raised by mobile-engineer from a real-device investigation), which found that **a rule-pack fix
> can only ever fix the future**: KHA-128's corrected sender patterns recover nothing already
> behind the watermark, so the user's actual recovery path today is "clear app data" — a data-loss
> event, not a recovery. ADR-006 gains a dated subsection. **The decision is that this is not a new
> mechanism at all: it is AC-A6.10's "re-check a linked bank" pointed at banks that were configured
> with the wrong patterns, so it rides with US-A6 and needs no schema change.** The document status
> line stays `APPROVED` because flipping it would block `/build` on every unrelated in-flight
> phase; the gate is applied to the new subsection itself, marked `DRAFT — awaiting human
> approval` inline. **One thing needs the human now, and it is a sequencing call rather than a
> design one — see H-17.** The two constraints the decision places on the in-flight KHA-128 PR are
> prohibitions that add no work, and are safe to honour before approval.

> **v1.8 is a methodology amendment, and the cheapest one in this document.** It ships `DRAFT`
> inside ADR-007 and **changes no schema, no rule and no code**. It answers a question the human
> asked directly: *what fields does a bank transaction SMS always contain?* — so that rules stop
> being invented per bank and start being written against a checklist. The honest summary is that
> **the existing schema was already right**: `MessageRule`/`FieldExtraction` express every slot the
> taxonomy names, and the shipping banks already conform — which is itself evidence that ADR-007's
> data-driven design was the correct call. The subsection's value is therefore (a) a checklist for
> whoever adds bank number eight, (b) a fixed label palette that makes the format-teaching
> capability being scoped in parallel *buildable* rather than open-ended, and (c) one silent-no-op
> defect in `rule_pack_loader.dart` that only became visible once the vocabulary was written down.
> **Nothing here blocks the in-flight six-bank rule dispatch, and the explicit recommendation is
> not to disturb it.**

---

## Changelog

| Version | Date | Change |
|---|---|---|
| **1.8** | 2026-07-30 | **ADR-007 extended — canonical SMS field taxonomy proposed, re-derived against SAMA Circular 42023876, approved.** Rules are currently written per bank from a blank page: 15+ message shapes across 7 banks in one day of device testing, each its own one-off regex. This records a **fixed slot vocabulary** — Tier 0 rule-declared (`intent`, `messageType`, `sign`, `affectsSpend`), Tier 1 universal (`amount`, `currency`, `instrumentRef`, `occurredAt`), Tier 2 conditional (counterparty in its three roles, `referenceNumber`, fee/FX, `settlementRef`, biller fields, balance-after), Tier 3 explicitly **not** slotted (branch, loyalty points, credit limit, IBAN). The evidence that the slot set is not arbitrary: a transaction SMS is a lossy rendering of an ISO 20022 `camt.054` notification, and three independent open-source parsers across India, Thailand and MENA converge on the same list. **No schema change and no rule change** — `MessageRule`/`FieldExtraction` already express every slot, and the six shipping banks already conform, so this is methodology plus one safety net. **The one real defect it exposes:** `rule_pack_loader.dart` `_parseExtract` validates `transform`, `maskPolicy`, `kind` and `timezone` but **never the field name**, and `RulePackMessageParser._extract` reads a hardcoded name list — so a typo'd `extract` key loads cleanly, is never read, and yields nothing. A **silent no-op**, which is exactly what `field_transforms.dart` makes fatal for a typo'd *transform* name. Not a live bug today (all packs use the correct names); closed by validating both `extract` keys and `requiredFields` against the vocabulary at load time. **Recommendation: apply forward, do not retrofit** the in-flight six-bank set — pattern churn is the risky operation (R-4, KHA-128) and there is nothing to retrofit at the field level. One zero-work carve-out for the reviewer of that dispatch, and one open question on `remainingBalance` serving two different quantities. |
| **1.7** | 2026-07-30 | **ADR-017 amended — KHA-137 decided, approved.** D1's content hash **drops `receivedAt` entirely**: `contentHmac = HMAC-SHA256(k, scheme ‖ normalisedBody ‖ normalisedSender)`. Folding the delivery instant in at millisecond precision meant a carrier redelivery — which by definition arrives at a *different* instant — hashed differently, D1 missed, and a second transaction was written; QA reproduced this on a device, doubling a real total. The AC-A5.1 test missed it because it varied the provider id and held `receivedAt` fixed, i.e. it varied the one thing a redelivery does not control. **AC-A5.3 is not weakened**, verified in code rather than assumed: every transaction rule in `sa-core.json` requires an in-body `occurredAt` captured to the minute, so two genuinely separate purchases differ in the body itself; and AC-A5.2's flag path is `DuplicatePolicy.decide`'s D2/D3 tiers over parsed *fields*, never the content hash. Coarse timestamp buckets and a "same-hash-within-window" variant are both **rejected**, and for the same arithmetic: identical bodies imply the same in-body minute, so the genuine pair is co-located in time and lands in any bucket/window together — the timestamp discriminates nothing it is asked to discriminate, while every boundary silently reproduces KHA-137. One **irreducible residual** is recorded: two real purchases, same card, merchant, amount **and minute** are byte-identical and the second is suppressed; recovery is US-B4 manual entry. **Forward-only, no backfill, no schema change (DB stays 7)** — but every stored digest becomes stale, which makes ADR-006 KHA-133 item **(F)** (the `sms_provider_id` pre-check in `_withDedupGuard`) live rather than latent, so it **must ship in the same PR** under (G).1's own rule. |
| **1.6** | 2026-07-30 | **ADR-006 extended — KHA-133 decided, approved.** A rule-pack fix is currently **forward-only**: the `NotFinancialSender` branch advances the watermark for a discarded message, `runIncremental` only reads `_id >` the watermark, and `importState == completed` is terminal — so KHA-128's corrected sender patterns cannot recover a single message already swept. Decision: **a user-triggered, bank-scoped re-scan, which is AC-A6.10's existing "check again" capability pointed at banks that were configured with wrong patterns rather than at a newly linked sender.** KHA-133 is therefore **not a new mechanism and rides with US-A6**. Both alternatives are rejected: an **automatic re-scan on pack change** re-walks the month on every APK install and silently back-dates transactions, and **recording the swept pack version in the watermark** buys a worse version of that at the price of a schema migration — unnecessary, because `advanceWatermark: false` plus D1 already make a bounded re-scan idempotent and cursor-neutral. **No schema change; DB stays where P5b leaves it.** Dedup safety is confirmed by code, not assumed: a `NotFinancialSender` discard leaves **no row at all**, so the re-scan's write is a *first* write with nothing to double-count, while already-stored messages are suppressed on `content_hmac`. **One real hole found:** `contentHmac` is computed over text sanitised with the pack's per-bank `redact[]`, so it is a function of the pack — change a `redact[]` and the hmac pre-check misses, the insert hits the `sms_provider_id` `UNIQUE` constraint, and a benign duplicate is reported as `failedWithError`, stalling the watermark. Latent today (all `redact` arrays are `[]`); closed by pre-checking `sms_provider_id` in `_withDedupGuard`. Privacy is settled **explicitly**: re-reading is not re-retaining, on the same ground ADR-007 v1.5 already used, and a bank-scoped re-scan reads *strictly less* than the sweep the app runs every 15 minutes. New **H-17**. Two prohibitions bind the in-flight KHA-128 PR (no `redact[]` changes, no `importState` reset) but add no work to it. |
| **1.5** | 2026-07-30 | **ADR-007 amended — KHA-127/KHA-128 decided.** The **hard sender gate stays**, and **NFR-P4's "retain nothing" is upheld unamended** — because nothing was ever lost: the message stays in the Android SMS provider, which the app holds `READ_SMS` on and can re-read at will. The defect was **non-observability of a derived fact**, and a derived fact is fixed by deriving it, not by persisting it. Three options were weighed. **Option 1 (loosen gate 1 on body-shape heuristics → needs-review) is REJECTED as a gate**, because routing on a body guess means persisting the *content* of messages from senders never confirmed to be banks — precisely the harm NFR-P4/NFR-P4a exist to prevent — and because it infers what the user can simply be asked. **Option 2 (on-device classifier) is REJECTED for v1**, decisively on grounds of *evidence*, not effort: NFR-M3 forbids training on the user's real SMS, NFR-S6/R-10 mean we could never measure its precision in the field, and a weight blob has no `ruleId` to record (NFR-A1) and no reviewable diff (NFR-M2). **Option 3 (user sender-linking, PRD Addendum A) is the actual fix**, and it is upgraded from "complementary" to primary. Option 1's heuristic **survives, relocated**: as an in-memory, per-sender-aggregated, **advisory ranking signal on the sender-recognition screen only** — never a gate, never persisted — where a false positive costs one row of screen position instead of a database row. Two additions the options list missed and which carry most of the value: **(i) sender-name suggestion from the pack's own `aliases`/`displayName`** — the string needed to recognise `Jazira Bank` was *already shipped* in `sa-core.json` (`aliases: ["ALJAZIRA","BAJ","الجزيرة"]`) and the gate never consulted it; **(ii) a proactive unrecognised-sender health signal**, because Addendum A only links the screen from *empty* states and the silent-sender-ID-change case has a non-empty home screen. NFR-P4 gains one clarification, not a relaxation: **a content-free, sender-free aggregate count is not retention of a message** and may be surfaced and logged (ADR-015). |
| **1.4** | 2026-07-29 | **ADR-008 amended again — KHA-106/KHA-107 decided together.** v1.3's trailing-digit **corroboration signal (ii) (“≥4 digits, no other corroboration”) is WITHDRAWN**; adjacency to a structural marker is now the *only* corroborator, because no length threshold can be made residue-safe — for any N, two strings sharing a prefix and carrying different N-digit runs always reduce to the same key (KHA-106). `CategorizationConfig.referenceDigitRunMinLength` is **deleted**, not retuned. The strip is redefined on **the last digit run that is trailing modulo structural noise**, with adjacency read on **either side** of the run, so `PANDA STORE 1234` and `PANDA 1234 STORE` produce one key (KHA-107); swapping steps 6 and 7 is rejected because it would destroy the only surviving corroborator. Withdrawing signal (ii) also makes `MerchantKey.of` genuinely **idempotent**, so the doc comment's claimed invariant becomes true rather than being corrected away. Cost, disclosed: `PANDA 1234` no longer equals `PANDA` — it is flagged, not merged. Docs-only here; the code change rides R-16's window. |
| **1.3** | 2026-07-29 | **ADR-008 amended — KHA-98/99/100/102 decided.** A **corroboration rule** is stated normatively: a token may be stripped only if it is *type-level* incapable of distinguishing two businesses. Consequences, all settled: **city names are dropped from the noise list entirely** (option (b) — KHA-98); the **trailing-digit strip is bounded and corroborated** (at most one run, adjacency or ≥4 digits — KHA-99); the **all-noise fallback key is removed**, so a string that tokenises to nothing yields *no merchant identity* rather than a placeholder identity (KHA-102, going deliberately further than QA's stated fix direction); **T3 is redefined over the token multiset**, not the token set (KHA-100). A clean-migration posture is claimed with an explicit premise and an explicit expiry (new risk **R-16**). **P4b must ship a "these are two different shops" affordance** — new **H-15**, and a `/revise-design` round. No other ADR is touched. |
| **1.2** | 2026-07-29 | **KHA-69 decided and recorded** — the audit-chain timestamp fix is forward-only, and **option (a)** is taken: no install carrying pre-P3a audit rows exists, so no migration is written. Recorded as a dated subsection under ADR-010, with the evidence (ADR-005 gates the DB key behind the lock; KHA-75 showed the lock had never succeeded on hardware; the first real-device unlock was on `56e9cbaa`, which already contains the fix) and with the binding standing condition that the P10 staging APK goes onto a clean install. No ADR is amended; nothing else changes. |
| **1.1** | 2026-07-28 | **ADR-018 added** — resolves the ADR-005 (cryptographic app lock) vs ADR-006 (background ingestion) conflict raised as **KHA-56**. Background ingestion is suspended while the app is locked; NFR-R1 is restated as an unlocked-window commitment. ADR-005 and ADR-006 amended in place; ADR-006's latency table replaced with one carrying a lock-state axis. **ADR-013 rewritten** to ratify and make normative the widened PAN/secret detection raised as **KHA-57** (originating defect KHA-54) — and to close two defects of the same class that KHA-54's fix did **not** close (the greedy grouped-PAN window, and grouped IBANs). §6.8, §8.1 (H-6, H-13, H-14), §8.2 (O-5, O-6), §8.3 (R-1) and §9 updated to match. |
| 1.0 | 2026-07-27 | Initial ADR (ADR-001..ADR-017), written against a greenfield repository. |

---

## Table of contents

1. [Context and constraints](#1-context-and-constraints)
2. [Decision register (the ADRs)](#2-decision-register-the-adrs)
3. [Module structure and boundaries](#3-module-structure-and-boundaries)
4. [Data model](#4-data-model)
5. [Contracts (there is no HTTP API — here is what replaces it)](#5-contracts-there-is-no-http-api--here-is-what-replaces-it)
6. [Security and compliance architecture](#6-security-and-compliance-architecture)
7. [Cross-cutting concerns](#7-cross-cutting-concerns)
8. [Risks, residual open questions, and what the human must decide](#8-risks-residual-open-questions-and-what-the-human-must-decide)
9. [Traceability: build-plan flags A-1..A-15 and PRD NFR coverage](#9-traceability)

---

## 1. Context and constraints

### 1.1 What we are building

Massrofy is a **single-user Android application, written in Flutter, installed by side-load**.
It reads the bank transaction SMS the user already receives in Saudi Arabia (Arabic and
English, RTL), parses them into a structured ledger, categorises them with a merchant
learning loop, and reports spending by month, category, bank, and instrument. It also
imports statements, tracks budgets, and keeps an encrypted backup that can be restored on a
new device.

### 1.2 The constraints that actually shape the architecture

These are the ones that eliminate options, not the ones that merely colour them:

| Constraint | Architectural consequence |
|---|---|
| **CON-1** — one user, no accounts, no tenancy, no server-side identity | Removes the entire authn/authz/session/tenancy layer that a normal banking system needs. There is nothing to authenticate *to*. Access control collapses to "is this the person holding the unlocked device". |
| **CON-2** — read-only with respect to money | There are no money-moving operations. Idempotency, which normally protects transfers, here protects *ingestion* instead. This is a materially smaller blast radius and the design must not accidentally re-introduce write paths to money. |
| **NFR-P2 / NFR-P3** — parsing and categorisation run on-device by default; off-device processing needs an explicit, opt-in, documented change | The parser and categoriser cannot be a service. Whatever we build runs in Dart on the handset. |
| **NFR-R4** — fully functional offline | No feature on the read/categorise path may block on the network. Combined with NFR-P2, almost nothing *can* be remote. |
| **AC-F4.2** — under network monitoring, no financial data leaves the device | A testable claim, not a slogan. The architecture must make it verifiable, not merely intended. |
| **NFR-R1 / OQ-16** — single-digit seconds from SMS arrival to visible in-app | Forces genuine background processing, which on modern Android is the single most hostile technical constraint in the build (R-1). |
| **NFR-A4** — exact decimal arithmetic; floating point prohibited | Dart has no native decimal type. This is a foundational type decision with reach into every later phase (R-3). |
| **NFR-A2/A3** — append-only mutation history | Every write to the ledger is two writes. Designed in at P1, never retrofitted. |
| **NFR-S1 / NFR-S2 / NFR-C2** — encrypted at rest, masked identifiers, never store PAN/CVV/PIN | Encryption is a storage-layer property, and redaction is an *ingestion-boundary* property, not a display-layer one. |
| **US-I3** — restore on a **new** device | Any key that lives only in the Android Keystore is device-bound and makes restore impossible. This kills the obvious design (R-2). |
| **OQ-3 / OQ-4 / X16** — side-load only, no app store | Removes Google Play policy review for SMS permissions (NFR-C3 satisfied by distribution choice). Also removes any update or crash-reporting channel (R-10, R-11). |
| **NFR-S6 / X13** — no analytics, advertising, or telemetry SDK | Nothing may phone home, including transitively via a dependency. |

### 1.3 Scale and latency envelope

Deliberately stated, because it justifies choosing simple options over scalable ones:

- **One user. One device at a time.** No concurrency beyond the app's own isolates.
- **Dataset size:** on the order of a few hundred transactions per month, tens of thousands
  over the product's life. Single-digit megabytes including retained SMS text.
- **Throughput:** a handful of SMS per day; a burst of a few hundred during first-run import.
- **Latency targets:** SMS-to-visible in single-digit seconds (NFR-R1); main screen render
  with no perceptible wait (NFR-R2).

At this scale, **nothing needs to be fast, and everything needs to be correct.** Every
trade-off in this document resolves toward correctness, auditability, and verifiability, and
away from throughput, caching, and cleverness. That is also the banking-domain default.

---

## 2. Decision register (the ADRs)

Each decision states the options that were genuinely considered and why the loser lost.
Decisions are stable IDs; engineers and reviewers should cite them.

---

### ADR-001 — There is **no backend**. No server, no API, no network permission.

**Answers build-plan flag A-1. This is the decision the manager held backend-engineer on.**

**Context.** The default team shape assumes a Java/Spring backend. The PRD points hard the
other way: CON-1 (no server-side identity), NFR-P2/P3 (processing on-device), NFR-R4 (fully
offline), AC-F4.2 (nothing leaves the device). The only server-adjacent capability in the
whole product is Epic I, encrypted cloud backup.

**Options considered.**

| Option | Assessment |
|---|---|
| **(a) Custom Spring Boot sync service** (REST + object storage) | Requires an identity system to know whose backup is whose — directly contradicts CON-1. Requires hosting, TLS certificates, patching, and operations, indefinitely, for one user. Creates a second copy of one person's complete financial history on infrastructure we operate, which is a liability even encrypted. Adds a network dependency that must then be carefully fenced off from the offline read path (NFR-R4). Nothing in the PRD needs server-side compute. **Rejected.** |
| **(b) Managed BaaS** (Firebase / Supabase / similar) | Still needs an account (CON-1). Firebase in particular drags in an SDK surface adjacent to analytics, which NFR-S6 and X13 prohibit; even with analytics disabled, the dependency ships code we would have to prove inert. Provider sees metadata (blob sizes, timing, account identity). **Rejected.** |
| **(c) Direct cloud-provider API from the app** (e.g. Google Drive `appDataFolder`) | No custom server, provider cannot read ciphertext. But it requires OAuth (an account — CON-1 friction), a network permission, a cloud SDK, and for a side-loaded unverified app the OAuth consent path for SMS-adjacent sensitive scopes is operationally fragile. It also makes AC-F4.2 a matter of *inspecting* our network traffic rather than *having none*. **Rejected for v1; retained as a deferred adapter — see ADR-016.** |
| **(d) Bring-your-own storage via Android's Storage Access Framework** — the app writes an end-to-end-encrypted blob to a user-chosen folder; the user's *existing* sync app (Drive, OneDrive, Dropbox, Nextcloud, Syncthing) propagates it to the cloud | Zero custom server code. Zero cloud SDK. Zero account system. **Zero network I/O performed by Massrofy.** The provider and the account holder see only ciphertext. **Chosen.** |

**Decision.**

1. **There is no backend service, and no HTTP API surface, in Massrofy v1.** `backend-engineer`
   is **not** dispatched at `/build`. The build-plan §2.1 conditional resolves to: **Epic I is
   mobile-engineer work.** The team for this feature is devops + mobile + qa + reviewer.
   Linear issues labelled `owner-backend-engineer-CONDITIONAL` should be relabelled
   `owner-mobile-engineer`.
2. Epic I is implemented as an **encrypted blob written through the Storage Access Framework**
   to a persisted tree/document URI the user selects once (ADR-011, ADR-012).
3. **The release build declares no `INTERNET` permission and no `ACCESS_NETWORK_STATE`
   permission.** Flutter's default `src/main/AndroidManifest.xml` does not include them; we
   additionally add explicit removal directives so that no transitive dependency can merge
   them back in:

   ```xml
   <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" tools:node="remove" />
   ```

   (Flutter's `src/debug/` and `src/profile/` manifests keep `INTERNET` for hot reload; only
   the release variant is network-mute.)

**Consequences.**

- *Good:* **AC-F4.2 stops being a claim and becomes a property enforced by the operating
  system.** No financial data can leave the device because no data can leave the device. QA's
  verification (P9) becomes a one-line assertion on the merged release manifest plus the
  network-monitor run, and it cannot regress silently. This is a materially stronger privacy
  posture than any server design could offer, which is the deciding argument.
- *Good:* NFR-S5 (TLS) is satisfied vacuously — there is no network communication to secure.
  NFR-S6 is enforced structurally: a telemetry SDK physically cannot transmit.
- *Good:* R-10's "no telemetry" and R-11's "no update channel" are unchanged by this
  decision — they were already true — but ADR-015 and ADR-006 give the compensating controls.
- *Bad / accepted:* no server-side FX rate lookup. FX must come from the SMS itself or the
  user (ADR-009). This is consistent with NFR-R4 and is the correct constraint anyway.
- *Bad / accepted:* backup upload is **not** performed by us; it depends on the user having a
  sync app pointed at the chosen folder. The app must surface backup freshness honestly
  ("last written locally at HH:MM — Massrofy cannot confirm your sync app uploaded it").
  The designer must handle this (see §8, item for D-10).
- **AC-F4.2 wording:** the PRD says "no financial data is transmitted off-device". Under this
  design nothing is transmitted by the app at all; a ciphertext blob later leaves via a
  third-party app the user chose. The claim holds as written, but the transparency screen
  (US-F4) must describe this chain accurately. Recommended clarification for the human in §8.

---

### ADR-002 — Money is an exact-decimal, currency-tagged value object; `double` is banned by construction and by CI.

**Answers A-5. Mitigates R-3.**

**Context.** NFR-A4 prohibits floating point for money. NFR-A5 requires every amount to carry
a currency and forbids summing across currencies without a stated conversion. Dart has no
built-in decimal type. Amounts appear in SMS with Arabic-Indic digits and Arabic separators.

**Options considered.**

| Option | Assessment |
|---|---|
| `double` / `num` | Prohibited outright by NFR-A4. Not considered further. |
| **Minor-unit `int`** (halalas ×100) | Exact and cheap. But the exponent varies by currency (SAR 2, KWD/BHD/JOD 3, JPY 0), so every read needs an exponent table; FX conversion produces fractional minor units; exchange rates need 6+ decimal places and don't fit the model at all; and an `int` in a log or export is ambiguous without its currency. |
| **`package:decimal`** (arbitrary-precision decimal over `BigInt`/`Rational`) | Exact at any scale, handles rates and conversions, division yields `Rational` so precision loss is explicit rather than silent. Costs allocations — irrelevant at this dataset size. |

**Decision.** A sealed value type `Money` in `lib/core/money/`:

- Internally `Decimal amount` (from `package:decimal`) + `String currencyCode` (ISO 4217).
- **Construction only via** `Money.parse(String, {required String currency})`,
  `Money.fromMinorUnits(int, {required String currency})`, and `Money.zero(currency)`.
  The default constructor is private. There is **no** `Money.fromDouble` and **no**
  `toDouble()` — the type physically cannot round-trip through a float.
- `operator +` / `operator -` / `compareTo` **throw `CurrencyMismatchError` unless the currency
  codes are identical** (NFR-A5 enforced at the type level, at runtime, in every path).
- Cross-currency arithmetic is possible **only** through
  `MoneyConverter.convert(Money, {required ExchangeRate rate})`, which requires an explicit
  rate carrying a rate value, a rate date, and a source — so AC-B9.3 traceability is
  structurally guaranteed rather than remembered.
- **Rounding:** stored values are never rounded. Conversion results are rounded
  `HALF_UP` to the target currency's exponent, and the rounding mode, rate, and rate date are
  recorded on the transaction. Display rounding is a presentation concern and never written back.
- **Parsing normalisation** (before `Decimal.parse`): map Arabic-Indic digits `٠-٩` (U+0660–0669)
  and Extended Arabic-Indic `۰-۹` (U+06F0–06F9) to ASCII; map Arabic decimal separator `٫`
  (U+066B) to `.`; strip Arabic thousands separator `٬` (U+066C), `,`, and bidi control
  characters (U+200E/200F/061C). This lives in `core/money/numeral_normalizer.dart` and is
  shared with the parser.

**Persistence.** SQLite has no decimal type. Each money column is stored as **two columns**:

| Column | Type | Role |
|---|---|---|
| `<name>_amount` | `TEXT` | **Authoritative.** Canonical decimal string, e.g. `"1234.50"`. Round-trips exactly, is human-inspectable in exports, needs no exponent table. |
| `<name>_currency` | `TEXT` | ISO 4217 code. Always present. Never nullable where an amount is present. |
| `<name>_minor` | `INTEGER` | **Non-authoritative.** Derived, for indexing and range filtering only (AC-E5.2). |

**Rule, non-negotiable: no monetary total displayed anywhere in the app may be produced by a
SQL `SUM()`, `AVG()`, or any arithmetic on `<name>_minor`.** All aggregation happens in Dart
over `Money`. At this dataset size the cost is negligible and it makes NFR-A4 and NFR-A6
simultaneously true.

**Enforcement (this is the part that actually mitigates R-3).**

1. A `custom_lint` rule plus a CI grep failing the build on `double`, `num`, `.toDouble()`,
   or `double.parse` anywhere under `lib/core/money/`, `lib/domain/`, or any file matching
   `*money*`, `*amount*`, `*budget*`, `*report*`.
2. A CI grep failing the build on `SUM(`, `TOTAL(`, or `AVG(` in any `.drift` file or raw SQL
   string that references a money column.
3. Property-based tests (associativity, commutativity, parse/serialise round-trip over
   randomly generated decimals with 0–4 fractional digits, and `a + b - b == a`).
4. A test asserting `Money` exposes no member whose return type is `double` or `num`
   (reflection-free: an explicit API-surface golden test).

**Consequences.** Slightly more ceremony in every money path. Mixed-currency addition fails
loudly at runtime rather than producing a wrong number — which is exactly the trade we want
in a banking-domain app. The `_minor` column is a documented footgun and is fenced by CI.

---

### ADR-003 — Local storage is **SQLCipher-encrypted SQLite via Drift**, whole-database encryption.

**Answers A-3 (storage half). Serves NFR-S1, NFR-R6, NFR-A6.**

**Options considered.**

| Option | Assessment |
|---|---|
| **Drift + `sqlcipher_flutter_libs`** | Relational (we have a genuinely relational domain: bank → instrument → transaction → audit), typed Dart DAOs, compile-time-checked SQL, first-class migration testing, isolate support for background work, and SQL triggers — which we need for append-only enforcement (ADR-010). **Chosen.** |
| `sqflite_sqlcipher` | Same encryption, but raw SQL strings, no compile-time checking, weaker migration tooling. Rejected on maintainability (NFR-M1 spirit). |
| Isar / ObjectBox | Fast NoSQL. Encryption support is weak or unmaintained; no triggers, so append-only becomes convention-only; relational integrity would be hand-rolled. Rejected. |
| Hive | Box-level AES-CBC with a weak key-derivation story; no relations; no triggers. Rejected. |
| Realm | Couples to Atlas/Device Sync we explicitly do not want (ADR-001). Rejected. |

**Field-level vs whole-database encryption.** Considered field-level (encrypt only amounts,
merchants, SMS bodies). **Rejected.** Field-level leaves indexes, the WAL, temp/journal files,
and the *shape* of the audit log readable; it also depends on a developer remembering to
encrypt each new sensitive column, which is exactly the failure mode NFR-S1 exists to prevent.
Whole-database encryption is uniform, covers retained raw SMS text and the audit trail in one
move, and needs no per-column judgement calls. **Banking default: choose the more thorough
option.** The cost — you cannot query the file with external tools — is a benefit here.

**Configuration.**

- SQLCipher 4 defaults (AES-256-CBC per page, HMAC-SHA512 page authentication).
- We supply a **raw 32-byte key** via `PRAGMA key = "x'<64 hex chars>'"`, bypassing SQLCipher's
  own PBKDF2 (our key is already high-entropy and already KDF-protected upstream — ADR-004).
- `PRAGMA cipher_memory_security = ON`.
- Journal mode WAL; `PRAGMA foreign_keys = ON`; `synchronous = FULL` on the ledger path
  (NFR-R6 — a device restart mid-write must not corrupt or lose recorded transactions).
- Key rotation via `PRAGMA rekey` (used on credential recovery and on erase-all).
- Migrations via Drift's `MigrationStrategy` with generated schema snapshots per version and a
  `verifySelf()` test plus a forward-migration test from an empty install (P1 exit check).

---

### ADR-004 — Key hierarchy: a Keystore-wrapped database key with a **user-held recovery secret as a second, device-independent wrapping**.

**Answers A-3 (key half) and, together with ADR-012, A-4. Directly addresses R-2.**

**Context.** Two requirements pull against each other. NFR-S3 wants biometric-gated access,
which argues for an Android Keystore key bound to user authentication. US-I3 wants restore on
a *new* device, which a Keystore-bound key makes impossible. Separately, Keystore keys are
invalidated when biometrics are re-enrolled or the device credential is removed — which, for a
key protecting the whole database, would mean permanent data loss.

**Decision — three keys, two independent unwrapping paths.**

```
                    ┌──────────────────────────────────────────┐
                    │  DB Master Key  (32B, CSPRNG, first run) │  ← opens the SQLCipher DB
                    └──────────────────────────────────────────┘
                        ▲                              ▲
            wrapped by  │                              │  wrapped by
    ┌───────────────────┴────────────┐   ┌─────────────┴──────────────────────┐
    │ Keystore KEK                   │   │ Passphrase KEK                     │
    │ AES-256-GCM, alias             │   │ Argon2id(recovery secret, salt,    │
    │ "massrofy.dbkek"               │   │   m=64MiB, t=3, p=2) → 32B         │
    │ setUserAuthenticationRequired  │   │ salt stored in cleartext locally   │
    │   (true)                       │   │   and in the backup envelope       │
    │ BIOMETRIC_STRONG|DEVICE_CRED   │   │ NOT device-bound                   │
    │ setInvalidatedByBiometric-     │   │                                    │
    │   Enrollment(true)             │   │                                    │
    │ → daily convenience path       │   │ → recovery + new-device path       │
    └────────────────────────────────┘   └────────────────────────────────────┘
```

- The DB Master Key is generated once, on first run, from a platform CSPRNG. It is **never**
  displayed, exported, or written unwrapped.
- Both wrapped blobs (`wrapped_by_keystore`, `wrapped_by_passphrase`) are stored in
  `flutter_secure_storage` (EncryptedSharedPreferences, itself Keystore-backed) — defence in
  depth on already-encrypted material.
- **Daily use:** app unlock runs `BiometricPrompt` with a `CryptoObject` bound to the Keystore
  KEK, unwraps the DB Master Key **once per unlock**, holds it in memory for the session, and
  zeroes it on lock (ADR-005).
- **Keystore invalidation** (new fingerprint enrolled, device credential changed or removed,
  device restored from an OS-level backup): unwrapping throws `KeyPermanentlyInvalidatedException`.
  The app then prompts for the **recovery secret**, unwraps via the Passphrase KEK, generates a
  **fresh** Keystore KEK, and re-wraps. **No data loss, and we keep the secure
  `setInvalidatedByBiometricEnrollment(true)` setting** — which we could not otherwise afford.
  This is the direct answer to A-3's "what happens on device credential change".
- **The recovery secret is the same secret that protects the backup** (ADR-012). One secret,
  one thing for the user to keep, two jobs. It is generated by the app, shown once, and the
  user must confirm it before backup is enabled.
- **Nothing device-bound is required to read a backup.** That is the whole point (R-2).

**Rotation.** `PRAGMA rekey` rotates the DB Master Key; the Keystore KEK is regenerated on
every recovery event and on demand from Settings; the backup data key is fresh per backup
(ADR-012). Rotation is cheap because the dataset is small.

**Consequences.**

- *Good:* R-2 is closed. Restore works on a device that has never seen the original Keystore.
- *Good:* the "weak passphrase" half of R-2 is closed too, because the secret is
  **app-generated 128-bit entropy**, not user-chosen (ADR-012).
- *Bad / accepted:* enrolling a new fingerprint forces one recovery-secret entry. This is the
  secure default and we choose it deliberately; the alternative
  (`setInvalidatedByBiometricEnrollment(false)`) would let anyone who can add a biometric to
  the device silently inherit access to the database key. **Flagged for the human in §8.**
- *Bad / accepted:* **if the user loses the recovery secret and the Keystore is invalidated,
  the local database is unrecoverable.** There is no escrow. Any escrow would mean somebody
  other than the user can decrypt, which contradicts AC-I2.1. The UI must say this in plain
  language, twice: at generation and at every backup-settings view.

---

### ADR-005 — App lock is enforced **cryptographically**, not by navigation.

**Serves NFR-S3, AC-F1.1, AC-F1.2.**
**Amended by ADR-018 (v1.1).** ADR-005 is **unchanged and upheld**; ADR-018 records what it
costs — namely that background SMS ingestion cannot run while the app is locked — and decides
that we pay that cost rather than weaken this decision. Read ADR-018 before touching the app
lock, the Keystore key policy, or the lock grace timer.

**Decision.**

- `androidx.biometric.BiometricPrompt` via `local_auth`, allowed authenticators
  `BIOMETRIC_STRONG | DEVICE_CREDENTIAL`.
- The lock is not a route guard. **Failing or cancelling authentication means the DB Master
  Key is never unwrapped, so the database physically cannot be opened.** AC-F1.2 ("no
  transaction data, totals, or card identifiers are visible") is therefore satisfied by
  cryptography, not by UI discipline. A screenshot-of-the-last-frame attack is handled by
  ADR-014.
- **Re-lock policy:** on `AppLifecycleState.paused`, start a grace timer (default **0 seconds**
  — lock immediately; user-configurable 0/15/30/60s). Past grace, zero the in-memory key
  (overwrite the byte list, drop the Drift connection) and require re-auth on resume.
- **No biometric and no device credential enrolled:** the app requires the user to set an
  app-level passphrase, which derives the Passphrase KEK (ADR-004) and becomes the sole unlock.
  We do not offer an unprotected mode. This app holds a complete record of one person's
  financial life; "no lock" is not an option we ship.
- **Failed-attempt handling:** delegated to the platform (`BiometricPrompt` lockout). For the
  passphrase path, exponential backoff after 5 failures, backoff state stored outside the
  encrypted DB (it must survive a locked DB).

**Implementation note (P1, ratified here because ADR-018 depends on it).** `massrofy.dbkek` is
created as a **time-bound** user-authentication key — `setUserAuthenticationParameters(5,
AUTH_BIOMETRIC_STRONG | AUTH_DEVICE_CREDENTIAL)` — not an auth-per-operation key. That was the
correct call: `local_auth` cannot hand a `CryptoObject` to our Keystore channel, so an
auth-per-operation key throws `UserNotAuthenticatedException` on every call. **The 5-second
validity window is the whole of the relaxation and it must stay small** — it is what makes
"unwrap immediately after the prompt succeeds" work, and it is *also* the reason a background
isolate can never unwrap opportunistically. Any proposal to lengthen it is a proposal to weaken
the app lock, and must come back through this ADR. See `android/.../KeystoreChannel.kt`.

---

### ADR-006 — SMS ingestion: a **wake-only broadcast receiver + a content-provider watermark**, with a periodic self-healing sweep and an opt-in foreground service.

**Answers A-2. Mitigates R-1. Serves NFR-R1, NFR-R3, NFR-R5, NFR-R6, NFR-A7, AC-A3.3.**
**Amended by ADR-018 (v1.1).** The three-layer mechanism below stands exactly as written. What
v1.0 got wrong is the **assumption, never stated, that the worker can open the database.** It
cannot while the app is locked (ADR-005). ADR-018 resolves that and **replaces the latency table
in this ADR** — the table below is superseded and retained only so the correction is legible.
**Extended by the KHA-133 decision (v1.6, 2026-07-30)** — the dated subsection at the end of this
ADR, **APPROVED**. The watermark and `importState` semantics below are
upheld unchanged; what v1.0 never provided is a way to **re-scan history after the rules change**,
which makes every rule-pack fix forward-only. Read that subsection before touching
`_processOne`'s `NotFinancialSender` branch, `HistoricalImporter.runOrResume`, `_withDedupGuard`,
or any `redact[]` array in a rule pack.

**Context.** `android.provider.Telephony.SMS_RECEIVED` is on Android's implicit-broadcast
exemption list, so a manifest-registered receiver is delivered even when the app process is
not running. That is what makes single-digit-second latency possible at all. But delivery
stops if the app is force-stopped, put in the *restricted* App Standby bucket, or killed by an
OEM battery manager (Xiaomi/Huawei/Oppo/vivo/Samsung autostart managers). That is R-1, and it
cannot be fully solved — only bounded and made visible.

**Options considered.**

| Option | Assessment |
|---|---|
| Receiver parses and writes the transaction inline | A broadcast receiver has roughly a 10-second budget. Reading the DB, unwrapping a key, decrypting pages, running regex rules, and writing two rows plus an audit entry can exceed it, and the process can be killed mid-write. Risks NFR-R6 and NFR-A7. Rejected. |
| Receiver passes the SMS body to a `WorkManager` job as input `Data` | WorkManager persists input `Data` in its own **unencrypted** SQLite database in app storage. That puts plaintext bank SMS in a store we do not control the encryption of — violates NFR-S1's intent. Would require us to envelope-encrypt the body before handing it over: workable, but it duplicates key handling and still leaks message length/timing. Rejected. |
| **Receiver carries no content at all; it is purely a wake signal. The worker re-reads from `content://sms/inbox WHERE date > watermark`.** | No PII transits any store we don't encrypt. Naturally idempotent and resumable. Unifies the incremental path with historical import (US-A3). A missed broadcast is self-healing — the next wake picks up everything since the watermark. **Chosen.** |

**Decision — a three-layer design.**

**Layer 1 — primary path (target: 1–3 seconds).**
1. Manifest-registered Kotlin `SmsReceiver` for `android.provider.Telephony.SMS_RECEIVED`
   (permission `RECEIVE_SMS`). It reads **nothing** from the intent except the fact that a
   message arrived. It enqueues an expedited `OneTimeWorkRequest` (unique work name
   `massrofy.ingest`, `ExistingWorkPolicy.KEEP`, `NetworkType.NOT_REQUIRED`,
   `OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST`) and returns immediately.
2. `IngestWorker` (a `CoroutineWorker`) starts a background `FlutterEngine` on a
   `@pragma('vm:entry-point')` Dart entrypoint. (The `workmanager` plugin implements exactly
   this pattern; the mobile engineer may use it or hand-roll the equivalent — the *contract*
   below is what is fixed, not the plugin choice.)
3. The Dart ingestion pipeline reads the SMS content provider for rows with
   `date > lastProcessedSmsDate OR _id > lastProcessedSmsProviderId` (permission `READ_SMS`),
   processes each message (ADR-007/008/013), and advances the watermark **in the same database
   transaction** as the writes it produced.
4. **Known race:** `SMS_RECEIVED` can fire microseconds before the default SMS app has written
   the row to the provider. Mitigation: the worker retries the provider read once after 750 ms
   if it finds nothing new; the Layer-2 sweep catches it unconditionally regardless.

**Layer 2 — self-healing sweep (bounded worst case: ~15 minutes).**
A `PeriodicWorkRequest` every 15 minutes (WorkManager's floor), plus a sweep on app foreground,
plus a `BOOT_COMPLETED` receiver (`RECEIVE_BOOT_COMPLETED`) that re-arms the periodic work.
This guarantees AC-A1.4 unconditionally: if the broadcast never arrives, the message is still
captured, just later. **This layer is what makes the product correct even when R-1 bites.**

**Layer 3 — opt-in escalation for hostile OEMs (R-1).**
An optional, user-visible **foreground service** (`FOREGROUND_SERVICE` +
`FOREGROUND_SERVICE_SPECIAL_USE` with a declared justification) that keeps the process
resident. **Off by default** — it costs battery, and NFR-R7 requires a reasonable footprint.
It is offered in Settings, together with the standard
`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt and, for known-hostile OEMs, a deep link
into the vendor's autostart settings. Rationale for `specialUse` over `dataSync`: Android 15
imposes runtime caps on `dataSync` foreground services that make them unsuitable for a
continuous monitor; `specialUse` normally invites Play policy review, which does not apply to
us (X16, side-load only).

**Honest latency statement — ⚠️ SUPERSEDED by ADR-018's table. Do not quote this one.**

> This table is wrong in one specific and important way: **every row silently assumes the
> database can be opened.** Under ADR-005 that is only true while the app is unlocked. The rows
> below therefore describe the *unlocked* device only. ADR-018 §"What NFR-R1 actually commits
> to" carries the corrected table, with a lock-state axis. Kept here, struck rather than
> deleted, because a reader who finds the old numbers quoted somewhere else needs to be able to
> see that they were superseded and why.

| Situation (⚠️ **unlocked app only**) | SMS-to-visible |
|---|---|
| App in foreground | immediate (< 1 s) |
| App backgrounded, normal standby bucket, broadcast delivered | **1–3 s (target)** |
| App in the *restricted* bucket or suppressed by an OEM manager, Layer 3 off | up to **15 minutes** (Layer 2) |
| App force-stopped by the user | until next app open (Android suppresses all delivery to force-stopped apps — no mitigation exists) |
| Layer 3 enabled | 1–3 s, at battery cost |

**These numbers are provisional on the P0 spike (KHA-7)** and must be confirmed against the
user's actual device and Android version before this ADR's latency claims are treated as
settled. **ADR-018 changes what that spike is for:** it no longer decides whether Layer 3 goes
default-on to protect NFR-R1 (it cannot), only whether the wake signal survives on this OEM at
all. **See §8, H-6.**

**Permissions in the release build (complete list).**
`RECEIVE_SMS`, `READ_SMS`, `RECEIVE_BOOT_COMPLETED`, `USE_BIOMETRIC`, `POST_NOTIFICATIONS`
(budget alerts, API 33+), `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` (declared;
used only if Layer 3 is enabled), `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (optional prompt).
**Explicitly absent:** `INTERNET`, `ACCESS_NETWORK_STATE`, any external-storage permission
(SAF is used instead), any location or contacts permission.

**Permission auto-reset (Android 11+):** if the app is unused for months, `RECEIVE_SMS`/`READ_SMS`
can be revoked automatically. On every foreground, the app checks permission state and, if
revoked, shows the AC-A1.3 warning ("ingestion has stopped; your existing data is intact")
rather than silently capturing nothing.

#### KHA-133 decision — **re-scanning history after the rules change: a user-triggered, bank-scoped re-scan that moves neither cursor.** Decided 2026-07-30.

> **STATUS: APPROVED (2026-07-30).** The document's own status line above stays `APPROVED`, per
> the house style established by v1.1–v1.5: flipping the whole architecture to `DRAFT` would
> block `/build` on every unrelated in-flight phase, which is a far larger blast radius than this
> one decision warrants — the gate was applied to this subsection only, and the human has now
> cleared it. **Human decision on shipping timing:** land this as a small standalone PR
> immediately after KHA-128 (a plain "check my banks again" action in Settings → Diagnostics),
> rather than waiting for the full US-A6 self-service screen — it is a genuine subset of what
> US-A6 must build regardless, so nothing here is thrown away when US-A6 lands.

**What is broken.** KHA-128 ships correct `senderPatterns` for the user's banks. It recovers
nothing already received, because three deliberate design choices compose into a trap:

1. `_processOne`'s `NotFinancialSender` arm **advances the watermark** for a discarded message
   ("examined, nothing to come back for" — correct in isolation).
2. `runIncremental` only ever reads `_id > lastProcessedSmsProviderId`.
3. `HistoricalImporter.runOrResume` returns immediately on `importState == completed`, a
   deliberately terminal state.

Each is right. Together they mean **the rule pack can only ever fix the future**, and there is no
re-scan path anywhere in `lib/`. The user's only current recovery is "clear app data", which
destroys the transactions they *do* have correctly and, per ADR-004/ADR-012, may cost the whole
encrypted store. **That is not a recovery path; it is a data-loss event wearing one's clothes.**

##### Q1 — Is a re-scan dedup-safe? **Yes, with one hole that must be closed first.**

Verified against the code rather than assumed, case by case:

| Prior outcome | Rows left behind | On re-scan |
|---|---|---|
| `NotFinancialSender` (KHA-133's population) | **None at all** — the arm goes straight to `_finish` and never enters `_withDedupGuard`. No `sms_provider_id`, no `content_hmac`, no timestamp | The write is a **first** write, not a second one. **There is nothing to double-count**, because D1 was never given anything to dedup against |
| `ParsedMessage` / `UnparsedMessage` / `IgnoredMessage` | `raw_message` row with both D1 keys | `findByContentHmac` hits → `suppressedAsExactDuplicate`, no second row, no second transaction |

So the ADR-017 D1 `UNIQUE` constraints do protect exactly what needs protecting, and the discard
population is safe *for the opposite reason* — not because dedup catches it, but because dedup has
nothing to catch. Both halves hold. **The hole is elsewhere:**

> `contentHmac` is computed over the **sanitised, normalised** body, and `SmsSanitizer.sanitize`
> is given `parser.redactionPatternsForSender(sender)` — the per-bank `redact[]` from the active
> pack. **The hmac is therefore a function of the pack, not of the message alone.** If any pack
> change alters a bank's `redact[]`, the recomputed hmac for an already-stored message differs,
> the `content_hmac` pre-check **misses**, and the insert hits the `sms_provider_id` `UNIQUE`
> constraint instead. Drift throws; `processAll`'s per-message `catch` counts `failedWithError`;
> `advancingIsSafe` goes false and `HistoricalImporter._walk` calls `pauseImport()`. **A benign
> duplicate is thereby reported as a stalled pipeline.**

Today this is **latent, not live**: every `redact` array in `sa-core.json` is `[]`. It goes live
the first time any pack adds one. The fix is one method: **`_withDedupGuard` must pre-check
`sms_provider_id` as well as `content_hmac`.** `RawMessageDao` today has `findByContentHmac` and
no `findBySmsProviderId`; add it. Both columns are already `UNIQUE`, so this changes no invariant
— it converts an unhandled constraint violation into the counted `suppressedAsExactDuplicate`
outcome D1 already specifies, and it makes D1's own doc comment ("the two keys catch different
things and **both are needed**") true, which it currently is not.

##### Q2 — Privacy. **Re-reading is not re-retaining, and a bank-scoped re-scan reads strictly *less* than the sweep the app already runs every 15 minutes.**

Stated explicitly rather than left implicit, because it is the question a reader will stop on:

- **NFR-P4 governs what Massrofy's database retains, not what the ingestion isolate may
  momentarily read.** This is not a new reading invented for KHA-133 — it is precisely the
  reading ADR-007's KHA-127/128 subsection already turned on ("*every one of those messages is
  still sitting in `content://sms/inbox`… the app can re-read all of it, at any time, for
  free*"). Reading it differently here would make the architecture incoherent with itself.
- **The re-scan is narrower than `runIncremental`.** The incremental sweep examines *every*
  sender in the window. A bank-scoped re-scan parses only messages whose sender resolves to the
  target bank, and for every other message in the window it looks at the **sender string and
  stops there** — the same depth the hard gate already goes to, on every sweep, today.
- **NFR-P4a / AC-A6.9 are untouched.** A re-scan is only ever run for a sender the pack already
  recognises or the user has affirmatively linked. An unlinked sender's body is never read beyond
  AC-A6.2's single-message, on-demand, redaction-applied preview.
- **Nothing new is persisted.** The re-scan writes exactly the rows the pipeline would have
  written the first time had the rules been right, and nothing else.

##### Q3 — The trigger. Three options; the schema-free one wins.

| Option | Assessment |
|---|---|
| **(1)** Automatic global re-scan on every rule-pack update | **Rejected.** "Did this pack change anything relevant to *this* user" is not cheaply answerable, so the honest version is *re-scan the whole window on every pack change* — which on a side-loaded app means every APK install re-walks the month, burning work and battery and emitting a burst of `duplicate_suppressed` events. That is the exact self-inflicted symptom the `importStateCompleted` fix was written to stop; re-introducing it deliberately would be perverse. It also **hides a state change**: transactions dated three weeks ago appearing silently after an app update is the specific hazard PRD §1's "trusts the numbers" criterion cannot survive. |
| **(2)** Record the pack id/version the watermark was last swept under; re-scan when it differs | **Rejected, and this is the option KHA-133 proposed.** It buys a *worse* version of option 1 at the price of a **schema migration** (a new `lastSweptRulePackId`/`Version` column, DB version 8) — persisting state to answer a question the user answers for free by tapping a button. Recorded here because the reasoning is the load-bearing part: **the reason no migration is needed is that D1 plus `advanceWatermark: false` already make a bounded re-scan idempotent and cursor-neutral.** There is no durable fact a re-scan needs to remember. |
| **(3)** A **user-triggered, bank-scoped re-scan** — i.e. exactly AC-A6.4 (at link time) and **AC-A6.10** ("check again" on demand) | **CHOSEN.** KHA-133 is not a new capability. It is **AC-A6.10's capability pointed at the two banks that were already configured with wrong patterns** rather than at a newly linked sender. US-A6 must build this mechanism regardless of KHA-133; building a second one would be duplication. It needs **no schema change**, it is scoped so it cannot re-read what it has no business re-reading, and it is *visible* — the user asked for it and is shown what it did. Simpler and more private than either alternative, which is why it is chosen. |

##### Normative: what the implementation must do

**(A) One mechanism, one code path.** A `RescanCoordinator` in `lib/features/ingestion/` that
chunks and calls `pipeline.processAll(chunk, advanceWatermark: false)` — the identical call
`HistoricalImporter._walk` already makes. **No second pipeline, no second parser entry point, and
no `importState` reset.** ADR-006's self-healing property comes from every path being the same
path; a divergent re-scan would forfeit it.

**(B) Neither cursor moves, and that is why there is no migration.** `advanceWatermark: false`;
`importState`, `importCursor` and `importFromDate` are **not written**. A re-scan is a transient
operation, not persisted state. The schema stays wherever P5b leaves it (7 at time of writing).

**(C) The window: `min(importFromDate, startOfCurrentMonthUtc(now))`.** Not a freshly computed
start-of-month. `importFromDate` is already frozen in the watermark row, and an import that began
last month legitimately covered ground a fresh computation would now exclude — **a re-scan must
never cover less than the import it is correcting.** Uses an existing column.

**(D) Scope: per bank.** The concrete sender set is derived by testing each distinct in-window
sender string against that bank's pack `senderPatterns` and user links — the enumeration AC-A6.1
already requires. `MessageParser` gains `String? bankIdForSender(String sender)`; US-A6 needs it
for AC-A6.1 anyway, so this decision adds no contract surface of its own. **"Check all banks
again" is permitted** as this same call looped over the known banks, and is the affordance
KHA-133's user actually needs (seven banks, not one) — it is a loop, **not** a second mechanism
and **not** a global blanket re-scan.

**(E) The result is reported to the user and written to the audit trail.** Return the existing
`IngestionRunResult` and show it: *"Bank Aljazira — 41 messages checked, 38 transactions added,
3 need review."* Record the re-check as a **user action** (ADR-010), like AC-A6.3's link. Not
optional: a re-scan makes weeks-old transactions appear at once, and retroactive numbers with no
stated cause are worse than no numbers.

**(F) Q1's dedup pre-check fix lands before or with the first re-scan code.** Non-negotiable, and
cheap.

**(G) Two prohibitions binding on the in-flight KHA-128 PR.** Neither adds work:

1. **Do not add or change any `redact[]` array.** All are `[]` today. Adding one shifts the
   `content_hmac` of every already-stored message from that bank and converts the future
   re-scan's benign duplicates into `failedWithError` stalls. If KHA-128 genuinely needs a
   `redact` pattern, then (F) must land in the same PR.
2. **Do not reset `importState`, `importCursor` or the watermark as a recovery shortcut, and do
   not add a "re-import" button.** It looks like a two-line win. It creates a second re-scan
   path that diverges from the one US-A6 must build, and it re-opens a state made terminal on
   purpose.

##### What this does *not* recover, said plainly

**Anything older than AC-A3.1's window.** The re-scan corrects the rules over the ground the
import already covered; it does not extend that ground. A message from a previous month was never
in scope and still is not. If the user needs it, that is Epic H (statement import) or a change to
AC-A3.1 — not this decision. Nobody should read "check again" as "full history".

**Discovery is a known weak point.** The re-check button is found only by a user who goes looking.
The standing discovery path is ADR-007 v1.5 item (D)'s "unrecognised senders" row in the
parser-health panel, plus AC-A6.11. **v1 stores no last-seen pack version**, so a bundled-pack
correction arriving as a new APK prompts nothing by itself — accepted, and the cheap mitigation is
to offer the re-check at the end of ADR-007's existing imported-pack activation confirmation flow,
where the user is already standing and no state is needed. Re-open trigger: if a second pack
correction ships after US-A6 and the user does not notice it, add the stored version and the
prompt. See **H-17**.

---

### ADR-007 — Parsing is a **data-driven rule pack**, not per-bank code.

**Answers A-6. Serves NFR-M1, NFR-M2. Mitigates R-4, R-11.**
**Amended by the KHA-127/KHA-128 decision (v1.5, 2026-07-30)** — the dated subsection at the end
of this ADR. Step 2 of the evaluation order below (**"no match → discard entirely, retain
nothing"**) is **upheld exactly as written**, but it is no longer allowed to be *silent*. Read the
subsection before touching `ingestion_pipeline.dart`'s `NotFinancialSender` branch, the sender
gate in `rule_pack_parser`, or anything that reads `IngestionStats`.

**Context.** PRD §3.4 shows two banks producing structurally different messages across nine
transaction types, in two languages, with merchant names in Latin script inside Arabic
messages. Formats change without notice. Side-load distribution means a code change requires
the user to manually install an APK (R-11).

**Decision.** Parsing rules are **declarative, versioned JSON documents ("rule packs")**
loaded at runtime. There is no per-bank Dart code. The engine is generic; banks are data.

Rule packs load from two sources:
1. **Bundled** — shipped as a Flutter asset, `source: bundled`, trusted.
2. **Imported** — a JSON file the user picks via SAF, `source: imported`, marked
   **`unverified`**. This is the answer to R-11: **parser rules can be updated without
   reinstalling the APK.** Before activation the app shows a human-readable diff (banks
   added/changed, rules added/removed) and requires confirmation.

**Rule pack schema (v1) — this is a contract; see §5.2 for the normative form.**

```
RulePack   { schemaVersion, packId, packVersion, locales[], banks[] }
BankRule   { bankId, displayName{ar,en}, aliases[], senderPatterns[], messageRules[] }
MessageRule{
  ruleId, priority, messageType, intent: transaction|ignore,
  match:   { anyOf[], allOf[], noneOf[] },        // regex, applied to normalised text
  extract: { <field>: { group, transform[] } },   // named capture groups → domain fields
  sign: debit|credit, affectsSpend: bool,
  requiredFields[], redact[]
}
```

**Evaluation order (deterministic, and this ordering is itself the classifier for US-A2):**

1. Normalise the message: Unicode NFKC, strip bidi controls, Arabic-Indic → ASCII digits,
   collapse whitespace, strip tatweel.
2. Resolve the **bank** by matching the SMS originating address against `senderPatterns`
   across all active packs. **No match → not a financial sender → discard entirely, retain
   nothing** (NFR-P4).
3. Within the bank, evaluate `messageRules` by descending `priority`, **first match wins**.
   - `intent: ignore` (OTP, marketing, balance-info) → **discard the body**; retain only a
     minimal counter row (bank, classification, timestamp, no text) for the parser-health panel
     (ADR-015). Satisfies AC-A2.1/A2.2/A2.5 and NFR-P4.
   - `intent: transaction` → run `redact[]` (ADR-013), then `extract`. If any `requiredFields`
     is missing → **review queue** with the sanitised text (US-A4, AC-A4.1).
4. **No rule matched, but the sender is a known financial sender** → **review queue** with the
   sanitised text. **Never discarded** (AC-A4.4, NFR-A7).

**Safety.** Rule packs are declarative only — there is no expression language, no `eval`, no
code. Regex evaluation runs in a background isolate with a **per-rule 250 ms timeout** to
contain catastrophic backtracking in a malformed imported pack. Imported packs are v1
**unsigned**; the mitigations are (a) declarative-only, (b) timeout, (c) mandatory user review
of the diff, and (d) **the app has no network permission**, so a hostile pack cannot exfiltrate
anything. Pack signing is deferred (§8).

**Provenance.** Every transaction records the `rulePackId`, `packVersion`, and `ruleId` that
produced it (NFR-A1). A rule change never rewrites history; re-parsing produces a *new*
candidate that the user confirms, and user edits always win (AC-B5.3).

**Testing (NFR-M2, NFR-M3).** A **synthetic** fixture corpus — realistic but fabricated, never
the user's real SMS — with expected structured output per fixture, run in CI. A rule change
that breaks a previously-passing fixture fails the build.

#### KHA-127 / KHA-128 decision — the sender gate stays hard. **The silence was the defect, and a derived fact is fixed by deriving it, not by retaining it.** Decided 2026-07-30.

**Status: DECIDED.** Answers the human's 2026-07-30 escalation, raised as potentially existential:
*"the app should be smart enough… if this is not working it will be a breaker for the entire idea,
since we will not be able to inject LLM to deal with these things inside the app."* Binding on the
US-A6 implementation. It is not a menu.

##### What actually failed, stated precisely

Seven banks produced total silence. The temptingly obvious diagnosis — *the app is not smart
enough to recognise a bank message* — is wrong, and acting on it would have cost the product its
trust proposition for nothing. Three facts settle it:

1. **Nothing was lost.** NFR-P4 governs what *Massrofy's database* retains. It does not govern
   whether the message survives. Every one of those messages is still sitting in
   `content://sms/inbox`, on a permission (`READ_SMS`) the app already holds and already uses on
   every ingestion run. The app can re-read all of it, at any time, for free.
2. **The app already knew.** `IngestionStats.discardedNonFinancialSender` is incremented on the
   `NotFinancialSender` branch of `ingestion_pipeline.dart`, summed across the run, returned to the
   caller — **and then dropped on the floor.** It is surfaced in no screen, no panel, and no
   diagnostic event. The app computed "I skipped 214 messages from senders I don't recognise" and
   said nothing. **That is the defect.** It is an observability defect, not an intelligence one.
3. **The answer was already in the shipped data.** `sa-core.json` carries
   `aliases: ["ALJAZIRA", "BAJ", "الجزيرة"]` and `displayName.en: "Bank Aljazira"` for
   `bank-aljazira`. The phone shows `Jazira Bank`. Those token-overlap obviously. The gate never
   looked, because `aliases` was specified for downstream entity resolution (AC-B12.3, §4.2 `Bank`)
   and never consulted at the sender step. **We shipped the string that identifies the bank and
   never compared it to the sender.**

So the product concept was never in danger from a missing intelligence tier. It was in danger from
a **hard gate with no voice**. A gate may be strict. It may not be mute.

##### The options, and why the one framed as "complementary" wins

| Option | Assessment |
|---|---|
| **(1)** Loosen gate 1: a body that "looks financial" from an unrecognised sender routes to needs-review | **REJECTED as a gate.** Four independent defeats. **(a) It persists content from senders never confirmed to be banks.** A needs-review item is a `RawMessage` row *with* `sanitizedBody` (§4.2 retention rules). The false positives are not abstract noise — they are a friend saying "I'll send you the 250 SAR tomorrow", a landlord, a clinic invoice. Option 1 harvests exactly the messages NFR-P4 exists to keep out, into the most sensitive store in the product. **(b) It needs X19, which is out of scope.** AC-A4.3 requires a dismissal to be durable, so every false positive mints a persisted record *about a message the user has just confirmed is not financial* — the precise thing PRD X19 and NFR-P4a rule out. **(c) The false-positive population is hostile.** A Saudi inbox is saturated with amount-bearing non-bank SMS: telecom balance and top-up notices, food-delivery order totals, BNPL reminders, government fee notices, and promotional pricing. Worse, **3-D Secure OTP messages routinely carry the transaction amount**, so the highest-volume amount-bearing sender class is also the one that must never be retained. **(d) It infers what it could ask.** The ground truth — *is this sender my bank?* — is known with certainty by one party, who is holding the phone. Guessing it at 90% when you can ask it at 100% is a bad trade, and it is the same trade ADR-008's KHA-98 decision already refused for merchant identity. |
| **(2)** A small bundled on-device classifier as a lower-confidence tier | **REJECTED for v1** — and on **evidence**, not effort, which matters because effort arguments expire and this one does not. **We have no training corpus and are forbidden from building one.** NFR-M3 bars the user's real SMS from the fixture corpus; training on our own synthetic fixtures teaches the model the priors we hand-wrote, i.e. it is a regex with worse auditability. **We could never evaluate it.** NFR-S6, R-10 and R-11 mean no telemetry, no crash channel, no field metrics, and no way to ship a retrained model except a manual APK install — a permanent unmeasurable black box on the most trust-critical path. **It breaks two properties ADR-007 exists to provide:** NFR-A1 requires every transaction to record the `ruleId` that produced it (weights have no `ruleId`), and NFR-M2 requires a rule change that breaks a fixture to fail CI (a weight diff is not reviewable). And it ships the one component of a "you can verify what this app does" product that **nobody can inspect** — weakening the trust story it was meant to serve. Re-open trigger stated as **O-7**. To be explicit for the record: this rejection is *not* the ADR-001 network argument. A fully offline model does not violate ADR-001. It fails on its own merits. |
| **(3)** User self-service sender linking (PRD Addendum A, US-A6 / C17) | **CHOSEN, and promoted from complementary to primary.** It is the only option that produces *certainty* rather than a better guess, it is the only one that yields *bank attribution* (option 1 yields a flat unattributed queue), and per AC-A6.4 linking triggers a lookback re-scan so it repairs the past as well as the future. **It is also the only option that needs no change to NFR-P4 at all.** |

**Option 1's heuristic is not discarded — it is relocated, and the relocation is the whole
decision.** As a *gate* it must be low-false-positive because a wrong answer costs a persisted
private message. As an **advisory ranking signal on the US-A6 screen** a wrong answer costs one
row of screen position. Same code, two orders of magnitude less consequence. That is where it goes.

##### Normative: the four things this decision requires

**(A) The sender gate is unchanged. NFR-P4 is unchanged.** `NotFinancialSender` still writes no
row — not a body, not a counter, not a timestamp, not a sender string. The claim in
`sms_permission_rationale_screen.dart` ("an unrecognised sender produces **no database row at
all**") stays literally true and stays tested. **No sender string from an unlinked sender is
persisted anywhere, ever.**

**(B) One clarification to NFR-P4, which is a boundary statement and not a relaxation.**
An engineer reading NFR-P4 literally could conclude that even *counting* discards is forbidden.
It is not, and it must not be:

> **A content-free, sender-free aggregate count is not retention of a message.** The number of
> messages skipped in a run may be surfaced in the UI and recorded as an ADR-015 diagnostic event.
> What may never be retained is *which sender*, *what it said*, or *when any individual one
> arrived*. `{discardedNonFinancialSender: 214}` is permitted. `{sender: "…", at: …}` is not.

This is already inside ADR-015's stated contract ("ids, enums, counts, durations — never free
text"). §4.2's `RawMessage` retention rules gain a matching bullet.

**(C) Sender-name suggestion, from data we already ship. Highest value, lowest risk, do it first.**
On the US-A6 screen only, for each unrecognised sender, compute a token-overlap score against every
active pack's `BankRule.displayNameAr` / `displayNameEn` / `aliases`, and pre-suggest the best
match: *"This looks like Bank Aljazira — is it?"* Constraints, all binding:

- **Suggestion only. Never an automatic link.** A machine fuzzy-matching two identities together is
  the exact defect class ADR-008's KHA-98 decision forbids. The user confirms.
- **What gets stored is the literal sender string**, matched whole-string, case-insensitive,
  trimmed, never as a regex (AC-A6.6). The fuzzy logic lives entirely on the screen and **never
  enters the ingestion path.** `MerchantKey`-style purity: the gate stays a literal comparison.
- Separately and independently: **normalise the incoming sender string** (trim, collapse internal
  whitespace, NFKC) before matching `senderPatterns`. Cheap, strictly increases matches, no
  downside. Stated honestly: **this alone would not have fixed KHA-128** — `Jazira Bank` fails
  `^(BAJ|Aljazira|...)$` on word order, not on whitespace. Do it anyway; it is correct.

**(D) The unrecognised-sender health signal. This is the part that closes the actual failure.**
PRD Addendum A links the sender screen from Home's **zero/empty** state and from an **empty** review
queue. Both are empty only at first run. **The silent-sender-ID-change case — a bank changes its
sender ID in month eight — has a fully populated home screen, and Addendum A as written is silent
for it, which is the same silence that produced KHA-128.** Therefore:

- On every ingestion run and on every foreground sweep, if the run's
  `discardedNonFinancialSender` count is non-zero, emit an ADR-015 diagnostic event (count only)
  **and** make the fact reachable from a persistently visible affordance — a row in the
  parser-health panel at minimum, and a dismissable-per-session entry point from Home. Not
  conditional on an empty state.
- The parser-health panel (ADR-015) gains an **"unrecognised senders"** row alongside its
  parsed/unparsed/ignored counts. It shows a **count**, and it links to the US-A6 screen where the
  live list is derived on demand. The panel never stores the senders.

##### The advisory financial-shape signal — concrete shape, since it is now advisory

`FinancialShapeSignal.of(String normalizedBody, {required bool panRedacted}) → {unlikely, possible,
likely}`. A pure function. Runs **only** on the US-A6 screen path, in memory, over text already
normalised by `SmsTextNormalizer` (so Arabic-Indic digits are already ASCII and bidi controls are
already stripped — write ASCII regexes). Never called from `ingestion_pipeline.dart`.

**Necessary conditions — both required, or the answer is `unlikely`:**

1. **An amount adjacent to a currency token**, not merely a number. Currency tokens: `SAR`, `SR`,
   `AED`, `QAR`, `KWD`, `BHD`, `OMR`, `JOD`, `USD`, `EUR`, `GBP`, `EGP`, `TRY`, `﷼` (U+FDFC),
   `⃀`/U+20C0, and `ريال`, `ر.س`, `درهم`, `دينار`, `دولار`, `جنيه`, `هللة`. **`$` alone does not
   count** — it is endemic in promotional text. Amount shape, requiring the token within ~12
   characters of a currency token on either side:
   `(?<![\d.,])\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?(?!\d)` or `(?<![\d.,])\d+(?:\.\d{1,3})?(?!\d)`.
2. **A transaction-event keyword** — a *completed movement on an account or card*, not a price.
   Arabic: `شراء`, `سحب`, `إيداع`/`ايداع`, `حوالة`, `تحويل`, `عملية`, `بطاقة`, `حسابك`,
   `نقاط البيع`, `صرف آلي`, `مدى`, `استرداد`, `فاتورة`, `خصم من الحساب`/`خصم من حسابك`.
   English: `purchase`, `withdrawal`, `deposit`, `transfer`, `payment`, `POS`, `ATM`, `debit`,
   `credit`, `refund`, `transaction`, `mada`, `authoris`/`authoriz`. **Bare `خصم` is excluded** —
   it means both *deduction* and *discount*, and the discount sense dominates in marketing.

**Corroborators (raise to `likely`; two or more required):** `panRedacted == true` (a message
containing a PAN is overwhelmingly a bank — and it is free, the sanitiser already returns it); a
masked instrument reference (`\*{2,}\s?\d{2,4}`, `\d{4}\*+`, `تنتهي ب`, `ending`); a
balance-after or reference field (`الرصيد`, `المتاح`, `available balance`, `مرجع`, `رقم العملية`,
`ref`, `trn`); an in-body date **and/or** time stamp (`\d{2}[/-]\d{2}[/-]\d{2,4}`, `\d{1,2}:\d{2}`);
a two-decimal amount (`\.\d{2}` — banks print cents, promotional pricing prints round numbers).

**Veto and demotion signals — this is where the false positives actually die:**

- **Veto to `unlikely` outright: OTP/verification shape.** `رمز`, `رمز التحقق`, `كلمة المرور`,
  `لا تشاركه`, `صالح لمدة`, `OTP`, `verification code`, `one-time`. **This veto is load-bearing:**
  Saudi 3-D Secure OTPs carry the transaction amount, the merchant, and the masked card, so they
  satisfy every positive signal above and must still never be retained (AC-A2.1).
- **Veto to `unlikely`: the sender is a plain mobile number** (`^\+?9665\d{8}$`, `^0?5\d{8}$`).
  Bank alerts in Saudi arrive from alphanumeric sender IDs, never an MSISDN. This single rule
  removes the most privacy-sensitive false-positive class — a person texting about money — and it
  costs one regex.
- **Demote one level (each):** a URL (`http`, `www.`, `.com`) — transaction alerts rarely carry
  links, marketing always does; `%` together with `خصم`/`عرض`/`discount`/`offer`/`sale`/`promo`;
  unsubscribe language (`لإلغاء`, `unsubscribe`, `STOP`); telecom-plan vocabulary (`الباقة`,
  `رصيدك المتبقي`, `جيجابايت`, `GB`, `MB`, `minutes`); delivery/e-commerce (`طلبك`, `شحنة`,
  `تم تسليم`, `order`, `shipment`, `delivery`).

**The aggregation is worth more than the per-message logic, and it is only available here.**
The signal shown to the user is **per sender, over that sender's whole message population in the
window**: *22 of 30 messages look like transactions*. A sender scoring `likely` on 70%+ of a
double-digit message count is a bank with near-certainty; a marketing sender that mentioned a price
once scores 1 of 40 and sorts to the bottom. **Gate 1 sees one message at a time and structurally
cannot do this.** That asymmetry is an independent argument for the relocation, on accuracy grounds
rather than privacy grounds.

**Where the lists live.** Dart constants in `lib/features/parsing/` for v1, **not** new rule-pack
schema surface. Prefer the simpler option and say so: these lists only affect screen ordering, so
making them updatable-as-data buys little and costs schema review. Promoting them into the pack is
noted as a v1.1 option under **O-7**.

##### What this decision does *not* fix, said plainly

The gap that remains is **gate 2 quality**, and the human should understand that it, not gate 1, is
where the concept is genuinely exposed. AC-A6.5 sets an honest floor: a linked sender delivers value
with *no* parsing rule, via the review queue and manual completion. Nothing is lost. But PRD §1
defines success as *"the user opens the app and trusts the numbers without having done manual data
entry."* If linking seven banks yields seven senders whose bodies no rule can parse, the user
hand-completes hundreds of messages a month and **the product fails its own success criterion while
every component behaves exactly as specified.** That is a rule-*content* problem, discharged by
obtaining real message samples per bank and writing rules — engineering and ops work (KHA-128's
other half), not an architecture change. The mechanism already half-exists: extend ADR-015's
"share diagnostics" pattern to a **user-initiated, redaction-applied, fully reviewable sample
export**. Note the NFR-M3 boundary carefully, because an engineer will otherwise either refuse the
task or violate the rule: the rule author may *read* real samples the user deliberately shared, and
must then commit a **synthetic** fixture that mimics the shape. Real message text never enters the
repository.

#### Canonical SMS field taxonomy — the fixed slot vocabulary rules are written against. Proposed 2026-07-30. Re-derived against SAMA Circular 42023876, 2026-07-30. Approved 2026-07-30.

**STATUS: APPROVED.** Everything above in ADR-007 stays `APPROVED` and is
unchanged by this subsection. It adds **no schema change, no rule change, and nothing that blocks the
in-flight six-bank rule dispatch** — it is a vocabulary, a checklist, and one loader-validation
recommendation. Read the recommendation at the end before anyone retrofits anything.

**Why now.** One day of real-device testing produced 15+ distinct message shapes across 7 Saudi banks
— purchases, transfers in and out, OTPs, POS vs ecommerce, Arabic and English variants of the same
bank — each written as its own regex from a blank page. That does not scale, and it blocks the
format-teaching capability being scoped in parallel: you cannot ask a user to *label* parts of a
message unless there is a small, fixed, well-understood set of labels to label with.

##### The primary authority: the message shape is regulated, not emergent

The slot set is not our invention and not a generalisation from samples. In Saudi Arabia **the
content of a bank transaction notification is mandated by the regulator**, which makes this the one
market where a parser can be written against a published specification rather than against
guesswork.

> **SAMA (Saudi Central Bank) — *Standardization of Notification Elements Sent to Financial
> Institutions Customers*, Circular No. 42023876, dated 14/04/1442H (≈ 29/11/2020), in force.**
> Binds **all** financial institutions in the Kingdom. Its stated purpose is customer awareness via
> notification messages covering transactions on **accounts, card memberships, and electronic
> wallets**. It sets a **minimum** element set per transaction category in **Table No. (1)**, and a
> **standardised bilingual (Arabic–English) transaction-description vocabulary** in **Table No. (2)**.
> Extended in 2021 by *The Key Elements of SMS Notifications for Newly Updated Mada Transactions*
> (compliance due end of Q1 2022). Adjacent instruments that also constrain notification content:
> *Instant SMS Notification Service* (SMS for **every** debit and credit on personal accounts and
> credit-card accounts) and the *Rules of Issuance and Operation of Credit Cards*.

This reframes the whole exercise. A Saudi bank SMS is not free-form prose that we hope has structure;
it is a rendering of a **regulator-specified minimum field set**. Consequences that matter
architecturally:

- **The slot set has a floor we can rely on.** If a rule cannot find `amount`, `occurredAt` or an
  instrument reference in a transaction-shaped message from a licensed institution, the likeliest
  explanation is a defect in *our* pattern, not a bank that omitted the field. That flips the default
  diagnosis for R-4/KHA-128-class losses.
- **SAMA defines the ceiling of what *will appear*; our tiers define the floor of what we *keep*.**
  These are different questions and the gap is deliberate. SAMA mandates that banks *send* things
  (available credit, total amount due) that NFR-S2/NFR-P4 would rather we did not *store*. Receiving
  and discarding a field is not a conformance failure — see Tier 3.
- **It is a prior, not a guarantee.** The SMS is still a lossy rendering chosen by each bank's
  template author, and observed messages deviate. The regulation tells a rule author what to *look*
  for; only a real sample tells them what the bank actually *printed*. Rules stay sample-verified.

**Both tables are now retrieved verbatim** (2026-07-30, follow-up fetch — the first pass could not
read through the rulebook's table viewer; a direct fetch of `/en/table-no-1` and `/en/table-no-2`
did). Full text below. Nothing in this subsection now rests on an unverified summary.

*Sources:* the circular at `rulebook.sama.gov.sa/en/standardization-notification-elements-sent-financial-institutions-customers`;
its tables at `/en/table-no-1` and `/en/table-no-2`; the 2021 extension at
`/en/key-elements-sms-notifications-newly-updated-mada-transactions`; and the adjacent
`/en/instant-sms-notification-service` and `/en/rules-issuance-and-operation-credit-cards`.

##### Table No. (1), verbatim — minimum elements per notification category

18 categories, each with its own minimum field list. Reproduced in full since this is the primary
engineering reference for what a rule's `requiredFields`/`extract` set should expect to find.

| Category | Minimum elements |
|---|---|
| Internal Purchases | Amount, Currency · Store Name · Card Type (Mada, Credit), Executed Through (e.g. Apple Pay, Mada Pay, Atheer) · Card Number (Last Four Digits) · Date · Time |
| International Purchases | Amount, Currency · Store Name · Country · Card Type (Mada, Credit), Executed Through · Card Number (Last Four Digits) · Date · Time |
| Internal Cash Withdrawal | Amount, Currency · Withdrawal Location (ATM Location or Branch/Code) · Card Type (Mada, Credit) · Card Number (Last Four Digits) · Date · Time |
| International Cash Withdrawal | Amount, Currency · Country · Fees · Card Type (Mada, Credit) · Card Number (Last Four Digits) · Date · Time |
| Checks | Amount, Currency · Payee Name / Cheque Holder's Account Number · Date · Time |
| Cash Deposit | Amount, Currency · Deposit Method (e.g. Branch or ATM) · Account Number · Date · Time |
| Domestic Transfers | Transferred Amount, Currency · Fees · Sender's Name (incoming) · Receiver's Name (outgoing) · Sender's Account Number (incoming) · Receiver's Account Number (outgoing) · Date · Time |
| International Transfers | Transferred Amount, Currency · Fees · Sender's Name · Receiver's Name · Sender's Account Number · Receiver's Account Number · Transfer Intermediary Company Name (e.g. Western Union) · Destination Country · Date · Time |
| Internet Purchases | Amount, Currency · Website or Store · Card Type (Mada, Credit), Executed Through · Card Number (Last Four Digits) · Account Number · Date · Time |
| Government Bill Payments | Amount, Currency · Entity · Service · Invoice Number · Date · Time |
| Other Bill Payments | Amount, Currency · Biller · Service · Invoice Number · Date · Time |
| Financing / Refinancing Transactions | Financing Type · Total Amount of Financing · Monthly Installment · Account Number · Date · Time |
| Monthly Financing Deduction | Financing Type · Due Installment · **Total Remaining** · Amount · Account Number · Date · Time |
| Fees | Amount, Currency · Reason · Account Number · Date · Time |
| Refund / Reversal | Amount, Currency · Country (external transactions) · Store/Website/Entity · Account Number · Date · Time |
| Mobile App Transactions | App Name (e.g. Apple Pay) · Amount, Currency · Store Name or Website · Card Type (Mada, Credit), Card Number (Last Four Digits) · Account Number · Date · Time |
| E-Wallet Top-Up | Wallet Name (e.g. STCPay) · Amount, Currency · Top-Up Channel (Mada, Credit, SADAD, etc.) · Card Number (Last Four Digits) · Date · Time |
| E-Wallet Transactions | Amount, Currency · Card Type (Mada, Credit) · Card Number (Last Four Digits) · Store or Website · Date · Time |

Two corrections this makes to claims below: **no category names a standalone "reference number"
element** — transfers are identified by sender/receiver name + account number, not a reference
code, so `referenceNumber`'s status as ADR-017 D2's dedup key is Massrofy's own design choice, not
a SAMA mandate; and **"Refund" and "Reversal" are one category, not two** in Table No. (1) — Table
No. (2)'s separate "Reverse Transaction" term is a *description*, not evidence of a second category
structure. The `reversal`-aliased-to-`refund` decision below is correct for exactly this reason,
made stronger, not weaker.

##### Table No. (2), verbatim — standardised bilingual transaction-description vocabulary

60 entries. This is the anchor-token reference for `messageType` regex — Arabic and English wording
a rule's message-body pattern should key on, never `senderPatterns`.

| Arabic | English |
|---|---|
| سداد فاتورة | Bill Payment |
| سداد فاتورة لمرة واحدة | Bill Payment one time |
| إصدار شيك مصدّق | Certified Cheque Issued |
| بطاقة ائتمانية الغاء حجز مبلغ | Credit Card Cash Release |
| بطاقة ائتمانية حجز مبلغ | Credit Card Cash Reserve |
| بطاقة ائتمانية استرجاع نقدي | Credit Card Cashback |
| بطاقة ائتمانية تأكيد سداد | Credit Card Credited |
| بطاقة ائتمانية تسديد | Credit Card Payment |
| بطاقة ائتمانية استرداد مبلغ | Credit Card Refund |
| إيداع رسوم | Credit Transaction Fees |
| حوالة واردة من بطاقة | Credit transfer from card |
| حوالة واردة بين حساباتك | Credit transfer Between Your Accounts |
| حوالة واردة حساب مواطن | Credit transfer Citizen Account |
| سحب نقدي طارئ | Credit transfer Emergency Cash Withdrawal |
| حوالة واردة من حسابك الجاري | Credit transfer From your Current Account |
| حوالة واردة من حسابك الاستثماري | Credit transfer From Your Investment Account |
| حوالة واردة حافز | Credit transfer Hafiz |
| حوالة واردة داخلية | Credit transfer Internal |
| حوالة واردة دولية | Credit transfer International |
| حوالة واردة تمويل | Credit transfer Loan |
| حوالة واردة محلية | Credit transfer Local |
| حوالة واردة راتب | Credit transfer Salary |
| حوالة واردة كفيل | Credit transfer Sponsor |
| حوالة واردة مكافأة طلاب | Credit transfer Student Reward |
| خصم رسوم | Debit Transaction Fees |
| حوالة صادرة الى بطاقة | Debit Transfer to card |
| حوالة صادرة بين حساباتك | Debit Transfer Between Your Account |
| حوالة صادرة داخلية | Debit Transfer Internal |
| حوالة صادرة دولية | Debit Transfer International |
| خصم قسط تمويل | Debit Transfer Loan Instalment |
| حوالة صادرة محلية | Debit Transfer Local |
| حوالة صادرة راتب | Debit Transfer Salary |
| حوالة صادرة مكفول | Debit Transfer Sponsored |
| حوالة صادرة الى حسابك الجاري | Debit Transfer To Your Current Account |
| حوالة صادرة الى حسابك الاستثماري | Debit Transfer To Your Investment account |
| خصم شيك مصدق | Debit Certified Cheque |
| خصم شيك ورقي | Debit Paper Cheque |
| إيداع صراف آلي | Deposit ATM |
| إيداع فرع | Deposit Branch |
| إيداع شيك مصدق | Deposit Certified Cheque |
| إيداع شيك ورقي | Deposit Paper Cheque |
| شراء عملة أجنبية | Foreign Currency Purchase |
| سحب صراف آلي دولي | International ATM Withdrawal |
| مدفوعات وزارة الداخلية | MOI Payments |
| شراء إنترنت | Online Purchase |
| امر مستديم سداد فواتير | Permanent transfer Bill Payment |
| امر مستديم حوالة صادرة داخلية | Permanent transfer Debit transfer Bank internal |
| امر مستديم حوالة صادرة بين حساباتك | Permanent transfer Debit transfer Between Your Accounts |
| امر مستديم حوالة صادرة دولية | Permanent transfer Debit transfer International |
| امر مستديم حوالة صادرة محلية | Permanent transfer Debit transfer Local |
| امر مستديم حوالة صادرة راتب | Permanent transfer Debit transfer Salary |
| امر مستديم مدفوعات وزارة الداخلية | Permanent transfer MOI Payments |
| شراء عبر نقاط البيع دولية | PoS International Purchase |
| شراء عبر نقاط البيع | Pos Purchase |
| شراء ونقد عبر نقاط البيع | Pos Purchase & Cashback |
| تسوية نقطة البيع | PoS settlement |
| حوالة واردة | Received transfer |
| استرجاع مدفوعات وزارة الداخلية | Refunding MOI Payments |
| حوالة عكسية | Reverse Transaction |
| سحب صراف آلي | ATM Withdrawal |
| سحب فرع | Branch Withdrawal |

##### Secondary corroboration — the same shape is reached independently elsewhere

SAMA is the authority; these remain in the record because they show the slot set is a property of the
*domain*, not of one regulator, which is what makes it safe to fix the vocabulary rather than keep
rediscovering it per bank. ISO 20022 `camt.054` is the formal model of exactly this artefact — a
bank-to-customer debit/credit notification.

| Source | Slots it settled on |
|---|---|
| ISO 20022 `camt.054` (the formal notification model) | amount + currency, `CdtDbtInd` (debit/credit), booking/value date, entry reference and end-to-end id, debtor and creditor (counterparty) plus their agents (counterparty bank), account, balance, `BkTxCd` (bank transaction code — event + channel), remittance information |
| `transaction-sms-parser` (JS, Indian market) | `account{type: CARD\|WALLET\|ACCOUNT, number, name}`, `balance{available, outstanding}`, `transaction{type: debit\|credit, amount, referenceNo, merchant}` |
| `pennywiseai-tracker` (Kotlin, 85+ banks across 14 countries, Arabic + English, includes Saudi) | `amount, type, merchant, reference, accountLast4, balance, creditLimit, currency, fromAccount, toAccount, isFromCard, bankName, timestamp` |
| `transaction-parser-th` (Thai market) | provider, type, date, time, from/to account, amount, balance |

One regulator and four independent derivations across three markets, one shape.

##### Tier 0 — declared by the rule, never extracted

These are not spans in the text. They are properties of the *template*, decided once by whoever
writes the rule — which is why they are auditable and why no regex should try to infer them.

`intent` · `messageType` · `sign` (= `CdtDbtInd`) · `affectsSpend`

**`messageType` carries the channel dimension, and should keep carrying it.** POS vs ecommerce vs ATM
vs wallet is the one "field" that is frequently *not* present as a span at all — it is implied by
which template the bank chose. Encoding it as `pos_purchase` / `online_purchase` / `withdrawal`
rather than as an extracted `channel` slot is correct and stays. SAMA's own structure agrees: it
organises the mandate by *transaction category*, and category, not a separate channel field, is what
selects the required elements.

**SAMA's categories, mapped.** Table No. (1), now retrieved verbatim above, has exactly 18: Internal
Purchases, International Purchases, Internal/International Cash Withdrawal, Checks, Cash Deposit,
Domestic/International Transfers, Internet Purchases, Government/Other Bill Payments,
Financing/Refinancing, Monthly Financing Deduction, Fees, Refund/Reversal, Mobile App Transactions,
E-Wallet Top-Up, E-Wallet Transactions. Mapping those against the shipped vocabulary is what this
re-derivation was for, and it found **four genuine gaps and four false ones.**

Vocabulary, shaped `<event>` optionally suffixed `_<channel>`. **Bold entries are added by this
revision;** the rest are unchanged and already shipping in `sa-core.json`:

`pos_purchase` · `online_purchase` · `withdrawal` · `refund` · `transfer_out` · `transfer_in` ·
`salary_income` · `bill_payment` · `card_repayment` · `installment` · `fee` · **`deposit`** ·
**`cheque`** · **`wallet_topup`** · **`reversal`** · `account_debit` · `account_credit`, plus the
`intent: ignore` set `otp` · `marketing` · `balance_info`.

| Added | Why the gap is real |
|---|---|
| `deposit` | SAMA treats deposits as their own category. Today a cash or salary-unrelated deposit can only be `account_credit`, which is the fallback bucket — it parses, but the user sees an unlabelled credit. |
| `cheque` | Its own SAMA category, and it carries a cheque number that belongs in `referenceNumber`. Nothing in the current vocabulary names it. |
| `wallet_topup` | **The highest-value addition.** Loading STC Pay / urpay / an Apple Pay balance is a SAMA category and is common in this market. Today it lands as `transfer_out` or `account_debit`. It is structurally a `card_repayment`-shaped event — *money moving between the user's own instruments* — and mislabelling it hides that from anyone reasoning about double counting. See the `affectsSpend` note below; the type must exist before that judgement can even be expressed. |
| `reversal` | SAMA distinguishes reversals from refunds. Arithmetically both are credits back, so **aliasing `reversal` to `refund` in v1 is acceptable and loses no money** — the reason to name it is that a reversal cancels a specific prior authorisation and is the correct future hook for matching-and-cancelling rather than posting income. Lowest priority of the four. |

**Considered and deliberately *not* added** — recording these matters as much as the additions,
because each is a plausible-looking mistake:

- *International purchase / withdrawal as separate types.* The international-ness is already carried,
  and carried better, by the presence of `convertedAmount` / `exchangeRate` / `feeAmount`. A type
  suffix would duplicate state that can then disagree with itself.
- *Apple Pay / mada Pay / Atheer / mobile-app as types.* SAMA mandates an **"Executed Through"**
  element naming the wallet or channel, so this *will* appear in real messages. It is a channel, not
  an event, and it changes no number — Tier 3. If it ever earns representation it is a `_<channel>`
  suffix, not a new event.
- *Financing disbursement.* A drawdown is a credit; `account_credit` carries it. Adding a type for a
  once-a-year event is vocabulary bloat at `TIER: personal`.
- *Government payment as distinct from bill payment.* SADAD-shaped and already served by
  `bill_payment` + `billerCode`.

**`affectsSpend` for `wallet_topup` is a deliberate per-rule call, not a default.** Massrofy ingests
bank SMS, so a top-up is normally the *only* visible event and should count as spend (`true`). If the
wallet's own notifications are also being ingested, counting both double-counts — the identical trap
`card_repayment` already documents. Rule authors must decide it explicitly and say why.

This stays **recommended, not enforced.** §5.2's forward-compatibility rule — an unrecognised
`messageType` routes to the review queue and is never discarded — is load-bearing and must not be
traded for a closed enum. A list a human checks against beats an enum that rejects a newer pack.
That property is now doing more work than before: the four new types must be able to appear in a pack
without an engine change, and under §5.2 they can.

**Table No. (2) is the anchor-token reference for whoever writes the discriminating regex**, now
reproduced in full above — 60 Arabic/English term pairs, e.g. `سداد فاتورة` / "Bill Payment". Two
cautions: it is a *description* vocabulary, not a sender-identity one, so it informs message-body
patterns and **not** `senderPatterns` — sender identity stays resolved per ADR-007 step 2 and
AC-B12.3 — and a bank that words a message differently is still a bank whose message we must parse,
so the list is a starting point for patterns, never a filter on them.

##### Tier 1 — universal slots

Present in essentially every transaction-shaped message, in every bank and both languages. **All four
correspond to elements SAMA mandates as a minimum across categories** — amount and currency, date and
time, and card details given as *type* plus *last four digits*.

| Slot | Note |
|---|---|
| *(bank identity)* | **Not a slot.** Resolved from the sender, never from the body (ADR-007 step 2, AC-B12.3). Listed only so nobody adds a `bankName` extract. |
| `amount` | The movement's value. SAMA-mandated. |
| `currency` | Satellite of `amount`. SAMA mandates it alongside the amount, but banks routinely omit it from the SAR-domestic template because it is implied — so it stays frequently absent as a span and supplied by `literal: "SAR"`. That is exactly what `literal` is for. |
| `instrumentRef` (+ `…Network`, `…Type`) | Which card or account. **SAMA corroborates the split we already enforce:** it mandates *card type* (mada, credit) and *card number — last four digits* as two separate elements. That is the regulator independently confirming AC-B13.1/2 — `kind` is rule-declared, never guessed from digit count. Guessing was already banned; it is now also contrary to how the source data is specified. |
| `occurredAt` | SAMA mandates date **and time**, which strengthens this slot's status: a missing timestamp span is a template quirk or a pattern defect, not the norm. `received_at_fallback` stays the correct safety net but should be the exception, and a rule relying on it habitually is worth a second look. |

##### Tier 2 — conditional slots, determined by `messageType`

SAMA's remaining mandated element families — reference/account numbers, transaction location or
entity name, and the FX and fee elements required for international and credit-card transactions —
land here. Every one already has a slot; **the re-derivation added no Tier 2 slot.** What it changed
is the confidence level: several of these are now known to be *required to be present*, not merely
observed sometimes.

| Slot | Appears on |
|---|---|
| `merchant` | purchases, refunds, bill payments (biller as merchant), ATM (location as merchant). SAMA's "transaction location or entity name" element |
| `counterpartyName` | transfers in/out, salary |
| `counterpartyBankName` | interbank transfers. This is the **other** bank; confusing it with the sending bank is the easiest wrong answer in the whole taxonomy |
| `referenceNumber` | transfers, cheques (the cheque number), some bill payments. **SAMA mandates a reference or account number for several categories**, which materially strengthens ADR-017 D2 — the dedup key we prefer is one the regulator requires to be there |
| `remainingBalance` (+ `…Currency`) | financing/installment messages — Table No. (1)'s "Total Remaining". **Not** a plain account balance-after; see the open question at the end for why |
| `feeAmount` (+ `…Currency`) | FX purchases, some transfers. SAMA-mandated for international card transactions |
| `convertedAmount` (+ `…Currency`), `exchangeRate` | foreign-currency purchases. `exchangeRate` is SAMA-mandated for these |
| `settlementRef` (+ `…Network`, `…Type`) | card repayment — the **second** instrument (AC-B14.1) |
| `billerCode`, `invoiceNumber` | bill payments (SADAD-shaped) |

**One rule turns this list into working guidance:** *if `affectsSpend` is true, `merchant` must be
populated*, aliasing another role's span where necessary. The categorisation loop (ADR-008,
US-D1/D2) keys on `merchantRawText`; a spend-affecting transaction with no merchant gives the
learning loop nothing to attach to and is permanently uncategorisable. This is why `sa-core.json`
maps an ATM location into `merchant`, and maps a biller name into both `merchant` and `billerCode`.
Those read like smells and are not — they are this rule, correctly applied.

##### Tier 3 — present in real messages and deliberately **not** given slots

Branch name · ATM city as its own field · loyalty/points balance · **credit limit and available
credit** · **"total amount due"** · **"Executed Through" (Apple Pay / mada Pay / Atheer / app)** ·
IBAN · the bank's service phone number · promotional tails · "available" vs "outstanding" balance as
two distinct figures.

**Three of these are now known to be SAMA-mandated, and that changes nothing about the decision — but
it does change how the decision must be justified.** Available credit and total amount due are
required elements of a credit-card notification; "Executed Through" is a required element of a mada
notification. They will therefore appear reliably, not occasionally, and a rule author will be
tempted to catch them. The answer is still no, for the reason stated at the top: **SAMA governs what
the bank must send; NFR-S2/NFR-P4 govern what we choose to keep.** Declining to extract a mandated
element is data minimisation, not non-conformance — we are the recipient, not the issuer. Say this
out loud in review, because "but the regulator requires it" reads like an argument for a slot and is
not one.

Each entry is either bank-specific, or (IBAN, full credit limit, available credit) something
NFR-S2/NFR-P4 would rather we did not hold at all. **Adding a slot is a schema decision and the
default answer is no.** The bar: a field earns a slot when it changes a number the user sees or
resolves an identity — not when it merely appears, and not merely because it is mandated upstream.

##### Does the existing schema support this? Yes — the gap is validation, not structure

`MessageRule` / `FieldExtraction` already express every slot above, and the six shipping banks
already use exactly this vocabulary. `instrumentRefNetwork` / `instrumentRefType` even work through
a `${field}Network` convention that generalises to `settlementRef` for free. **No restructuring is
warranted, and `sa-core.json`'s organisation does not change.**

The taxonomy does expose one real defect, and it is a defect this codebase has already ruled
unacceptable once, in the neighbouring case:

> `rule_pack_loader.dart` `_parseExtract` validates `transform`, `maskPolicy`, `kind` and `timezone`
> — but **never the field name**. `RulePackMessageParser._extract` reads a hardcoded list of names.
> So `extract: { "merchantName": {...} }` loads cleanly, is never read, and yields nothing. A typo'd
> field name is a **silent no-op** — precisely what `field_transforms.dart` makes fatal for a typo'd
> *transform* name, for precisely the same reason.

`requiredFields` shares the gap: it is `_optionalStringList` with no vocabulary check, so a name
outside `ParsedFields.presentFieldNames` can never be satisfied. That one fails *safe* (permanent
review queue) rather than open, and today every rule uses only `["amount","occurredAt"]` — so
neither is a live bug. Both become cheap to close once the vocabulary is written down, which is what
this subsection does.

**The fix, when it is scheduled:** hold the vocabulary as a constant beside
`ParsedFields.presentFieldNames` — the satellite names (`convertedCurrency`, `feeCurrency`,
`remainingBalanceCurrency`, `<instrument>Network`, `<instrument>Type`) belong in it too — and reject
unknown names in both `extract` keys and `requiredFields` at **load time**. It can only reject packs
that are already broken.

##### What this means for the format-teaching capability (scoped by product-owner in parallel)

Not duplicating their PRD work. Three observations from the architecture side:

1. **A fixed label palette is what makes the feature buildable at all.** With Tier 1 + Tier 2 the
   palette is ~14 chips — unchanged by the SAMA re-derivation, which added four `messageType` values
   but no new extractable slot — each carrying a *type* — money · currency · datetime · masked-identifier ·
   reference · free text. Typed labels let the app reject a bad selection **at teach time** ("that
   span doesn't look like an amount") instead of at parse time, months later, inside someone's
   totals. Free-form labels make that check impossible: there is nothing to check against.
2. **It keeps PRD X18 intact rather than reopening it.** The user labels spans of *their own*
   message; the app synthesises the `FieldExtraction`. The user still never writes or sees a regex —
   and synthesis is only possible because the target field set is closed and typed.
3. **Two constraints, offered early because they are cheap now and expensive later.** (a) A taught
   rule must land in the **same `MessageRule` shape**, so provenance (NFR-A1), `requiredFields`,
   `redact` and priority all still apply — with a distinct `source` alongside `bundled` / `imported`,
   so a taught rule is visible in the audit trail and disableable without touching bundled packs.
   (b) **Tier 0 is not labelable.** `sign`, `affectsSpend` and `messageType` are not spans in the
   text, so they are a short wizard ("did money leave or arrive?"), not a highlight. Getting
   `affectsSpend` wrong on a card repayment double-counts every repayment — the one question worth
   asking out loud.

   The safety story the taxonomy makes available for free: re-run the taught rule against the message
   the user just labelled and show them the rendered transaction. If it reproduces what they
   confirmed, activate it; if not, do not.

##### Recommendation: apply forward, do not retrofit

**Do not retrofit the six-bank rule set** (`bank-aljazira` / `d360` / `nera` / `stc-bank` / `sab` /
`al-rajhi`). Reasoning:

- There is nothing to retrofit at the field level — the shipping rules already conform. The taxonomy
  was derived partly *from* them.
- The only substantive change is engine-side loader validation, which is orthogonal to rule content
  and lands separately, after the pack is device-verified.
- Pattern churn is the genuinely risky operation here. R-4 and KHA-128 are the live evidence that a
  wrong pattern loses a financial message silently. Re-touching six banks' regexes days before device
  testing, to gain documentation conformance we already have, is a bad trade.

**One carve-out, and it is zero work:** whoever reviews the in-flight dispatch should check the diff's
`extract` keys and `requiredFields` entries against the vocabulary above. A *new* name outside it is
cheap to correct before anything is persisted from it and expensive after — and nothing currently
catches it.

**The four new `messageType` values are additive and need no engine change** (§5.2), so they are
strictly forward-looking too: use them when a cheque, deposit, wallet top-up or reversal template is
first written for a bank. Do not reclassify existing rules to reach them.

##### Open questions for the human

**1. `remainingBalance` — narrowed by Table No. (1), not fully closed.** Now that Table No. (1) is
verbatim (above), it names exactly **one** "remaining" element, in exactly one category: **"Total
Remaining"**, under *Monthly Financing Deduction*, alongside "Financing Type" and "Due Installment".
That is unambiguously the loan/financing **remaining-principal** sense (PRD §3.4) — Table No. (1) has
**no "account balance-after" field in any of its 18 categories**, so that sense is not a regulator
mandate at all, just something a bank may print beyond the minimum. The third sense, a card's
**available credit**, comes from a *different* document (the Credit Card Issuance Rules, not Table
No. (1)) and was already ruled Tier 3 below — excluded, not stored.

Net effect: the regulator's own primary table treats "remaining balance" as **one thing** —
financing remaining-principal — which is the strongest evidence yet for keeping `remainingBalance`
a single slot, now with a tighter, SAMA-anchored meaning: *populate it for financing/installment
messages only; a bank that separately prints a balance-after on a plain debit notification is
printing something SAMA doesn't require, treat it as Tier 3 unless a future need justifies a slot.*
**Approved 2026-07-30** — `remainingBalance` stays single, scoped to financing/installment only.

**2. Obtain the two SAMA tables verbatim — done, 2026-07-30.** Both retrieved and reproduced in full
above via a direct fetch of `/en/table-no-1` and `/en/table-no-2`. No remaining
**[unverified detail]** markers in this subsection.

---

### ADR-008 — Merchant normalisation is a canonical-key pipeline with an explicit **alias table**; matching is tiered and never silently wrong.

**Answers A-7. Mitigates R-5. Serves US-D1..D5, AC-D2.3, AC-D2.4.**
**Amended by the KHA-98 decision (v1.3, 2026-07-29) and then by the KHA-106/KHA-107 decision
(v1.4, 2026-07-29)** — the two dated subsections at the end of this ADR, in order. **Read both:
v1.4 withdraws one clause of v1.3** (the "≥4 digits" corroboration signal) and restates the
trailing-digit step. Three things below are **superseded and annotated rather than deleted**, per this document's
house style (ADR-006 does the same with its latency table), so that a reader who finds the old
text quoted somewhere else can see that it was superseded and why: the noise-token list no longer
contains city names, the trailing-digit strip is now bounded and corroborated, and **T3 is defined
over the token *multiset*, not the token set.** Read the subsection before touching
`merchant_key.dart`, `merchant_matcher.dart`, or `CategorizationConfig`.

**Normalisation pipeline** (`merchantRaw` → `merchantKey`):
Unicode NFKC → strip bidi controls and tatweel → remove Arabic diacritics → fold Arabic letter
variants (`أإآٱ→ا`, `ة→ه`, `ى→ي`, `ؤ→و`, `ئ→ي`) → case-fold Latin to upper → ~~strip trailing
store/terminal/reference digit runs~~ → ~~strip a configurable noise-token list (`BRANCH`,
`STORE`, `FRC`, city names, terminal ids)~~ → collapse whitespace.

> ⚠️ **The two struck steps are superseded by the KHA-98 decision below.** *"City names"* was
> wrong — a city name is a proper noun and can be the *distinguishing* token of two unrelated
> businesses, which made this line the direct cause of a High-severity identity merge at
> confidence 1.00. *"Trailing digit runs"* was unbounded, which made it the cause of the same
> defect in a second shape. The corrected steps are stated normatively in the subsection.

**Matching tiers.**

| Tier | Condition | Confidence | Action |
|---|---|---|---|
| T1 | exact `merchantKey` match on a **user-created** rule | 1.00 | auto-apply |
| T2 | exact `merchantKey` match on a **seed** rule | 0.90 | auto-apply |
| T3 | ~~token-set~~ **token-multiset** Jaccard ≥ 0.80 against a known merchant (amended, KHA-100) | 0.60–0.85 | apply **only if ≥ threshold**, otherwise flag |
| T4 | normalised Damerau-Levenshtein ratio ≥ 0.90 | ≤ 0.60 | **never auto-apply** — surface as "did you mean…" in review |
| — | no match | 0.00 | Uncategorized + `needsReview` (AC-D2.4) |

`autoApplyThreshold` is **a single named constant in `CategorizationConfig`**, initial value
**0.85**, tunable without touching matching code. This is the residual of OQ-14: the *value* is
a build-phase tuning parameter to be set against the corpus in P4, not a product commitment.
The observable bar from AC-D2.3 — **match, or flag; never silently miscategorise** — is
enforced by the tier table above regardless of the value.

**Cross-script matching (the hard half of R-5).** Arabic and Latin renderings of the same
merchant cannot be reliably transliterated. We do not try. Instead: a **`MerchantAlias`** table.
From the review UI the user can link an alias to a canonical merchant in one action; rules key
on `merchantId`, not on the raw string, so one link fixes both scripts forever.

**Rule creation is user-driven only.** An automatic match never creates or mutates a rule.
Only explicit user actions do (AC-D3.2). User-sourced rules always outrank seed rules
(AC-D3.1). Scope choice ("this transaction only" / "this and future from this merchant") is
carried on the correction command, per US-D5.

#### KHA-98 decision — normalisation may only strip what cannot distinguish two businesses. **Option (b). Decided 2026-07-29.**

**Status: DECIDED. Settles KHA-98 (High), KHA-99, KHA-100 and KHA-102 in one policy, because
QA's own note is right that they are one question. Binding on the mobile-engineer's fix; it is
not a menu.**

##### The defect, in one paragraph

`MerchantKey.of('MAKKAH BAKERY')` and `MerchantKey.of('MADINAH BAKERY')` both return `'BAKERY'`,
because ADR-008 v1.0 told the pipeline to strip city names unconditionally. `merchant.merchant_key`
is `UNIQUE`, so two unrelated businesses become **one row**, whose `canonical_name` is whichever
raw string arrived first. Categorising one then auto-applies to the other at **tier T1,
confidence 1.00, `needsReview` false**. No confidence gate can catch this, because it is not a
fuzzy-match confidence problem at all: it is a **deterministic collision manufactured by
normalisation, upstream of every tier**. `autoApplyThreshold` could be set to 1.01 and the merge
would still happen. That is what makes it High and what makes it an architecture decision rather
than a tuning one. (All merchant strings in this subsection are synthetic — NFR-M3.)

##### The rule this ADR was missing: **corroboration**

ADR-008 v1.0 shipped a *list* where it should have shipped a *rule*. Lists cannot be reviewed;
you cannot tell whether the next entry someone adds is safe. Here is the rule, and it is the part
of this decision that must outlive the specific fixes below.

> **A token may be removed from a merchant string only if it is incapable, by its kind, of
> distinguishing one business from another.**
>
> Three conditions, all required:
>
> 1. **Type-level, not instance-level.** Whether a token is strippable must be decidable from the
>    token alone. `MerchantKey.of` stays a **pure, deterministic, database-free function**.
> 2. **Structural, not proper.** A strippable token names *what kind of thing* a merchant is —
>    an outlet, legal-form or terminal word (`BRANCH`, `STORE`, `FRC`, `LLC`, `فرع`). A **proper
>    noun** — a city, a district, a mall, a person — names *which* one, and is never strippable.
> 3. **Residue-safe.** Stripping must never be able to reduce two strings that differ only in a
>    proper noun, or only in a number that is part of a name, to the same key.
>
> **And the collapse bar, which is the answer to the manager's question "when is it safe to
> collapse two raw strings into one identity?":** a machine may collapse two raw merchant strings
> into one identity **only** when their difference is confined to (i) structural noise tokens of
> the kind above, (ii) a digit run corroborated as a store/terminal/reference number **by a
> structural marker word adjacent to it in the same string** (tightened by KHA-106, v1.4 —
> corroboration means evidence carried by the input, never a prior about digit counts), (iii)
> separators and whitespace, (iv) case, and (v) Arabic/Latin orthographic folding. **Every other
> collapse is a user action** — a `MerchantAlias` link — recorded in the audit trail and
> reversible. This is the same principle ADR-008 already applies to cross-script matching
> (*"Arabic and Latin renderings cannot be reliably transliterated. We do not try."*) and the
> same principle ADR-017/R-8 applies to duplicate transactions. It was simply never applied to
> normalisation itself.

##### The three options, and why (b) wins

| Option | Assessment |
|---|---|
| **(a)** Strip a city token only when another significant token survives **and** the resulting key already names a known merchant | **Rejected, and not narrowly.** Two independent defeats. **First, it fails condition 1**: "already names a known merchant" is a database lookup, so the identity function becomes stateful and *arrival-order dependent*. `PANDA RIYADH` arriving first keys as `PANDA RIYADH`; if `PANDA` is later created, `PANDA JEDDAH` keys as `PANDA` — the same chain now holds two rows, and which row a message lands in depends on history. A `UNIQUE` identity column computed by a non-deterministic function is a worse property than the defect it fixes. **Second, and decisively, it does not fix the reported defect**: the corroboration it offers is *exactly the condition under which the merge occurs*. If the user ever has a merchant keyed `BAKERY` — a shop called "Bakery" is entirely ordinary — then `MAKKAH BAKERY` and `MADINAH BAKERY` both strip, both corroborate, and both merge, at 1.00, as before. Option (a) makes the collision rarer and harder to reason about. It does not close it. |
| **(b)** **Drop city names from the noise list entirely; let the tiers handle chain branches** | **CHOSEN.** Purity preserved. The defect is closed at its root rather than gated. The cost is real and is stated below, and the *direction* of the residual error is the one AC-D2.3 explicitly asks for. |
| **(c)** Keep the list; require a "these are two different shops" split UI in P4b | **Rejected as a fix; adopted as a companion requirement.** (c) does not address the identity merge at all — it is a manual repair offered *after* the damage, and the damage is the expensive kind: `merchant_key` is `UNIQUE`, so splitting means minting a second merchant, re-attributing historical transactions by their retained `merchantRawText`, and writing an audit entry per re-attributed row. Choosing (c) alone would mean deliberately shipping a default that manufactures work of that shape. **However**, a split/unlink affordance is still required for an independent reason — see the P4b answer below — so (c)'s deliverable survives, attached to (b) rather than substituting for it. |

##### Settled answer 1 — **city tokens: DROPPED. Unconditionally.**

All twelve city entries (`RIYADH`, `JEDDAH`, `DAMMAM`, `KHOBAR`, `MAKKAH`, `MADINAH` and their
folded Arabic forms) leave `MerchantKey.noiseTokens`. The remaining list — outlet, legal-form and
terminal vocabulary — is exactly the set that satisfies condition 2, and **no proper noun may ever
be added to it**. A test must pin that: the noise list is asserted against an explicit allow-list
of structural words, so a future "helpful" addition fails CI rather than silently merging two
shops.

**What this costs, stated honestly.** A chain's branches stop auto-merging. Against the current
matcher:

| Synthetic pair | Keys after the fix | Tier reached | Outcome |
|---|---|---|---|
| `MAKKAH BAKERY` / `MADINAH BAKERY` | `MAKKAH BAKERY` / `MADINAH BAKERY` | Jaccard 1/3 = 0.33 (below the 0.80 T3 floor); DL ratio ≈ 0.79 (below the 0.90 T4 floor) | `MerchantMatch.none` → Uncategorized + `needsReview`. **The defect is closed.** |
| `PANDA RIYADH` / `PANDA JEDDAH` | `PANDA RIYADH` / `PANDA JEDDAH` | Jaccard 1/3 = 0.33 | flagged for review, not merged |
| `PANDA STORE 1234` / `Panda` | `PANDA` / `PANDA` | T1/T2 exact | **unchanged** — the pipeline's own motivating case from PRD §3.4 still works |

Note the second row is the cost: the user tags two Panda branches instead of one. Note also that
QA's report estimates that pair at Jaccard 0.5; the shipped `_jaccard` computes |A∩B|/|A∪B| =
1/3 = 0.33. Both are far below the 0.80 floor, so the conclusion is unchanged, but the correct
figure is recorded here because a future tuner will read it.

**Why this cost is the right one to pay.** The two errors are not symmetric and the asymmetry is
the whole argument:

- **Two rows that should be one** is recoverable in one user action. The `MerchantAlias` table
  already exists for exactly this, and ADR-008 already promises *"one link fixes both scripts
  forever"*. Linking `PANDA JEDDAH` to `PANDA RIYADH` is the user asserting identity — which is
  the only actor this architecture trusts to assert it.
- **One row that should be two** destroys the identity. The canonical name is wrong, the money is
  attributed to the wrong business, correcting one shop re-points the other's future messages, and
  the repair requires the forensic split described in option (c).

AC-D2.3 already chose between these: *"match, or flag as low-confidence — never silently
miscategorize, never silently merge unrelated merchants."* Flagging is named; over-merging is
forbidden. **Prefer the simpler and more conservative option, and say so explicitly: (b) is
both.** It deletes code rather than adding a lookup, and it fails toward asking the user.

##### Settled answer 2 — **trailing digits: BOUNDED and CORROBORATED (KHA-99)**

> ⚠️ **Rule 3's signal (ii) below is WITHDRAWN by the KHA-106 decision (v1.4).** Rules 1, 2 and 4
> stand; rule 3 now requires **adjacency and nothing else**, and the strip's *position* rule is
> restated in v1.4 (KHA-107). The struck text is kept, not deleted, because it was quoted into
> `merchant_key.dart` and into `CategorizationConfig` and a reader who meets it there must be able
> to see that it was superseded and why. **Read settled answers 7 and 8 before this section's
> consequence list — its last bullet is now only half true, and the case the list never showed is
> the one that produced KHA-106.**

The current step is a `while` loop with no bound, so `QAMART 100`, `QAMART 200` and
`QAMART 100 200 300` all key as `QAMART` — the KHA-98 shape in a second guise. But unlike a city
name, a digit run *does* have a recognisable reference shape, so the answer is not "drop it"; it
is "corroborate it". Normative:

1. **At most one** trailing all-digit token is removed. Two digit runs in a row are not a
   reference; they are part of a name or a garbled string, and collapsing them is a guess.
2. It is removed **only if at least one non-digit token remains** afterwards.
3. It is removed **only if corroborated as a reference** by either signal:
   - **(i) Adjacency** — the token immediately before it is a structural noise token this pipeline
     is also stripping (`STORE`, `BRANCH`, `BR`, `TERMINAL`, `TERM`, `POS`, `FRC`, `فرع`, `محل`).
     This is PRD §3.4's actual observed shape: `PANDA STORE 1234`.
   - ~~**(ii) Length** — the run is **≥ 4 digits**. Four or more digits is a till, terminal or
     reference id, not a branch number a human says out loud.~~ **WITHDRAWN by KHA-106 (v1.4):
     this signal collapses `QAMART 1000` and `QAMART 2000` onto one key at confidence 1.00, which
     condition 3 of this ADR's own corroboration rule forbids. See settled answer 7.**
4. **Leading digits keep their existing protection.** `7 ELEVEN` must survive. That asymmetry was
   already deliberate and already documented in `merchant_key.dart`; it stands.

~~The `4` is a named constant beside `autoApplyThreshold` (suggested: `referenceDigitRunMinLength`),
tunable against the corpus, with the same posture as **O-1**: the *value* is tuning, the *bar* is
not.~~ **Superseded by KHA-106 (v1.4): the constant is deleted, not retuned — the O-1 posture
cannot protect a constant whose mere existence is the defect.** Consequences on synthetic input:

- `QAMART 100` / `QAMART 200` → keys differ. Jaccard 0.33 → no T3. Damerau-Levenshtein ratio
  1 − 1/10 = **0.90**, which meets the T4 floor — so this pair surfaces as *"did you mean QAMART
  100?"*, `canAutoApply` false, `needsReview` true. **That is the ideal outcome, not a
  consolation:** the app says what it noticed and lets the person decide.
- `CAFE 1` / `CAFE 2` → keys differ; DL ratio 0.83, below the T4 floor → `none` + `needsReview`.
- `QAMART 100 200 300` → `QAMART 100 200 300` (rule 1 and rule 3 both decline).
- `PANDA STORE 1234` → `PANDA` (adjacency corroboration) — **still true in v1.4.**
  ~~`PANDA 1234` → `PANDA` (length corroboration).~~ **No longer true: KHA-106 (v1.4) withdraws
  length corroboration, so `PANDA 1234` keys as `PANDA 1234` and is flagged against `PANDA` rather
  than merged with it. That is the disclosed cost of settled answer 7.**

> **What this list should have contained, and the reason this ADR needed a v1.4.** Every bullet
> above pairs a stripped string with a *sibling that keeps its digits*, so the list reads as though
> corroboration always separates siblings. It never showed the pair where corroboration fires on
> **both** sides — `QAMART 1000` / `QAMART 2000` — which is the one case where the strip merges two
> identities. A consequences list that only shows the cases the rule handles is not a consequences
> list. When writing one, **pick the input that makes the rule fire twice.**

##### Settled answer 3 — **the all-noise fallback key is REMOVED (KHA-102)**

`MerchantKey.ofOrNull('***')` currently returns `'***'`, defeating the exact guard it exists to
be. `of()` falls back to the *folded string* when every token was stripped; a punctuation-only
string tokenises to nothing but folds to itself, so it is non-empty and `ofOrNull`'s `isEmpty`
test misses it. One rule then categorises every masked-merchant transaction across every bank —
which `ofOrNull`'s own doc comment correctly calls *"the single most damaging silent merge
available in this design"*.

**Decision: when every token is stripped, there is no key.** `of` returns the empty string,
`ofOrNull` returns null, and the transaction is `skippedNoMerchant` — identical treatment to a
transaction that carried no merchant text at all, which is what the method already promises.

**This deliberately goes further than QA's stated fix direction, and the reason matters.**
`docs/defects.md` proposes *"require the fallback key to contain at least one letter or digit"*.
That closes `'***'` and leaves `'STORE'` and `'فرع'` open — a merchant string consisting only of
structural noise would still become an identity, and two unrelated masked strings would still
collapse onto it. The general form of the argument is short and is the reason to prefer removal
over patching: **an all-noise string is by construction made only of tokens we have just declared
incapable of distinguishing two businesses, so a key built from it is by construction incapable of
distinguishing two businesses.** That is precisely the silent merge. Patching the symptom would
have left the class open.

**The cost, and why it is near-zero.** A merchant genuinely named nothing but a noise word ("Store",
"محل") gets no merchant identity, so no rule can be learned for it and its transactions are
individually categorised each time. The noise list is deliberately short and, in the code's own
words, consists only of words *"that cannot plausibly be a merchant on their own"* — and with the
city entries now gone, that claim is finally true. **Nothing is lost or hidden:** the transaction
is still written, still carries its `merchantRawText`, still appears in totals, still audits.
NFR-A7 is untouched. We decline to *identify*; we never discard.

##### Settled answer 4 — **T3 means the token MULTISET (KHA-100)**

The ambiguity is real: ADR-008 said "token-set", and `CategorizationConfig`'s tuning rationale
defends 0.85 as *"the two strings contain the same tokens and differ only in order, spacing, case,
store number or noise words"* — a **permutation** claim. The code compares Dart `Set`s, so
multiplicity is invisible and `QAFE QAFE` reaches Jaccard 1.0 against `QAFE`, auto-applying
another merchant's rule at exactly the threshold.

**Decision: T3 is defined over the token multiset, and the code moves to meet the rationale — not
the other way round.** Jaccard is computed with multiplicities, so `{QAFE, QAFE}` vs `{QAFE}` is
1/2 = 0.5, below the 0.80 floor; the pair falls through and can never auto-apply.

> **Correction recorded at implementation (2026-07-29, mobile-engineer), factual only — the
> decision above is unchanged.** This paragraph originally said the pair *"falls through to T4 and
> becomes a suggestion"*. It falls through **past** T4 as well: the Damerau-Levenshtein ratio for
> `QAFE QAFE` against `QAFE` is 1 − 5/9 ≈ **0.44**, well under the 0.90 T4 floor, so the matcher
> returns `MerchantMatch.none` and does not offer a "did you mean" either. Both outcomes are
> refusals and neither can auto-apply, so nothing about the decision or its safety argument moves —
> but a future tuner reading "it becomes a suggestion" would be surprised by the observed
> behaviour, so the executed answer is recorded here and pinned by PROBE D in
> `test/security/qa_pr27_probe_test.dart`.

Two reasons, in order of weight. **First, it is what the corroboration rule requires:** no
normalisation step in this pipeline produces or removes a repeated token, so a duplicated token is
a genuine difference between two strings, and collapsing it is a machine asserting identity on a
guess. **Second, it is the more conservative of two live options** — the alternative was to weaken
the documented rationale to match the code, which would leave a real (if narrow) auto-apply path
open *and* leave the next tuner reading a rationale that overstates the safety of 0.85. Fixing the
code makes the sentence in `CategorizationConfig` literally true, which is worth more than the
handful of lines it costs.

##### Settled answer 5 — the R-16 migration posture: **clean migration, no re-key, with a stated premise and a stated expiry**

Every fix above changes the output of `MerchantKey.of` for inputs that already have rows. On an
install holding `merchant` rows, that would require a re-key migration — and a nasty one, because
re-keying can *split* one row into two, which means re-attributing historical transactions by
their retained `merchantRawText` and writing an audit entry per re-attribution (NFR-A2). **No such
migration is written, because no such install exists.** The premise, stated explicitly so the next
reader does not have to re-derive it:

> **Premise.** No install anywhere holds a `merchant`, `merchant_alias` or `merchant_rule` row.

**The evidence, and an honest note on how strong it is.** Three facts compose:

1. Those tables were created by **schema v7**, which landed on `main` at `42db8ff` (PR #27) on
   **2026-07-29** — the same day as this decision.
2. **No build carrying schema v7 has been installed on any device.** code-reviewer's PR #20 gate
   blocks *"any build that reaches a device"* until KHA-87/88 close, and **KHA-88 is still open**
   (PR #24's merge commit: *"KHA-88 stays open for the set-valued-link schema half"*). The KHA-7
   device spike is still in Backlog, and `docs/build-plan.md` §7.3 row 5 instructs the human to
   wait for P3b-3 before running it. KHA-53 (the P10 staging release) has not started.
3. Therefore no `MerchantKey` has ever been computed outside CI.

> **This is weaker evidence than ADR-010's KHA-69 argument, and the difference must not be
> glossed.** KHA-69's premise was *structural* — the DB key is provisioned behind the app-lock
> gate, so audit rows could not exist. This premise is **procedural**: it holds because nobody has
> installed an APK yet, and it can be falsified by one person doing one ordinary thing.
> Specifically, note that a routed UI is **not** required to populate `merchant`: the categorizer
> is already bound into live ingestion (`presentation/providers/categorization_providers.dart` →
> `ingestion_providers.dart`), so a single ingested SMS on an unlocked v7 install creates merchant
> rows with no screen involved. Anyone reasoning about this from `lib/app.dart`'s routing would
> reach the wrong answer — which is the exact trap `docs/lessons.md` records ("'unreachable today'
> is a claim about *navigation*, not about code").

**Expiry condition, binding.** *This posture is void the moment any build carrying schema v7 or
later is installed on a device and unlocked.* Before relying on it again, check both:
(i) has any APK containing `lib/features/categorization/` been installed on hardware?
(ii) does `merchant` hold any row on any install? **If either answer is yes, this decision does
not authorise a clean migration** and the re-key-plus-re-attribution migration described above
becomes mandatory. Recorded as **R-16** in §8.3.

**The window is open today and closes on a human action, not on a code change.** That is the
argument for landing the mobile-engineer's fix before the P3b-3 device run, not after it.

##### Settled answer 6 — **does P4b need a "these are two different shops" affordance? YES.**

Plainly: **yes**, and choosing option (b) does not remove the need. The reasoning is not the one
KHA-98 gives (that reason — *"P4a is already creating the merged rows"* — is dissolved by (b)
together with the clean-migration posture, since no merged rows exist and none will be created).
The reason that survives is this:

> After this decision, the `MerchantAlias` link is **the only remaining operation in the entire
> product that collapses two identities into one.** It therefore carries the whole of AC-D2.3's
> "never silently merge" burden by itself. R-8's standing principle — a merge must be
> user-confirmed **and reversible**, never automatic — applies to it exactly as it applies to the
> transaction merge in ADR-017. **An irreversible identity link is the same defect as an automatic
> one, one step later.**

The minimum surface, scoped so the designer is not guessing:

1. **Where.** On **S-16 (Learned / Merchant Rules)**, or a merchant-detail sheet reached from it —
   not a new top-level screen. For a merchant that has aliases, list them with their `script` and
   `source`.
2. **The action.** *"This is a different shop"* on an alias: detaches it into its own `Merchant`
   row, re-points the transactions whose `merchantRawText` produced that alias key, and leaves the
   remaining transactions where they are.
3. **Audit.** One audit entry per re-pointed transaction, actor `user` — the same shape AC-D4.4
   already requires for a bulk historical re-apply. The split is a new event, never an erasure
   (NFR-A3).
4. **Confirmation.** A confirmation dialog, not a single tap. This is O-QA-8/KHA-90's lesson
   applied before the fact rather than after: the riskiest operation in a screen must not be
   cheaper to trigger than the safer ones beside it.

**This is a process event and it is named here so the manager can act on it.** `docs/design.md`
contains no such affordance — S-16 today is search plus `{Merchant} → {Category}` rows plus the
S-17 edit sheet. **A `/revise-design` round is therefore required before whichever P4b issue
carries this can ship.** It is additive (one action on an existing screen, one dialog), so it
should not require re-approving the whole design document — but design approval is a human gate
under `CLAUDE.md`, so **the human must approve the delta.** Raised as **H-15** in §8.1. This
amendment does not block on it, and neither should the rest of P4b.

##### What this decision does **not** change

`MerchantAlias`, the cross-script posture, tier ordering, T1/T2/T4 semantics, `canAutoApply`'s
structural refusal of T4, `minimumFuzzyMatchKeyLength`, and the value of `autoApplyThreshold`
(**still 0.85** — nothing here is a threshold-tuning change, and O-1 stands). KHA-101, KHA-103,
KHA-104 and KHA-105 are engineering defects with no architectural content and are **not** settled
here.

##### Where this must be enforced and observed

- `MerchantKey.noiseTokens` pinned against an explicit structural-word allow-list, so adding a
  proper noun fails a test rather than merging two shops.
- Regression tests, from this subsection's synthetic table verbatim: `MAKKAH BAKERY` ≠
  `MADINAH BAKERY`; `QAMART 100` ≠ `QAMART 200`; `QAMART 100 200 300` keeps all three runs;
  `PANDA STORE 1234` == `Panda`; `MerchantKey.ofOrNull('***')` and `ofOrNull('-*-')` both null;
  `MerchantKey.ofOrNull('STORE')` null; `QAFE QAFE` does not reach T3 against `QAFE`.
- The corroboration rule quoted in `merchant_key.dart`'s library comment, replacing the current
  *"a chain's branches are the chain"* defence — which is the sentence that made the defect look
  intentional to three consecutive readers.
- `CategorizationConfig`'s 0.85 rationale updated to state the multiset semantics, since that
  rationale is what the next tuner reads.

#### KHA-106 / KHA-107 decision — corroboration means **evidence in the string**, never a prior about digit counts; and the strip becomes order-insensitive. **Decided 2026-07-29.**

**Status: DECIDED. Settles KHA-106 (High) and KHA-107 (Low) in one decision, as KHA-107 asks,
because both change `MerchantKey.of` and their fixes interact — the obvious fix for one destroys
the fix for the other. Amends settled answer 2 above; nothing else in the KHA-98 decision moves.
Binding on the mobile-engineer's implementation; it is not a menu. All merchant strings here are
synthetic (NFR-M3).**

##### The defect, and it is mine

v1.3 stated a rule and then violated it three paragraphs later. Condition 3 of the corroboration
rule says stripping *"must never be able to reduce two strings that differ only in a proper noun,
**or only in a number that is part of a name**, to the same key."* Signal (ii) of settled answer 2
— strip a trailing run of ≥4 digits, no other corroboration required — does exactly that:

| Input | v1.3 key | Result |
|---|---|---|
| `QAMART 1000` | `QAMART` | one `merchant` row (`merchant_key` is `UNIQUE`), canonical name = whichever arrived first |
| `QAMART 2000` | `QAMART` | tier **T1**, confidence **1.00**, `needsReview` false |

This is the KHA-98/KHA-99 shape unchanged: a **deterministic collision manufactured by
normalisation, upstream of every tier**, which no threshold can gate. Pinned by **PROBE M2** in
`test/security/qa_pr30_probe_test.dart`. The implementation is not at fault — it is a faithful
rendering of my spec. **And this is an undisclosed consequence, not an accepted cost:** settled
answer 2's consequence list showed `PANDA 1234 → PANDA` as a benefit and never showed the sibling
pair. `PANDA RIYADH` is a documented cost because it was written down *with* its failure direction;
this was not written down at all.

##### Why no length threshold can be fixed — the general argument

This matters more than the specific choice below, because the next person to reach for a digit
heuristic needs to know it is not a tuning problem:

> A length-only signal decides strippability **from the digit run alone**, and the residue it
> leaves is **the prefix**. Therefore, for *any* threshold N, two strings that share a prefix and
> carry different qualifying runs reduce to the same key. Sibling collapse is not a bad choice of
> N — it is what a length signal **is**. Raising N to 5 or 6 only changes *which* siblings collide;
> it never stops siblings colliding.

So the only three moves available are: remove the signal, make the function impure, or accept the
collision. That is precisely the option list KHA-106 offers, and it is exhaustive.

##### The three options

| Option | Assessment |
|---|---|
| **(1)** Drop signal (ii); adjacency corroboration always required | **CHOSEN.** Purity kept, determinism kept, the collision closed at its root rather than gated. It *deletes* a branch rather than adding one, and it fails toward asking the user. Its cost — `PANDA 1234` no longer equals `PANDA` — is real, is stated below, and points in the direction AC-D2.3 names. |
| **(2)** Add a residue condition — strip only if no other **stored** key differs solely by a trailing digit run | **Rejected, on the same ground v1.3 rejected KHA-98 option (a), and the rejection is stronger here.** It fails condition 1: the identity function becomes a database lookup, so a `UNIQUE` identity column is computed by an **arrival-order-dependent** function. Worse, look at what it actually does: `QAMART 1000` arrives first, sees no sibling, and strips — so **the chain-level key `QAMART` is now owned by one numbered outlet**, and a later genuine bare `QAMART` string lands on that outlet's row at T1/1.00. The proposal moves the merge rather than removing it. It also destroys idempotence (see settled answer 8), since `of` would answer differently on Tuesday. |
| **(3)** Accept and document the 4-digit-sibling cost | **Rejected, and the distinction is the load-bearing one in this whole ADR.** `PANDA RIYADH` is documentable because its failure direction is **refusal**: two rows that should be one, repairable in a single `MerchantAlias` action. This failure direction is **silence**: one row that should be two, at confidence 1.00, discovered only when the user notices the wrong shop's money in the wrong place. **We document costs that fail toward asking; we fix costs that fail toward silence.** Documenting a violation of a rule this document calls binding would make the rule advisory, and an advisory corroboration rule is the v1.0 token list again. |

##### Settled answer 7 — **signal (ii) is WITHDRAWN. Adjacency is the only corroborator. (KHA-106)**

Normative, replacing rule 3 of settled answer 2. Rules 1, 2 and 4 stand **unchanged**:

> **Rule 3 (v1.4).** The candidate digit run is removed **only if a `referenceMarkerTokens` word is
> adjacent to it** — immediately before **or** immediately after it in the token list (the "or
> after" half is settled answer 8). There is no other corroboration signal, and in particular
> **there is no signal derived from how many digits the run contains.**

`CategorizationConfig.referenceDigitRunMinLength` is **deleted**, not raised to some safer number.
A dormant tunable is an invitation to reopen a High-severity defect by editing a config file, and
**O-1's posture — "the value is tuning, the bar is not" — cannot protect a constant whose mere
existence is the bar.** (v1.3's doc comment said lowering it to 1 would restore KHA-99. The truth
is that *every* value restores KHA-106.)

**The precise reading of condition 3 that v1.3 left implicit, and that this decision turns on.**
Adjacency corroboration still collapses `PANDA STORE 1234` and `PANDA STORE 5678` onto `PANDA`, and
that is **not** a condition-3 violation:

> Condition 3 forbids collapsing strings that differ only in a number **that is part of a name**. A
> marker word beside the run is *the string itself stating that the run is not part of the name* —
> evidence carried by the input, decidable from the token pair alone, so condition 1 (purity) is
> intact. A bare digit run makes no such statement, so a machine that strips it is **guessing which
> of the two kinds of number it is looking at**. That is the whole distinction:
> **corroboration is evidence in the string; it is never a prior about digit counts.**

**The asymmetry with the city decision, stated openly rather than left for a reader to find.** A
numbered outlet under an explicit marker merges into its chain (`PANDA STORE 1234` → `PANDA`) while
a city-named branch does not (`PANDA RIYADH` stays). The difference is not that numbers matter less
than words; it is that `STORE` **states the role of the token beside it** and `RIYADH` states
nothing about its own role. PRD §3.4 requires the first case to work. Where the marker's claim is
wrong in fact — separately-owned franchises under one chain marker — the repair is the split
affordance of settled answer 6, and the existence of that repair is what makes this line tolerable.

**Consequences on synthetic input** (multiset Jaccard uses `|A∩B| / (|A|+|B|−|A∩B|)`; DL ratio is
`1 − distance / maxLength`, both as shipped):

| Pair | v1.3 keys | **v1.4 keys** | Tier reached | Outcome |
|---|---|---|---|---|
| `QAMART 1000` / `QAMART 2000` | `QAMART` / `QAMART` — **merged at 1.00** | `QAMART 1000` / `QAMART 2000` | Jaccard 1/3 = 0.33 (no T3); DL 1 − 1/11 ≈ **0.909** ≥ 0.90 | T4 *"did you mean QAMART 1000?"*, `canAutoApply` **false**. **The defect is closed, and the app says what it noticed.** |
| `PANDA 1234` / `Panda` | `PANDA` / `PANDA` | `PANDA 1234` / `PANDA` | Jaccard 1/2 = 0.50 (no T3); DL 1 − 5/10 = 0.50 (no T4) | `MerchantMatch.none` + `needsReview`. **This is the cost of settled answer 7, and the only one.** |
| `PANDA STORE 1234` / `Panda` | `PANDA` / `PANDA` | **unchanged** | T1/T2 exact | PRD §3.4's motivating case still works |
| `QAMART 100` / `QAMART 200` | differ | **unchanged** | DL 0.90 | T4 suggestion, never auto-applied |
| `CAFE 1` / `CAFE 2` | differ | **unchanged** | none | flagged |
| `QAMART 100 200 300` | all runs kept | **unchanged** (rule 1) | — | — |
| `7 ELEVEN` | kept | **unchanged** (rule 4) | — | — |

The cost row is the same trade v1.3 already made for city names, in the same direction, for the
same reason — **two rows that should be one is one user action; one row that should be two destroys
the identity** — so the argument is not repeated here beyond the pointer.

##### Settled answer 8 — **the strip is positioned modulo noise and reads adjacency on either side (KHA-107)**

**First, a finding that changes what KHA-107 is.** Settled answer 7, on its own, makes
`MerchantKey.of` genuinely idempotent. The proof is one line and belongs in the code:

> Step 7 removes every `noiseTokens` word, and `referenceMarkerTokens ⊆ noiseTokens`. With signal
> (ii) withdrawn, marker adjacency is the **only** corroborator. Therefore **no output of `of` can
> ever contain a corroborator**, so step 6 is a no-op on a second pass and step 7 is too:
> `of(of(x)) == of(x)`.

So KHA-107's option 3 — correct the doc comment to admit an ordering dependence — would be
documenting a defect whose cause we have just removed. The invariant becomes **true**, and the doc
comment keeps its claim but must gain its *reason*, because the reason is fragile in a specific
way: **idempotence holds only because every corroborator is itself stripped later in the pipeline.**
Any future signal that survives step 7 (a length signal, a "digits following a letter" signal, a
regex on the raw string) silently breaks it again. That warning goes in the code, and a test pins
the invariant so it cannot be broken quietly.

**Second, the behaviour KHA-107 actually reports, which idempotence does not fix.**
`PANDA STORE 1234` → `PANDA` while `PANDA 1234 STORE` → `PANDA 1234`: the same three tokens in a
different order produce two keys for one shop, against PRD §3.4's promise that all renderings of one
shop reach one key. Pinned by **PROBE M1**. Decision — **fix it**, with the minimum change that does
not widen the *class* of what may be stripped:

> **Step 6 (v1.4, normative).**
> 1. The **candidate** is the last all-digit token such that **every token after it is a
>    `noiseTokens` word** — i.e. the run is trailing once structural noise is disregarded. If no
>    such token exists, nothing is stripped.
> 2. Refuse if the token immediately before the candidate is itself all-digit (rule 1, unchanged).
> 3. Refuse unless at least one non-digit token remains afterwards (rule 2, unchanged — note this
>    deliberately counts a noise token as a survivor, so `STORE 7` still yields **no key** via
>    KHA-102 rather than the junk key `7`).
> 4. Corroborate by adjacency **on either side** in the pre-strip token list: the token immediately
>    before **or** immediately after the candidate is a `referenceMarkerTokens` word.
> 5. Remove **at most one** token, ever — the candidate. Leading digits keep their protection
>    (rule 4, unchanged): `7 ELEVEN` and `7 ELEVEN STORE` both survive, because `ELEVEN` is not a
>    noise token, so `7` is never a candidate.

**Why this is not a loosening of the bar.** Every additional strip it permits is corroborated by
exactly the signal v1.3 already accepted — a structural marker beside the run. What changes is the
marker's *position*, which is an accident of how one acquirer orders its tokens and carries no
information about the number. Order-insensitivity is simply what "all renderings of one shop → one
key" means when two renderings are permutations of each other.

**Rejected alternatives, and the first one matters because it is the obvious move:**

- **Swap steps 6 and 7 (noise-strip first).** **Rejected.** After step 7 the marker is *gone*, and
  adjacency is now the only corroborator — so `PANDA STORE 1234` would key as `PANDA 1234` and
  PRD §3.4's motivating case breaks. KHA-107 was right that the two decisions interact; the
  interaction runs in the opposite direction from the one the issue suggested. **The digit strip
  must run before the noise strip precisely because it consumes the noise tokens as evidence.**
- **Iterate to a fixed point.** **Rejected.** Unnecessary once settled answer 7 lands (one pass is
  already a fixed point), and a loop over a mutating token list is exactly how v1.0's unbounded
  `while` became KHA-99. A rule that needs iteration to be stable is a rule whose single-pass
  meaning nobody can state.
- **Doc comment only.** **Rejected as insufficient**, per the finding above. Recorded honestly: this
  is the *most* conservative option in the "strip less" sense, and it is the one thing in this
  amendment a human could reasonably overrule. **The KHA-106 half is not optional; the KHA-107 half
  is a correctness improvement riding in the same migration window** because doing it later costs a
  re-key migration that doing it now does not.

**Worked examples** (synthetic; this table is the regression suite):

| Input | v1.3 key | **v1.4 key** | Why |
|---|---|---|---|
| `PANDA STORE 1234` | `PANDA` | `PANDA` | marker before the run |
| `PANDA 1234 STORE` | `PANDA 1234` | **`PANDA`** | run is trailing modulo noise; marker after it. **KHA-107 closed** |
| `PANDA 1234` | `PANDA` | **`PANDA 1234`** | no marker anywhere. **The disclosed cost** |
| `QAMART 1000` / `QAMART 2000` | `QAMART` / `QAMART` | **`QAMART 1000` / `QAMART 2000`** | **KHA-106 closed** |
| `QAMART 1000 STORE` / `QAMART 2000 STORE` | `QAMART 1000` / `QAMART 2000` | **both `QAMART`** | marker after the run ⇒ accepted signal-(i) collapse, identical to v1.3's `QAMART STORE 1000` / `QAMART STORE 2000`. **Disclosed, not hidden: reordering does change this shape** |
| `QAMART 100 200 300` | unchanged | unchanged | rule 1 |
| `7 ELEVEN` / `7 ELEVEN STORE` | `7 ELEVEN` | `7 ELEVEN` | `ELEVEN` is not noise ⇒ `7` is never a candidate |
| `STORE 7` | no key | no key | strips, then all-noise ⇒ KHA-102 |
| `1234 STORE` | `1234` | **no key** | candidate strips, remainder is all-noise ⇒ KHA-102. More conservative, and correct |
| `***` / `-*-` | no key | no key | KHA-102, untouched |

##### Settled answer 9 — **this document is docs-only; the decision needs code, and the window is R-16's**

Stated plainly because the manager needs a scheduling answer:

- **This amendment requires no P4a-2 PR of its own.** It is a documentation change to
  `docs/architecture.md` and lands as such.
- **The decision does require a code change** — both halves alter `MerchantKey.of`'s output, so both
  sit inside **R-16**. The binding condition is not a phase label: **it must land before any APK
  containing `lib/features/categorization/` is installed on hardware.** After that, R-16's premise
  is void and this becomes a re-key migration that can split one merchant row into two, with
  per-transaction re-attribution and one audit entry per row.
- **It may ride with the first P4b PR** provided that PR lands before the device run. If P4b's first
  PR is not the next thing to merge — or if the now-cleared KHA-7 device spike makes it plausible
  that someone sideloads a product APK in the same session — then a **small dedicated PR touching
  only `merchant_key.dart`, `categorization_config.dart` and their tests** is the right call. It is
  a change of a few dozen lines against a migration of a few hundred. (KHA-7 is a throwaway harness
  and does not itself populate `merchant`; R-16's expiry is written against *any* schema-v7 build
  reaching a device, which is the real trigger and is a human action, not a code change.)

**What the mobile-engineer must change** (no Dart is written here — this is the specification):

1. `merchant_key.dart`, `_stripCorroboratedTrailingDigitRun` — delete the length branch; implement
   candidate selection and two-sided adjacency exactly as settled answer 8 states; rules 1, 2 and 4
   unchanged. The method's name is now slightly wrong ("trailing" is trailing-modulo-noise); rename
   or document, your call.
2. `merchant_key.dart` doc comments — restate rule 3; update the library-header pipeline diagram's
   step 6 line; **keep** the idempotence claim on `of` and add its reason (*every corroborator is
   itself a noise token, so no output can be corroborated*) plus the explicit warning that any
   corroborator surviving step 7 breaks it.
3. `categorization_config.dart` — **delete** `referenceDigitRunMinLength` and its doc comment
   outright. Do not leave it unused.
4. Tests, all from the worked-example table verbatim, plus: `of(of(x)) == of(x)` asserted over the
   whole synthetic corpus (table-driven, not one case); `CanonicalText.fold` idempotence pinned,
   since the proof above rests on it; `PANDA 1234` ≠ `PANDA` pinned **as a cost**, so a future
   "improvement" that reintroduces length stripping fails CI rather than passing quietly.
5. `test/security/qa_pr30_probe_test.dart` — PROBE M1 and M2 flip from defect-documenting to
   invariant-asserting, per the convention the PR #27 probes already set.
6. **No migration.** R-16's posture covers this change on the same premise and the same expiry.

##### What this decision does **not** change

Everything else in the KHA-98 decision: the corroboration rule itself, the city-token drop, the
all-noise no-key rule (KHA-102), multiset T3 (KHA-100), `autoApplyThreshold` **0.85** (O-1 stands —
nothing here is threshold tuning), the split/unlink affordance and **H-15**, tier semantics,
`minimumFuzzyMatchKeyLength`, and rules 1, 2 and 4 of the digit strip. R-16's premise and expiry are
unchanged — this amendment **adds to what the window must carry, it does not extend the window.**

##### Noticed while deciding this, and deliberately **not** settled

`1234 STORE 5678` keys as `1234` — an all-digit key — in both v1.3 and v1.4, so this decision
neither creates nor removes it. But an all-digit key is a weak identity that two different banks'
reference-only strings could share, which is KHA-102's class in a shape KHA-102 did not cover. **A
recommendation, not a decision:** QA should probe it against the P4 synthetic corpus. If the shape
occurs, the likely answer is *"a key must retain at least one non-digit token"* — and that is
another change to `of`'s output, so it belongs **inside** R-16's window, i.e. decided before the
device run rather than after it.

---

### ADR-009 — FX: prefer what the SMS states; never invent a rate; never sum across currencies.

**Answers A-9. Serves US-B9, AC-B9.1/2/3, NFR-A5.**

Base currency defaults to **SAR**, user-configurable.

| Case | Handling | `fxRateSource` |
|---|---|---|
| SMS gives foreign amount **and** the converted base amount (PRD §3.4 shows this) | Store both; derive `impliedRate = base / foreign` as a `Rational`, display to 8 dp | `sms_implied` |
| SMS states a rate explicitly | Store the stated rate | `sms_stated` |
| Foreign currency, **no** conversion in the SMS | **Do not invent a rate.** Store the native amount, set `conversionPending = true`, **exclude from base-currency totals**, and show an explicit line "N transactions not converted" so AC-C1.3 / AC-E3.2 reconciliation is visibly incomplete rather than silently wrong. User may enter a rate, or accept the most recent known rate for the pair with a visible marker | `user` / `carried_forward` |

There is no network rate lookup — by ADR-001 there cannot be, and by NFR-R4 there should not be.

**FX / international fees** (PRD §3.4 notes a fee riding alongside the amount) are recorded as
a **linked child transaction** (`parentTransactionId`, `transactionType = fee`), not as a field.
This is stronger than the PRD's "own field" note and satisfies its intent: the fee is
independently categorisable, independently visible, and — critically for NFR-A6 — every total
still traces to a set of transaction records with nothing hidden inside another row.

---

### ADR-010 — The audit trail is append-only by **DAO shape + SQL triggers + a hash chain**, and we state the enforcement boundary honestly.

**Answers A-10. Serves NFR-A1, NFR-A2, NFR-A3, US-F5.**

**Mechanism, in three layers.**

1. **API shape.** `AuditLogDao` exposes exactly two operations: `append(entry)` and
   `queryFor(entityType, entityId)`. There is no update or delete method to call.
2. **Database triggers.** Enforced against *any* code path, present or future:
   ```sql
   CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_entry
     BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
   CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_entry
     BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
   ```
   (Erase-all deletes the database file wholesale rather than rows, so it is unaffected — that
   is intentional, per AC-F3.1.)
3. **Tamper evidence.** Each entry carries `prevHash` and
   `entryHash = HMAC-SHA256(auditChainKey, prevHash || canonicalJson(entry))`, forming a chain.
   `auditChainKey` is a separate Keystore-held key. Settings exposes a **"Verify history
   integrity"** action that walks the chain.

**The enforcement boundary — stated plainly, because over-claiming here would be dishonest.**

> Append-only is enforced **against the application and against any non-root actor on the
> device**. It is **tamper-evident, not tamper-proof, against the device owner.** The owner of a
> rooted device can extract the database key and the chain key from the Keystore/process memory
> and rewrite both the history and its chain. NFR-A2/A3 as written — "history entries must not
> be editable or deletable from the UI" — is fully met. A stronger claim (a genuinely immutable
> ledger) would require an append-only remote witness, which contradicts ADR-001 and CON-1, and
> would be pointless: this is one person auditing their own records, and they are not their own
> adversary.

**What gets an audit entry.** Every create, update, delete, restore, merge, categorisation, and
rule application on: `transaction`, `instrument`, `bank`, `merchant_rule`, `category`, `budget`,
plus `backup` and `erase` lifecycle events. Each entry records `actor`
(`user` | `system_rule` | `parser` | `importer`), `actorDetail` (e.g. the `ruleId` that fired —
satisfying AC-F5.2's "which rule applied"), timestamp, and a `fieldChanges` list of
`{field, from, to}`.

#### KHA-69 decision — the chain fix is forward-only, and that is accepted. **Option (a). Decided 2026-07-29.**

**Status: DECIDED. Recorded by mobile-engineer during P3b-2, at the manager's instruction.
Supersedes the "pick one" list in KHA-69's description.**

**The defect.** `AuditLogDao.append` on `main@c6879f3` hashed the **untruncated** `changedAt`,
while Drift persists a `DateTimeColumn` as whole Unix seconds. Every entry written with a real
`DateTime.now()` therefore hashed a value that could never be read back, and
`verifyChainIntegrity()` — which recomputes from the stored, truncated value — reported
**tampering on intact history**. P3a fixed `append` (`_toWholeSecondsUtc`, applied once, before
both the hash and the insert) but changed neither `verifyChainIntegrity()` nor `_canonicalize`.
The fix is therefore **forward-only**: an entry written by any pre-P3a build would still
recompute to a different hash, and because the chain is sequential the first bad entry poisons
every entry after it — so the user would be told their *entire* history had been tampered with,
permanently, on an otherwise fully patched install.

**The decision: option (a) — confirm no install carrying pre-P3a audit rows exists, and state it
here so the next person does not have to re-derive it.** No migration is written. Options (b) (a
v3→v4 re-chaining migration) and (c) (a genesis marker) are **not** taken.

**The evidence, which is now conclusive rather than merely plausible.** Three facts compose:

1. **The DB Master Key is provisioned *behind* the app-lock gate** (ADR-005). No unlock means no
   database, which means no `audit_entry` table, which means no audit rows. This is structural,
   not a matter of usage patterns.
2. **KHA-75 established that the app lock had never once succeeded on real hardware.** A correct
   fingerprint *and* a correct device PIN both reported "auth failed", caused by a Keystore
   channel byte-encoding defect. Nine merged PRs of product code had never been executed
   end-to-end by a human.
3. **The first successful real-device unlock in this app's history was on build `56e9cbaa`**,
   confirmed 2026-07-28/29 — and that build **already contains P3a's timestamp fix.**

Therefore every audit row that has ever existed on a real device was written by fixed code.
There is nothing to re-chain.

**Why (b) was rejected on principle as well as on cost.** A re-chaining migration would rewrite
an append-only history — the precise operation the trail exists to make impossible — in order to
repair rows that do not exist. Even done honestly (recording the re-chaining in the trail
itself, as KHA-69 required), it would establish that this app is willing to rewrite history
under some circumstances, which is a materially weaker property than never doing so. Paying that
for a null set is a bad trade. **(c) remains the correct remedy if the evidence above is ever
falsified** — it degrades verification to *"verified from &lt;date&gt;"* rather than "tampered", and
it does not rewrite anything.

**The standing condition this decision carries, and it is binding:** the **P10 staging APK must
go onto a clean install.** If any device is ever found holding audit rows written before
`56e9cbaa`, this decision is void and option (c) becomes the remedy. The window in which (a) is
free closes the moment someone unlocks a pre-P3a build.

**Where this is enforced and observed:**
- The reasoning is repeated in the schema **v5** migration branch in
  `lib/data/db/app_database.dart`, next to the code that would have carried a re-chaining step.
- `test/data/db/schema_v5_migration_test.dart` pins the two consequences a test *can* pin: an
  ordinary upgrade leaves `verifyChainIntegrity()` true, and the migration writes **no**
  `audit_entry` row of its own. A test cannot prove "no device holds such a row"; it can prove
  that we did not quietly take option (b), and it can act as the alarm if the assumption breaks.

---

### ADR-011 — Erase-all reaches every copy it can reach, and says out loud where it cannot.

**Answers A-12. Serves US-F3, AC-F3.1/2/3, NFR-P5, NFR-P7.**

**Sequence.**
1. Explicit confirmation (type-to-confirm), with copy naming exactly what is destroyed
   (AC-F3.3: cancel destroys nothing).
2. **Overwrite the backup blob with a zero-length tombstone via the persisted SAF URI, then
   delete it.** Overwriting first matters: the user's sync app propagates the *empty* file, so
   the cloud-side current version becomes empty even if the provider ignores deletions.
3. Close the Drift connection; delete the database file, `-wal`, `-shm`, and any temp/journal.
4. Delete all `flutter_secure_storage` entries (wrapped keys, salts, watermark cache).
5. Delete the Keystore aliases (`massrofy.dbkek`, `massrofy.auditchain`, `massrofy.contenthmac`).
6. Cancel all WorkManager work and clear its state; clear the diagnostic ring buffer; delete any
   export files inside app-private storage.
7. Release persisted SAF URI permissions.
8. Re-run first-run setup with a **freshly generated** DB Master Key.

**The honest limit, which the confirmation screen must state.** Once a third-party sync app has
uploaded the blob, the cloud provider's **trash and version history** may retain earlier,
non-empty versions. We cannot reach those. Rotating our key does not help, because those copies
are encrypted under the *old* key which the user still holds. Therefore the erase-all flow must
instruct the user to also empty their cloud provider's trash and purge version history. **A
hard delete that leaves an encrypted cloud copy is not a hard delete, and we say so rather than
pretend otherwise.**

Note also: manual exports (US-F2) are written to a user-chosen SAF location outside our reach by
design. Erase-all warns about them; it does not claim to delete them.

---

### ADR-012 — Backup: an E2E-encrypted envelope, keyed by an **app-generated recovery secret**, written through SAF. No escrow.

**Answers A-4 and the storage half of A-1. Closes R-2. Serves US-I1/I2/I3, AC-I1.1/I2.1/I3.1, NFR-S7.**

**Key derivation.**

- On enabling backup, the app generates **128 bits of CSPRNG entropy** and renders it as a
  **12-word BIP-39 English mnemonic** (the "Recovery Phrase"). The user must transcribe it and
  confirm by re-entering three randomly chosen words before backup activates.
  - *Why generated, not user-chosen:* this removes the weak-passphrase half of R-2 by
    construction. A user-chosen passphrase mode is offered as a secondary option for users who
    insist, and in that mode the KDF is Argon2id with a warning.
- `BackupRootKey = HKDF-SHA256(entropy, salt = backupSalt, info = "massrofy/backup/v1")` for the
  generated-phrase mode; `Argon2id(passphrase, backupSalt, m=64MiB, t=3, p=2)` for the
  passphrase mode. **The envelope header records which KDF was used**, so restore never has to
  guess.
- `backupSalt` is 32 random bytes, stored **in cleartext inside the envelope header**. It must
  be — otherwise a new device cannot derive the key. A salt is not a secret.
- Per-backup `DataKey = 32 random bytes`, wrapped by `BackupRootKey` (AES-256-GCM) and placed in
  the header. Payload encrypted with **XChaCha20-Poly1305** (or AES-256-GCM with a random 96-bit
  nonce per chunk), chunked so large payloads stream without loading whole into memory.
- The Recovery Phrase may **optionally** be cached in the Android Keystore on the current device
  so routine incremental backups don't re-prompt. **That cache is a convenience only.** The
  authoritative copy is the user's transcription. **Nothing device-bound is required to restore.**

**Restore on a new device (the AC-I3.1 path, end to end).**
Install APK → first run → "Restore from backup" → pick the blob via SAF (from wherever the sync
app placed it) → app reads the **cleartext header** (version, KDF, salt, wrapped data key,
content digest) → prompts for the 12-word Recovery Phrase → derives `BackupRootKey` → unwraps
`DataKey` → decrypts and verifies the digest → imports transactions, instruments, banks,
merchants, rules, categories, budgets, and audit history → generates a **fresh local** DB Master
Key and Keystore KEK for the new device. **No original device. No Keystore. No account. No
network.**

**Trigger policy (AC-I1.1 — "without requiring a manual export step").** A debounced background
write: on any ledger mutation, schedule a backup work request with a 5-minute debounce; also a
daily periodic write; also on demand. Because the write is local file I/O to a SAF URI, it is
fast and offline. The UI reports **"last written locally at HH:MM"** and states honestly that
Massrofy cannot confirm the user's sync app has uploaded it (a direct consequence of ADR-001).

**No escrow, deliberately.** Any recovery mechanism that works without the user's secret means
someone other than the user can decrypt, which is precisely what AC-I2.1 forbids. **If the
Recovery Phrase is lost, the backup is permanently unreadable.** This is the correct trade for a
banking-domain app and it must be stated in the UI, not buried.

**Relationship to exports (NFR-S7).** Manual exports (US-F2) remain **plain and unencrypted** by
the human's decision (OQ-13), with the AC-F2.3 warning as a required control. Backups are
**always** encrypted. These are two different features and must never share a code path — a
shared serialiser with an `encrypt: bool` flag is exactly how an unencrypted backup ships by
accident. Separate use-cases, separate outputs.

---

### ADR-013 — Redaction happens at the **ingestion boundary**, enforced by a type.

**Answers A-13. Serves NFR-S2, NFR-C2, NFR-P1.**
**Rewritten at v1.1 to resolve KHA-57.** v1.0's "what gets redacted" table was a *sketch* — it
described the intent in one line per pattern and left the shape of the pattern to the
implementer. KHA-54 proved that was not good enough: three under-redaction defects all fitted
inside v1.0's literal wording. §"The normative patterns" below replaces the sketch. **It is
deliberately over-specified.** Redaction is the one place in this app where a plausible-looking
implementation and a correct one are indistinguishable by eye, and where the failure is silent,
permanent, and exactly what NFR-S2/NFR-C2 exist to prevent.

**Where.** In `SmsSanitizer`, between "read from the SMS content provider" and "write anything
to the database". **Raw, unredacted SMS text is never persisted, not even briefly.**

**Order of the pipeline, normative** (P2 implements this and it must not drift):

```
raw body ─► SmsSanitizer.sanitize(raw, extraRedactPatterns: pack.redact[])  ADR-013  ◄── this ADR
             └─► SanitizedSmsText          ─────────────► persisted as RawMessage.sanitizedBody
                    └─► SmsTextNormalizer.normalize(...)  ADR-007 step 1
                           ├─► MessageParser
                           └─► ContentHmac (dedup key, ADR-017 D1)
```

Two consequences that are decisions, not accidents, and are ratified here:

1. **Sanitisation runs on the raw body, before normalisation.** So `SmsSanitizer` may **not**
   assume the normaliser has already folded digit families, stripped bidi controls, or collapsed
   whitespace. Every one of those is a way a PAN escapes. The sanitizer does its own folding, for
   matching purposes only.
2. **What is persisted is the sanitised *raw* text, not the normalised text.** AC-B1.2 requires
   the user to verify a parse against something that looks like what their bank actually sent.

**How it is enforced (the mechanism, not the intention).** The raw-message DAO's insert method
accepts **only** a `SanitizedSmsText` value type. `SanitizedSmsText` has a private constructor
and can be produced **only** by `SmsSanitizer`. A developer cannot write an unsanitised `String`
into the message table because the code will not compile.

---

#### The normative patterns (v1.1 — this is the ratified wording; cite it by name)

**§13.1 — What counts as a digit.** Any of: ASCII `0-9`; Arabic-Indic `U+0660–U+0669`; Extended
(Persian) Arabic-Indic `U+06F0–U+06F9`. Dart's `\d` is ASCII-only, so **`\d` is a defect in this
file** and CI review should treat it as one. Luhn is computed on digit *values*, so a PAN written
in Arabic-Indic numerals checksums identically to the same PAN in ASCII and cannot evade the rule
by changing script.

**§13.2 — Ignorable characters.** Before matching, and **for matching purposes only**, remove:
bidi controls `U+200E`, `U+200F`, `U+061C`, `U+202A–U+202E`, `U+2066–U+2069`, and the soft hyphen
`U+00AD`. *Why this is load-bearing:* an Arabic RTL bank template routinely wraps a Latin-script
number in directional marks. One `U+200F` sitting between two groups of a card number defeats the
grouped-PAN rule below entirely, and — per §13.1's ordering note — the sanitizer cannot rely on
the normaliser to have removed it, because the normaliser runs afterwards. The characters are
removed from the *matching view* of the text; the persisted string retains its original
formatting outside the replaced spans.

**§13.3 — Group separators.** Exactly **one** character from: SPACE `U+0020`, NBSP `U+00A0`,
NARROW NBSP `U+202F`, HYPHEN-MINUS `U+002D`, EN DASH `U+2013`.

Deliberately **excluded**, with reasons, so nobody re-adds them on a hunch:

| Excluded | Why |
|---|---|
| The full stop `.` | It is the decimal and thousands separator in amounts. Including it trades a real risk of destroying a transaction amount (which sends a genuine transaction to the review queue) for coverage of a PAN format issuers do not use |
| Newline | A line break in a bank SMS separates *fields*. Joining across one fuses two unrelated numbers, and Luhn is only a 1-in-10 filter, so the fused result would sometimes validate |
| A **run** of two or more separators | Same reason: it lets the pattern swallow two numbers that merely sit near each other in a sentence |

**§13.4 — PAN detection (the rule KHA-57 ratifies, plus the defect it must also close).**

A *digit-group sequence* is `g1 sep g2 sep … sep gn`, where each `gi` is a maximal run of **two or
more** digits (§13.1) and each `sep` is a single separator (§13.3). `n = 1` is the ordinary
contiguous case.

For each maximal digit-group sequence in the message:

1. Enumerate the contiguous windows `gi..gj`, **longest first, then leftmost**.
2. Concatenate the window's digits (separators discarded).
3. If the concatenation is **13–19 digits long AND Luhn-valid** (ISO/IEC 7812-1): replace the
   whole matched span *including its internal separators* with `****<last4>`, set
   `panRedacted = true`, and resume scanning after the window.
4. Otherwise try the next window. If no window matches, the text is left exactly as it was.

> **The "longest window, then backtrack" scan is the part that must not be simplified away, and
> it is not what shipped.** PR #2 tests only the *maximal* sequence. That leaves a real PAN in
> cleartext whenever a bank template puts another grouped number immediately after the card
> number: `purchase 4111 1111 1111 1111 45` matches as one 18-digit sequence, fails Luhn, and is
> returned **untouched — PAN and all — with `panRedacted = false`.** That is the identical
> failure mode as KHA-54 gap 3, and the KHA-54 corpus misses it only because every fixture
> happens to place a non-digit token (`SAR`) immediately after the PAN. **Closing this is a
> condition of ratifying the widening** (see §8.1 H-14).

**Why Luhn stays, rather than "redact every long number".** A blunt rule would destroy
transaction reference numbers, which are ADR-017 D2's reliable duplicate key. That is a
correctness regression bought for no security gain. Luhn is what makes this rule *precise*
instead of merely aggressive, and it is the reason the window may be widened safely.

**Why the window is 13–19 and not 12–19.** 12-digit Maestro PANs are **out of scope, explicitly**.
Lowering the floor to 12 materially increases collisions with reference numbers and account
suffixes. The wider context matters here: by CON-3 and NFR-S2 the messages we actually expect
carry a *masked* last-4, so a full PAN in a bank's own SMS is already anomalous. **This whole rule
is a backstop.** A backstop should be calibrated for precision against the numbers that
legitimately appear, not for maximum recall against one that should never appear at all.

**§13.5 — IBAN detection.** Same ignorable-character and separator handling as §13.2/§13.3.

- **MUST:** `SA` (case-insensitive) followed by 22 digits, **tolerating single group separators
  between groups.** Replace with `SA**…<last4>`. *This closes a defect of exactly the KHA-54 gap-3
  class that KHA-54's fix did not touch:* the conventional print form of a Saudi IBAN is
  `SA03 8000 0000 6080 1016 7519`, and a contiguous-only `SA[digits]{22}` pattern does not match
  it, so the grouped form currently survives in full (see §8.1 H-14).
- **SHOULD (follow-up, not blocking):** generalise to `[A-Za-z]{2}[digits]{2}[A-Za-z0-9]{11,30}`
  gated on the **ISO 7064 mod-97-10 check digit** — the IBAN analogue of Luhn, and precise for the
  same reason. This picks up a foreign counterparty IBAN on an outbound international transfer,
  which is third-party PII we have no reason to retain (NFR-P1). Deferred only because it is
  additional surface on an open PR, not because it is doubtful. Tracked as **O-6**.

**§13.6 — Secret-adjacency sweep (CVV / PIN / OTP / passwords).**

Ratified as implemented in PR #2, with two **corrections to v1.0's wording**:

- v1.0 said "digits (3–8)". **The upper bound is withdrawn.** A 9-digit code is still a secret; an
  upper bound is an under-redaction bug wearing a specificity costume. The rule is **every digit
  run of 3 or more digits, no upper bound.**
- v1.0 said "preceded by", implying one direction and the nearest run. **Both are withdrawn.** The
  rule is **every** qualifying run within the window, in **either** direction. KHA-54 gaps 1 and 2
  were both caused by "the nearest run, in one direction".

Normative window: within **12 words** of a secret keyword, with a hard ceiling of **120
characters**, measured over the text strictly between the keyword and the run. Word-counting is
the primary bound and the character count is only a ceiling — measuring in characters alone is
precisely what let `"Your verification code, valid for 5 minutes, is 903212"` redact nothing.
Replacement is `[REDACTED]` (the whole run; the last 4 are **not** retained — unlike a PAN, no
part of a secret has downstream value).

Keyword set, ratified: `CVV`, `CVC`, `PIN`, `OTP`, `one-time password` / `one time password`,
`verification code`, `access code`, `رمز التحقق`, `رمز الدخول`, `رمز التفعيل`, `رمز`,
`الرقم السري`, `كلمة المرور`. Case-insensitive. **Adding a synonym is a data change and needs no
ADR amendment; removing one does.**

**§13.7 — Per-bank `redact[]` from the rule pack (ADR-007).** Applied **last**, after §13.4–§13.6.
Replace the named `(?<secret>…)` group if present, otherwise the whole match, with `[REDACTED]`.
The generic passes are the fallback for any sender whose pack declares no `redact[]`; a per-bank
pattern is never a *substitute* for the generic path, and a change that weakens the generic path
"because the rule pack covers it" should be rejected.

**§13.8 — Messages classified `intent: ignore, messageType: otp`.** Body never persisted at all
(NFR-P4, §4.2 `RawMessage` retention rules). Unchanged from v1.0.

---

#### Over-redaction is the ratified failure mode — and it has a floor

The asymmetry is the whole argument and it is worth stating once, precisely, so that every future
tuning decision resolves the same way:

> A destroyed amount produces a message that fails to parse, lands in the review queue (US-A4),
> and is **visible to the user and recoverable in one tap**. A surviving live PAN or one-time code
> is **invisible and permanent**. These are not symmetric errors, so the thresholds must not be
> tuned symmetrically. **When in doubt, redact.** This is the same reasoning ADR-017 uses to bias
> toward flagging over auto-removal, and the same banking-domain default that runs through this
> whole document.

**But "when in doubt, redact" is a bias, not a licence.** Three bounds keep it honest, and all
three are testable:

1. Luhn (§13.4) and mod-97 (§13.5) mean the identifier rules fire on numbers that are
   *structurally* card/account numbers, not on long numbers generally.
2. The 12-word / 120-character window (§13.6) means a keyword near the start of a message cannot
   cause the whole message to be destroyed. There is a required regression test for exactly this:
   a purchase amount far from an OTP keyword **must survive**.
3. The secret sweep only fires in a message that contains a secret keyword at all — and such a
   message is almost always `intent: ignore`, whose body is discarded anyway. The realistic
   over-redaction blast radius is a transaction message that mentions a code, which is precisely
   the case where a secret would otherwise be persisted.

#### Testing obligations (binding on engineers and QA)

- **Assert exact output, never `contains('[REDACTED]')`.** That assertion shape is what let the
  original KHA-54 leak pass green: `"Your OTP for account [REDACTED] is 567890"` satisfies it
  while publishing a live code. Every redaction test pins the whole expected string **and**
  asserts that no 3-digit window of the secret survives anywhere in the output.
- **Every new redaction test must be confirmed to fail against the pre-fix implementation.** A
  test that was green before the fix is not a regression test.
- Required fixtures, in addition to the existing KHA-54 corpus: a grouped PAN followed
  immediately by another grouped number (§13.4's backtracking case); a grouped SA IBAN (§13.5); a
  PAN with a bidi mark between groups (§13.2); a PAN separated by NBSP; a grouped date and a
  grouped reference number that must **survive** (precision, not just recall).

#### What this buys us against the compliance requirements

**NFR-C2 satisfaction.** We do not attempt to *secure* cardholder data — we **avoid handling it**,
which is what NFR-C2 asks for. A full PAN or any sensitive authentication datum is destroyed at
the boundary and never reaches storage, logs, exports, or backups. Massrofy is not in PCI-DSS
scope (it is not a merchant, processor, or service provider and never transmits cardholder
data), but the design adopts the posture regardless because the PRD asks for it.

**Masked identifiers (NFR-S2) in the data model.** Instruments store `maskedIdentifier`
(e.g. `****4821`, `SA**…7712`) and a `refKey` for matching that is derived from *the masked form
we received*, never from a full number — because the SMS never gives us one and we would refuse
it if it did. There is no column anywhere in the schema capable of holding a full PAN, a CVV, or
a PIN.

---

### ADR-014 — App-switcher obscuring without shipping a bypass.

**Answers A-15. Serves NFR-S8, AC-F1.3.**

**Context.** The naive answer is a permanent `FLAG_SECURE`, which also blocks all screenshots
and screen recording — breaking QA (P9 evidence) and the designer's review loop. But NFR-S8 asks
for the *app-switcher snapshot* to be obscured, not for screenshots to be banned.

**Decision — three complementary measures.**

1. `Activity.setRecentsScreenshotEnabled(false)` on API 33+ — the precise, supported API for
   exactly this requirement.
2. Below API 33, set `FLAG_SECURE` in `onPause()` and clear it in `onResume()`, so the recents
   snapshot is blanked while foreground screenshots still work.
3. Belt and braces at the Flutter layer: on `AppLifecycleState.inactive`, render an opaque
   branded scrim over the whole app before the system captures its snapshot; remove on `resumed`.
   This covers the versions where the `FLAG_SECURE` toggle timing is not guaranteed.

**QA escape hatch, with no shipped bypass.** A `--dart-define=MASSROFY_DISABLE_PRIVACY_OVERLAY=true`
flag exists, and the code path that reads it is wrapped in `if (!kReleaseMode)`, so the Dart
compiler tree-shakes it out of the release binary entirely. **There is no runtime toggle in a
release build.** CI asserts this with a test that fails if the overlay can be disabled under
`kReleaseMode`. QA takes foreground screenshots normally; only switcher-snapshot capture needs
the debug build.

---

### ADR-015 — Diagnostics: a local, redaction-safe ring buffer the user deliberately shares. No telemetry.

**Answers A-14. Mitigates R-10. Serves NFR-S4, NFR-S6.**

- A bounded in-app **structured event ring buffer** (last 2,000 events) stored inside the
  encrypted database. Events carry ids, enums, counts, and durations — **never** free text from
  an SMS, a merchant name, or an amount.
- Crash capture: `FlutterError.onError` + `PlatformDispatcher.instance.onError` + a native
  `Thread.setDefaultUncaughtExceptionHandler`, all writing **stack traces only** (no captured
  values) into the same buffer. No Crashlytics, no Sentry, no network — and by ADR-001, none is
  even possible.
- **`SafeLogger`** is the only permitted logging entry point. It accepts a `LogSafe` marker type,
  not arbitrary `String`. `toString()` on `Money`, `Transaction`, `RawMessage`, and `Instrument`
  is overridden to emit `Money(<redacted>)`, `Transaction(id=…)` — so even an accidental
  interpolation cannot leak a value. CI greps for `print(` and `debugPrint(` outside the logger
  and fails the build.
- **Settings → Diagnostics** shows the buffer, plus a **parser-health panel**: parsed / unparsed
  / ignored counts per bank per day, and top failing rule ids. This is genuinely actionable for
  R-4 without exposing a single character of message content.
- **"Share diagnostics"** produces a file the user can read in full before sending. Nothing
  leaves the device without an explicit user action on a reviewable artefact.

`production-support` works from that shared file plus the user's own description. That is the
honest cost of the correct privacy posture, and we accept it (R-10).

---

### ADR-016 — Statement import: **CSV in v1, PDF descoped to v1.1** (recommendation for the human).

**Answers A-11. Mitigates R-6. Serves Epic H.**

**Assessment.** On-device PDF text extraction in Flutter is possible but the risk is not in the
library — it is in the inputs. Saudi bank statement PDFs are frequently password-protected
(national ID or card digits), often image-only scans, and vary in layout per bank and per
statement period. Image-only PDFs would require OCR, which is explicitly out of scope (X9). With
no network (ADR-001) there is no server-side extraction fallback. The realistic outcome of
forcing PDF into v1 is an unreliable feature that erodes trust in the numbers, which is the one
thing this product cannot afford.

**Recommendation.** Ship **CSV as the must-have for v1**; treat PDF as **v1.1**.

**Architecture either way.** Define a `StatementSource` port:
`Stream<StatementLine> parse(SanitizedFile)`, with `CsvStatementSource` implemented now. The
reconciliation engine consumes `StatementLine`, not files, so `PdfStatementSource` can be added
later **without touching reconciliation, matching, or the learning loop.** No redesign is
implied by deferring it.

**Reconciliation invariants** (AC-H1.1, AC-H2.1): every statement line ends in exactly one of
`matched` / `added` / `unmatched_flagged`. Counts must sum to the line count. Nothing is silently
dropped. Reconciliation-added transactions carry `provenance = statement` and pass through the
identical categorisation and learning path as SMS-derived ones (AC-H3.1) — there is one
categorisation use-case and three provenances, never three pipelines.

**This is a recommendation, not a unilateral descope** — build-plan §7.3 item 3 puts it to the
human. See §8.

---

### ADR-017 — Duplicate detection: suppress only exact duplicates; **flag, never auto-remove**, everything else.

**Answers A-8. Mitigates R-8. Serves US-A5, AC-A5.1/2/3.**

Three tiers, applied in order:

| Tier | Key | Action |
|---|---|---|
| **D1 — exact** | `smsProviderId` UNIQUE (re-scan idempotency, AC-A3.3) **and** `contentHmac = HMAC-SHA256(k, scheme‖normalisedBody‖normalisedSender)` UNIQUE (carrier retry, AC-A5.1) — **no delivery timestamp; see the KHA-137 subsection below** | **Suppress silently**, but write a diagnostic event recording the suppression. Storing an HMAC rather than the text keeps the dedup index non-reversible. |
| **D2 — reference number** | same `referenceNumber` + same instrument (PRD §3.4 confirms transfers carry these) | Treat as the same transaction. If it enriches an existing record, **merge — and write an audit entry recording the merge.** Never a silent destruction. |
| **D3 — heuristic** | same instrument + same amount + same currency + \|Δt\| ≤ 15 min, and (merchant equal **or** one message is an authorisation-type and the other a posting-type) | **Flag as a possible duplicate for user confirmation. Never auto-remove.** Both remain in the list and in totals until the user decides. |

**The bias is explicit and deliberate.** AC-A5.2 (auth vs posting alerts) and AC-A5.3 (two
genuine identical purchases the same day) pull in opposite directions, and only one of the two
failure modes is recoverable: an inflated total is visible and fixable, a silently deleted real
transaction is invisible and unfixable. **We bias hard toward flagging.** Banking default:
prefer the auditable, recoverable error.

#### KHA-137 decision — **D1's content hash drops `receivedAt` entirely.** Decided 2026-07-30.

> **STATUS: APPROVED (2026-07-30).** The human approved the fix and explicitly accepted the
> disclosed same-minute residual (two genuinely separate purchases at the same merchant, same
> amount, within the same in-body minute, would collide and the second would need manual entry —
> judged unavoidable and rare). Scoped to this subsection, per the house style established by
> v1.1–v1.6: the document's own `APPROVED` line above stays as it is, because
> flipping the whole architecture to `DRAFT` would block every unrelated in-flight phase for one
> decision. The rest of ADR-017 is unchanged and remains in force.

**What is broken.** `ContentHmac.compute` folds `smsTimestampUtc` — the SMS's `receivedAt`,
at **millisecond** precision — into the digest. A carrier redelivery arrives at a *different
instant by definition*, so it produces a different digest, so `_withDedupGuard`'s
`findByContentHmac` misses, so a second transaction is written. The `smsProviderId` key does not
catch it either, because a redelivery is a *new* provider row. **D1 has two keys and, for the one
case it was built for, neither fires.** QA reproduced this on a device: a real total went from
−312.40 SAR to −624.80 SAR. `content_hmac.dart`'s own doc comment names carrier redelivery as
"the exact case D1 exists for" — the file argues correctly for the normalised body and then
defeats itself in the next field.

**Why the test suite passed anyway** (worth one line, because it is the reusable lesson): the
AC-A5.1 test builds its redelivery with `receivedAt: first.receivedAt` and varies only the
provider id — it holds fixed the one variable a real redelivery does not control. A test that
cannot fail is not coverage.

**The decision.** The digest is a function of **the message text and its sender, and nothing
else**:

> `contentHmac = HMAC-SHA256(k, "massrofy/content-hmac/v2" ‖ normalisedBody ‖ normalisedSender)`,
> `\x00`-separated as today.

**Why this does not weaken AC-A5.3.** Three facts, checked in the code rather than reasoned from
the ACs:

1. **Genuinely separate purchases already differ in the body.** Every transaction rule in
   `sa-core.json` lists `occurredAt` in `requiredFields`, and every template's regex captures a
   date-time **to the minute** *from the message text*. The existing AC-A5.3 test is itself the
   proof: it separates its two purchases by in-body time (`09:00` / `09:40`) and never depends on
   `receivedAt`.
2. **AC-A5.2's flag path is not the content hash.** Possible-duplicate flagging is
   `DuplicatePolicy.decide` — D2 (reference number + instrument) and D3 (instrument + amount +
   currency + 15-minute window + merchant/auth-posting), over **parsed fields**, returning
   `acceptAndFlag`. It never consults `contentHmac`. Collapsing D1's key therefore cannot move
   work from "flag" to "silently drop" through that route.
3. So the timestamp component was never what protected AC-A5.3. The **body** was. Removing it
   costs AC-A5.3 nothing and gives AC-A5.1 the guarantee it was always supposed to have.

**The residual, stated plainly rather than buried.** Two genuinely separate purchases, same card,
same merchant, same amount, **in the same minute**, produce byte-identical SMS. D1 will now
suppress the second one. This is **irreducible from the message**: nothing in the text
distinguishes the two, and the only external discriminator is the delivery instant — the very
field a redelivery also changes. In that one case AC-A5.1 and AC-A5.3 are formally contradictory
and we resolve toward AC-A5.1, because carrier redelivery is common and same-minute duplicate
spend is rare. The suppression is **not invisible** (`_withDedupGuard` writes the
`duplicate_suppressed` diagnostic, ADR-015) and the recovery is **US-B4 manual entry**.

**Options rejected.**

| Option | Assessment |
|---|---|
| **Coarse-bucket the timestamp** (same day, same hour) | **Rejected, and it fails on its own terms.** Every bucket has a boundary, so a redelivery that straddles one silently reproduces KHA-137 — *intermittently*, which is worse than a clean rule because it is unreproducible in the field. And it does not buy what it is for: byte-identical bodies imply the same in-body minute, so both genuine purchases land in the **same** bucket regardless. It keeps the failure mode and not the benefit. |
| **Keep the timestamp out of the hash but suppress only if the stored row's `receivedAt` is within a window `W`** | **Rejected, by the same arithmetic.** The pair AC-A5.3 wants separated is co-located in time *by construction* (same in-body minute ⇒ deliveries seconds apart), so every `W` ≥ 1 minute suppresses them too; and every finite `W` lets a store-and-forward redelivery through. The window discriminates nothing, and it adds a tunable no evidence can tune. |
| **Flag rather than suppress on a D1 hash hit** (raised because ADR-017 biases toward flagging) | **Rejected.** It writes two transactions and asks the user, which is exactly what AC-A5.1 forbids — *"exactly one transaction exists"*. It would put a confirmation prompt in front of the user for the **common** case in order to serve the rare one. ADR-017's flag bias governs the *ambiguous* tiers; D1 is the tier defined as unambiguous. |

**Normative — what the implementation must do.**

**(A) The new signature.** `smsTimestampUtc` is **removed from the parameter list**, not merely
ignored — an unused parameter is an invitation to re-add it:

```dart
static String compute({
  required List<int> key,
  required String normalizedBody,
  required String sender,
});
// material = ['massrofy/content-hmac/v2', normalizedBody,
//             SmsTextNormalizer.normalize(sender).toLowerCase()].join('\x00')
```

The scheme tag goes **first** so the digest is self-describing and a future third revision has to
change it deliberately rather than collide by accident. The **sender is canonicalised the same
way the body is** — `SmsTextNormalizer.normalize`, then lower-cased — because rule-pack
`senderPatterns` already compile with `caseSensitive: false`, so the parser treats `D360` and
`d360` as one bank while the digest treats them as two messages. That is the same class of defect
(delivery noise defeating dedup) and it is free to close **now**, while digests are being
invalidated anyway; closing it later would cost a second invalidation. `ingestion_pipeline.dart`
is the only caller.

**(B) The key-derivation label does not change.** It stays `massrofy/dedup-content-hmac/v1`. That
label separates *keys by protocol domain* (ADR-017 B5 / KHA-21); it is not a message-format
version, and bumping it would rotate a Keystore-derived subkey for no security reason.

**(C) Forward-only. No backfill, no migration, no schema change — DB stays at version 7.** Every
already-stored digest becomes stale. A backfill would be **partial by construction**:
content-free noise rows (`insertIgnoredNoContent`) retain no body to recompute from, and NFR-P4
is why. The exposure is bounded to messages ingested *before* the update whose redelivery arrives
*after* it — hours, not weeks. `content_hmac` stays a plain `TEXT UNIQUE` with no format
assumption, and a v1 digest can never equal a v2 digest, so the two coexist without false
suppression. Same posture as v1.2 (KHA-69) and v1.6.

**(D) ADR-006 KHA-133 item (F) — the `sms_provider_id` pre-check in `_withDedupGuard` — must
land in the same PR. Non-negotiable.** (G).1 of that subsection states the rule already: anything
that shifts the `content_hmac` of stored messages converts a re-scan's benign duplicates into
`failedWithError` stalls, and "then (F) must land in the same PR". **This change shifts every
stored digest, so it makes that hazard live rather than latent** — the first historical-import
resume or bank-scoped re-scan over pre-fix messages would miss on `content_hmac`, hit the
`sms_provider_id` `UNIQUE` constraint, throw, set `advancingIsSafe = false` and call
`pauseImport()`. Shipping the hash change without (F) trades a doubling bug for a stalled
pipeline.

**(E) Regression tests, at minimum.** (i) AC-A5.1 with the redelivery given a **different**
`receivedAt` — this is the test that must fail before the fix; (ii) the existing AC-A5.3 and
AC-A5.2 tests unchanged and still green; (iii) sender case/whitespace variation hashing equal;
(iv) a re-scan of a pre-fix row (stale v1 digest, same provider id) counted as
`suppressedAsExactDuplicate` rather than `failedWithError`, which is (D)'s test.

**(F) Doc comments that assert the old formula must be corrected in the same PR**, or the next
reader re-derives the bug: `content_hmac.dart` (library comment and `compute`),
`raw_message_table.dart` (`contentHmac` column), `domain_separated_key.dart:10`, and
`ingestion_pipeline.dart`'s `_withDedupGuard` comment.

---

### ADR-018 — Background ingestion is **suspended while the app is locked.** NFR-R1 is an unlocked-window commitment.

**Added v1.1. Resolves KHA-56. Amends ADR-005 (upheld unchanged) and ADR-006 (latency table
replaced). Touches NFR-R1, NFR-S1, NFR-S3, NFR-A7, AC-A1.4, AC-F1.2, and risk R-1.**

**The conflict, stated exactly.** ADR-005 makes the app lock cryptographic: the DB Master Key is
unwrapped only through a Keystore key created with `setUserAuthenticationRequired(true)`, so
failing or skipping authentication means the database *physically cannot be opened*. ADR-006
assumes a background worker can read SMS and write transactions while the user is away. **Both
cannot be true at once, and v1.0 never noticed**, because ADR-006 was written from the ingestion
side and ADR-005 from the security side and neither names the other.

As implemented, the key is **time-bound with a 5-second authentication validity window**
(ADR-005 implementation note). A background isolate woken by an SMS broadcast has no user
present and no recent authentication, so it cannot unwrap the key — not sometimes, not usually,
**never**, unless a human happened to authenticate within the previous five seconds. Since the
lock grace timer defaults to 0 s, *the app is locked from the moment the user leaves it*. The
locked case is therefore not an edge case; **it is the normal case.**

mobile-engineer implemented `runBackgroundIngestion()` as a documented no-op that does not
advance the watermark, so nothing is lost, and escalated rather than deciding. That was the
right call and this ADR ratifies it.

**Options considered.**

| Option | Assessment |
|---|---|
| **(a) A locked run is a no-op. The watermark does not advance; the messages stay in the SMS provider; the post-unlock sweep picks up everything since the watermark.** (What PR #2 shipped) | Zero security cost. Zero new stores, keys, or code paths. Correctness fully preserved (NFR-A7, AC-A1.4 — the message *is* there when the user next opens the app, which is what that criterion actually asks for). Cost: near-real-time ingestion does not happen while locked. **Chosen — see the four arguments below.** |
| (b) A second Keystore key with `setUserAuthenticationRequired(false)`, protecting a small encrypted **"ingest inbox"**. The background worker parses into the inbox; on unlock the inbox drains into the ledger | The only option that genuinely delivers near-real-time ingestion while locked. **Rejected** — it buys no durability, buys latency no one can observe, and punctures the single strongest claim this architecture makes. Full reasoning below |
| (c) A plaintext staging file or queue | **Rejected outright.** Contradicts NFR-S1 in the plainest possible way. Recorded only because it is the obvious shortcut and someone will suggest it again |
| (d) Weaken the lock itself — drop `setUserAuthenticationRequired(true)` on `massrofy.dbkek`, or stretch the 5-second validity window to minutes or hours so the worker can slip in | **Rejected.** This deletes ADR-005 and downgrades AC-F1.2 from a cryptographic guarantee to a navigational one. We would be trading the app's headline security property for background convenience — the exact inversion of the banking-domain default |
| (e) Lean on ADR-006's Layer-3 foreground service to keep the process, and the in-memory key, resident | **Rejected as a solution, because it is not one.** ADR-005 zeroes the in-memory key on lock. Process residency does not survive that. A foreground service that is running while the app is locked is burning battery to hold a key it no longer has |

**Why (b) loses, in four arguments. This is the substance of the decision.**

1. **It buys no durability — only latency.** The SMS content provider is already a durable,
   OS-managed store of exactly these messages, and ADR-006 deliberately made it the queue (that
   is precisely why the receiver carries no content). An ingest inbox would be a **second copy of
   the same financial data, in a weaker container, to avoid re-reading a store that never went
   away.** Nothing is protected against loss that is not already protected.
2. **The latency it buys has no observer.** NFR-R1 exists so that the user "opens the app and
   trusts the numbers" (PRD §1). **While the app is locked, the user is not looking at it.** The
   requirement that genuinely matters is *"by the time the first screen renders after unlock,
   everything has been ingested and the total is right"* — and option (a) satisfies that, because
   the post-unlock sweep runs the identical pipeline over a handful of messages in milliseconds.
   Option (b) spends a real security concession on a number nobody reads.
3. **It punctures the one claim this architecture is proudest of.** §6.8 says a lost or stolen
   **unlocked** phone is mitigated *because the lock is cryptographic*. An auth-free inbox holds
   the most recent transactions — amounts, merchants, masked instrument identifiers, timestamps —
   readable by anyone who can run code as this app on a device that is OS-unlocked but
   Massrofy-locked. Narrow, yes. But it turns "nothing is readable" into "the most recent ones
   are readable", and that is a sentence the transparency screen (US-F4, NFR-P6) would then have
   to say out loud. **A security property you have to add a footnote to is a materially weaker
   property.**
4. **It does not even move the audit boundary forward.** The audit hash-chain key
   (`massrofy.auditchain`) is itself auth-gated, so an inbox write can carry no audit entry and
   no chain link. Entries would still be minted at drain time. So (b) delivers no earlier
   auditability, and it *adds*: a second store for erase-all to reach (ADR-011), a second thing
   to decide about in backup (ADR-012), a second key lifecycle, and a permanent second answer to
   "where does sensitive data live" (§4.3).

**Banking-domain default, applied explicitly:** prefer the more secure and more auditable option,
and do not create a second copy of financial data in a weaker container to buy latency the user
cannot perceive. That default and the engineering analysis point the same way here, which is the
comfortable case.

**Decision.**

1. **`runBackgroundIngestion()` is a no-op when the database cannot be opened. This is the
   design, not a stub.** It MUST NOT advance the watermark, and it MUST report success to
   WorkManager rather than failure — retrying would burn the backoff budget on a condition only a
   human unlocking the phone can clear. The code comment in
   `lib/features/ingestion/background_entrypoint.dart` should be updated from "raising this as an
   ADR gap" to citing ADR-018.
2. **It MUST emit a diagnostic event** (`ingest.skipped.locked`, counts only, ADR-015) so
   Settings → Diagnostics → parser health can show how often the locked path fires. This is what
   turns an invisible behaviour into an observable one, and it is the evidence the human will
   need if H-13 is ever revisited.
3. **Unlock MUST run a sweep as part of the unlock transition** — not lazily after the home
   screen has already painted. The home screen MUST show an explicit "updating" state until the
   post-unlock sweep completes and MUST NOT render a stale month total as though it were final.
   *A wrong number shown confidently for 800 ms is worse than a spinner shown honestly for 800
   ms*, and for this product — whose entire success criterion is "the user trusts the numbers" —
   that is not a small point. **This is a new requirement on the presentation phase and on the
   designer's loading states (D-8).**
4. **The lock grace default stays 0 seconds.** While unlocked — foreground, or backgrounded
   inside a user-configured grace window — the in-memory key is live and ADR-006 Layer 1 works
   exactly as specified, in 1–3 s. Do not widen the default grace to buy latency; that is option
   (d) in disguise.
5. **Optional, opt-in "arrival nudge" — default OFF, and it is a compensating control, not
   compliance with NFR-R1.** A locked-state wake MAY post a **content-free** local notification
   ("A new bank message is waiting — unlock to record it"). It MUST match the sender against the
   **bundled** rule pack's `senderPatterns` only (a Flutter asset, readable with no database), so
   it never fires for personal SMS; imported packs live in the encrypted DB and are therefore
   unavailable while locked, which MUST be stated rather than worked around. It MUST retain
   nothing (NFR-P4 — a momentary classification step), MUST contain no amount, merchant, or
   instrument identifier, and MUST use `VISIBILITY_SECRET` so a lock-screen preview leaks
   nothing. **This is the only way to recover the *spirit* of NFR-R1 while locked at zero
   security cost — because it moves a notification, not data.** Scoped to the notifications phase
   (P6/P7), not to P2. Put to the human as **H-13**.
6. **ADR-006 Layer 3 is re-scoped, not removed.** Its remaining value is keeping the *wake
   signal* alive on hostile OEMs so the periodic sweep is not suppressed — which matters mostly
   for the user who keeps the app open. **It cannot deliver near-real-time ingestion while
   locked, because it cannot open the database either.** It stays off by default, and it MUST NOT
   be made default-on on the strength of NFR-R1. See the revision to H-6.

**What NFR-R1 actually commits to now. This table supersedes ADR-006's.**

| App state | SMS-to-visible |
|---|---|
| Foreground, unlocked | **< 1 s** |
| Backgrounded but still inside the lock grace window (key in memory), broadcast delivered | **1–3 s** — but note the grace default is 0 s, so this row is empty unless the user opts in |
| **Locked — the default state whenever the user is not in the app** | **Not ingested until unlock.** Visible within **~1 s of the unlock completing**, via the mandatory post-unlock sweep (decision 3). Nothing is lost: the watermark has not moved |
| Locked, *and* the broadcast was suppressed by an OEM battery manager or the restricted bucket | **Identical to the row above.** Suppression is irrelevant while locked — the post-unlock sweep is unconditional and watermark-driven. R-1 has, in the locked case, stopped mattering |
| Force-stopped by the user | Until next app open (Android suppresses all delivery to force-stopped apps; no mitigation exists) |
| Layer 3 enabled | **No change to any row above.** It buys process residency, not key access |

> **Stated plainly, because the PRD deserves a straight answer.** NFR-R1 / OQ-16 asks for
> "single-digit seconds from SMS arrival to appearing in-app, not merely by the time the app is
> next opened." **As shipped, that holds only while the app is unlocked. While locked — which is
> most of the time — the commitment is "single-digit seconds from unlock, with nothing lost and
> nothing silently reordered."** That is a genuine reduction against the PRD's wording and it is
> put to the human as **H-13** rather than quietly reinterpreted. What we are *not* willing to do
> is buy the original wording with a second, weaker copy of the user's financial history.
>
> Note also what does **not** change: **AC-A1.4** — *"given a new SMS arrives while the app is not
> in the foreground, when the user next opens the app, then that transaction is already
> present"* — is fully satisfied, and NFR-A7 (never silently discard) is untouched. The reduction
> is confined to latency, and only to latency observed by nobody.

**Consequences.**

- *Good:* ADR-005's guarantee survives intact and §6.8's threat table needs no footnote. AC-F1.2
  ("no transaction data, totals, or card identifiers are visible") remains cryptographic and now
  extends, without qualification, to data that arrived *while* locked.
- *Good:* no second store, no second key, no second thing for ADR-011 erase-all and ADR-012
  backup to reason about. The simplest possible resolution is also the most secure one.
- *Bad / accepted:* the P0 spike KHA-7's original question is now largely moot for the locked
  case, and NFR-R1's headline number is smaller than the PRD implies. Both are stated rather than
  absorbed.
- *Bad / accepted:* a user who never opens the app for a week has no ingestion for a week. That is
  also true of every other design that respects ADR-005, and their data is intact and complete
  the moment they do open it.
- **Revisit trigger:** if the diagnostics from decision 2 show the locked path firing constantly
  *and* the user reports the post-unlock wait as perceptible, the next thing to try is decision 5
  (the nudge), then a shorter grace *offered* to the user — **not** option (b).

---

## 3. Module structure and boundaries

There are no services and no network calls, so "service boundaries" here means **module
boundaries and the dependency rule between them.**

```
lib/
  core/                     no dependencies on features; pure and unit-testable
    money/                  Money, ExchangeRate, MoneyConverter, numeral_normalizer   [ADR-002]
    crypto/                 KeyManager, envelope crypto, HMAC, Argon2id/HKDF facades  [ADR-004, ADR-012]
    logging/                SafeLogger, LogSafe, diagnostic ring buffer               [ADR-015]
    result/                 Result<T, AppFailure>, sealed failure taxonomy            [§7.1]
    time/                   Clock, Asia/Riyadh period boundaries, tz handling         [§7.4]
    text/                   Unicode/Arabic normalisation (shared: parser + merchants) [ADR-007, ADR-008]
    config/                 AppConfig, CategorizationConfig (autoApplyThreshold)      [ADR-008]

  domain/                   entities, value objects, repository INTERFACES, use-cases
                            depends on core only; knows nothing about Drift or Android

  data/
    db/                     Drift schema, migrations, SQLCipher wiring                [ADR-003]
    dao/                    one DAO per aggregate; AuditLogDao is append-only         [ADR-010]
    secure/                 platform channel → Android Keystore, BiometricPrompt      [ADR-004, ADR-005]
    sms/                    SMS content-provider reader + watermark                   [ADR-006]
    files/                  SAF document/tree access (backup, export, import)         [ADR-011, ADR-012]

  features/                 each depends on domain; NEVER on another feature's internals
    ingestion/              wake handling, watermark sweep, sanitizer, dispatcher     [ADR-006, ADR-013]
    parsing/                rule-pack model, loader, matcher, field extractors        [ADR-007]
    ledger/                 banks, instruments, transactions, audit writes            [§4]
    categorization/         categories, merchants, aliases, rules, confidence         [ADR-008]
    reporting/              period aggregation over Money; no persisted derived totals [§7.5]
    budgets/                budget model, progress, alert dedup                       [§4]
    statements/             CSV source, reconciliation engine                         [ADR-016]
    backup/                 envelope format, encrypt/decrypt, SAF target, restore     [ADR-012]
    security/               app lock, privacy overlay, erase-all orchestration        [ADR-005, ADR-011, ADR-014]

  presentation/             screens, widgets, Riverpod providers, l10n (ar/en, RTL)

android/app/src/main/kotlin/…/
  SmsReceiver.kt            wake-only broadcast receiver                              [ADR-006]
  BootReceiver.kt           re-arm periodic work after reboot                         [ADR-006]
  IngestWorker.kt           WorkManager → background FlutterEngine                    [ADR-006]
  ForegroundIngestService.kt opt-in Layer-3 service                                   [ADR-006]
  KeystoreChannel.kt        Keystore KEK wrap/unwrap, BiometricPrompt CryptoObject    [ADR-004]
  PrivacyPlugin.kt          setRecentsScreenshotEnabled / FLAG_SECURE toggle          [ADR-014]
```

**Dependency rule (enforced in CI by an import-boundary lint).**
`presentation → features → domain ← data`. `core` is a leaf. **`domain` imports nothing from
`data`, `features`, or `presentation`.** Features communicate only through domain ports —
`ingestion` never imports `categorization` internals; it emits a domain event that
`categorization` consumes.

**State management: Riverpod 2.** Chosen over Bloc for DI plus async state in a single-developer
codebase: less boilerplate per screen, `AsyncValue` maps cleanly onto the loading/empty/error
states the designer must cover (D-8), and provider overriding makes widget tests cheap. The
mobile-engineer agent's brief already sanctions Riverpod or Bloc; this ADR fixes the choice so
two features don't diverge.

**Data flow, end to end:**

```
SMS arrives
   │  [Kotlin] SmsReceiver — wake only, carries no content            ADR-006
   ▼
WorkManager expedited job ──► background FlutterEngine (Dart entrypoint)
   │
   ├─ app LOCKED? ──► no-op. Watermark unchanged, diagnostic event only. ADR-018
   │                  (the messages wait in the SMS provider; the post-unlock
   │                   sweep runs this identical pipeline and loses nothing)
   ▼
ingestion: read content://sms/inbox WHERE date > watermark            ADR-006
   ▼
SmsSanitizer ── redact PAN/CVV/PIN → SanitizedSmsText                 ADR-013
   ▼
parsing: resolve bank → match rule → extract fields                   ADR-007
   ├─ no financial sender ────────────► discard, retain nothing       NFR-P4
   ├─ intent:ignore ──────────────────► counter row only, no body     NFR-P4
   ├─ no rule / missing required ─────► review queue + sanitised text US-A4
   ▼
dedup (D1 suppress / D2 merge+audit / D3 flag)                        ADR-017
   ▼
ledger: upsert bank → instrument → transaction   ┐ single DB txn,
        + audit entry                            ├ advances the
        + advance watermark                      ┘ watermark atomically
   ▼
categorization: merchant key → tiered match → category + confidence   ADR-008
   ▼
Drift stream ──► Riverpod ──► UI updates (no polling)
   │
   └─► budgets: evaluate thresholds → local notification (deduped)
   └─► backup: debounced encrypted write to SAF URI                   ADR-012
```

---

## 4. Data model

Concrete enough to implement against; not full DDL. Money columns follow ADR-002's
`*_amount TEXT` / `*_currency TEXT` / `*_minor INTEGER` triple. All tables live inside the
SQLCipher-encrypted database (ADR-003), so **every column below is encrypted at rest**.

### 4.1 Entity relationships

```
Bank 1───N Instrument ────┐
                          │ 1
                          │
                          N
                     Transaction ──N──1 Category
                        │  │  │
                        │  │  └──N──0..1 Merchant ──1──N MerchantAlias
                        │  │                    └──1──0..1 MerchantRule ──N──1 Category
                        │  └──0..1 RawMessage
                        └──1──N AuditEntry
                        └──0..N Transaction (children: fees)   via parentTransactionId
                        └──0..1 InternalTransferLink

Instrument 0..1───0..1 Instrument      (card → settlement account, US-B14)
Budget N───0..1 Category
Budget 1───N BudgetAlertLog
StatementImport 1───N StatementLine ──0..1 Transaction
RulePack 1───N (referenced by Transaction.rulePackId / ruleId)
```

### 4.2 Entities

**`Bank`** — US-B12, AC-B12.1/B12.3
`id` · `canonicalKey` (stable, from the rule pack) · `displayNameAr` · `displayNameEn` ·
`aliases[]` · `source` (`rule_pack` | `user`) · `createdAt` · `firstSeenMessageId`
> AC-B12.3 (Arabic name in one message, an abbreviation in another must resolve to **one** bank)
> is satisfied by resolving on `canonicalKey` from the rule pack's `senderPatterns` and
> `aliases`, never on the display string.

**`Instrument`** — US-B2/B3/B13/B14/B15
`id` · `bankId` FK · `kind` (`account` | `card`) · `maskedIdentifier` (e.g. `****4821`) ·
`refKey` (normalised match key derived from the **masked** form — ADR-013) · `network`
(`visa` | `mada` | `mastercard` | null) · `cardType` (`credit` | `debit` | `prepaid` | null) ·
`friendlyName` (user, US-B3) · `currencyCode` · **`settlementAccountId`** FK → `Instrument`,
nullable (US-B14) · `linkSource` (`sms_repayment` | `user` | null) · `linkObservedAt` ·
`isArchived` · `createdAt` · `firstSeenMessageId`
> AC-B13.1/2: `kind` comes from the matched rule, not from a guess.
> AC-B14.1: a card-repayment message names both the card and the debiting account; that is the
> only automatic source of `settlementAccountId`.
> AC-B14.3: null means **shown as unlinked**, never inferred.
> AC-B3.2: matching is on `refKey`, so renaming never spawns a duplicate instrument.

**`Transaction`** — Epic B, the core record
`id` · `instrumentId` FK **nullable** (explicit-unknown per AC-B1.3) · `occurredAt` (UTC) ·
`occurredAtOffset` · `timeSource` (`sms_explicit` | `sms_local_assumed` | `received_at_fallback`) ·
`direction` (`debit` | `credit`) · `transactionType` (`purchase`, `refund`, `withdrawal`,
`transfer_out`, `transfer_in`, `salary_income`, `bill_payment`, `card_repayment`, `fee`,
`installment`, `adjustment`, `unknown`) · **`affectsSpend`** bool ·
`amount_{amount,currency,minor}` · `baseAmount_{amount,currency,minor}` nullable ·
`fxRate` TEXT nullable · `fxRateDate` · `fxRateSource` · `conversionPending` bool ·
`merchantRawText` nullable · `merchantId` FK nullable · `counterpartyName` ·
`counterpartyBankName` · `referenceNumber` nullable · `remainingBalance_*` nullable ·
`categoryId` FK · `categorySource` (`user` | `rule` | `default` | `none`) ·
`categoryConfidence` REAL · `needsReview` bool · `reviewReason` ·
**`provenance`** (`sms` | `manual` | `statement`) · `sourceMessageId` FK nullable ·
`rulePackId` · `rulePackVersion` · `ruleId` · `parentTransactionId` FK nullable ·
`internalTransferGroupId` nullable · `isDeleted` bool · `deletedAt` · `isExcluded` bool ·
`createdAt` · `updatedAt`
> `categoryConfidence` is `REAL` — this is **not money**, so a float is correct here.
> `affectsSpend = false` for `transfer_in`/`transfer_out` confirmed internal, `salary_income`,
> and `card_repayment` (US-B10/B11) — repayment is settlement of spend already counted, not new
> spend, and double-counting it is the single easiest way to make every total wrong.
> `isDeleted` implements soft delete (US-B8); erase-all is the only hard delete (AC-B8.3).
> Refunds (US-B7) are `direction = credit` and reduce period spend, never increase it.

**`RawMessage`** — AC-B1.2, US-A4, NFR-A1, NFR-P4
`id` · `smsProviderId` UNIQUE nullable · `sender` · `receivedAt` ·
`sanitizedBody` TEXT **nullable** · `contentHmac` UNIQUE · `bankId` nullable ·
`classification` (`financial_parsed` | `financial_unparsed` | `ignored_otp` |
`ignored_marketing` | `ignored_info`) · `panRedacted` bool · `dismissedAsNotTransaction` bool ·
`createdAt`
> **Retention rules (NFR-P4, and they are precise on purpose):**
> - Sender matches **no** financial sender → **no row at all.** Nothing retained.
> - Financial sender + `intent: ignore` → row **with `sanitizedBody = NULL`**. Bank,
>   classification, and timestamp only, for the parser-health panel. No content.
> - Financial sender + parsed or unparsed → row **with** `sanitizedBody` (redacted), because
>   AC-B1.2 requires the user to be able to verify the parse and AC-A4.1 requires the raw text
>   in the review queue.
> - **Clarification added v1.5 (KHA-127/128), a boundary and not a relaxation:** the first bullet
>   forbids retaining a *message*. It does **not** forbid a **content-free, sender-free aggregate
>   count**. `{discardedNonFinancialSender: 214}` may be surfaced in the UI and logged as an
>   ADR-015 event; `{sender: "…", at: …}` may not. Rule of thumb: if it could tell you *who* texted
>   the user or *what they said*, it is retention and it is forbidden. **The count is required, not
>   merely permitted** — see ADR-007's KHA-127/128 subsection, item (D).

**`Merchant`** / **`MerchantAlias`** — ADR-008, R-5
`Merchant`: `id` · `canonicalName` · `merchantKey` UNIQUE · `createdAt`
`MerchantAlias`: `id` · `merchantId` FK · `aliasKey` · `script` (`arabic` | `latin` | `mixed`) ·
`source` (`user` | `observed`) · `createdAt`

**`MerchantRule`** — Epic D
`id` · `merchantId` FK · `categoryId` FK · `matchType` (`exact_key` | `token_set` |
`manual_alias`) · `source` (`user` | `seed`) · `isEnabled` · `appliedCount` · `createdAt` ·
`updatedAt`
> `source = user` always outranks `source = seed` (AC-D3.1/D3.2). Rules are created and updated
> **only** by explicit user action, never by an automatic match.

**`Category`** — Epic C
`id` · `key` · `nameAr` · `nameEn` · `iconToken` · `colorToken` · `parentCategoryId` nullable ·
`isSystem` · `isArchived` · `sortOrder` · `createdAt`
> AC-C3.3: deleting a category in use is blocked by `FK RESTRICT`; the app must force a
> reassign-or-Uncategorize decision. No transaction may point at a missing category.
> AC-C3.4: renaming preserves `id`, so history is intact.
> The default starter list (OQ-18) is proposed by the designer in `docs/design.md`, seeded as
> `isSystem = true`, and is fully editable. It is **not** invented in code.

**`AuditEntry`** — ADR-010, NFR-A2/A3, US-F5
`id` · `entityType` · `entityId` · `action` (`create` | `update` | `delete` | `restore` |
`merge` | `categorize` | `rule_apply`) · `actor` (`user` | `system_rule` | `parser` |
`importer`) · `actorDetail` (e.g. `ruleId`) · `changedAt` · `fieldChanges` JSON
`[{field, from, to}]` · `prevHash` · `entryHash`
> Protected by `BEFORE UPDATE` / `BEFORE DELETE` triggers and a hash chain.

**`Budget`** / **`BudgetAlertLog`** — Epic G
`Budget`: `id` · `scope` (`overall` | `category`) · `categoryId` nullable ·
`amount_{amount,currency,minor}` · `periodType` (`calendar_month`) · `startMonth` (`YYYY-MM`) ·
`isActive` · `alertEnabled` · `alertThresholdPercent` (default 100) · `createdAt`
`BudgetAlertLog`: `id` · `budgetId` FK · `periodKey` (`YYYY-MM`) · `thresholdPercent` ·
`firedAt` — **`UNIQUE(budgetId, periodKey, thresholdPercent)`**
> That unique constraint is how AC-G3.1 ("exactly one alert per budget per period") is
> guaranteed at the database level rather than by hopeful application logic.
> Budget progress counts only `affectsSpend = true` (US-B10/B11).

**`ExchangeRate`** — ADR-009
`id` · `fromCurrency` · `toCurrency` · `rate` TEXT · `rateDate` · `source` (`sms_implied` |
`sms_stated` | `user` | `carried_forward`) · `createdAt`

**`InternalTransferLink`** — US-B11, R-7
`groupId` · `outTransactionId` · `inTransactionId` · `confidence` · `confirmedByUser` bool
> AC-B11.2: when the app cannot determine whether a transfer is internal, it **flags for
> review** and never guesses. `confirmedByUser = false` means the pair is a *candidate*, and
> candidates do not change spend totals until confirmed. R-7's bootstrap problem is handled by
> making the unknown state visible rather than by defaulting either way.

**`RulePack`** — ADR-007
`id` · `packId` · `packVersion` · `source` (`bundled` | `imported`) · `checksum` ·
`signatureStatus` (`bundled_trusted` | `unverified`) · `importedAt` · `isActive`

**`StatementImport`** / **`StatementLine`** — Epic H
`StatementImport`: `id` · `fileName` · `sourceType` (`csv`) · `importedAt` · `lineCount` ·
`matchedCount` · `addedCount` · `unmatchedCount`
`StatementLine`: `id` · `importId` FK · `lineIndex` · `parsedFields` JSON ·
`matchStatus` (`matched` | `added` | `unmatched_flagged`) · `matchedTransactionId` nullable
> Invariant: `matched + added + unmatched = lineCount`. Asserted in code and in a test.

**`IngestWatermark`** (single row) — ADR-006
`lastProcessedSmsProviderId` · `lastProcessedSmsDate` · `importState` (`idle` | `running` |
`paused` | `completed`) · `importCursor` · `importFromDate` (start of current calendar month, per
AC-A3.1)
> **Correction, v1.6:** this row omitted `completed`, which the shipped schema has and which is
> **terminal** — it is deliberately a different value from the initial `idle`, because reusing
> `idle` to mean "finished" made every app foreground re-run the whole month's backfill. Its
> terminality is also the third of the three choices that make a rule-pack fix forward-only, so
> it must be written down where a reader of the data model will see it (ADR-006's KHA-133
> subsection).
> **No column is added for re-scan.** A re-scan is transient: it runs with
> `advanceWatermark: false` and writes none of these fields. Recording *which rule pack the
> watermark was last swept under* was considered and rejected — see that subsection, Q3 option (2).

**`AppSettings`** (single row)
`baseCurrency` (default `SAR`) · `locale` · `lockGraceSeconds` · `autoApplyThreshold` ·
`backupEnabled` · `backupTargetUri` · `lastBackupWrittenAt` · `foregroundServiceEnabled` ·
`onboardingComplete`

### 4.3 Where the sensitive data lives

| Data | Location | Protection |
|---|---|---|
| Redacted SMS text | `RawMessage.sanitizedBody` | SQLCipher whole-DB; PAN/CVV/PIN destroyed **before** insert (ADR-013 §13.1–§13.8) |
| SMS that arrived while the app was **locked** | **Nowhere of ours** — they stay in the Android SMS content provider until unlock | ADR-018: there is deliberately **no** staging store, inbox, or auth-free cache. Whatever protects the OS's own SMS store protects them, and Massrofy holds no second copy |
| Amounts, merchants, counterparties | `Transaction` | SQLCipher; never logged (ADR-015); never in an unencrypted backup |
| Masked instrument identifiers | `Instrument.maskedIdentifier` | Masked at the source; there is no column able to hold a full PAN |
| Audit history | `AuditEntry` | SQLCipher + append-only triggers + HMAC chain |
| DB Master Key | in memory only while unlocked; wrapped at rest | Keystore KEK (auth-required) **and** Argon2id/HKDF recovery wrapping (ADR-004) |
| Recovery Phrase | **the user's own custody** (paper / password manager); optional Keystore convenience cache | Never transmitted; never in an export; never in a log |
| Backup blob | user-chosen SAF location, then their sync provider | XChaCha20-Poly1305 under a key the provider cannot derive (ADR-012) |
| Manual export | user-chosen SAF location | **Plaintext by decision (OQ-13)**; AC-F2.3 warning is a required control, not a nicety |
| Diagnostics | encrypted DB ring buffer | Ids/enums/counts only; user reviews the file before sharing |

---

## 5. Contracts (there is no HTTP API — here is what replaces it)

### 5.1 There is no API surface. Stated plainly.

**Massrofy v1 exposes no HTTP endpoints, consumes no HTTP endpoints, and ships no network
client.** The release build carries no `INTERNET` permission (ADR-001). There is therefore no
REST/GraphQL/gRPC contract, no authentication scheme, no rate limiting, no API versioning, and
no `docs/api.md` in the conventional sense.

**Action for the team:** `docs/api.md` should be created containing exactly
`N/A — no network API surface. See docs/architecture.md ADR-001.` plus a pointer to §5.2 and
§5.3 below. This prevents an engineer or reviewer from assuming the file is merely missing.

The two contracts that *do* need to be stable across versions, and that engineers implement
against, are the **rule pack schema** and the **backup envelope**. Both are versioned, both are
read by code that may be older or newer than the writer, and both are treated with the same
rigour an API contract would get.

### 5.2 Contract A — Rule pack schema `v1` (ADR-007)

```jsonc
{
  "schemaVersion": 1,
  "packId": "sa-core",
  "packVersion": "2026.07.27",
  "locales": ["ar", "en"],
  "banks": [
    {
      "bankId": "bank-aljazira",
      "displayName": { "ar": "بنك الجزيرة", "en": "Bank Aljazira" },
      "aliases": ["ALJAZIRA", "BAJ"],
      "senderPatterns": ["^(BAJ|Aljazira)$"],
      "messageRules": [
        {
          "ruleId": "baj-pos-purchase-ar",
          "priority": 100,
          "messageType": "purchase",
          "intent": "transaction",
          "match": {
            "allOf": ["شراء", "بطاقة"],
            "noneOf": ["رمز التحقق", "عرض"]
          },
          "extract": {
            "amount":        { "group": "amt",  "transform": ["normalizeNumerals"] },
            "currency":      { "group": "cur",  "transform": ["upper"] },
            "merchant":      { "group": "mer",  "transform": ["trim","collapseWs","stripTrailingRef"] },
            "instrumentRef": { "group": "card", "kind": "card", "maskPolicy": "last4" },
            "occurredAt":    { "group": "dt",   "format": "dd/MM/yy HH:mm", "timezone": "Asia/Riyadh" },
            "referenceNumber": { "group": "ref" }
          },
          "regex": "(?<mer>...)\\s(?<amt>[\\d.,٠-٩٫]+)\\s(?<cur>[A-Z]{3})...",
          "sign": "debit",
          "affectsSpend": true,
          "requiredFields": ["amount", "occurredAt"],
          "redact": ["(?i)(cvv|pin|رمز)\\D{0,5}(?<secret>\\d{3,8})"]
        },
        {
          "ruleId": "baj-otp",
          "priority": 900,
          "messageType": "otp",
          "intent": "ignore",
          "match": { "anyOf": ["رمز التحقق", "OTP", "verification code"] }
        }
      ]
    }
  ]
}
```

**Compatibility rules (treat these as you would API versioning):**
- A pack with a `schemaVersion` **greater** than the app supports is rejected with a clear
  message; it is never partially applied.
- Unknown fields inside a known `schemaVersion` are **ignored**, so packs may carry forward-
  compatible hints.
- `messageType` values not recognised by the app are treated as `unknown` → **review queue**,
  never discarded (NFR-A7).
- Higher `priority` wins; ties broken by declaration order; **first match wins**.

### 5.3 Contract B — Backup envelope `v1` (ADR-012)

A single file: a **cleartext JSON header**, a `0x00` separator byte, then the ciphertext.
The header *must* be readable without any key — otherwise restore on a new device is impossible.

```jsonc
// header — CLEARTEXT, contains no financial data and no secret
{
  "format": "massrofy-backup",
  "envelopeVersion": 1,
  "createdAt": "2026-07-27T09:14:00Z",
  "kdf": {
    "algorithm": "hkdf-sha256",          // or "argon2id" in user-passphrase mode
    "salt": "<base64, 32 bytes>",        // NOT secret; required for derivation
    "params": { "m": 65536, "t": 3, "p": 2 }   // present only for argon2id
  },
  "cipher": "xchacha20poly1305",
  "wrappedDataKey": "<base64>",          // DataKey wrapped with BackupRootKey (AES-256-GCM)
  "wrapNonce": "<base64>",
  "payloadNonce": "<base64>",
  "payloadDigest": "<base64 sha-256 of plaintext>",
  "schemaVersion": 7,                    // Drift schema version of the payload
  "recordCounts": { "transactions": 1842, "instruments": 6, "rules": 91 }
}
```

Plaintext payload (before encryption): a gzipped JSON document containing `banks`,
`instruments`, `transactions`, `rawMessages`, `merchants`, `merchantAliases`, `merchantRules`,
`categories`, `budgets`, `exchangeRates`, `auditEntries`, `settings` — with money serialised as
`{"amount": "1234.50", "currency": "SAR"}` objects (ADR-002), never as numbers.

**Restore compatibility:** if the payload's `schemaVersion` is lower than the app's, the normal
Drift migration chain runs after import. If it is **higher**, restore is refused with a message
telling the user to update the app — a partial restore of an unknown schema is worse than no
restore.

**`recordCounts` is in the cleartext header deliberately** — it lets the user verify a backup
is non-empty without decrypting it. It leaks approximate activity volume to anyone holding the
file, which we judge an acceptable trade for that verification. **Flagged for the human in §8**
in case they disagree; moving it inside the ciphertext is a one-line change.

### 5.4 Contract C — internal domain ports (what engineers code against)

No network, but the module boundaries in §3 are real contracts. The load-bearing ones:

```dart
abstract interface class SmsSource {                    // data/sms  → features/ingestion
  Future<List<RawSmsRecord>> readSince(IngestWatermark w);
}

abstract interface class MessageParser {                // features/parsing → ingestion
  ParseOutcome parse(SanitizedSmsText text, String sender);
  // ParseOutcome = Parsed(fields, ruleRef) | Ignored(reason) | Unparsed(reason)
  //                                          ^ never a fourth "dropped" case (NFR-A7)
}

abstract interface class Categorizer {                  // features/categorization
  CategorySuggestion suggest(MerchantKey key);          // {categoryId?, confidence, matchTier}
}

abstract interface class TransactionRepository {        // domain port; impl in data/dao
  Future<Result<TransactionId, AppFailure>> upsertFromIngest(IngestedTransaction t);
  // implementation MUST write the audit entry and advance the watermark in the same DB txn
}

abstract interface class StatementSource {              // ADR-016 — PDF slots in here later
  Stream<StatementLine> parse(SanitizedFile file);
}

abstract interface class BackupTarget {                 // ADR-012; Drive adapter slots in later
  Future<Result<Unit, AppFailure>> write(Uint8List envelope);
  Future<Result<Uint8List, AppFailure>> read();
  Future<Result<Unit, AppFailure>> tombstoneAndDelete();   // ADR-011
}
```

---

## 6. Security and compliance architecture

### 6.1 Authentication and authorisation

There is **no authentication system** and there is **nothing to authorise against** — CON-1
removes accounts, tenancy, and server-side identity entirely. The complete access-control model
is:

| Layer | Control |
|---|---|
| Device | OS lock screen (outside our control, but a precondition) |
| App | `BiometricPrompt` (`BIOMETRIC_STRONG \| DEVICE_CREDENTIAL`) on launch and on resume past the grace window (ADR-005) |
| Data | **The DB Master Key is unwrappable only through a Keystore key that requires user authentication.** Failing auth means the database cannot be opened at all — access control is cryptographic, not navigational |
| Backup | A separate secret in the user's own custody (ADR-012); the storage provider is untrusted by design |

**Deliberately absent:** sessions, tokens, refresh flows, roles, permissions, RBAC. Adding any
of them would mean inventing a user model the PRD explicitly forbids (X1, CON-1). If a future
version ever adds a second user, this is the section that must be rewritten first.

### 6.2 Encryption at rest

- **Whole-database** SQLCipher, AES-256-CBC per page with HMAC-SHA512 page authentication
  (ADR-003). Covers transactions, retained SMS text, learned rules, budgets, the audit trail,
  and the diagnostic buffer — the complete NFR-S1 list, with no per-column judgement calls.
- Small secrets (wrapped keys, salts) in `flutter_secure_storage` → EncryptedSharedPreferences,
  Keystore-backed. Already-encrypted material, stored encrypted again.
- Keys in the **Android Keystore** (hardware-backed / StrongBox where available), never in
  application memory longer than a session, zeroed on lock (ADR-004, ADR-005).
- **What is deliberately not encrypted by us:** the manual export (US-F2/OQ-13, plaintext by the
  human's decision, with the AC-F2.3 warning as the compensating control).

### 6.3 Encryption in transit

**There is no transit.** ADR-001 removes the `INTERNET` permission from the release build.
NFR-S5 ("if any network communication exists at all, it must use current TLS") is satisfied by
the antecedent being false. The backup blob travels only inside a third-party sync app the user
chose, as ciphertext, over that app's own transport.

If ADR-016's deferred Drive adapter is ever built, NFR-S5 becomes live and that change must
re-open this ADR — hence the explicit deferral rather than a quiet "maybe later".

### 6.4 PII and sensitive-data handling

| Control | Mechanism |
|---|---|
| **Data minimisation** (NFR-P1) | Non-financial senders produce **no stored row at all**. OTP/marketing from financial senders store a counter with **no body**. Only parsed and unparsed financial messages retain (redacted) text, and only because AC-B1.2 and AC-A4.1 require it |
| **Never store PAN/CVV/PIN** (NFR-S2, NFR-C2) | Redaction at the ingestion boundary, enforced by the `SanitizedSmsText` type — unsanitised text cannot compile into a write (ADR-013). No schema column can hold a full PAN |
| **Masked display** (NFR-S2) | Instruments carry only `****last4`; the raw form we receive is already masked |
| **No sensitive values in logs** (NFR-S4) | `SafeLogger` + `LogSafe` marker type + redacted `toString()` overrides + a CI grep banning `print`/`debugPrint` (ADR-015) |
| **No telemetry** (NFR-S6, X13) | Structurally impossible — no network permission (ADR-001). Dependency review at PR time is a second line, not the first |
| **Deletion** (NFR-P5, NFR-P7) | ADR-011, including the honest statement about provider trash and version history |
| **Transparency** (NFR-P6, US-F4) | The in-app privacy screen must describe: everything stays on the device; nothing is transmitted by the app; if backup is enabled, an encrypted file is written to a folder **you** chose and **your** sync app uploads it; the app cannot read it back without your Recovery Phrase, and neither can anyone else |

### 6.5 Audit trail

ADR-010: append-only DAO shape + SQL triggers + an HMAC hash chain, with the enforcement
boundary (tamper-evident, not tamper-proof against a rooted device owner) stated rather than
glossed over. Provenance per NFR-A1 is carried on every transaction as
`provenance` + `sourceMessageId` + `rulePackId`/`ruleId`.

### 6.6 Compliance posture

| Requirement | How it is satisfied |
|---|---|
| **NFR-C1** — not advice, not a payment initiator | CON-2 is architectural: there is no code path that moves money, and no network to move it over. Product copy is the designer's and PO's responsibility |
| **NFR-C2** — PCI-adjacent: avoid handling, don't try to secure | ADR-013. We destroy, at the boundary, anything resembling a PAN or authentication datum. Massrofy is not in PCI-DSS scope (not a merchant, processor, or service provider; never transmits cardholder data) but adopts the avoidance posture regardless |
| **NFR-C3** — platform SMS-permission policy | **Satisfied by the distribution decision.** `RECEIVE_SMS`/`READ_SMS` are restricted permissions on Google Play requiring a Permissions Declaration, which a spending tracker would very likely fail (it is not a default SMS handler). OQ-3/OQ-4/X16 resolve distribution to **personal side-load**, so Play policy does not apply. **This is a load-bearing dependency: publishing to Play later would require re-architecting ingestion, and this ADR does not support that path** |
| **NFR-C4** — data-subject-style rights | Access → US-F2 export; erasure → US-F3 + ADR-011; rectification → US-B5 edit with audit. All local, all user-initiated. Data residency is trivially satisfied: **the data never leaves the user's device except as ciphertext they route themselves**, so there is no cross-border transfer question to answer |
| **NFR-C5** — no redistribution to third parties | No network. The only egress is a user-chosen encrypted file |

### 6.7 Data residency

Because of ADR-001 there is no data residency question in the usual sense: no processing and no
storage occurs outside the user's handset. If the user points the backup folder at a cloud
provider, the **ciphertext** may land in any region that provider chooses — but the plaintext
never leaves Saudi Arabia unless the user's own device does. The transparency screen should say
this, since it is one of the few genuinely reassuring things we can say without qualification.

### 6.8 Threat model, briefly

| Threat | Mitigated? |
|---|---|
| Lost/stolen unlocked phone | Yes — app lock is cryptographic (ADR-005); switcher snapshot obscured (ADR-014). **And this claim needs no footnote**, because ADR-018 declined to create an auth-free staging store for SMS that arrive while locked. There is no subset of the ledger readable without authentication |
| Lost/stolen locked phone | Yes — DB key is Keystore-wrapped behind user auth; database file is opaque |
| Cloud account compromise | Yes — provider holds ciphertext only; the key is never in the cloud (ADR-012) |
| Malicious app on the device reading our files | Yes — app-private storage + whole-DB encryption |
| Network attacker | N/A — no network |
| Malicious imported rule pack | Partly — declarative-only, regex timeout, mandatory user review, no network to exfiltrate to. Signing deferred (§8) |
| Rooted device / determined owner | **No, and we say so** (ADR-010). The owner is not the adversary in this threat model |
| Backup file leaked to an attacker | Yes for confidentiality (ciphertext); **`recordCounts` in the header leaks approximate activity volume** — flagged in §8 |

---

## 7. Cross-cutting concerns

### 7.1 Error handling

- `Result<T, AppFailure>` (sealed) at every layer boundary. **Exceptions do not cross the domain
  boundary**; platform-channel and Drift exceptions are caught at the `data` edge and mapped to
  a typed failure.
- Failure taxonomy: `ParseFailure`, `PermissionFailure`, `CryptoFailure`, `StorageFailure`,
  `IntegrityFailure`, `FileAccessFailure`, `ValidationFailure`.
- **Per-message isolation (NFR-R5):** the ingestion loop wraps each message individually. One
  malformed message can never abort a batch. A failure produces a `RawMessage` with
  `financial_unparsed` and a reason — **never a silent drop** (NFR-A7, AC-A4.4).
- **There is no "swallow" path anywhere in ingestion.** Code review should treat a bare `catch`
  with an empty body in `features/ingestion` or `features/parsing` as an automatic rejection.

### 7.2 Idempotency (the analogue of money-operation idempotency)

CON-2 means there are **no money-moving operations to make idempotent.** The equivalent risk is
double-*recording*, and it is handled the same way:

| Operation | Idempotency key | Mechanism |
|---|---|---|
| SMS ingestion | `smsProviderId` UNIQUE + `contentHmac` UNIQUE | `INSERT … ON CONFLICT DO NOTHING`, inside the same DB transaction that advances the watermark. A crash mid-batch re-runs safely (AC-A3.3, NFR-R6) |
| Historical import | `importCursor` + the same unique keys | Resumable and duplicate-free (AC-A3.3) |
| Statement import | `(importId, lineIndex)` | Re-import produces no duplicates |
| Budget alert | `UNIQUE(budgetId, periodKey, thresholdPercent)` | Exactly one alert per budget per period (AC-G3.1) |
| Backup write | payload digest | Identical content is not rewritten |

**Rule: every write triggered by an external event carries an idempotency key.** Reviewers
should look for it.

### 7.3 Logging and observability

ADR-015. `SafeLogger` only; ids/enums/counts only; encrypted ring buffer; a user-reviewable
share action; a parser-health panel. No remote sink exists or can exist.

### 7.4 Time and period boundaries

- Store UTC instants **plus** the original offset and a `timeSource` marker.
- Bank SMS frequently give local time with no offset; we assume `Asia/Riyadh` and record
  `timeSource = sms_local_assumed` so an odd-looking timestamp is explainable later.
- "Calendar month" (AC-E1.4, OQ-12) is computed in `Asia/Riyadh`, not UTC, so a purchase at
  23:30 on the 31st does not fall into the next month. `package:timezone`, single `Clock`
  abstraction in `core/time/` so tests can freeze it.

### 7.5 Sync vs async boundaries

| Work | Where |
|---|---|
| UI reads | Drift streams → Riverpod. Reactive, no polling |
| SMS ingestion | Background isolate via WorkManager (ADR-006) — **but only while the app is unlocked; a locked run is a no-op that does not advance the watermark (ADR-018)** |
| Post-unlock sweep | Part of the unlock transition, **before** the home screen presents a total as final (ADR-018 decision 3) |
| Historical import | Background isolate, chunked, cancellable, progress-reporting (AC-A3.2, NFR-R3) |
| Rule-pack evaluation | Background isolate with a per-rule timeout (ADR-007) |
| Backup encryption | Background isolate (ADR-012) |
| Statement import | Background isolate |
| Report aggregation | Dart, over `Money` (ADR-002); isolate for multi-month ranges |

**No derived monetary figure is ever persisted** (NFR-A6). Report caching is **in-memory only**
and invalidated on any ledger write. A persisted total is a number that can drift away from the
ledger it claims to summarise, and in a banking-domain app that is a defect waiting to happen.

### 7.6 Localisation and RTL

`flutter_localizations` + ARB files, `ar` and `en`. RTL via `Directionality` driven by locale,
with `EdgeInsetsDirectional` / `AlignmentDirectional` used everywhere (no raw `left`/`right`)
— enforced by lint. **Numeral rendering (Eastern-Arabic vs Western digits) for amounts is a
design decision (D-1), not an architecture one**; the architecture supports both via
`NumberFormat` with an explicit numbering-system override, and the `core/text/` normaliser
handles both on the input side regardless.

### 7.7 Testing strategy

| Level | Coverage |
|---|---|
| Unit | `Money` (property-based), numeral/text normalisation, redaction, rule matching, dedup tiers, merchant matching tiers, KDF/envelope round-trip |
| Golden corpus | **Synthetic** SMS fixtures → expected structured output, per bank per message type (NFR-M2, NFR-M3). A rule change that breaks a passing fixture fails CI |
| DB | Drift migration tests, `verifySelf()`, append-only trigger tests (an UPDATE against `audit_entry` **must** throw) |
| Widget | Every screen, in `ar` RTL and `en` LTR, at the largest OS font scale |
| Integration | Ingestion end-to-end against a fake SMS provider; backup → wipe → restore on a fresh database with **only** the Recovery Phrase |
| Security | Release-manifest assertion (no `INTERNET`); log-scrubbing assertion; "DB file is unreadable without the key" assertion; a test asserting no `Money` API returns `double` |

**Hard rule, repeated because it matters (NFR-M3): the user's genuine bank SMS never enter the
repository, a test fixture, a defect report, or any tool.** Reproduce with synthetic
equivalents. This binds QA and production-support as much as engineering.

---

## 8. Risks, residual open questions, and what the human must decide

### 8.1 Decisions the human should actively weigh in on

| # | Question | This ADR's position |
|---|---|---|
| **H-1** | **Confirm no backend.** ADR-001 resolves build-plan §2.1: no server, no API, and the release build has **no `INTERNET` permission**. `backend-engineer` is not dispatched. Epic I is mobile work. | Recommended, strongly. It makes AC-F4.2 an OS-enforced property rather than a promise |
| **H-2** | **AC-F4.2 wording.** Under ADR-001 nothing is transmitted by the app at all; an encrypted blob later leaves via a sync app the user chose. Suggest the PRD ratify: *"the release build declares no network permission; the only egress is a ciphertext backup file the user routes through their own storage provider."* | A clarification, not a scope change |
| **H-3** | **PDF statement import** (R-6, ADR-016). Recommend **CSV in v1, PDF in v1.1**, behind a `StatementSource` port so PDF drops in later without redesign | Needs an explicit yes/no; build-plan §7.3 item 3 |
| **H-4** | **No key escrow.** If the Recovery Phrase is lost, the backup **and** (after a Keystore invalidation) the local database are permanently unrecoverable. Any escrow contradicts AC-I2.1 | Confirm you accept this |
| **H-5** | **Biometric re-enrollment friction.** We choose `setInvalidatedByBiometricEnrollment(true)` — the secure setting — so adding a fingerprint forces one Recovery-Phrase entry. The alternative lets anyone who can add a biometric inherit database access | Confirm the friction is acceptable |
| **H-6** | **~~NFR-R1 is provisional on the P0 spike (KHA-7)~~ — REVISED at v1.1 by ADR-018.** The spike no longer decides NFR-R1: Layer 3 cannot buy latency while the app is locked, because it cannot open the database either. The spike's remaining question is narrower — does the `SMS_RECEIVED` wake signal survive on this OEM at all, which affects only the *unlocked* rows of ADR-018's table | Either run KHA-7 for the narrowed question or retire it explicitly. **Do not make Layer 3 default-on on NFR-R1 grounds; it would cost battery and deliver nothing** |
| **H-7** | **`recordCounts` sits in the cleartext backup header** so a backup can be verified non-empty without decrypting. It leaks approximate activity volume to anyone holding the file | Say the word and it moves inside the ciphertext |
| **H-8** | **Recovery secret format:** a 12-word BIP-39 mnemonic (chosen) vs a Base32 code vs a user passphrase. We generate it rather than let the user choose one, specifically to close the weak-passphrase half of R-2 | Confirm; the designer needs this for the backup flow |
| **H-9** | **Base currency defaults to SAR**, user-changeable | Confirm |
| **H-10** | **Internal transfers are never auto-confirmed** — a candidate pair always waits for the user (AC-B11.2, R-7). Safer, but potentially tedious in month one | Confirm the bias toward asking |
| **H-11** | **Google Drive API adapter deferred to v1.1** (ADR-001 option (c), behind the `BackupTarget` port). v1 is SAF-only, which means the user must have a sync app pointed at the folder | Confirm SAF-only is acceptable UX for v1 |
| **H-12** | **Play publication is architecturally foreclosed.** ADR-006 depends on `RECEIVE_SMS`/`READ_SMS`, which Play restricts to default SMS handlers. NFR-C3 is satisfied *by* side-loading. Publishing later would require re-architecting ingestion | Acknowledge the lock-in |
| **H-13** | **⚠️ NFR-R1 is reduced. This is the one item in v1.1 you should actually weigh.** ADR-018 decides that background SMS ingestion is suspended while the app is locked, because the alternative is a second, auth-free copy of your financial data. **Net effect: "seconds from SMS arrival" holds while the app is unlocked; while locked it becomes "seconds from unlock, with nothing lost."** AC-A1.4 is still fully met. If you want the *feel* of the original, ADR-018 decision 5 offers an opt-in, content-free "a bank message is waiting" notification at zero security cost | **Confirm the reduction**, and say yes/no to building the opt-in nudge in P6/P7. If you would rather have the original latency and accept an auth-free ingest inbox, say so — but read ADR-018's four arguments first; I recommend against it clearly |
| **H-14** | **Ratifying ADR-013's widening surfaced two live defects of the same class that KHA-54's fix did *not* close.** (i) The grouped-PAN scan tests only the maximal digit-group sequence, so `4111 1111 1111 1111 45` leaves a full PAN in cleartext with `panRedacted = false`. (ii) Grouped SA IBANs (`SA03 8000 0000 6080 1016 7519`) are not matched at all. Both are security defects in an open PR, not future work | **No decision needed — flagging for visibility.** These are must-fix under §13.4/§13.5 before PR #2 merges, and should be raised as `bug` issues routed to mobile-engineer. Tell me if you want them held to a follow-up instead |
| **H-15** | **⚠️ A `/revise-design` round is now required — this is the v1.3 item that needs you.** The KHA-98 decision makes the `MerchantAlias` link the **only** remaining operation in the product that collapses two identities into one, so it must be reversible (R-8's principle). That needs a **"This is a different shop"** affordance on **S-16 (Learned / Merchant Rules)** plus a confirmation dialog, and `docs/design.md` has neither. The change is **additive** — one action on an existing screen, one dialog, no new top-level screen — so in my judgement it does not require re-approving the whole design document, only the delta. But design approval is a human gate under `CLAUDE.md`, so it is yours to approve, not the team's to assume | **Two things, please.** (1) Confirm the additive-delta reading, so the manager can run `/revise-design` scoped to S-16 rather than re-opening gate 2. (2) Note the sequencing: this blocks only the P4b issue that carries the split affordance — not P4b as a whole, and not the mobile-engineer's KHA-98/99/100/102 fix, which should land first and independently |
| **H-16** | **⚠️ The v1.5 item, and the one you asked for a real opinion on.** You framed KHA-128 as possibly existential — *"the app should be smart enough… we will not be able to inject LLM."* **My independent judgement: the architecture is sound and needs a fix, not a rework — but the fix is not the one that looks obvious, and the diagnosis in the question is worth correcting.** The app was never insufficiently smart. It was **mute**: it counted 214 skipped messages on every run and told nobody, and the string that identifies `Jazira Bank` was already shipped in `sa-core.json`'s `aliases` and never compared to the sender. So: **hard sender gate KEPT, NFR-P4 KEPT unamended** (nothing was lost — the messages are still in the SMS provider we hold `READ_SMS` on); **option 1 rejected as a gate** (it would persist private non-bank message content, and needs the out-of-scope X19); **option 2 rejected for v1** on evidence grounds, not effort — we have no lawful training corpus (NFR-M3) and no way to measure it in the field (NFR-S6/R-10); **option 3, which was framed as merely complementary, is the primary fix.** Option 1's heuristic survives as an advisory ranking signal on the sender screen, where a false positive costs a screen row instead of a database row | **Three things.** (1) **Approve PRD Addendum A** — it is the load-bearing fix and it is currently `DRAFT`, so nothing here can be built until you do. (2) **Confirm you accept "the app asks you once per bank" instead of "the app guesses"** — this is the actual product decision inside all of this, and I recommend it strongly: it is more accurate (certainty, not 90%), more private, and cheaper. (3) **Note where the real risk actually sits — it is not gate 1.** It is whether the bundled rules can *parse* your seven banks' message bodies once linked. AC-A6.5 guarantees nothing is lost, but hand-completing hundreds of messages a month fails PRD §1's own definition of success. **That needs real sample messages from your seven banks; it is the highest-leverage thing available right now and it is ops work, not architecture.** Say the word and I will spec the user-initiated redacted sample export |
| **H-17** | **⚠️ The v1.6 item, and it is a sequencing call, not a design one.** KHA-133's decision is settled: the re-scan is AC-A6.10's capability, bank-scoped, user-triggered, no schema change, riding with US-A6. What is **not** settled is *when your already-received messages come back*. KHA-128 merging fixes the future only; **the recovery lands with US-A6**, and until then the only recovery the app offers is "clear app data", which I am explicitly telling you **not to do** — it destroys the transactions you already have correctly and, per ADR-004/ADR-012, may cost the whole encrypted store. Two ways to close the gap: **(a)** wait for US-A6, which is already next per OQ-23 — correct, zero extra work, and right if US-A6 is days away; **(b)** land items (A)–(F) of the KHA-133 subsection as a small PR **immediately after** KHA-128, with a plain "check my banks again" button in Settings → Diagnostics, then let US-A6 dress the same mechanism in its real screen. **(b) is not a stopgap and throws nothing away** — it is a subset of the mechanism US-A6 must build anyway, which is exactly why I am willing to recommend it. I did *not* consider a third option worth offering: resetting `importState` to re-run the import. It is two lines, it is dedup-safe, and I am still refusing it — it creates a second re-scan path that diverges from the one US-A6 needs, and ADR-006's self-healing property comes entirely from there being one path | **Two things.** (1) **Approve or amend the KHA-133 subsection** (currently `DRAFT` inline; the rest of this document stays `APPROVED`). (2) **Pick (a) or (b).** I recommend **(b)** if US-A6 is more than a few days out, **(a)** if it is imminent. Also worth noting for the record: **v1 stores no last-seen rule-pack version**, so a future bundled-pack correction arriving as a new APK will prompt nothing by itself — the user has to go and tap "check again". I accepted that rather than pay for a schema column; if it bites twice, that is the re-open trigger |

### 8.2 Residual open questions I am deliberately **not** deciding here

| # | Item | Why deferred, and where it lands |
|---|---|---|
| **O-1** | **The numeric value of `autoApplyThreshold`** (residual OQ-14). Initial **0.85**, and the token-set/edit-distance constants alongside it | These must be **tuned against the synthetic corpus in P4**, not guessed in P0. Deciding a number now would be false precision. The architecture pins the *structure* — one named constant, one place, tiered matching where T4 can never auto-apply — so tuning never requires a redesign. The observable bar (AC-D2.3/D2.4: match or flag, never silently miscategorise) is enforced regardless of the value. **Reaffirmed at v1.3, with one correction to how the bar is guaranteed:** KHA-98 showed that the bar is *not* enforced by tier structure alone, because a normalisation collision arrives at T1 already merged and never meets a gate. The bar is now enforced by the tier structure **plus** the corroboration rule in ADR-008's KHA-98 subsection. 0.85 is unchanged. ~~`referenceDigitRunMinLength = 4` joins it as a tunable with the same posture~~ — **retracted at v1.4 (KHA-106): that constant is deleted, not tuned. It was never an O-1-shaped tunable, because its existence *was* the bar rather than a setting of it; a corroboration signal that admits any value at all is unsafe at every value. O-1 covers thresholds that trade precision against recall, not switches that decide whether two businesses are one** |
| **O-2** | **Rule-pack signing for imported packs.** v1 ships unsigned, mitigated by declarative-only rules, a regex timeout, mandatory user review of the diff, and no network permission | Signing needs a key-distribution story that only matters once packs are shared beyond the user. Revisit if that changes |
| **O-3** | **Exact wording of the erase-all cloud-trash warning** (ADR-011) and the backup-freshness copy (ADR-012) | Designer's call (D-10), with the architectural facts fixed here |
| **O-4** | Whether the diagnostic ring buffer should survive erase-all for post-mortem purposes | Currently: it is wiped, because AC-F3.1 says "all data". Raise only if production-support finds this blocking |
| **O-5** | **`setInvalidatedByBiometricEnrollment` shipped as `false` in P1, where ADR-004 specifies `true`.** Observed while researching KHA-56; **not** part of either escalation and **not** decided here. The engineer's reasoning is sound and documented in `KeystoreChannel.kt`: `true` is only safe once `unwrapWithRecoverySecret` is real, which is Epic I / P8, and shipping it today would mean the first biometric re-enrolment permanently destroys the database with no way back | **This must flip to `true` in P8, in the same PR that makes the recovery path real.** Until then H-5's stated posture is not yet in force and the human should know that. Recommend a Linear issue blocking P8 exit so it cannot be forgotten — silence here is how a temporary deviation becomes permanent |
| **O-6** | **Generic IBAN detection via the ISO 7064 mod-97-10 check** (ADR-013 §13.5 SHOULD), covering foreign counterparty IBANs on outbound international transfers | Deferred as additional surface on an already-large open PR, not because it is doubtful. It is the exact analogue of Luhn and would be precise rather than blunt. Pick it up in P3 or as a standalone hardening issue |
| **O-7** | **The on-device classifier (KHA-127/128 option 2), and the home of the financial-shape keyword lists.** Rejected for v1 in ADR-007's KHA-127/128 subsection; the lists ship as Dart constants rather than as rule-pack schema | **Stated re-open trigger, so this is a decision and not a shrug: re-open the classifier only if, after PRD Addendum A ships and the user has linked their real banks, the sender-recognition screen is measurably failing** — i.e. the user reports banks still going unnoticed *despite* the health signal firing, or the unrecognised-sender list is too noisy to use even with per-sender aggregation and the mobile-number veto. Until then the classifier is a guess where certainty is available. And the precondition would still not be met: we would need a lawfully-obtained labelled corpus (NFR-M3) and a way to evaluate precision without telemetry (NFR-S6). **If that trigger fires, the correct first move is still not a model — it is tuning the veto lists, which is a data change.** Promoting the lists into the rule-pack schema becomes worth its review cost only at that point |

### 8.3 Risk register updates (against build-plan §6)

| Risk | Status after this ADR |
|---|---|
| **R-1** background SMS reliability | **Re-characterised at v1.1 by ADR-018, and largely dissolved.** Three-layer design still stands for the *unlocked* case (1–3 s normal, ~15 min worst case, opt-in foreground service for hostile OEMs). But while the app is **locked** — the normal state — no layer can write, so OEM broadcast suppression stops mattering: the unconditional post-unlock sweep catches everything either way. **R-1's remaining exposure is confined to the unlocked window.** The residual risk has moved from "will a broadcast arrive" to "does the post-unlock sweep complete before the user reads a total" — which ADR-018 decision 3 answers with a mandatory updating state. KHA-7 narrowed accordingly (H-6) |
| **R-2** backup key recovery | **Closed.** App-generated 128-bit Recovery Phrase, HKDF/Argon2id, salt in the cleartext envelope header, nothing device-bound required to restore (ADR-004, ADR-012). QA must test restore on a device that has never seen the original Keystore |
| **R-3** exact decimal money | **Closed by construction.** `Money` cannot round-trip a float; cross-currency arithmetic throws; CI bans `double` in money paths and `SUM()` on money columns (ADR-002) |
| **R-4** parser brittleness | **Mitigated.** Data-driven rule packs, importable without an APK reinstall, corpus regression in CI, review queue as the never-lose-a-message safety net (ADR-007) |
| **R-5** cross-script merchant matching | **Re-characterised at v1.3, and the mitigation was incomplete as written.** The alias table and the never-auto-applying fuzzy tier stand. What v1.0 missed is that **the normalisation pipeline was itself a merge mechanism** — KHA-98/KHA-99/KHA-102 all merged unrelated merchants *upstream of every tier*, at confidence 1.00, where no gate exists. R-5's real surface was never only "too loose vs too strict matching"; it was also "too aggressive normalisation", which is invisible to every control the ADR named. Closed by the corroboration rule (ADR-008, KHA-98 decision), which bounds what normalisation may collapse and pushes everything else onto a user-created, auditable, **reversible** alias link. **v1.4 note:** the first attempt at that bound still contained a length heuristic that merged `QAMART 1000` with `QAMART 2000` at 1.00 (KHA-106) — evidence that this risk's real failure mode is *a plausible-sounding stripping heuristic*, and that the control that catches it is an adversarial probe over sibling strings, not review of the rule's prose |
| **R-16** merchant re-key migration window *(added 2026-07-29; the manager's KHA-98 brief calls this "R-17" — **R-16 is the correct next free ID**: `docs/build-plan.md` v1.4 ends at R-15 and no R-16 or R-17 exists in either document)* | **Open, time-boxed, and it expires on a human action.** The KHA-98 fix changes `MerchantKey.of`'s output, which on a populated install would require a re-key migration that can *split* one merchant row into two — meaning re-attribution of historical transactions by `merchantRawText` and one audit entry per row. That migration is **not** written, on the stated premise that no install holds a `merchant` row (schema v7 landed today; no v7 build has reached a device; KHA-88 and the PR #20 device gate are still open). **The premise is procedural, not structural**, and a routed UI is not needed to break it — the categorizer is already bound into live ingestion, so one ingested SMS on an unlocked v7 install populates the table. Land the fix before the P3b-3 device run. Full expiry condition in ADR-008's KHA-98 subsection. **Owner: mobile-engineer (fix), manager (sequencing).** **Widened at v1.4 (2026-07-29):** the KHA-106/KHA-107 decision changes `MerchantKey.of`'s output again (length corroboration withdrawn; strip made order-insensitive), so **that change rides this same window** and is subject to the same expiry. The window is not extended — it now simply has to carry two changes instead of one, which is an argument for landing them together and soon. The KHA-7 device spike is now cleared to run; it is a throwaway harness and does not itself populate `merchant`, but the expiry is written against *any* schema-v7 build reaching hardware, so treat a spike session as the moment the window can close. |
| **R-6** on-device PDF | **Recommend descope to v1.1**, behind a port so it costs nothing to add later (ADR-016). Human decision H-3 |
| **R-7** internal-transfer bootstrap | **Mitigated.** Candidates never change totals until confirmed; unknown state is visible, not guessed (§4.2 `InternalTransferLink`) |
| **R-8** auth-vs-posting duplicates | **Mitigated with an explicit bias.** Only exact-content duplicates are suppressed; everything else is flagged, never auto-removed (ADR-017) |
| **R-9** single-implementer bottleneck | Unchanged — a planning matter. The module boundaries in §3 at least make P4∥P5 and P6∥P7∥P8 genuinely parallel |
| **R-10** no telemetry | **Accepted as correct**, compensated by the local diagnostic buffer and parser-health panel (ADR-015) |
| **R-11** no update channel | **Partially solved for the part that matters:** parser rules update as **data** via an imported rule pack, no reinstall needed (ADR-007). Code changes still require a manual APK install |

---

## 9. Traceability

### 9.1 Build-plan §7.1 flags → where each is answered

| Flag | Answer |
|---|---|
| A-1 backend or not | **ADR-001** — no backend, no API, no `INTERNET` permission |
| A-2 background SMS + honest latency | **ADR-006** (three layers) **+ ADR-018** (what happens while locked; the superseding latency table) |
| A-3 encryption at rest, key storage, rotation, credential change | **ADR-003** + **ADR-004** |
| A-4 backup key derivation, escrow, recovery | **ADR-012** (+ ADR-004) — generated Recovery Phrase, no escrow |
| A-5 exact-decimal money + CI enforcement | **ADR-002** |
| A-6 parser rule model + data updates | **ADR-007** + §5.2 |
| A-7 merchant normalisation, matching, confidence threshold | **ADR-008** + its **KHA-98 decision** (v1.3) + its **KHA-106/KHA-107 decision** (v1.4) — the corroboration rule is the normative answer to "what may normalisation collapse", and v1.4 fixes the one signal that violated it: corroboration must be **evidence carried by the string**, never a prior about digit counts. Threshold value is residual **O-1**; `referenceDigitRunMinLength` is no longer a tunable at all |
| A-8 duplicate detection | **ADR-017** |
| A-9 FX handling offline | **ADR-009** |
| A-10 audit-trail enforcement boundary | **ADR-010** — stated, not over-claimed |
| A-11 PDF feasibility | **ADR-016** — recommend descope, decision **H-3** |
| A-12 erase-all reaching every copy | **ADR-011** — including what we cannot reach |
| A-13 redaction before storage | **ADR-013** — type-enforced at the ingestion boundary; normative patterns in §13.1–§13.8 (v1.1) |
| A-14 diagnostics without telemetry | **ADR-015** |
| A-15 `FLAG_SECURE` vs QA screenshots | **ADR-014** — no shipped bypass |

### 9.2 PRD NFR coverage

| NFR | Where |
|---|---|
| S1 encrypted at rest | ADR-003, ADR-004, §6.2 |
| S2 masked identifiers, never store PAN/CVV/PIN | ADR-013 §13.1–§13.8, §4.2 `Instrument`, §6.4 |
| S3 biometric/passcode gate | ADR-005 (+ ADR-018 — what the gate costs, and why we pay it) |
| S4 no sensitive values in logs | ADR-015, §7.3 |
| S5 TLS if any network | §6.3 — vacuous under ADR-001 |
| S6 no third-party telemetry | ADR-001 (structural), ADR-015 |
| S7 backup always encrypted; export may be plain | ADR-012 — separate code paths, deliberately |
| S8 switcher snapshot obscured | ADR-014 |
| P1–P7 privacy, minimisation, on-device processing, deletion, transparency | ADR-001, ADR-013, ADR-011, §4.2 `RawMessage` retention rules, §6.4 |
| C1–C5 compliance | §6.6 |
| A1 provenance | §4.2 `Transaction` (`provenance`, `sourceMessageId`, `rulePackId`/`ruleId`) |
| A2/A3 append-only history | ADR-010 |
| A4 exact decimal | ADR-002 |
| A5 explicit currency, no blind cross-currency sums | ADR-002 (throws), ADR-009 |
| A6 totals traceable, no orphan derived figures | §7.5 — no persisted derived totals |
| A7 never silently discard a financial SMS | ADR-007 step 4, ADR-017, §7.1 |
| R1 seconds latency | ADR-006 for the unlocked window; **ADR-018 supersedes the commitment while locked** (seconds from unlock, nothing lost). Reduction put to the human as **H-13** |
| R2 responsive main screen | §7.5 — Drift streams, isolates |
| R3 resumable non-blocking import | ADR-006, §7.2 |
| R4 fully offline | ADR-001 — offline is the only mode |
| R5 isolated parse failures | §7.1 |
| R6 no data loss on crash/restart | ADR-003 (`synchronous=FULL`, WAL), §7.2 (atomic watermark) |
| R7 reasonable battery/storage | ADR-006 — Layer 3 off by default |
| U1–U8 accessibility and RTL | §7.6 + `docs/design.md` (designer owns the visual half) |
| M1 rules updatable without redesign | ADR-007 + §5.2 |
| M2 testable against a corpus | §7.7 |
| M3 no real SMS in the repo | §7.7 — binds every agent |

---

*End of ADR. This document is a proposal. It becomes binding only when the human changes the
status line at the top to `APPROVED`. The solution-architect does not approve its own work.*
