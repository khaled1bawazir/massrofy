STATUS: APPROVED

# Massrofy — Architecture Decision Record

**Version:** 1.3
**Date:** 2026-07-29 (v1.2: 2026-07-29; v1.1: 2026-07-28; v1.0: 2026-07-27)
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

---

## Changelog

| Version | Date | Change |
|---|---|---|
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

---

### ADR-007 — Parsing is a **data-driven rule pack**, not per-bank code.

**Answers A-6. Serves NFR-M1, NFR-M2. Mitigates R-4, R-11.**

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

---

### ADR-008 — Merchant normalisation is a canonical-key pipeline with an explicit **alias table**; matching is tiered and never silently wrong.

**Answers A-7. Mitigates R-5. Serves US-D1..D5, AC-D2.3, AC-D2.4.**
**Amended by the KHA-98 decision (v1.3, 2026-07-29)** — the dated subsection at the end of this
ADR. Three things below are **superseded and annotated rather than deleted**, per this document's
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
> the kind above, (ii) a digit run corroborated as a store/terminal/reference number, (iii)
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
   - **(ii) Length** — the run is **≥ 4 digits**. Four or more digits is a till, terminal or
     reference id, not a branch number a human says out loud.
4. **Leading digits keep their existing protection.** `7 ELEVEN` must survive. That asymmetry was
   already deliberate and already documented in `merchant_key.dart`; it stands.

The `4` is a named constant beside `autoApplyThreshold` (suggested: `referenceDigitRunMinLength`),
tunable against the corpus, with the same posture as **O-1**: the *value* is tuning, the *bar* is
not. Consequences on synthetic input:

- `QAMART 100` / `QAMART 200` → keys differ. Jaccard 0.33 → no T3. Damerau-Levenshtein ratio
  1 − 1/10 = **0.90**, which meets the T4 floor — so this pair surfaces as *"did you mean QAMART
  100?"*, `canAutoApply` false, `needsReview` true. **That is the ideal outcome, not a
  consolation:** the app says what it noticed and lets the person decide.
- `CAFE 1` / `CAFE 2` → keys differ; DL ratio 0.83, below the T4 floor → `none` + `needsReview`.
- `QAMART 100 200 300` → `QAMART 100 200 300` (rule 1 and rule 3 both decline).
- `PANDA STORE 1234` → `PANDA` (adjacency corroboration). `PANDA 1234` → `PANDA` (length
  corroboration). Both preserved.

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
1/2 = 0.5, below the 0.80 floor; the pair falls through to T4 and becomes a suggestion that can
never auto-apply.

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
| **D1 — exact** | `smsProviderId` UNIQUE (re-scan idempotency, AC-A3.3) **and** `contentHmac = HMAC-SHA256(k, normalisedBody‖sender‖smsTimestamp)` UNIQUE (carrier retry, AC-A5.1) | **Suppress silently**, but write a diagnostic event recording the suppression. Storing an HMAC rather than the text keeps the dedup index non-reversible. |
| **D2 — reference number** | same `referenceNumber` + same instrument (PRD §3.4 confirms transfers carry these) | Treat as the same transaction. If it enriches an existing record, **merge — and write an audit entry recording the merge.** Never a silent destruction. |
| **D3 — heuristic** | same instrument + same amount + same currency + \|Δt\| ≤ 15 min, and (merchant equal **or** one message is an authorisation-type and the other a posting-type) | **Flag as a possible duplicate for user confirmation. Never auto-remove.** Both remain in the list and in totals until the user decides. |

**The bias is explicit and deliberate.** AC-A5.2 (auth vs posting alerts) and AC-A5.3 (two
genuine identical purchases the same day) pull in opposite directions, and only one of the two
failure modes is recoverable: an inflated total is visible and fixable, a silently deleted real
transaction is invisible and unfixable. **We bias hard toward flagging.** Banking default:
prefer the auditable, recoverable error.

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
`paused`) · `importCursor` · `importFromDate` (start of current calendar month, per AC-A3.1)

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

### 8.2 Residual open questions I am deliberately **not** deciding here

