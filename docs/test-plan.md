STATUS: IN PROGRESS — covers Epic 0 (Foundation), Epic A (SMS ingestion) and the
Epic B slice built by P3a (PR #11)

# Massrofy — Test Plan and Acceptance-Criteria Traceability Matrix

**Author:** qa-tester agent
**Date:** 2026-07-28
**Linear issue:** KHA-48
**Source of truth:** `docs/PRD.md` §5 (Acceptance Criteria), `docs/build-plan.md` §9 (P9 QA hardening), `docs/architecture.md` (ADRs)

> This document is written retroactively. QA should have started it during P0 per
> the build plan ("QA should be writing the traceability matrix during P0, not
> waiting for code") and run continuously alongside P2–P8. It did not — KHA-48 sat
> untouched in Backlog while P1 merged and P2 went up for review. This first
> version catches up on everything built so far (Epic 0 / P1, merged to `main`;
> Epic A / P2, on branch `feature/p2-sms-ingestion-parsing`, PR #2, **open, not yet
> merged** as of this writing) and must be extended phase-by-phase from here on,
> per the build plan's intent, so it never falls behind again.

---

## 1. Methodology — what was actually run, not just read

Every result below was produced by running the named command myself against the
real code, not by trusting a PR description. Environment: Flutter 3.44.8 (stable),
Dart 3.12.2, Android SDK 35.0.0 / build-tools 35.0.0, Temurin JDK 21, on Windows.

| Check | Command | Run against |
|---|---|---|
| Static analysis | `flutter analyze --fatal-infos` | `main` (P1) and `feature/p2-sms-ingestion-parsing` (P2, PR #2) |
| Formatting | `dart format --set-exit-if-changed .` | both |
| Unit + widget tests | `flutter test --exclude-tags=release_mode_guard` | both |
| Release-mode privacy-overlay guard (ADR-014) | `flutter test --dart-define=dart.vm.product=true --dart-define=MASSROFY_DISABLE_PRIVACY_OVERLAY=true test/features/security/privacy_overlay_release_mode_test.dart` | P2 branch (test file also exists on `main`, same result expected) |
| Money-type ban (ADR-002) | `bash .github/scripts/check_money_type_ban.sh` | P2 branch |
| No-network-permission guard (ADR-001), incl. a real `flutter build apk --release --target-platform android-arm64` and inspection of the merged release manifest | `bash .github/scripts/check_no_network_permission.sh` | P2 branch |

**Results, exactly as observed:**

| Branch | `flutter analyze --fatal-infos` | `dart format` | `flutter test` | Money-type guard | No-network guard |
|---|---|---|---|---|---|
| `main` (P1, merged) | 0 issues | clean | **146 tests: 143 passed, 3 skipped (desktop SQLCipher, honestly marked — see §4), 0 failed** | not re-run separately (superset re-run on P2 branch) | not re-run separately |
| `feature/p2-sms-ingestion-parsing` (P2, PR #2 open) | 0 issues | clean, 109 files, 0 changed | **476 tests: 473 passed, 3 skipped (same 3 as above), 0 failed** | PASS — no `double`/`num`/`SUM(`/`TOTAL(`/`AVG(` in a money-critical path | PASS — static manifest has both `tools:node="remove"` directives; **the real merged release manifest** (built fresh, `flutter build apk --release --target-platform android-arm64` succeeded) contains no `INTERNET`/`ACCESS_NETWORK_STATE` across every plugin (`flutter_secure_storage`, `local_auth`, `sqlcipher_flutter_libs`, `flutter_plugin_android_lifecycle`) |

### 1a. Second pass — P3a, PR #11 (`feature/p3a-domain-spine`, head `51bb730`)

Run 2026-07-28 in the same environment (Flutter 3.44.8 / Dart 3.12.2, Windows),
against a detached checkout of the PR head — **not** against the engineer's
working tree and not against the PR description.

| Check | Command | Result observed |
|---|---|---|
| Static analysis | `flutter analyze --fatal-infos` | **No issues found!** (4.8s) |
| Formatting | `dart format --set-exit-if-changed lib test integration_test` | **Formatted 142 files (0 changed)** |
| Money-type ban (ADR-002) | `bash .github/scripts/check_money_type_ban.sh` | **PASS** — no banned `double`/`num`/SQL aggregation |
| Unit + widget tests | `flutter test --exclude-tags=release_mode_guard` | **+628 ~3: All tests passed!** (3 skipped = the same desktop-SQLCipher trio as every previous pass) |
| QA's own adversarial suite (new, this pass) | `flutter test test/security/p3a_adversarial_test.dart` | **+18: All tests passed** — every attack repelled (§6a). With it added, the whole suite is **+646 ~3** |

**The engineer's claimed local numbers are reproducible exactly** (628 passing,
3 skipped, clean analyze/format/money-guard). `flutter build apk --debug` was not
re-run in this pass; it is not a QA gate and CI covers it.

**Independent verification of the two claims PR #11 makes about itself:**

1. **The P1 audit-chain defect was real, and the fix is correct.** Not taken on
   trust: I checked out the pre-PR `lib/data/dao/audit_log_dao.dart` from `main`
   (`git checkout c6879f3 -- lib/data/dao/audit_log_dao.dart`) over the PR's test
   file and re-ran `flutter test test/data/dao/audit_log_dao_test.dart`. Both new
   regression tests **fail** against the old code —
   `REGRESSION — a chain written with sub-second timestamps still verifies` and
   `a chain written with the real clock verifies`, each `Expected: true / Actual:
   <false>` — and both pass with the fix. That is proof the defect existed in
   merged, shipped code (`main`), that the two tests pin *this* defect and not an
   adjacent one, and that the fix works. The fix is also correct *by
   construction*, not by coincidence: `_toWholeSecondsUtc` is applied once,
   before both `_canonicalize` (which feeds the HMAC) and the insert, so the
   hashed value and the stored value are the same object. **One consequence the
   PR does not address — see D-QA-1 (`docs/defects.md`) / KHA-69: the fix is
   forward-only, so audit rows already on disk from a pre-P3a build stay
   un-verifiable.**
2. **The "silent drift codegen failure" claim is genuinely tested, not asserted.**
   `test/data/db/schema_v3_migration_test.dart` asserts foreign keys via
   `PRAGMA foreign_key_list` — SQLite's own metadata — on a fresh install *and*
   on a genuinely upgraded v2 database, so it fails if a constraint silently
   disappears again. Cross-checked three ways: the table declarations use
   `integer().customConstraint('NOT NULL REFERENCES bank(id)')`
   (`instrument_table.dart:48`, `:87`, `transaction_table.dart:155`); the
   generated `app_database.g.dart` carries the matching
   `$customConstraints: 'NOT NULL REFERENCES bank(id)'` / `'REFERENCES
   instrument(id)'`; and the constraint is proven *enforced*, not merely
   declared, by `bank_instrument_dao_test.dart`'s
   `the instrument cannot be orphaned — the foreign key is real` plus
   `PRAGMA foreign_keys = ON` in `app_database.dart:137`. My own adversarial
   suite re-confirms enforcement from the other end (§6a, attack 4).

The PR #2 description's own numbers (423 → 449 tests across two review rounds) are
now 476 after the third round (keyword-boundary fix, ADR-018 doc comments, KHA-58
citation) — consistent with the commit history on the branch. **Nothing in this
report is asserted from the PR text alone; every number above was reproduced.**

**Not reproduced in this pass (environment/time-boundedness, stated honestly):**
- `android-sqlcipher-integration-test` (the CI job that boots a real Android
  emulator to exercise SQLCipher) — confirmed **present and correctly wired** in
  `.github/workflows/ci.yml`, but not independently re-run here (would require
  booting a KVM-backed Linux emulator; this session ran on Windows against a real
  Android SDK, which is sufficient for a release *build* but not for booting that
  specific CI emulator job). This job is real CI coverage, distinct from — and a
  stronger claim than — the 3 tests skipped on the desktop `flutter test` host.
- No physical Android device or emulator instance was available in this session to
  exercise the SMS broadcast receiver, runtime permission grant, or the headless
  background `FlutterEngine` path end to end. This is the single largest
  verification gap in the build and is called out explicitly in §5.

---

## 2. How to read the matrix

Each row: **AC ID** (or NFR ID for Epic 0, which has no PRD acceptance criteria of
its own) → **Test case** (file + test/group name, cited exactly, not paraphrased)
→ **Test type** → **Result**.

Result values:
- **PASS** — an automated test exists, was run in this session, and passed.
- **PASS (partial)** — the testable slice passes; a stated part of the AC is not
  covered by any automated test (reason given).
- **GAP** — no automated test exists for this AC, or the AC requires evidence
  (typically a real device) that no automated test in this repo can produce.
- **N/A — not yet built** — the epic is not implemented yet (later phase).

---

## 3. Epic 0 — Foundation (P1, merged to `main` via PR #1)

The PRD's AC set (§5) does not define acceptance criteria for Epic 0 — it is
cross-cutting infrastructure that P1's "done checks" (build-plan.md §"P1 —
Foundation") describe instead, each traced to the NFRs it exists to satisfy. This
matrix uses those done-checks as the criteria.

| Done check (build-plan.md P1) | NFR(s) | Test case | Test type | Result |
|---|---|---|---|---|
| Money value type — no `double` in any money path; mixed-currency arithmetic fails loudly | NFR-A4, NFR-A5 | `test/core/money/money_test.dart` groups "Money.parse — construction and normalisation", "Arithmetic requires matching currencies (ADR-002 / NFR-A5)" (throws `CurrencyMismatchError`), "Property-style tests (ADR-002 enforcement item 3)" (commutativity/associativity/round-trip), "the only ways to construct a Money are the named factories" (API-surface golden test — no `Money.fromDouble`/`toDouble()`); `.github/scripts/check_money_type_ban.sh` (CI grep) | Unit + CI static check | **PASS** — script independently re-run, passes |
| FX conversion is explicit, traceable (rate + rate date), rounds deterministically | NFR-A5, AC-B9.3 (early, incidental) | `test/core/money/money_converter_test.dart` groups "MoneyConverter.convert (ADR-002 / ADR-009)", "ExchangeRate — traceability (AC-B9.3)" | Unit | PASS |
| Encrypted local datastore; DB file unreadable without the key; forward migration from empty install | NFR-S1, NFR-R6 | `test/data/db/app_database_encryption_test.dart` groups "the DB file on disk must not be readable/parseable without...", "PRAGMA-key interpolation is guarded by shape validation, not trusted...", "forward migration from an empty install" — **3 of these are `skip`-marked when run via `flutter test` on a desktop host** (no Android Keystore/SQLCipher native build on Windows/Linux/macOS — honestly documented in the file's own doc comment, confirmed by reading it); real coverage is `.github/workflows/ci.yml` job `android-sqlcipher-integration-test`, which runs `integration_test/db_encryption_test.dart` on a genuine Android emulator | Unit (3 skipped by design) + CI integration (emulator) | **PASS (partial)** — DAO/trigger/hash-chain logic is covered against a plain in-memory DB (`test/data/dao/*`); the SQLCipher-specific claim is covered by CI's emulator job, which I confirmed is correctly configured but did not re-run myself this session (§1) |
| Masking + redaction: a full PAN-like string is never persisted or logged; identifiers render masked everywhere | NFR-S2, NFR-C2 | `test/core/text/masking_test.dart` (`formatMaskedCardOrAccount`, `formatMaskedIban`); `test/core/text/sms_sanitizer_test.dart` groups "PAN redaction (Luhn-valid 13-19 digit runs)", "CVV/PIN/OTP redaction" | Unit | PASS |
| Append-only audit trail: any mutation writes an immutable history entry (actor, timestamp, before/after); update/delete against history fails | NFR-A1, NFR-A2, NFR-A3 | `test/data/dao/audit_log_dao_test.dart` groups "AuditLogDao.append / queryFor (ADR-010 API shape)" (no update/delete method exists), "a raw SQL UPDATE against audit_entry is aborted by the trigger", "a raw SQL DELETE against audit_entry is aborted by the trigger", "Hash chain (ADR-010 tamper evidence)", "append() is atomic" | Unit (against a plain in-memory DB with the same trigger DDL) | PASS |
| App lock: resumes locked; failed/cancelled auth never unlocks; switcher snapshot shows no figures | NFR-S3, NFR-S8, AC-F1.1, AC-F1.2, AC-F1.3 (early, incidental) | `test/features/security/app_lock_controller_test.dart` — in particular "FAILED OR CANCELLED AUTHENTICATION NEVER UNLOCKS (ADR-005 core guarantee)", "5 consecutive failures trigger lockout with exponential backoff", "ADR-005 lockout counter survives an app restart"; `test/widget/lock_gate_screen_test.dart` "AC-F1.2 — nothing that looks like transaction data, a total, or a card identifier is ever rendered on the lock gate"; `test/features/security/privacy_overlay_test.dart` + `test/features/security/privacy_overlay_release_mode_test.dart` (independently re-run under genuine `dart.vm.product=true` this session — §1) | Unit + widget | **PASS** |
| No sensitive values in logs (`SafeLogger` is the only entry point; `print`/`debugPrint` banned) | NFR-S4 | `test/core/logging/safe_logger_test.dart` group "SafeLogger — the only permitted logging entry point (ADR-015)"; `analysis_options.yaml`'s `avoid_print: true` lint rule, enforced by `flutter analyze --fatal-infos` (independently re-run, 0 issues — no `print(`/`debugPrint(` calls anywhere in `lib/`) | Unit + static analysis | **PASS** |

**Verdict for Epic 0: every P1 done-check has genuine, passing automated coverage.**
The one honestly-flagged gap (SQLCipher-on-desktop) has compensating CI coverage
(a real Android emulator job) that I confirmed is correctly configured but did not
personally re-execute.

---

## 4. Epic A — SMS ingestion (PRD §5, US-A1..A5, 19 ACs) — P2, PR #2 (open)

**Branch:** `feature/p2-sms-ingestion-parsing`. **Not yet merged as of this
report.** All results below were produced against that branch's actual code, not
the PR description.

| AC | Test case | Test type | Result |
|---|---|---|---|
| AC-A1.1 — granted access, new SMS arrives, transaction appears with no user action | `test/features/ingestion/ingestion_pipeline_test.dart` (the whole synthetic corpus, end to end: message → transaction) proves the **processing** half. The **delivery** half — a real `SMS_RECEIVED` broadcast actually reaching `SmsReceiver.kt` on a device/emulator — has no automated test anywhere in this repo | Unit (processing) / **device (delivery) — none exists** | **GAP** — device verification missing (see §5) |
| AC-A1.2 — no access granted, opens app, shows explanation + a way to grant, never a bare empty state | `test/widget/p2_screens_test.dart` group "S-02 — SMS permission rationale (AC-A1.2, design flag D-9)": shows all four guarantees before any OS dialog; offers both a grant path and a decline path; renders in Arabic RTL; does not overflow at 2.0 text scale | Widget | PASS |
| AC-A1.3 — access revoked mid-life, opens app, warns ingestion stopped AND existing data is intact | `test/widget/p2_screens_test.dart` group "S-04 — limited mode (AC-A1.2, AC-A1.3)": "always states that existing data is intact"; "the revoked banner carries BOTH halves of AC-A1.3"; "denied → retry", "permanentlyDenied → deep-link to Settings" | Widget | **PASS (partial)** — UI given a mocked permission state is fully tested; the underlying `SmsPermissionService` (`lib/features/ingestion/sms_permission_service.dart`) that actually detects revocation on each foreground has no dedicated unit test of its own (only exercised indirectly through the widget layer with a fake) |
| AC-A1.4 — SMS arrives while not foregrounded, next open, transaction already present | `test/features/ingestion/ingestion_pipeline_test.dart` group "ADR-006 — the watermark" (advances past every processed message; a second run picks up only what is new; monotonic under concurrent sweeps) + `test/features/ingestion/historical_importer_test.dart` "AC-A3.3 — interruption and resumption" (same watermark mechanism) prove the **self-healing sweep never loses a message**, at the logic level | Unit | **PASS (partial)** — logic-level guarantee proven; whether the periodic ~15-minute `WorkManager` sweep genuinely survives OEM battery managers / Doze on a real device is unverified (R-1, KHA-7). Separately: `runBackgroundIngestion()` (`lib/features/ingestion/background_entrypoint.dart`) — the ADR-018 no-op-while-locked path — has **no unit test of its own** (trivial function, `return true`, but untested) |
| AC-A2.1 — OTP SMS from a bank sender → no transaction | `test/features/parsing/rule_pack_corpus_test.dart:120`, fixture in `test/fixtures/synthetic_sms_corpus.dart:407` | Unit (corpus) | PASS |
| AC-A2.2 — marketing/promotional SMS from a bank sender → no transaction | Fixture `test/fixtures/synthetic_sms_corpus.dart:420`, run through `rule_pack_corpus_test.dart`'s bundled-pack assertions | Unit (corpus) | PASS |
| AC-A2.3 — SMS from a non-financial sender → no transaction | `test/features/parsing/rule_pack_corpus_test.dart:185` group "non-financial senders (AC-A2.3, NFR-P4)" | Unit (corpus) | PASS |
| AC-A2.4 — genuine purchase SMS from a configured financial sender → exactly one transaction | `test/features/parsing/rule_pack_corpus_test.dart:192` | Unit (corpus) | PASS |
| AC-A2.5 — balance-enquiry/informational SMS, no purchase → no spending transaction | Fixture `test/fixtures/synthetic_sms_corpus.dart:430`, exercised via `rule_pack_corpus_test.dart` and `ingestion_pipeline_test.dart` corpus runs | Unit (corpus) | PASS |
| AC-A3.1 — first-run import starts from the beginning of the current calendar month | `test/features/ingestion/historical_importer_test.dart` group "AC-A3.1 — the window is the current calendar month, in Riyadh": before-the-1st excluded; boundary computed in Asia/Riyadh, not UTC | Unit | PASS. Note: Asia/Riyadh is a hard-coded +03:00 constant (no `package:timezone`), correct for this one zone (no DST) — a documented, deliberate limitation (ADR-007 deviation #4), not a defect |
| AC-A3.2 — progress shown, app stays responsive during a large import | `test/features/ingestion/historical_importer_test.dart` group "AC-A3.2 — progress is reportable without exposing content"; `test/widget/p2_screens_test.dart` group "S-05 — import progress (AC-A3.2)": determinate bar + live count, indeterminate sweep state, no NaN on a zero total, user can leave (non-blocking), states the import scope | Unit + widget | **PASS (partial)** — functional behaviour is fully covered; actual UI responsiveness/frame-timing under a genuinely large real inbox (hundreds+ of messages) has no performance/instrumentation test |
| AC-A3.3 — interrupted import resumes without duplicating | `test/features/ingestion/historical_importer_test.dart` group "AC-A3.3 — interruption and resumption": resumes without duplicating; **even a total cursor loss cannot create duplicates** (relies on ADR-017 D1's `UNIQUE` constraints, not just the cursor); a completed import does no redundant work on re-run | Unit | **PASS** — strong coverage, including the adversarial "cursor is gone entirely" case |
| AC-A4.1 — unparsed financial SMS appears in "Needs review" with original (sanitised) text visible | `test/features/ingestion/ingestion_pipeline_test.dart:172`; `test/features/parsing/rule_pack_corpus_test.dart:166` (NFR-A7 group); `test/widget/p2_screens_test.dart` group "S-18 — Needs Review inbox": "shows the original (sanitised) message text", "explains WHY it could not be understood" | Unit + widget | PASS |
| AC-A4.2 — user fills in missing fields on an unparsed SMS → normal transaction created, item leaves the review list | `test/widget/p2_screens_test.dart:465` "offers both AC-A4.2 actions and wires them up" — **UI callback wiring only.** The action itself (constructing and persisting a real `Transaction` from user-supplied fields) needs the P3 domain model, which does not exist yet; P2 deliberately implements this as a passed-in callback, not a working create-transaction flow (disclosed in PR #2 §"Other deviations and gaps", item 9) | Widget (wiring only) | **GAP (by design, correctly scoped)** — not yet AC-satisfying end-to-end; re-test when P3 lands |
| AC-A4.3 — dismiss an unparsed SMS as "not a transaction" → removed from the list, never reappears on re-scan | `RawMessageDao.dismissAsNotTransaction()` exists (`lib/data/dao/raw_message_dao.dart`) and the review-queue query filters on `dismissedAsNotTransaction = 0`; `test/widget/p2_screens_test.dart:469-483` proves the **UI button invokes the dismiss callback with the right id**. **No test — DAO-level or pipeline-level — calls `dismissAsNotTransaction()` and then asserts (a) the item leaves the queue query and (b) re-ingesting the same message (same `contentHmac`) does not resurrect it.** `test/data/dao/raw_message_dao_test.dart` has 4 tests, none of them this one | Widget (partial) | **GAP (test coverage)** — the code reads correctly by inspection (the doc comment in `review_queue.dart` explains the "update, never delete" reasoning clearly, and D1's `UNIQUE` constraint on `contentHmac` would independently block a literal re-insert), but there is no regression test proving it. Recommend one to mobile-engineer before this is marked done |
| AC-A4.4 — any processed SMS that is neither a transaction nor in the review list is a defect; nothing is silently discarded | `test/features/parsing/rule_pack_corpus_test.dart` group "NFR-A7 — nothing is silently discarded"; `test/features/ingestion/ingestion_pipeline_test.dart` "NFR-A7 — every message is accounted for, none vanish"; structurally enforced by `ParseOutcome` being a **sealed type with no `dropped` case** and an exhaustive `switch` with no `default:` (confirmed by reading `lib/features/ingestion/ingestion_pipeline.dart`) | Unit + compile-time enforcement | **PASS — the best-covered AC in this set**, both by test and by the type system |
| AC-A5.1 — identical SMS delivered twice (carrier retry) → exactly one transaction | `test/features/ingestion/ingestion_pipeline_test.dart:289` "AC-A5.1, the content-HMAC key" | Unit | PASS |
| AC-A5.2 — two SMS from different senders describing the same transaction (auth + posting) → flagged for user confirmation, not silently merged/double-counted | `test/features/ingestion/ingestion_pipeline_test.dart:354`; `test/features/ingestion/duplicate_policy_test.dart` group "D3 — the heuristic tier" | Unit | PASS |
| AC-A5.3 — two genuinely separate purchases, same merchant/amount/day → both retained | `test/features/ingestion/ingestion_pipeline_test.dart:315`; `test/features/ingestion/duplicate_policy_test.dart:117` "outside the 15-minute window, two identical purchases are..." | Unit | PASS |

**Epic A tally: 19 ACs. 13 full PASS, 3 PASS (partial — the testable slice is
covered, a stated real-device or performance slice is not), 1 GAP by design
(AC-A4.2, correctly deferred to P3), 1 GAP — device (AC-A1.1), 1 test-coverage
GAP found by QA (AC-A4.3, §above). No AC in Epic A is unaccounted for.**

*(AC-A1.1's device gap and AC-A1.4's partial-device gap are, correctly, the same
underlying open risk — see §5. They're listed against both ACs because both name
it explicitly.)*

---

## 5. Open risks recorded, not invented — the two device-verification gaps

The task that produced this document specifically asked me to either verify or
formally record two items PR #2 itself flagged as unverified. I did not find a way
to close either from this environment; both are formally recorded here rather than
asserted-away:

1. **KHA-7 (the P0 background-SMS latency spike) has never been run.** Confirmed
   independently: the issue is still in **Backlog**, its only comment (dated
   2026-07-28) is the one already noting P2 shipped without its result. NFR-R1's
   "single-digit seconds" claim (as reduced by ADR-018 to "seconds from *unlock*,
   while locked") rests on ADR-006's latency table, which is explicitly
   "provisional on the P0 spike." **No new evidence exists to close this.**
2. **No automated test — unit, widget, or CI-integration — exercises the real
   Kotlin SMS receiver, the runtime `RECEIVE_SMS`/`READ_SMS` permission grant flow
   for a side-loaded APK, or the headless `FlutterEngine` background-isolate path**
   (`SmsReceiver.kt`, `SmsChannel.kt`, `IngestWorker.kt`, `IngestScheduler.kt`,
   `BootReceiver.kt`, `ForegroundIngestService.kt` — confirmed by searching
   `integration_test/` and `test/`, which contain no reference to any of these
   files). This is a **materially different verification posture than SQLCipher
   gets** in the same PR: ADR-003's encryption claim has a real CI job
   (`android-sqlcipher-integration-test`) booting a genuine Android emulator; the
   SMS-ingestion wake path has no equivalent. The Dart-side pipeline that runs
   *after* a message reaches the content provider is thoroughly tested (§4); the
   OS-level delivery *into* that pipeline is not tested at all.

Both risks are already disclosed in PR #2's "Honest limits" section and are
consistent with what I independently found — I am not raising anything PR #2 did
not already say. What this document adds is: (a) independent confirmation these
gaps are real and unchanged, (b) the precise AC and NFR references they leave
open (AC-A1.1, AC-A1.4, NFR-R1), and (c) a recommendation.

**Recommendation:** these should block neither PR #2's merge (the design is
watermark-based and self-healing — a suppressed broadcast degrades latency, it
does not lose data, per ADR-006/ADR-018) nor P3's start. They should block **P10's
device test** (build-plan.md's actual acceptance test — "a signed APK is installed
on the user's real device, ingests real SMS") and should be the first thing KHA-52
(E2E acceptance) exercises. I am not filing a new Linear bug for either — both are
already tracked (KHA-7 directly; the receiver/permission-flow gap is implicit in
KHA-7's scope and in PR #2's own text) and inventing a duplicate would only add
noise. I did add a QA-confirmation comment to KHA-7 (see below).

---

## 6. Security/privacy verification against what's built so far

| Claim | NFR | Verification | Result |
|---|---|---|---|
| Money is never a `double`/`num` in a money-critical path; no SQL `SUM`/`TOTAL`/`AVG` on a money column | NFR-A4, NFR-A5 | `.github/scripts/check_money_type_ban.sh` — read in full, confirmed it's a real grep-based CI guard (not a stub), independently re-run against the P2 branch | **PASS** |
| Sensitive values never reach logs/crash reports | NFR-S4 | `SafeLogger` unit tests + `avoid_print: true` lint rule enforced via `flutter analyze --fatal-infos` (independently re-run, 0 issues) | **PASS** |
| Full PAN / CVV / PIN / OTP never persisted, even briefly | NFR-S2, NFR-C2 | `test/core/text/sms_sanitizer_test.dart`, `sms_sanitizer_kha54_test.dart`, `sms_sanitizer_adr013_v11_test.dart`, `sms_sanitizer_keyword_boundary_test.dart` — all pass; assertions are exact-string, not `contains('[REDACTED]')` (per architecture.md's explicit testing obligation, which I confirmed the test files actually follow, e.g. `sms_sanitizer_test.dart`'s digit-window helper that checks no 3-digit fragment of a secret survives anywhere in the output) | **PASS** — this is the area with the deepest, most adversarial test coverage in the codebase, consistent with two rounds of dedicated review |
| No `INTERNET`/`ACCESS_NETWORK_STATE` in the shipped release build (AC-F4.2-style no-egress, for what's built so far) | ADR-001, AC-F4.2 | `.github/scripts/check_no_network_permission.sh`, independently re-run end to end including a genuine `flutter build apk --release --target-platform android-arm64` and inspection of every merged manifest fragment across every plugin | **PASS** — this is the strongest kind of evidence available without a live network-monitoring device session, and it is exactly what the ADR promised: a structural, CI-checkable guarantee rather than a claim |
| App-switcher snapshot never shows figures; no runtime bypass in a release build | NFR-S8, ADR-014 | `privacy_overlay_test.dart` + `privacy_overlay_release_mode_test.dart`, independently re-run under genuine `dart.vm.product=true` semantics | **PASS** |

No full network-monitoring session (e.g. mitmproxy against a running installed
APK) was performed — that requires a device, same constraint as §5. The static
guarantee (no network permission exists in the built artifact) is a stronger claim
than a monitoring session would add for what's built so far, since a network call
without the permission is not merely unobserved, it is impossible on Android.

### 6a. Adversarial security pass over P3a (new in this pass — QA-authored)

Per the banking-domain rule that attempted attacks are audit evidence whether or
not they succeed, I wrote and ran `test/security/p3a_adversarial_test.dart`
(18 tests, all passing) against the PR head. It does not restate the
implementation's own assertions; it attacks the feature.

**Threat model, stated honestly.** Massrofy is single-user, offline and has no
network permission (ADR-001), so there is no cross-tenant authorization boundary
to bypass and no remote attacker — "act on another user's account id" has no
meaning here. The two adversaries that *are* real are (a) attacker-controlled
**SMS text** that reaches storage, and (b) the device owner or another process
editing the database directly on a rooted device, which ADR-010 answers with
tamper-*evidence*. Both are exercised.

| Attack attempted | Result |
|---|---|
| **SQL injection** — 7 payloads (`'; DROP TABLE instrument;--`, `' OR '1'='1`, `Robert'); DROP TABLE transactions;--`, a subselect-concatenation payload, and one carrying an embedded NUL written as `\x00`, since a value that truncates a C string is the classic way past a naive check) as an instrument friendly name, as bank display names, as the S-19 merchant field, and as the currency code | **Repelled.** Every payload stored as literal text (proof it was bound, not spliced), schema intact, row counts unchanged, audit chain still verifying. The hostile currency code never reaches storage at all — `Money.tryParse` rejects it and the service returns `CompletionRejected` |
| **Identity forging via `refKey`** — a masked identifier containing the `:` separator (`bank-victim:card:4821`) to make one bank's message resolve to another bank's instrument | **Repelled.** `buildInstrumentRefKey` reduces the identifier to digits first, so no separator can be smuggled in; result is `bank-attacker:card:4821`. An unknown `kind` yields `null` (no mystery instrument) rather than a forged key |
| **Double-spend analogue** — two `UnparsedCompletionService.complete()` calls on the same queued message started concurrently (the check-then-write race the existing sequential test cannot reach) | **Repelled.** Exactly one transaction, one `CompletionAccepted`, one `CompletionMessageUnavailable`, queue empty, chain verifies. The single Drift transaction around read-check-write is what makes this hold |
| **Mass assignment / referential integrity** — an S-19 draft naming `instrumentId: 9999`, which does not exist | **Repelled.** SQLite's foreign key rejects it and the service's transaction rolls the whole unit back: no transaction row, and the message is still in the review queue (nothing lost, NFR-A7). This is also independent confirmation that the FK from deviation #1 is genuinely *enforced*, not merely declared |
| **Audit back-dating** — dropping the `audit_no_update` trigger (i.e. the strongest attacker ADR-010 contemplates) and shifting a stored `changed_at` by 60 seconds | **Detected.** `verifyChainIntegrity()` returns false. This is the exact column the P1 defect mis-hashed, so it also proves the fix did not weaken tamper-detection while making intact history verify |
| **Audit completeness** — a scripted 6-mutation sequence (bank create, 2 instrument creates, an enrichment, a rename, a settlement link) | **Exactly 6 audit rows, chain verifies.** No P3a mutation path bypasses the audit trail |
| **Money math** — 3-decimal KWD through storage; cross-currency blending; `Money.sum` with a foreign value in the bucket; refunds driving a period negative; `0.1` summed ten times | **All correct.** `12.345 KWD` keeps three decimals and `_minor` = 12345 (KWD's exponent, not a hard-coded 2); totals are per-currency sets with no blended figure to read; a mixed bucket throws rather than returning a wrong number; ten `0.1`s sum to exactly `1` |
| **Corrupted amount column** — rewriting `amount_amount` to `'not-a-number'` outside the app | **Observation, not an exploit** — the row silently disappears from every list and total with no signal (`toLedgerTransactionOrNull` returns null by design). Only reachable by editing the database outside the app, since the write path only ever stores `Money.toCanonicalString()`. Recorded as **O-QA-1** in `docs/defects.md` |
| **Negative amount typed on S-19** | **Observation, not an exploit** — accepted, and a `debit` of `-50` reduces the period total. Single-user and self-inflicted only, but two different inputs produce the same ledger effect. Recorded as **O-QA-2** and routed to KHA-26's form validation |

---

## 7. Epic B — the P3a slice (PR #11, `feature/p3a-domain-spine`, open)

**Scope of this section.** P3a is deliberately the *spine* half of P3 (build-plan
v1.2 §P3): the bank/instrument hierarchy (KHA-23), the real transaction record
(KHA-25) and the first half of KHA-64 (S-19 / AC-A4.2). KHA-24, 26, 27, 28, 29,
66 and KHA-64's enrichment merge are **not** in it. The rows below cover only the
ACs P3a actually claims; every other Epic B AC is listed in §7b as not-yet-built,
so nothing is quietly counted twice or quietly dropped.

Every test name below was read in the file and observed passing in this session's
run. Nothing here is copied from the PR description.

### 7a. Traceability — Epic B ACs in P3a's scope

| AC | Test case (file → test/group name, verbatim) | Test type | Result |
|---|---|---|---|
| AC-B1.1 — amount, currency, merchant, date-time, identifier and type all displayed | `test/widget/p3_screens_test.dart` group "S-11 — Transaction Detail (AC-B1.1..B1.4)" → `AC-B1.1 — amount, merchant, date-time, instrument and type…` | Widget | PASS |
| AC-B1.2 — original SMS text viewable from the detail view | same group → `AC-B1.2 — the original message is available, collapsed by…` and `a manual entry says there is no original message rather than…` | Widget | PASS. Note: the panel starts **collapsed** — a deliberate shoulder-surfing mitigation (NFR-S3), still "viewable" as the AC requires |
| AC-B1.3 — an absent optional field reads as explicitly unknown, never blank/zero/guessed | `test/data/dao/transaction_dao_p3_test.dart` group "AC-B1.3 — unknown is stored as unknown, never as a default" → `every optional field the message did not state is NULL in the row…` + `a genuine zero fee is stored as zero and is distinguishable from an…`; `test/widget/p3_screens_test.dart` → `AC-B1.3 — a field the message did not state reads as…` | Unit + widget | **PASS** — the zero-vs-unknown pair is the part that matters and it is tested on both sides |
| AC-B1.4 — displayed amount matches the SMS exactly, no rounding | `transaction_dao_p3_test.dart` group "AC-B1.4 — exact precision, no rounding, in and out of storage" (parameterised: `0.1`, `12.345 KWD`, `1234567.89`, … each `$amount $currency round-trips byte-identically`); `p3_screens_test.dart` → `AC-B1.4 — the amount is the exact stored decimal, with no…`; my own `test/security/p3a_adversarial_test.dart` → `a 3-decimal currency keeps all three decimals through storage (AC-B1.4)` (also asserts the non-authoritative `_minor` column uses KWD's exponent 3, not a hard-coded 2) | Unit + widget + QA adversarial | **PASS** |
| AC-B2.1 — each bank listed with its own totals; drilling in shows only its own instruments | `test/features/ledger/bank_tree_test.dart` group "AC-B2.1 — each bank has its own figure and only its own…" → `a bank node contains no instrument belonging to another bank`, `each bank total covers only its own transactions`; end-to-end in `test/features/ledger/ingestion_ledger_test.dart` → `drilling into a bank shows only its own instruments` | Unit | PASS |
| AC-B2.2 — two cards at one bank listed separately with their own period totals | `bank_tree_test.dart` group "AC-B2.2 / AC-B2.3 — per-instrument figures" → `two cards at the same bank carry their own respective totals` | Unit | PASS |
| AC-B2.3 — instrument detail lists only its transactions and the total equals their sum | `bank_tree_test.dart` → `NFR-A6 — the bank total equals the sum of its instruments, because…`; `test/features/ledger/period_totals_test.dart` group "AC-B2.3 — the total equals the sum of those transactions" → `three debits sum exactly`, `NFR-A4 — the arithmetic is exact decimal, not floating point`; `ingestion_ledger_test.dart` → `a per-instrument total equals the sum of exactly that instrument's…` (recomputed independently from raw rows — a genuine cross-check, not a re-assertion of the same code); `transaction_dao_p3_test.dart` → `forInstrument returns only that instrument, and excludes deleted…`; `p3_screens_test.dart` → `AC-B2.3 — only this instrument's transactions are listed, with its own total above them` | Unit + widget | **PASS** |
| AC-B3.1 — a rename appears everywhere the instrument is referenced | `test/data/dao/bank_instrument_dao_test.dart` → `AC-B3.1/B3.2 — a rename changes the label and NOT the match key…`; `bank_tree_test.dart` group "AC-B15.2 / AC-B3.1 — how an instrument is labelled" → `a renamed instrument is labelled by its friendly name`, `a whitespace-only name does not count as a name`; `p3_screens_test.dart` → `S-25 — the rename sheet returns the new name (AC-B3.1)` | Unit + widget | PASS |
| AC-B3.2 — a later SMS with that instrument's identifier attaches to the **renamed** instrument, not a new one | `bank_instrument_dao_test.dart` → `AC-B3.1/B3.2 — …so the next message attaches to the renamed instrument`; `ingestion_ledger_test.dart` group "AC-B3.1 / AC-B3.2 — a rename survives re-ingestion"; structurally guaranteed because `refKey` (`<bank>:<kind>:<last4>`) has no parameter through which a friendly name could reach it — I read `instrument_identity.dart` and `instrument_dao.rename()` to confirm the key is never rewritten | Unit | **PASS — structurally, not just behaviourally** |
| AC-B4.2 — saving is blocked with a message **naming** the missing field (S-19 slice only) | `test/features/ledger/unparsed_completion_test.dart` group "AC-B4.2 — validation names the field, and writes nothing" → `a missing amount is rejected by name`, `an unparseable currency is reported as a currency problem, not as a…`, `missing date and type are both reported…`, `a rejected attempt writes NO transaction and leaves the item in the queue`; `p3_screens_test.dart` → `AC-B4.2 — saving with no amount names the missing field and emits no draft` | Unit + widget | **PASS for the S-19 path only.** The manual-entry form the AC was written for is KHA-26 (not built) — recorded as partial so KHA-26 is still held to it |
| AC-B6.4 — a deletion is recorded with timestamp and prior values | `transaction_dao_p3_test.dart` group "soft delete records when (AC-B6.4)" → `deletedAt is set on delete and cleared on restore`; audit side covered by `audit_log_dao_test.dart` (P1) | Unit | **PASS (partial)** — the *storage* half is done; the change-history **view** an "auditor" would inspect is KHA-40 (P5) |
| AC-B7.1 — a credit decreases the period's spend | `period_totals_test.dart` group "AC-B7.1 — a credit reduces spend, never increases it" → `a refund subtracts from the period figure`, `a month with more refunds than purchases goes negative rather than…`; my adversarial suite → `a refund subtracts from spend and can drive a period negative, which must not be clamped` | Unit + QA adversarial | **PASS (incidental)** — full AC-B7.x ownership stays with KHA-28 |
| AC-B12.1 — a never-seen bank is created from sender/message content and the instrument placed under it | `bank_instrument_dao_test.dart` group "AC-B12.1 / AC-B15.1 — auto-creation on first mention"; `test/features/ledger/ledger_entity_resolver_test.dart`; `ingestion_ledger_test.dart` (full corpus through the real pipeline) | Unit | PASS. **Deviation worth the reviewer's eye, not a defect:** a bank row is created when a message produces a *transaction*, not when any recognised sender is seen. Documented in `ledger_entity_resolver.dart`; consistent with the AC's own "…**and** the account or card mentioned is placed under it" |
| AC-B12.2 — a bank page lists accounts and cards as two groups plus a combined bank total | `p3_screens_test.dart` group "S-22 — Bank Detail (AC-B12.2, AC-B13.3)" → `accounts and cards are separate segments, never one merged list`, `AC-B12.2 — the bank total is shown above the segments`, `a bank with no instruments says so instead of showing an empty segment` | Widget | PASS |
| AC-B12.3 — the same bank named differently in two SMS resolves to **one** entity | `test/features/ledger/bank_directory_test.dart` group "AC-B12.3 — one bank, many names" → Arabic name / English name / abbreviation all resolve; case and whitespace; Arabic spelling variants (`الجزيرة` vs `الجزيره`); branding punctuation (`D-360`/`D360`/`d 360`); **and the negative cases** `two different banks stay two banks`, `an unknown name resolves to nothing — it never invents a bank`, `is not fuzzy — similar-but-different names stay different`. End-to-end: `ingestion_ledger_test.dart` → `AC-B12.3 — exactly two banks, despite four distinct sender strings and both Arabic and Latin naming` | Unit + corpus | **PASS — the best-covered AC in this PR.** The corpus assertion is the strong one: identity leaking onto the sender string would produce a third row and fail it |
| AC-B13.1 — an account-shaped message creates/matches an **account** | `bank_instrument_dao_test.dart` → `an account and a card with the same last four coexist as two rows under one bank`; `test/features/ledger/instrument_identity_test.dart` → `AC-B13.1/2 — an account and a card sharing the last four are NOT…`; `ingestion_ledger_test.dart` → `AC-B13.1/B13.2 — instruments are typed from the rule…` | Unit + corpus | PASS — `kind` comes from the matched rule's declaration; I confirmed by reading `ledger_entity_resolver.dart` that there is **no** inference from digit length anywhere |
| AC-B13.2 — a card-shaped message creates/matches a **card** | same as AC-B13.1 | Unit + corpus | PASS |
| AC-B13.3 — account activity and card activity stay distinguishable, never merged | `bank_tree_test.dart` group "AC-B13.3 — account activity and card activity are never merged" → `accounts and cards are separate collections`; `p3_screens_test.dart` S-22 group | Unit + widget | PASS |
| AC-B14.1 — a card-repayment SMS naming card + source account records the link | `bank_instrument_dao_test.dart` group "US-B14 — the card to settlement-account link" → `AC-B14.1 — a repayment observation records the link and its source`, `a contradicting SMS observation does not overwrite an existing link`, `the user always outranks an SMS observation`; end-to-end `ingestion_ledger_test.dart` → `AC-B14.1 — the card-repayment templates produce a settlement link, and nothing else does` | Unit + corpus | **PASS** — including the "nothing else does" half, which is what stops a guessed link |
| AC-B14.2 — a linked card shows its settlement account | `bank_tree_test.dart` group "AC-B14.2 / AC-B14.3 — the settlement link" → `a linked card carries the account label for context`, `a link to an account with no friendly name falls back to its masked…`; `p3_screens_test.dart` → `AC-B14.2 — a linked card shows its settlement account` | Unit + widget | PASS |
| AC-B14.3 — an unlinked card is shown as unlinked, never guessed | `bank_instrument_dao_test.dart` → `AC-B14.3 — with no repayment message seen, the link stays null`; `p3_screens_test.dart` → `AC-B14.3 — an unlinked card says so neutrally, and offers no guess` | Unit + widget | PASS |
| AC-B15.1 — entities are auto-created with no setup step | `bank_instrument_dao_test.dart` → `the first mention creates the bank; there is no setup step`; `ingestion_ledger_test.dart` → `AC-B15.1 — every instrument was created with no user action, and each records the message that first mentioned it (NFR-A1)` | Unit + corpus | PASS |
| AC-B15.2 — an auto-created instrument is labelled by its raw (masked) identifier | `bank_tree_test.dart` → `an auto-created, not-yet-renamed instrument is labelled by its…`; `p3_screens_test.dart` → `AC-B15.2 — an auto-created card is labelled by its masked identifier and captioned as unnamed` | Unit + widget | PASS |
| **AC-A4.2** (Epic A, re-tested — was a scoped GAP in §4) — completing an unparsed SMS creates a normal transaction and the item leaves the review list | `unparsed_completion_test.dart` group "AC-A4.2 — the happy path" → `a queued message becomes a real transaction and leaves the queue`, `the message row is reclassified, never deleted…`, `NFR-A1 — provenance is SMS-with-manual-completion, and the source…`, `the completed transaction appears in period totals`, `AC-B1.4 — the amount the user typed is stored with its exact…`, `NFR-A2 — the audit entry names the USER as the actor, not the…`; group "the message is no longer completable" → `a message that was already completed cannot be completed twice`; `p3_screens_test.dart` S-19 group; my adversarial suite adds the **concurrent** case | Unit + widget + QA adversarial | **GAP → PASS.** This closes the one by-design gap §4 recorded against P2 |

**Epic B (P3a scope) tally: 20 AC rows — 17 full PASS, 3 PASS (partial), 0 FAIL.**
The three partials (AC-B4.2, AC-B6.4, AC-B7.1) are partial only because the rest
of each AC belongs to an issue that has not started (KHA-26, KHA-40, KHA-28); no
part of P3a's own claimed scope is untested.

### 7b. Epic B ACs deliberately NOT in P3a, and the schema gap one of them leaves

Recorded so the next pass does not have to rediscover the boundary:
AC-B5.x (edit), AC-B6.1–B6.3 (delete UI), AC-B8.x (Recently Deleted), AC-B9.1/B9.2
(multi-currency display and base-currency totals), AC-B10.x/B11.x (income,
withdrawals, internal transfers) and AC-B4.1/B4.3 (manual entry) are **not built**.
KHA-24/26/27/28/29 own them.

One item is worth a reviewer's attention because it is *visible in shipped UI*
rather than merely absent: **AC-B9.3** requires the conversion **rate and rate
date** to be visible. `transaction_detail_screen.dart:331` renders the exchange
rate, but architecture §4.2's `fxRateDate` / `fxRateSource` / `conversionPending`
columns were not added in schema v3, so there is no date to show. A rate the user
cannot date is exactly the traceability AC-B9.3 exists to require. Filed as
**D-QA-2** / **KHA-70** (`docs/defects.md`), related to KHA-27; **not** a P3a merge blocker,
because AC-B9.x is KHA-27's scope and the current display is honest about showing
only what the message stated.

### 7c. Epics C–I — not yet built

Per PRD §9: C (15 ACs), D (14), E (14), F (14), G (4), H (3), I (3) have no
implementation on `main` or on any open PR (build-plan P4–P8 have not started).
No test rows are invented for them.

---

## 8. Untestable-as-written criteria

None found in Epic 0, Epic A, or the Epic B slice built by P3a. Every AC in the
built scope is either automatable (and mostly is) or requires a real device (§5)
— which is a verification-environment constraint, not a wording problem with the
AC. No AC is being sent back to product-owner from either pass.

One Epic B AC is *loosely* worded rather than untestable and is called out here
so KHA-26 does not inherit an argument: **AC-B6.4** says "an auditor (the user)
inspects the change history", which mixes a storage guarantee with a UI that
belongs to a different phase (KHA-40). P3a satisfies the storage half. This does
not need a PRD change; it needs KHA-40 to cite AC-B6.4 explicitly, which it
already does.

---

## 9. Summary

| Epic | ACs / done-checks in scope | PASS | PASS (partial) | GAP | Status |
|---|---|---|---|---|---|
| 0 — Foundation (P1) | 8 done-checks | 7 | 1 (SQLCipher desktop-vs-emulator split) | 0 | Merged, main — verified |
| A — SMS ingestion (P2) | 19 ACs | 13 + 1 (AC-A4.2 closed by P3a) | 3 | 2 (1 device, 1 QA-found test gap → now KHA-66) | Merged — verified against the branch before merge |
| B — instruments/transactions, **P3a slice only** | 20 AC rows | 17 | 3 (each waiting on KHA-26/28/40, not on P3a) | 0 | **PR #11 open** — verified against head `51bb730` |
| B — remainder + C–I | ~139 ACs | — | — | — | Not yet built |

**Overall (pass 2, PR #11):** no defect found in P3a's own scope that would block
merge. Every check the engineer claimed was reproduced exactly (628 passing,
clean analyze/format/money-guard), both self-reported claims were independently
verified rather than accepted (§1a), and 18 QA-authored attacks were all repelled
(§6a). Three items were raised and none is a P3a blocker:

- **D-QA-1 → KHA-69** (medium) — audit rows written by any *pre-P3a* build will keep
  failing `verifyChainIntegrity()` forever, because the fix repairs the write
  path but not history already on disk. Blocking the PR would leave the worse bug
  in place; this needs deciding before any real install (P10).
- **D-QA-2 → KHA-70** (medium) — AC-B9.3: the FX rate is displayed with no rate date,
  because §4.2's `fxRateDate`/`fxRateSource` columns are not in schema v3. Routed
  to KHA-27, whose scope this is.
- **O-QA-1 / O-QA-2** (low) — a corrupted amount column silently drops a row from
  the ledger view; a negative amount typed on S-19 is accepted.

Carried forward, unchanged: the two device-verification gaps (§5) remain open and
belong on the P10/KHA-52 critical path.