| # | Item | Why deferred, and where it lands |
|---|---|---|
| **O-1** | **The numeric value of `autoApplyThreshold`** (residual OQ-14). Initial **0.85**, and the token-set/edit-distance constants alongside it | These must be **tuned against the synthetic corpus in P4**, not guessed in P0. Deciding a number now would be false precision. The architecture pins the *structure* — one named constant, one place, tiered matching where T4 can never auto-apply — so tuning never requires a redesign. The observable bar (AC-D2.3/D2.4: match or flag, never silently miscategorise) is enforced regardless of the value. **Reaffirmed at v1.3, with one correction to how the bar is guaranteed:** KHA-98 showed that the bar is *not* enforced by tier structure alone, because a normalisation collision arrives at T1 already merged and never meets a gate. The bar is now enforced by the tier structure **plus** the corroboration rule in ADR-008's KHA-98 subsection. 0.85 is unchanged; `referenceDigitRunMinLength = 4` joins it as a tunable with the same posture |
| **O-2** | **Rule-pack signing for imported packs.** v1 ships unsigned, mitigated by declarative-only rules, a regex timeout, mandatory user review of the diff, and no network permission | Signing needs a key-distribution story that only matters once packs are shared beyond the user. Revisit if that changes |
| **O-3** | **Exact wording of the erase-all cloud-trash warning** (ADR-011) and the backup-freshness copy (ADR-012) | Designer's call (D-10), with the architectural facts fixed here |
| **O-4** | Whether the diagnostic ring buffer should survive erase-all for post-mortem purposes | Currently: it is wiped, because AC-F3.1 says "all data". Raise only if production-support finds this blocking |
| **O-5** | **`setInvalidatedByBiometricEnrollment` shipped as `false` in P1, where ADR-004 specifies `true`.** Observed while researching KHA-56; **not** part of either escalation and **not** decided here. The engineer's reasoning is sound and documented in `KeystoreChannel.kt`: `true` is only safe once `unwrapWithRecoverySecret` is real, which is Epic I / P8, and shipping it today would mean the first biometric re-enrolment permanently destroys the database with no way back | **This must flip to `true` in P8, in the same PR that makes the recovery path real.** Until then H-5's stated posture is not yet in force and the human should know that. Recommend a Linear issue blocking P8 exit so it cannot be forgotten — silence here is how a temporary deviation becomes permanent |
| **O-6** | **Generic IBAN detection via the ISO 7064 mod-97-10 check** (ADR-013 §13.5 SHOULD), covering foreign counterparty IBANs on outbound international transfers | Deferred as additional surface on an already-large open PR, not because it is doubtful. It is the exact analogue of Luhn and would be precise rather than blunt. Pick it up in P3 or as a standalone hardening issue |

### 8.3 Risk register updates (against build-plan §6)

| Risk | Status after this ADR |
|---|---|
| **R-1** background SMS reliability | **Re-characterised at v1.1 by ADR-018, and largely dissolved.** Three-layer design still stands for the *unlocked* case (1–3 s normal, ~15 min worst case, opt-in foreground service for hostile OEMs). But while the app is **locked** — the normal state — no layer can write, so OEM broadcast suppression stops mattering: the unconditional post-unlock sweep catches everything either way. **R-1's remaining exposure is confined to the unlocked window.** The residual risk has moved from "will a broadcast arrive" to "does the post-unlock sweep complete before the user reads a total" — which ADR-018 decision 3 answers with a mandatory updating state. KHA-7 narrowed accordingly (H-6) |
| **R-2** backup key recovery | **Closed.** App-generated 128-bit Recovery Phrase, HKDF/Argon2id, salt in the cleartext envelope header, nothing device-bound required to restore (ADR-004, ADR-012). QA must test restore on a device that has never seen the original Keystore |
| **R-3** exact decimal money | **Closed by construction.** `Money` cannot round-trip a float; cross-currency arithmetic throws; CI bans `double` in money paths and `SUM()` on money columns (ADR-002) |
| **R-4** parser brittleness | **Mitigated.** Data-driven rule packs, importable without an APK reinstall, corpus regression in CI, review queue as the never-lose-a-message safety net (ADR-007) |
| **R-5** cross-script merchant matching | **Re-characterised at v1.3, and the mitigation was incomplete as written.** The alias table and the never-auto-applying fuzzy tier stand. What v1.0 missed is that **the normalisation pipeline was itself a merge mechanism** — KHA-98/KHA-99/KHA-102 all merged unrelated merchants *upstream of every tier*, at confidence 1.00, where no gate exists. R-5's real surface was never only "too loose vs too strict matching"; it was also "too aggressive normalisation", which is invisible to every control the ADR named. Closed by the corroboration rule (ADR-008, KHA-98 decision), which bounds what normalisation may collapse and pushes everything else onto a user-created, auditable, **reversible** alias link |
| **R-16** merchant re-key migration window *(added 2026-07-29; the manager's KHA-98 brief calls this "R-17" — **R-16 is the correct next free ID**: `docs/build-plan.md` v1.4 ends at R-15 and no R-16 or R-17 exists in either document)* | **Open, time-boxed, and it expires on a human action.** The KHA-98 fix changes `MerchantKey.of`'s output, which on a populated install would require a re-key migration that can *split* one merchant row into two — meaning re-attribution of historical transactions by `merchantRawText` and one audit entry per row. That migration is **not** written, on the stated premise that no install holds a `merchant` row (schema v7 landed today; no v7 build has reached a device; KHA-88 and the PR #20 device gate are still open). **The premise is procedural, not structural**, and a routed UI is not needed to break it — the categorizer is already bound into live ingestion, so one ingested SMS on an unlocked v7 install populates the table. Land the fix before the P3b-3 device run. Full expiry condition in ADR-008's KHA-98 subsection. **Owner: mobile-engineer (fix), manager (sequencing).** |
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
| A-7 merchant normalisation, matching, confidence threshold | **ADR-008** + its **KHA-98 decision** (v1.3) — the corroboration rule is the normative answer to "what may normalisation collapse"; threshold value is residual **O-1** |
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
