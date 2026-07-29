STATUS: IN PROGRESS — covers Epic 0 (Foundation), Epic A (SMS ingestion), the
Epic B slice built by P3a (PR #11), the P3b-1 slice (PR #18) and the P3b-2
mutation surface (PR #20)

# Massrofy — Test Plan and Acceptance-Criteria Traceability Matrix

**Author:** qa-tester agent
**Date:** 2026-07-29 (pass 4); 2026-07-28 (passes 1–3)
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

### 7d. Third pass — P3b-1, PR #18 (`feature/p3b-1-currency-refunds-transfers`, head `3ba320d`)

Run 2026-07-29, same environment (Flutter 3.44.8 / Dart 3.12.2, Temurin JDK 21,
Windows), against a checkout of the PR head SHA verified to equal
`3ba320d61f762793adc02b52b0de67dfd669ea62`. Nothing below is copied from the PR
description; every command was re-run and every cited test name was read in the
file and observed passing in this session's run.

| Check | Command | Engineer claimed | QA observed |
|---|---|---|---|
| Static analysis | `flutter analyze --fatal-infos` | No issues | **No issues found (9.4s)** — matches |
| Formatting | `dart format --set-exit-if-changed lib test integration_test` | 159 files, 0 changed | **159 files, 0 changed** — matches |
| Unit + widget tests | `flutter test --exclude-tags=release_mode_guard` | "+782 ~3", body text says 784 | **+784 ~3, exit 0** — matches the 784 figure; the 3 skips are the pre-existing desktop-SQLCipher cases, unchanged by this PR |
| Money-type ban (ADR-002) | `bash .github/scripts/check_money_type_ban.sh` | clean | **clean** — re-checked by hand against the four new columns: `fxRateDate` is `DateTimeColumn`, `fxRateSource`/`internalTransferGroupId`/`internalTransferState` are `TextColumn`, `conversionPending` is `BoolColumn`. No `real()`/`double`/`num` introduced |
| Android build | `flutter build apk --debug` | succeeds | **succeeds** (`app-debug.apk`, 192.9s) |

**Audit-trail invariant re-checked (NFR-A2/NFR-R6):** `TransactionDao` has seven
mutating methods and seven `auditLogDao.append(...)` calls, each inside the same
Drift `transaction()` block. PR #18 adds **no** new mutation method — the FX and
internal-transfer columns ride on the two existing insert paths — so the P3a
audit verification carries forward unchanged.

#### QA-authored probe suite

Because two of this PR's claims are corrections to previously-filed defects, they
were verified by executing code rather than by reading doc comments.
`test/security/qa_pr18_probe_test.dart` (11 tests, all passing) is the evidence.
It is QA-authored and is **not** part of the engineer's claimed coverage.

| Probe | What it attacks | Result |
|---|---|---|
| A1 | `insertFromParsedSms` with `-50.00 SAR` | **Repelled** — `ArgumentError`, `transactions` table empty. Note the guard throws *synchronously*, before the `Future` exists |
| A2 | `insertManualCompletion` with `-50.00 SAR` | **Repelled** — same |
| A3 | `TransactionDao.create()` with `-1.500 KWD` | **SUCCEEDED — see D-QA-3.** Row stored (`amountAmount = '-1.5'`, `amountMinor = -1500`) with a well-formed audit entry |
| A4 | Does that negative row invert a total? | **Yes** — a debit carrying a negative magnitude yields `-50` net spend: the exact O-QA-2 shape, still reachable through the unguarded path |
| B1 | Refund **larger** than the original charge (not covered by AC-B7.2 or by `combined_totals_test`) | **Correct** — `100 − 250 = −150`, not clamped; `netKept = 150` |
| B2 | Three-transaction foreign over-refund, each leg on its **own** rate (`sms_implied` then `sms_stated 3.60`) | **Correct** — `+450.12 − 450.12 − 72.00 = −72.00`. No rate bleeds between transactions |
| C1 | Internal transfer where the **incoming** leg has no resolved instrument | Counted as spend (safe over-statement) but `needsReviewCount == 0` — **see D-QA-4** |
| C2 | Month-boundary transfer (31 Jul out / 1 Aug in) | **Correct with the real callers.** `report()` runs the detector over the whole live set, so the pair is seen and July excludes it. Pre-filtering the list first yields `2000` instead — a documented sharp edge, not a live bug: `periodReportProvider` and `bankTreeProvider` both pass the full `watchLive()` stream |
| C3 | Cross-currency internal transfer (2000 SAR out / 533.19 USD in, same reference) | Not paired (correct — no invented rate) but `needsReviewCount == 0`, contradicting the file's own doc — **see D-QA-4** |
| C4 | Unproven candidate pair — does it inflate income as well as spend? | Yes, both by 2000; but `netKept` stays invariant at `0` and both legs are flagged (`needsReviewCount == 2`). Acceptable |
| D1 | Is the per-instrument exclusion assertion strong, or could it pass for a weaker reason? | **Genuinely strong** — see below |

#### Verification of the three headline claims

1. **Sign convention (`lib/core/money/sign_convention.dart`).** Independently
   confirmed on the two paths the PR names: the DAO rejects a negative magnitude
   and writes nothing. The *ingestion* half was confirmed by reading
   `ingestion_pipeline.dart:585` (`amount == null || violationForAmount(amount) != null`
   → `rawMessageDao.insert(classification: 'financial_unparsed')`,
   `routedToReviewQueue + 1`) — the branch is correct but **has no test**
   (O-QA-4), because the bundled pack cannot produce a negative amount and no
   synthetic pack fixture was added. The claim "there is no negative number
   anywhere in the transaction table" is **false as stated** (D-QA-3).

2. **`combined_totals_test.dart` arithmetic.** Every hand-calculated figure in
   the comments was re-computed independently and all are correct:
   `152.75 + 450.12 − 187.46 + 800.00 − 75.00 = 1140.41`; the stated-rate leg
   `20.00 × 3.7500 = 75.00`; native SAR `952.75` / USD `50.01` / EUR `35`;
   card slice `152.75 + 450.12 − 187.46 − 75.00 = 340.41`; bank tree
   `800 + 0 + 340.41 = 1140.41`; `netKept 14500 − 1140.41 = 13359.59`;
   soft-delete `1140.41 + 187.46 = 1327.87`; unproven variant `1140.41 + 2000 = 3140.41`;
   USD-base `+120.00 − 49.99 − 20.00 = 50.01`. **No arithmetic error found.**

3. **Is the slicing assertion real?** Yes, and this was the specific thing
   checked. `tx()` defaults `affectsSpend: true`, and fixture 5 (the internal
   leg) does **not** override it, so its exclusion cannot come from the pack
   veto. Fixture 10 is the *same* `transfer_out` type on the *same* instrument
   and **is** counted (800.00), so the exclusion cannot come from the transaction
   type either. The only remaining explanation is the whole-ledger pair analysis
   `BankTreeBuilder` hands down. Probe D1 reproduces this in isolation
   (`analyze()` returns `internal` for the paired leg and `null` for the
   unpaired one on the same instrument). **The assertion proves what it claims.**
   *One weaker row noted:* the savings-account assertion (`totals.base` is null)
   would also pass because that leg carries `affectsSpend: false` and is
   `transferIn` (income) — it is not load-bearing. Not a defect.

4. **The `transfer_out` fix.** Confirmed the old behaviour was wrong against the
   codebase's own definition: `internal_transfer.dart:333-345` requires both legs
   to resolve to *different, known* instruments with matching amount+currency
   inside a 24h window — a property of the **pair**, which an S-19 form filling
   one leg cannot observe. So `'transfer_out'` in `_nonSpendTypes` dropped genuine
   third-party payments. The regression test
   (`p3b_screens_test.dart` → `an outgoing transfer completed by hand now COUNTS as spend…`)
   drives the real widget and asserts `affectsSpend == true`, and probe D1 confirms
   the classifier still excludes the *paired* case. Fix and test both correct.

#### 7d-i. Traceability — Epic B ACs claimed by KHA-27 / KHA-28 / KHA-29 / KHA-70

| AC | Test case (file → test name, verbatim) | Type | Result |
|---|---|---|---|
| **AC-B7.1** — a refund/credit is recorded as a credit and **decreases** period spend | `period_totals_test.dart` group "AC-B7.1 — a credit reduces spend, never increases it" → `a refund subtracts from the period figure`, `a month with more refunds than purchases goes negative rather than…`; `spend_classification_test.dart` (refund → `spendCredit`); `combined_totals_test.dart` → `net spend in the base currency is 1,140.41 SAR`; QA probe B1 (over-refund → `−150`, uncovered by the engineer's suite) | Unit + QA probe | **PASS** |
| **AC-B7.2** — charge + refund net to zero, or to the difference | `p3b_ingestion_totals_test.dart` group "AC-B7.2 — a charge and its full refund net to zero" → `Aljazira's card: 187.46 charged, 187.46 refunded, and the card's…` (asserts a *computed* `0.00` with `isEmpty == false`, not an empty state) and `D360's card: 450.12 charged, 187.46 refunded, net 262.66 — a…`. Both run through the real pack → parser → DAO → schema v4 → mapper → totals | Integration | **PASS (partial)** — the AC says *"the net effect on that **category** is zero"*. There is no `Category` table until P4, so the netting is proven at the instrument/period level only. Flagged so P4 is still held to the category half |
| **AC-B7.3** — a credit is visually distinct from a debit (NFR-U4: not colour alone) | `p3b_screens_test.dart` group "AC-B7.3 / NFR-U4 — a credit is distinguishable without colour" → `a credit is "+", a debit is "−", and each carries a spoken…` | Widget | **PASS** — sign + semantic label, so it survives greyscale and a screen reader |
| **AC-B9.1** — both native and converted amounts displayed | `p3b_screens_test.dart` → `AC-B9.1 — a foreign transaction shows BOTH its native amount…` | Widget | **PASS** |
| **AC-B9.2** — period totals computed in the base currency from each transaction's **recorded** conversion, never by summing across currencies | `base_currency_test.dart` (ADR-009 cases 1–4, incl. `no rate is invented; the value is explicitly unavailable`, `a malformed stored rate degrades to "not converted", never to a…`, `a zero or negative stored rate is refused — it would convert real…`); `combined_totals_test.dart` → `the native per-currency breakdown reconciles with the same five…` and `the EUR purchase is missing from the base figure AND visible on the…`; `p3b_screens_test.dart` group "AC-B9.2 — the \"not converted\" line"; QA probe B2 (per-leg rates do not bleed) | Unit + widget + QA probe | **PASS** — the strongest AC in this PR. `Money.sum` throws `CurrencyMismatchError` if a wrong-currency value ever reaches a bucket, so NFR-A5 is enforced at runtime as well as by the type |
| **AC-B9.3 / KHA-70** — the rate **and rate date** are inspectable | `p3b_screens_test.dart` → `**the KHA-70 done check**: a rate is NEVER rendered without…` (the widget half) and `AC-B9.3 — the rate source is stated in words, so the user…`; `p3b_ingestion_totals_test.dart` → `**KHA-70's DAO done-check**: a message stating no rate stores NULL…`, `a message stating the rate stores it verbatim, with the movement…`, `a message giving both amounts but no rate stores the IMPLIED rate,…`; `base_currency_test.dart` → `**the KHA-70 case**: when the message stated no time, the rate date…` | Widget + integration | **PASS — KHA-70 closed.** Both halves of the issue's own done-check are present. The `occurredAtUtc`-not-`occurredAt` distinction was verified in `ingestion_pipeline.dart:612-623`: a delivery-time fallback leaves the rate date NULL rather than fabricating one |
| **AC-B10.1** — salary is recorded as income, not spend | `p3b_ingestion_totals_test.dart` → `AC-B10.1 — a salary message becomes income, not spend`; `p3b_screens_test.dart` → `AC-B10.1 — salary is offered, and choosing it sets the…`; `spend_classification_test.dart` | Integration + widget | **PASS (partial)** — the AC's second clause, *"visible in a distinct income view"*, is not built. The figure ships inside the Spent-vs-Kept card; a dedicated income screen is P5. Disclosed in the PR body |
| **AC-B10.2** — an ATM withdrawal is recorded as a withdrawal | `p3b_ingestion_totals_test.dart` → `AC-B10.2 — an ATM withdrawal is a withdrawal, and is in neither…`; `spend_classification_test.dart` (`cashWithdrawal`); `p3b_screens_test.dart` → `AC-B10.2 — a cash withdrawal is a debit that does not count…`; `combined_totals_test.dart` asserts `cashWithdrawals.base == 500` reported but never subtracted | Integration + widget | **PASS (partial)** — the "later reclassify the cash as spending via manual entry" clause needs KHA-26's manual entry (P3b-2) |
| **AC-B10.3** — "spent vs kept" nets spend against income | `combined_totals_test.dart` → `AC-B10.3 — spent vs kept nets income against spend and nothing…` (`14500 − 1140.41 = 13359.59`, hand-checked); `p3b_screens_test.dart` group "S-32 Spent vs Kept — AC-B10.3" → `every component of the netting is on screen, so the user can…`, `cash withdrawn and internal transfers are shown but NOT…`, `a period that spent more than it received shows a negative…`, `with no data at all it says so, rather than showing 0.00`, `an incomplete report says the figures are incomplete` | Unit + widget | **PASS** — `netKept` correctly returns `null` (not zero) when a component holds unconvertible transactions, which is the subtle half |
| **AC-B11.1** — internal transfers excluded from all spend totals | `internal_transfer_test.dart`; `combined_totals_test.dart` → `the internal transfer is excluded from spend and shown as its own…` and **`**the slicing test**: a per-instrument total still excludes the internal transfer, even though its partner leg is on another instrument`**; QA probe D1 independently reproduces the discrimination | Unit + QA probe | **PASS** — verified strong, not incidental (see "Is the slicing assertion real?" above). **Partial on the AC's second clause** (*"and category breakdowns"*) — no `Category` table until P4 |
| **AC-B11.2** — an undeterminable transfer is **flagged for review**, not silently classified | `internal_transfer_test.dart`; `combined_totals_test.dart` group "AC-B11.2 — the same month with an UNPROVEN internal transfer" → `the candidate keeps counting as spend — 1,140.41 + 2,000.00`, `…and the user is told the figure is provisional`; `p3b_screens_test.dart` → `an unproven candidate says it is still being counted —…`, `a persisted state on the row is used when the caller passes…` | Unit + widget | **PASS (partial) — two named gaps.** (a) A transfer the detector cannot *pair at all* — cross-currency, or a leg whose instrument did not resolve — is counted as spend with **no** review flag (QA probes C1/C3, **D-QA-4**). (b) Derived candidates do not reach the Needs Review inbox and cannot be confirmed — disclosed by the engineer and tracked as **KHA-78** |
| **NFR-A5** — no hard-coded base currency | `base_currency_test.dart` group "NFR-A5 — the base currency is a parameter, not an assumption"; `combined_totals_test.dart` → `the same month reported in USD converts what it can and reports…` (`50.01` USD, 3 unconverted, SAR never blended in) | Unit | **PASS** |
| **NFR-A6** — no derived figure that cannot be traced to its constituents | `combined_totals_test.dart` → `the bank total equals the sum of its instruments, which equals the…`; the detector is a pure function with nothing cached (read, confirmed); every `PeriodTotals` carries `transactionCount` beside its figure | Unit | **PASS** |
| **PRD §3.4** — the FX fee is its own field, never folded into spend | `combined_totals_test.dart` → `the FX fee is its own figure and is not inside net spend…` (pins that spend is *not* `1151.66`); `base_currency_test.dart` group "the FX fee converts on its own terms (PRD §3.4)" incl. `a fee in a third currency with no rate is NOT silently added to a…` | Unit | **PASS** |
| **Schema v4 migration** | `schema_v4_migration_test.dart`; `schema_v3_migration_test.dart` (updated to strip v4's columns — the "duplicate column name" trap the PR body calls out) | Unit | **PASS** |
| **O-QA-2 (from pass 2) — a negative amount typed on S-19** | `p3a_adversarial_test.dart` → `a NEGATIVE amount can no longer reach the ledger — O-QA-2, closed at…` (the test that used to *assert the defect* now asserts the fix) and `zero is still a valid amount — it is a different fact from unknown…`; `sign_convention_test.dart` (7 tests); QA probes A1/A2 | Unit + QA probe | **CLOSED at the domain layer**, with the caveat in D-QA-3. The form-level message is KHA-26's half, still open |

**P3b-1 tally: 15 AC/invariant rows — 9 full PASS, 6 PASS (partial), 0 FAIL.**
Every partial is partial because the remainder of the AC belongs to an issue that
has not started (P4 categories, P5 income view, KHA-26, KHA-78) — except
AC-B11.2's gap (a), which is new and is filed as D-QA-4.

#### 7d-ii. QA-found items on PR #18 (none merge-blocking)

| Ref | Severity | Summary |
|---|---|---|
| **D-QA-3** | Medium | `TransactionDao.create()` carries no `checkMovementAmount` guard and stores a negative amount with a valid audit entry. No production caller today, so not exploitable — but it falsifies the PR's "no negative number anywhere in the transaction table", and `transaction_dao_test.dart:173` (`a negative KWD amount preserves its sign correctly`) **actively pins the wrong invariant**, so closing the gap means changing a currently-green test |
| **D-QA-4** | Low–Medium | A transfer the detector cannot pair *at all* (cross-currency legs, or a leg whose instrument did not resolve) is counted as spend with no review flag, though `internal_transfer.dart:338-341` says such transfers *"stay visible as spend **and as a review item**"*. AC-B11.2's flag is only produced for *paired* candidates |
| **O-QA-3** | Low | `ingestion_pipeline.dart:578` says *"a negative **or zero** magnitude is as unusable as a missing one"* and the comment below says a zero amount *"must never happen"* — both contradict `sign_convention.dart`'s deliberate "zero is valid" (KHA-25) and the passing test that pins it. The **code** is right; the comment invites a future engineer to "fix" it and break KHA-25 |
| **O-QA-4** | Low | The ingestion negative-amount → review-queue branch has no test. It is the NFR-A7 half of the O-QA-2 closure claim; only the DAO half is covered. Reachable only via an imported pack (risk R-11), which is exactly the scenario it was written for |

### 7e. Fourth pass — P3b-2, PR #20 (`feature/p3b-2-mutation-surface`, head `61efd7b`)

**Scope:** seven Linear issues (KHA-26, KHA-64 second half, KHA-66, KHA-74,
KHA-78, KHA-79, KHA-80) plus the recorded KHA-69 decision. `security-sensitive`.
Schema v5 (`user_edited_fields`, `merged_into_id`, `merged_from_transaction_id`).

#### Reproduction of the engineer's claimed local gates

Every gate was re-run by QA on this machine against head `61efd7b`, not read
from the PR body:

| Claimed | Reproduced | Result |
|---|---|---|
| `flutter analyze --fatal-infos` → No issues found! | yes | **MATCH** — clean in 4.7s |
| `dart format --set-exit-if-changed .` → 181 files, 0 changed | yes | **MATCH** — exit 0 |
| `flutter test --exclude-tags=release_mode_guard` → `+986 ~3` | yes | **MATCH** — 986 passing, 3 skipped, 0 failing |
| `flutter build apk --debug` → built | yes | **MATCH** — `app-debug.apk`, exit 0 |
| `.github/scripts/check_money_type_ban.sh` | yes | **MATCH** — no banned usage |

With QA's own probe suites added the tree runs **1023 passing / 3 skipped / 0
failing**. `check_no_network_permission.sh` was **not** run (needs a release
build + merged manifest); CI owns it, and the PR says so.

#### QA-authored probe suite for PR #20

`test/security/qa_pr20_probe_test.dart` (33 probes) and
`test/security/qa_pr20_probe_rescan_test.dart` (4 probes). Deliberately lopsided
toward the merge: `docs/build-plan.md` calls it *"the single highest-risk
operation in P3"*, so it got roughly two thirds of the attack surface.

| Probe | Attack | Outcome |
|---|---|---|
| **A1** | Merge a row carrying an FX **fee** into one that has none | **DEFECT D-QA-5** — the fee total drops from 9.20 SAR to *nothing*. `MergeEnrichment` has no fee field, and the fee's only carrier is soft-deleted |
| **A2** | Merge a **converted** foreign purchase into an unconverted duplicate | **DEFECT D-QA-6** — base-currency spend drops from 150 SAR to *null*. The mergeable row that could be converted is discarded; the survivor cannot be |
| **A3** | Check the blast radius of A2 | Repelled — the native `40.00 USD` figure survives and is reported as `unconverted`, so the damage is bounded to the base view |
| **A4** | Root cause: does `MergePlan.between` compare fee/converted at all? | Confirmed it does **not** — refusal covers amount, currency, direction, type only |
| **B1** | Is the "both keep their own `sourceMessageId`" claim real? | **Repelled — the claim holds**, verified by execution |
| **B2** | Absorb a **second** duplicate into the same survivor | **DEFECT D-QA-7** — `merged_from_transaction_id` is a scalar; the first pointer is silently overwritten |
| **B3** | Undo the **first** of two merges into one survivor | **DEFECT D-QA-8 (high)** — the survivor's pointer to the *second* absorbed row is cleared, the two rows' links now contradict each other, and the survivor gains **no audit entry** for the write |
| **B4** | Minimal case of the same NFR-A2 gap (single merge, then undo) | **DEFECT D-QA-8** — the survivor's history reads "merge" with no reversal |
| **B5** | Does a merge hide the absorbed row's audit history? | Repelled — both histories queryable by id, chain intact |
| **B6** | Build a merge **chain** (a→b, then b→c) | **DEFECT D-QA-9 (low)** — chains are permitted in the survivor direction; the PR's own test named *"no chains"* pins only the absorbed direction |
| **B7** | **Concurrent** merges of the same row into two different survivors | Repelled — exactly one completes, the loser sees `notLive`, money is right, chain intact |
| **C1** | `confirmedByUser: false` | Repelled — nothing read, nothing written, no audit entry |
| **C2** | Reach `TransactionDao.mergeDuplicatePair` outside the service | Reachable (public method, `actor` defaults to `'user'`); no production caller today. **Observation O-QA-5** |
| **C3** | Does a refusal mutate anything? | Repelled — no audit entry, no column change |
| **D1** | Merge over a field the user deliberately **cleared** | **Repelled — the nastiest AC-B5.3 case genuinely holds** |
| **D2** | Put the user's edit on the **losing** side of the merge | **DEFECT D-QA-10** — the parser's value on the survivor wins; the user's correction leaves every screen |
| **D3** | Does a user value **copied** onto the survivor inherit its protection? | **DEFECT D-QA-11** — it does not; the survivor holds a user value the app believes is the parser's |
| **D4** | Can a merge blank a populated field? | **Repelled — behaviourally confirmed**, not just type-shape asserted |
| **D5** | Is the protected set actually written on edit? | Repelled — it is |
| **E1–E4** | Negative magnitude through `create()`, `insertManual()`, `applyUserEdit()`, `insertFromParsedSms()`, `insertManualCompletion()` | **All repelled — KHA-79 genuinely closed at all five DAO write paths** |
| **E5** | Is zero accepted? | Accepted, and that is the documented KHA-25 decision, not a hole |
| **E6** | Raw Drift insert, bypassing the DAO | Succeeds — no CHECK constraint on the column. Unreachable from app code. **Observation O-QA-6**, relevant to P7 |
| **F1** | Does confirming a transfer remove it from the next total? | Repelled — **KHA-78 works**; both legs leave spend |
| **F2** | Does rejecting stop the detector re-proposing? | Repelled — `external` persists, `stateFor`/`unpairableReasonFor` both honour it |
| **F3** | Is the two-leg decision atomic and audited? | Repelled — one `transaction()`, one audit entry per leg, chain intact |
| **F4** | Soft delete → restore with the same id | Repelled — `create/delete/restore` on one id, AC-B8.2 literal |
| **F5** | Is a merge undo recorded as such? | Repelled — `create/merge/restore` on the absorbed row |
| **F6** | Does undo reverse the **enrichment**? | **DEFECT D-QA-12 (low)** — it does not; both rows end up claiming the same merchant. The doc says "reverses the whole thing" |
| **G1** | Corrupt `amount_amount` | Repelled — **KHA-74 works**; surfaced as `UnreadableTransaction`, not dropped |
| **G2** | Unknown currency code | Not caught — `Money` does not validate currency codes, so the library doc over-claims. Benign (the row is visible and reported `unconverted`). **Observation O-QA-7** |
| **rescan ×4** | Edit merchant / amount / clear-a-field, then re-scan through the **real pipeline** twice | **All repelled — AC-B5.3's re-scan half genuinely holds.** But PR #20 had **no** such test; see D-QA-13 |

#### Independent verification of the four claimed structural merge properties

Re-derived from behaviour, not from the doc comment:

1. **"Nothing is destroyed."** **HOLDS.** No probe produced a hard delete. B1/B5
   confirm both rows and both audit histories survive with pointers each way —
   *for a single merge*. It degrades after a second merge into the same
   survivor (D-QA-7) and breaks on the undo path (D-QA-8).
2. **"Both sides keep their own `sourceMessageId`."** **HOLDS, verified by
   execution** (B1). NFR-A6's literal traceability is met.
3. **"`confirmedByUser` is required with no default; `false` writes nothing."**
   **HOLDS** (C1). Grep of `lib/` confirms one call site. Caveat O-QA-5: the DAO
   method underneath is public with `actor` defaulting to `'user'`, so the
   control is the service layer plus a test, not the type system.
4. **"`MergeEnrichment` cannot express 'write null'."** **HOLDS for the five
   fields it carries** (D1/D4). It is **false as a statement about the merge**:
   the fields it does *not* carry (fee, converted amount, FX rate) leave the
   ledger with the soft-deleted row — D-QA-5/D-QA-6. The type-level property is
   real; the safety conclusion drawn from it is wider than the type.

#### Independent verification of the KHA-69 decision (checkable, and checked)

The load-bearing claim is *"the first successful real-device unlock was on
`56e9cbaa`, which already contains the P3a timestamp fix."* QA verified both
halves against the repository rather than accepting them:

- `git log 56e9cbaa` shows `8e549d8` (P3a, PR #11) as an ancestor — **true**.
- `git show 56e9cbaa:lib/data/dao/audit_log_dao.dart` contains
  `_toWholeSecondsUtc` at lines 112 and 201 — **true**.

The remaining premise ("no device unlocked an earlier build") is a claim about
human device history that no test can settle. The ADR states this and makes the
decision **void** if falsified, with the clean-install condition binding at P10 —
which is the honest framing. **Accepted.** One follow-up: the standing condition
lives only in prose and should be a checklist item on the P10 issue (KHA-52), or
it evaporates exactly like the AC-A4.3 follow-up that became KHA-66.

#### 7e-i. Traceability — every AC claimed by PR #20's seven issues

| AC / done-check | Test case (file → test name) | Type | Result |
|---|---|---|---|
| **AC-B4.1** — a manual transaction joins all totals/breakdowns | `manual_entry_test.dart` group "AC-B4.1 — the transaction joins every total and breakdown" (4 tests: cash purchase, refund nets, withdrawal is neither, hand-entered transfer counts) | Unit | **PASS** |
| **AC-B4.2** — a missing required field blocks saving and **names** the field | `manual_entry_test.dart` group "AC-B4.2 — validation names the missing field" (6 tests incl. unreadable amount naming both fields) | Unit | **PASS** |
| **AC-B4.3** — manual transactions visually distinguishable | `manual_entry_test.dart` group "AC-B4.3"; `p3b2_screens_test.dart` (S-20 form, Manual badge) | Unit + widget | **PASS** |
| **AC-B5.1** — an edit corrects the value everywhere | `transaction_edit_test.dart` group "AC-B5.1" (merchant, amount→total, missing row, no-op save) | Unit | **PASS** |
| **AC-B5.2** — detail view shows **both** original and edited value | `transaction_edit_test.dart` group "AC-B5.2" (4 tests, incl. "after THREE edits the original is still the parser's value" and "a `system_rule` update does not become a claimed user original") | Unit | **PASS** — read from the audit trail, not a duplicate column; verified the three-edit case is genuinely load-bearing |
| **AC-B5.3** — a later automated write must not overwrite a user edit | *Merge half:* `transaction_edit_test.dart` group "AC-B5.3" (3 tests) + QA probes D1/D4. *Re-scan half:* **no test in PR #20**; QA supplied `qa_pr20_probe_rescan_test.dart` (4 tests) and it passes | Unit + QA probe | **PASS (partial) — D-QA-13.** The property holds; KHA-26's own done-check names "edit-then-rescan preserves the edit" and PR #20 does not contain it. Also **D-QA-10/D-QA-11**: the rule is "don't overwrite the survivor", which is narrower than "user intent outranks the parser, always" |
| **AC-B6.1** — deleting removes it from lists and recalculates totals | `transaction_edit_test.dart` → `AC-B6.1 — a deleted transaction is out of every total`; QA probe F4; `deleted_transaction_rescan_test.dart` → `the period total stays without it across the re-scan` | Unit + integration + QA probe | **PASS** |
| **AC-B6.2** — deletion requires explicit confirmation | `p3b2_screens_test.dart` (S-11 delete confirmation dialog, cancel clause); `transaction_detail_screen.dart:166` `_confirmDelete` | Widget | **PASS** — the widget the engineer's self-review found missing is present and tested |
| **AC-B6.3** — a deleted transaction is not resurrected by re-scanning its SMS | `deleted_transaction_rescan_test.dart` (8 tests, **real `IngestionPipeline` + real rule pack**, both mechanisms asserted independently) | Integration | **PASS** — verified this is a genuine pipeline test, not a mock |
| **AC-B6.4** — every operation writes an audit entry with before/after and actor | `transaction_dao_p3b2_test.dart`; QA probes F3/F4/F5/B3/B4 | Unit + QA probe | **PASS (partial) — D-QA-8.** True for create/edit/delete/restore/merge/transfer-decision on the *subject* row. **False for the survivor row on the merge-undo path**: `restore()` writes to the survivor's `merged_from_transaction_id` and appends no entry against the survivor |
| **AC-B8.1** — deletion is soft; the row moves to Recently Deleted | `transaction_edit_test.dart` → `AC-B8.1 — the deleted row is retained, not destroyed`; `recently_deleted_screen.dart` + `p3b2_screens_test.dart` (S-44) | Unit + widget | **PASS** |
| **AC-B8.2** — restore returns it with full prior history | QA probe F4 (`create/delete/restore` on one id); `deleted_transaction_rescan_test.dart` → `the deleted row is retained, so US-B8 restore still works…` | Integration + QA probe | **PASS** — same row id, so the history is addressable; verified by execution |
| **AC-B8.3** — erase-all leaves nothing restorable | none | — | **NOT TESTED — disclosed by the engineer, filed as KHA-86.** Erase-all does not exist (ADR-011, Epic F). Accepted: the deferral and its issue were created in the same action, per `docs/lessons.md` |
| **AC-A4.2** — an unparsed message can be completed into a real transaction | `unparsed_completion.dart` + P3a tests; `complete_unparsed_screen.dart` | Integration + widget | **PASS** (closed in P3a; unchanged here) |
| **AC-A4.3** — a dismissed message stays dismissed across a full re-scan | `dismissed_message_rescan_test.dart` (7 tests, calls `dismissAsNotTransaction()` directly, real re-scan, ×5 repeats, DB-level column assertion) | Integration | **PASS — KHA-66 closed.** Flipped from GAP; the done-check is met literally |
| **AC-A5.2** — a possible duplicate is flagged and mergeable by explicit action | `transaction_merge_test.dart` (19 tests); QA probes A/B/C/D | Unit + QA probe | **PASS (partial)** — the merge works and is user-confirmed, but see D-QA-5/6/7/8/10/11 for what it loses on the way |
| **AC-A5.3** — two genuine identical purchases can be kept | `needs_review_screen.dart` "Keep both" offered with equal prominence; `p3b2_screens_test.dart` | Widget | **PASS** |
| **AC-B11.2** — an undeterminable transfer is flagged, not silently classified | `internal_transfer_unpairable_test.dart` (16 tests: cross-currency near-match, unresolved instrument, both legs flagged, lone transfer correctly **not** flagged); `internal_transfer_decision_test.dart` (13); `p3b2_screens_test.dart` transfers tab; inverted `qa_pr18_probe_test.dart` PROBE C; QA probes F1/F2/F3 | Unit + widget + QA probe | **PASS — D-QA-4 (KHA-80) and KHA-78 both closed.** Was PASS (partial) in pass 3. Confirming removes both legs from spend; rejecting persists and survives re-derivation |
| **KHA-74 / O-QA-1** — an unparsable amount is reported, not silently dropped | `ledger_mapping_unreadable_test.dart` (8 tests); `p3b2_screens_test.dart` (S-18 renders defects above the tabs); QA probe G1 | Unit + widget + QA probe | **PASS** |
| **KHA-79 / D-QA-3** — every DAO write path refuses a negative magnitude | `transaction_dao_test.dart` → `a negative KWD amount is REJECTED at the write boundary (KHA-79)`; inverted `qa_pr18_probe_test.dart` (2 probes); QA probes E1–E4 | Unit + QA probe | **PASS — closed.** QA verified the previously-green wrong-invariant test was genuinely **inverted, not skipped or deleted**: the old body asserted `amountMinor == -1500`, the new one asserts `throwsA(isA<ArgumentError>())` and that no row and no audit entry are written. Residual O-QA-6 (no CHECK constraint) |
| **KHA-69 / D-QA-1** — the audit-chain decision is recorded | `docs/architecture.md` v1.2 §ADR-010 subsection; `schema_v5_migration_test.dart` (5 tests: upgrade leaves `verifyChainIntegrity()` true; migration writes **no** `audit_entry` row of its own) | Doc + unit | **PASS — decided (option a), evidence independently re-verified against git.** See above. Follow-up: put the clean-install condition on KHA-52 |
| **NFR-A2** — mutation and audit entry in one `transaction()` block | `transaction_dao_p3b2_test.dart` (incl. mid-decision failure rolls the first leg back); QA probes F3/B3/B4 | Unit + QA probe | **PASS (partial) — D-QA-8** on the restore/undo path only |
| **NFR-A6** — every derived figure traces to its constituents | QA probes B1/B5; `transaction_merge_test.dart` | Unit + QA probe | **PASS (partial)** — literal for a single merge; degrades after a second merge (D-QA-7) and is left self-contradictory by the undo path (D-QA-8) |
| **R-8** — never silently delete a real transaction | whole probe suite | QA probe | **UPHELD.** No probe made a transaction row disappear. Every finding is a *derived figure* or a *pointer* problem, never a lost row — the asymmetry R-8 asks for is genuinely built in |
| **Schema v5 migration** | `schema_v5_migration_test.dart`; `schema_v4_migration_test.dart` and `schema_v3_migration_test.dart` updated to strip v5's columns | Unit | **PASS** |

**P3b-2 tally: 25 AC/invariant rows — 17 full PASS, 6 PASS (partial), 1 NOT
TESTED (disclosed, ticketed as KHA-86), 0 FAIL.**

#### 7e-ii. QA-found items on PR #20

None is merge-blocking: no probe lost a transaction row, no probe merged without
confirmation, and no probe got a negative magnitude past the DAO. Every finding
is either a derived figure that a *user-initiated, reversible* action degrades,
or a traceability/audit-completeness gap.

| Ref | Severity | Summary |
|---|---|---|
| **D-QA-5** | **High** | A merge silently removes the absorbed row's **FX fee** from the fee total. `MergeEnrichment` has no fee field and `MergePlan.between` does not compare fees, so a mergeable pair may disagree about a real charge. Probe A1 |
| **D-QA-6** | **High** | A merge can drop a foreign purchase out of the **base-currency spend total** entirely, when the survivor is the unconverted row. `convertedAmount`/`fxRate` are neither compared nor carried. Probe A2 |
| **D-QA-7** | Medium | A survivor that absorbs a **second** duplicate silently forgets the first: `merged_from_transaction_id` is a single scalar. Probe B2 |
| **D-QA-8** | **High** | `restore()` unconditionally clears `merged_from_transaction_id` on `existing.mergedIntoId` without checking it refers to the row being restored, corrupting the survivor's link to a *different* absorbed row — **and writes no audit entry against the survivor at all**, on any undo. Probes B3/B4 |
| **D-QA-9** | Low | Merge **chains** are possible in the survivor direction (a→b then b→c), contradicting the PR test named "no chains". Probe B6 |
| **D-QA-10** | Medium | A user edit on the **losing** side of a merge is discarded in favour of the parser's value on the survivor. AC-B5.3 says user intent outranks the parser *always*; the implementation says "do not overwrite the survivor". Probe D2 |
| **D-QA-11** | Medium | A user-authored value **copied onto the survivor** by a merge does not inherit `user_edited_fields` protection, so the next automated write (P7 import, another merge) may overwrite it. Probe D3 |
| **D-QA-12** | Low | Undoing a merge does not reverse the **enrichment**, so both rows end up claiming the same merchant/reference. The doc comment says restore "reverses the whole thing". Probe F6 |
| **D-QA-13** | Low | **AC-B5.3's re-scan half has no test in PR #20**, though KHA-26's done-check names it ("edit-then-rescan preserves the edit") and the symmetric AC-B6.3 case got one during self-review. The property holds — QA supplied `qa_pr20_probe_rescan_test.dart` |
| **O-QA-5** | Observation | `TransactionDao.mergeDuplicatePair` is public with `actor` defaulting to `'user'`. The "never automatic" control is the service layer plus a test, not the type system. No production caller today |
| **O-QA-6** | Observation | No CHECK constraint on `amount_amount`; a raw Drift insert still stores a negative magnitude and inverts a total. Unreachable from app code; relevant when P7 adds statement import |
| **O-QA-7** | Observation | `ledger_mapping.dart`'s doc says an unreadable row includes "a currency code this build does not understand". `Money` performs no currency validation, so that half is not implemented. Benign — such a row is visible and reported `unconverted` |
| **O-QA-8** | Observation | The merge button in the review inbox fires on a single tap with no confirmation dialog, while soft delete — a strictly less dangerous operation — owns one (AC-B6.2). `confirmedByUser` would be set by the not-yet-written caller. Worth an in-screen confirmation before the merge is ever routed |
| **O-QA-9** | Observation | None of P3b-2's providers (`transactionMergeServiceProvider`, `manualEntryServiceProvider`, …) has a production consumer, because the app shell still routes only to `HomePlaceholderScreen`. Consistent across the whole screen layer, pre-existing, and disclosed by the PR's own "nothing here has run on a device" — noted so "its only caller is a user action in the review inbox" is read as *intent*, not as a present fact |

### 7f. Fifth pass — P3b-3, PR #24 (`fix/p3b-3-merge-money-invariants`, head `8761e3e`)

**Scope:** the merge-safety gate. KHA-87 (High), KHA-88 (High), KHA-89 (Medium),
KHA-90 (O-QA-5 / O-QA-7 / O-QA-8 only). `security-sensitive`. No schema change.
This is the **second adversarial round on the same merge operation** — PR #20's
probes are now the fixed baseline, so this pass deliberately attacks past them.

**Gate note (per `docs/lessons.md`, 2026-07-29):** every result below was
measured by QA on this machine against head **`8761e3e`**, not read from the PR
body. Flutter 3.44.8 stable, Dart 3.12.2.

#### Reproduction of the engineer's claimed local gates

| Claimed on `8761e3e` | Reproduced | Result |
|---|---|---|
| `flutter analyze --fatal-infos` → No issues found! | yes | **MATCH** — clean in 5.5s |
| `dart format --set-exit-if-changed .` → 183 files, 0 changed | yes | **MATCH** — exit 0 |
| `flutter test --exclude-tags=release_mode_guard` → `+1040 ~3` | yes | **MATCH** — 1040 passing, 3 skipped, 0 failing |
| `flutter build apk --debug` → built | yes | **MATCH** — `app-debug.apk`, exit 0 |
| `.github/scripts/check_money_type_ban.sh` | yes | **MATCH** — no banned `double`/`num`/SQL-aggregation usage |

With QA's own `test/security/qa_pr24_probe_test.dart` (17 probes) added the tree
runs **1057 passing / 3 skipped / 0 failing**, still analyze- and format-clean.
`check_no_network_permission.sh` was **not** run (needs a release build + merged
manifest); CI owns it. Evidence: `docs/evidence/qa-pr24/`.

#### QA-authored probe suite for PR #24

`test/security/qa_pr24_probe_test.dart`. The one judgment call in this PR is the
**hybrid** rule — refuse on genuine disagreement, gap-fill on absence — so the
suite is aimed squarely at it: can the null-detection be fooled, does the
verbatim `MoneyColumns` copy propagate an inconsistency, and do the new refusals
survive *composition* rather than only the single-step case the fix's own tests
cover.

| Probe | Attack | Outcome |
|---|---|---|
| **H1** | Is a stored **zero** fee mistaken for a gap and overwritten? (KHA-25 says zero ≠ unknown) | **Repelled, both directions** — `MoneyColumns.read` is a strict null check, so `0` vs `9.20` is `feeDiffers` |
| **H2** | Can the verbatim triple copy pair one row's `_minor` with another row's amount? | **Repelled** — `fillMoney` returns the incoming triple whole or null; all three columns are written from one object. Question 2 of the review brief answered: the reasoning holds |
| **H3** | Feed the gap-fill a **half-written** triple (amount present, currency null) | **DEFECT D-QA-14** — reads as an absence, so `9.20` is silently overwritten by `5.00` with no refusal. The null-detection *can* be fooled |
| **H4** | Give the survivor a converted amount and the other row a contradicting **rate** | **DEFECT D-QA-15** — no single FX field collides, so nothing refuses; the survivor ends up stating `150 SAR` beside a rate of `9.99` on `40.00 USD` |
| **H5** | Does a gap-filled `fx_rate` actually move `report.spend.base`? | Confirmed **yes** (ADR-009 case 3) — establishes that H4 operates on a money write, not a label. The intended behaviour, asserted to set H4's severity floor |
| **H6** | Carry an **unparseable** rate onto a `conversion_pending` survivor | **DEFECT D-QA-16** — the pending flag is cleared because *a string arrived*, without checking it converts. Bounded: the "not converted" line is derived from the conversion attempt, not the flag |
| **J1** | Compose D-QA-7's scalar-pointer overwrite with an undo, then merge the survivor away | **DEFECT D-QA-17 (Medium)** — `MergeRefusal.chainWouldForm` is **defeated**. `first → survivor → newSurvivor` forms, exactly the shape B6 asserts is refused |
| **J2** | Three-way merge in the intended order: can the *result* absorb a third alert and keep what it gained? | **Repelled — holds.** Fee from merge 1 and merchant from merge 2 both survive; one movement, one fee |
| **J3** | Does a **carried** fee become a real disagreement for a later merge? | **Repelled — holds.** The third alert's `5.00` is refused against the carried `9.20` |
| **J4** | Undo a merge that carried money | **Observation O-QA-10** — the fee total goes `9.2 → 9.2 → 18.4`. D-QA-12's "don't un-enrich" was decided for descriptive fields and now also preserves money. Consistent with the amount, which doubles too; R-8's safe direction |
| **J5** | Is the internal-transfer verdict genuinely carried **as a pair** with its group id? | **Repelled — holds.** State + group id both land; the `internal` verdict removes the survivor from spend. Question 3 of the review brief answered |
| **J6** | Survivor holds a verdict with **no** group id; absorbed row holds the same verdict **with** one | **DEFECT D-QA-18 (Low)** — the carry is gated on the *state* being null, so the group id is never filled. The survivor keeps the "half a decision" the pairing exists to prevent |
| **J7** | Does a user-set `category_id` on the losing row genuinely refuse, and write nothing? | **Repelled — holds.** `userEditDiffers`, and neither row is touched (asserted against the audit log, not only `isDeleted`). Question 4 of the review brief answered |
| **J8** | Same, but a **rule-assigned** category (not in `user_edited_fields`) | **DEFECT D-QA-19 (Low)** — neither compared, nor carried, nor refused. The KHA-87 shape, on a non-money column, still present |
| **K1** | Is the KHA-87 "forcing function" schema-derived, or a hand-written list? | **DEFECT D-QA-20 (Low)** — hand-written. A schema-derived version (written in the probe, from Drift's own `$columns`) immediately names two columns with **no recorded decision**: `provenance`, `provenance_detail` |
| **L1** | Is the `merge_undo` entry really in the same DB transaction as the write it describes, with a real before/after? | **Repelled — holds.** Survivor `updated_at` and entry `changed_at` are the same instant (one `timestamp`, one `transaction()` block); the entry carries `mergedFromTransactionId: <id> → null`, not a stub; chain integrity holds. Question 5 of the review brief answered |
| **L2** | Point a soft-deleted row at a **dangling** survivor id, then undo | **Repelled — holds.** `getSingleOrNull` lets the undo complete, and no phantom entry is written against the nonexistent row |

#### Independent verification of the hybrid design (the review's central question)

Re-derived from behaviour:

1. **"Refuse on disagreement" is sound.** Every money column is compared as its
   authoritative stored string, currency is part of the value (A6/H1), and a
   carried value becomes the survivor's own for the next comparison (J3). Zero
   is defended as a value, not read as an absence (H1) — the KHA-25 distinction
   survives.
2. **"Gap-fill on absence" is sound *for a whole triple*, and the justification
   is genuine.** The engineer's reading of QA's own A1/A2 reproductions is
   correct: those are null-then-value pairs, and pure refuse-on-any-difference
   would have refused the exact D2 shape ADR-017 exists to resolve. The claim
   "strictly safer than either half alone" holds for the money triples.
3. **The gap-fill's weak point is not the triple — it is what surrounds it.**
   Where a value is stored as *one* object (`MoneyColumns`) the hybrid is
   airtight (H2). Where a value is spread across *independent* columns the same
   rule applies field-by-field and composes badly: the FX block is four separate
   gap-fills (H4), the transfer verdict is gated on one of its two halves (J6),
   and a triple with one column missing reads as absent (H3). The design is
   right; its application is not uniformly whole-value.

**Verdict on the design question: sound, with one real gap — the "one value =
one unit" discipline the money triple gets is not applied to the FX block or
the transfer pair.** None of the gaps loses money from a total.

#### 7f-i. Traceability — every done-check claimed by PR #24

| Issue / done-check | Test case (file → test name) | Type | Result |
|---|---|---|---|
| **KHA-87** — a merge carries the fee / converted amount / FX rate under the gap-fill rule, **or** refuses with a new `MergeRefusal` + localised copy | `qa_pr20_probe_test.dart` A1/A2/A3/A4 (inverted), A1b/A2b/A5/A6/A7; `transaction_merge.dart` `feeDiffers`/`conversionDiffers`/`remainingBalanceDiffers`; EN+AR copy for all six new refusals | Unit + QA probe | **PASS** — QA re-ran A1 and A2 and confirms `fees.base == '9.2'` and `spend.base == '150'` after the merge, and that the assertions are genuinely inverted (original scenario, original comment, `INVERTED (was: ...)` marker) — not renamed or weakened |
| **KHA-87** — probes A1/A2 **inverted**, not deleted | `qa_pr20_probe_test.dart` | QA probe | **PASS** — verified by diff: same fixtures, same message ids, same amounts; only the assertion flipped |
| **KHA-87** — a test pins that `MergePlan.between` compares **every money-bearing column**, so a new column cannot silently join the "neither compared nor carried" set | `qa_pr20_probe_test.dart` A8; `transaction_merge_test.dart` "every user-editable field is either compared outright, carried, or explicitly refused" | Unit + QA probe | **PASS (partial) — D-QA-20.** The *field-vocabulary* forcing function is real and schema-derived over `TransactionField.all`. The *column* check (A8) is a hand-written map of four columns, so a new column changes nothing about whether it passes. QA's schema-derived version finds `provenance` / `provenance_detail` undecided |
| **KHA-88 / D-QA-8** — `restore()` clears the survivor's pointer **only when it names the row being restored** | `qa_pr20_probe_test.dart` B3 (inverted); QA probe L2 | QA probe | **PASS** — identity check present and verified; a dangling id does not abort the undo |
| **KHA-88 / D-QA-8** — an audit entry is appended **against the survivor** recording that write | `qa_pr20_probe_test.dart` B4 (inverted); QA probe L1 | QA probe | **PASS** — `create, merge, merge_undo`, genuine `b → null` before/after, **inside the same `transaction()` block** (corroborated behaviourally: row `updated_at` and entry `changed_at` are one instant), chain integrity holds |
| **KHA-88 / D-QA-7** — the set-valued link, or a refusal, or the doc stops claiming a bidirectional pointer | `transaction_merge.dart` library doc; `qa_pr20_probe_test.dart` B2 | Doc + QA probe | **PASS (partial) — deliberately deferred and honestly disclosed.** The doc no longer over-claims and B2 pins the reachability that makes the degradation tolerable. But see **D-QA-17**: the same scalar is the *input to the chain guard*, so the degradation is not only "reduced convenience". KHA-88 must stay open |
| **KHA-88 / D-QA-9** — a decision is recorded on chains and the doc/test names match | `transaction_merge_test.dart` (both directions side by side); `qa_pr20_probe_test.dart` B6/B6b (inverted) | Unit + QA probe | **PASS (partial) — D-QA-17.** The single-step guard is real and correct. It is defeated by composition with an undo |
| **KHA-88 / D-QA-12** — a decision is recorded on enrichment-reversal | `transaction_merge.dart` property 1; `qa_pr20_probe_test.dart` F6 | Doc + QA probe | **PASS** as a decision. **O-QA-10**: the rationale predates money being carried, and now permits a fee to double-count after an undo |
| **KHA-89 / D-QA-10** — the merge prefers the user's value **or** refuses naming the disagreement | `qa_pr20_probe_test.dart` D2 (inverted), D2b; QA probe J7 | Unit + QA probe | **PASS** — `MergeRefusal.userEditDiffers` with EN+AR copy; refusal writes nothing on either row |
| **KHA-89 / D-QA-11** — a copied field carries its protected status onto the survivor | `qa_pr20_probe_test.dart` D3 (inverted) | QA probe | **PASS** — `MergeEnrichment.protectedFields` unioned into the survivor's `user_edited_fields` in the **same** write; D3 proves it behaviourally with a second merge |
| **KHA-89 / D-QA-13** — the edit-then-rescan test lives in `test/features/ingestion/` | `test/features/ingestion/edited_transaction_rescan_test.dart` | Integration | **PASS** — moved beside `deleted_transaction_rescan_test.dart`, its sibling one AC apart |
| **KHA-90 / O-QA-5** — `actor` is required with no default | `transaction_dao.dart:1253`; `qa_pr20_probe_test.dart` C2 | Compile-time | **PASS** — enforced by the compiler, which is stronger than a runtime assertion |
| **KHA-90 / O-QA-7** — fix the sentence or add the validation | `ledger_mapping.dart` `UnreadableReason.unparsableAmount`; `qa_pr20_probe_test.dart` G2 | Doc + QA probe | **PASS** — the sentence was corrected and the *reason* the behaviour is right (visible, not dropped — KHA-74) is now recorded and pinned |
| **KHA-90 / O-QA-8** — an in-screen confirmation before the merge is routed | `needs_review_screen.dart` `_confirmMerge`; `p3b2_screens_test.dart` (confirm / cancel / barrier-dismiss); EN+AR copy | Widget | **PASS** — mirrors the delete dialog, cancel positively worded (`Keep both`) and **first**; a barrier tap merges nothing. Verified all three widget tests exist and assert `actions isEmpty` on the non-merge paths |
| **AC-A5.2** — a possible duplicate is flagged and mergeable by explicit action | `transaction_merge_test.dart` (+3 tests); `qa_pr20_probe_test.dart` A/B/C/D; `qa_pr24_probe_test.dart` H/J | Unit + QA probe | **PASS** — was PASS (partial) in pass 4. The merge no longer loses a reported figure |
| **AC-B5.3** — user intent outranks the parser, **always** | `transaction_merge.dart` D-QA-10 loop; `edited_transaction_rescan_test.dart`; probes D1–D3, J7 | Unit + integration | **PASS** — was PASS (partial). Both directions and both paths (merge, re-scan) now covered |
| **AC-B6.4 / NFR-A2** — every mutation writes an entry with before/after and actor | probes B3/B4, L1; `transaction_dao_p3b2_test.dart` | Unit + QA probe | **PASS** — was PASS (partial) on the undo path. The last known exception is closed |
| **NFR-A6** — every derived figure traces to its constituents | probes B1/B2/B5, J1 | QA probe | **PASS (partial)** — literal per merge. Degrades after a second merge into one survivor (D-QA-7, disclosed) and, via **D-QA-17**, a chain can now form in which the middle row's absorbed row points at a soft-deleted row |
| **PRD §3.4** — the FX fee is its own reported figure, never folded into spend | probes A1/A1b/A5; `period_totals.dart` | Unit + QA probe | **PASS** — the fee survives a merge and is not double-counted by one (A5) |
| **ADR-002** — no `double`/`num` in any money path | `check_money_type_ban.sh`; `MoneyColumns` is `String`+`String`+`int?`; probe H2 | Script + unit | **PASS** — re-run by QA, clean. Comparison is on the authoritative strings; `_minor` is excluded from `==` and copied only alongside its own amount |
| **R-8** — never silently delete a real transaction | whole probe suite (17 new + 37 inherited) | QA probe | **UPHELD.** No probe made a transaction row disappear. D-QA-14 is the only probe that **overwrote** a stored money value, and it needs a raw-SQL-produced half-triple to set up |

**P3b-3 tally: 22 rows — 16 full PASS, 5 PASS (partial), 0 NOT TESTED, 0 FAIL.**

#### 7f-ii. QA-found items on PR #24

None is merge-blocking. Every finding is either (a) unreachable without a raw
SQL write, (b) a self-consistency/provenance problem in a *displayed* field
rather than a total, or (c) a guard that composes badly with a degradation this
PR explicitly disclosed and left open on KHA-88. **No probe removed money from a
total, and every High-severity finding from PR #20 is genuinely closed.**

| Ref | Severity | Summary |
|---|---|---|
| **D-QA-14** | Medium | A half-written money triple (`fee_amount_amount` set, `fee_amount_currency` null) reads as an **absence**, so the gap-fill **overwrites a stored money value** with no refusal — the one thing property 3 says is structurally impossible. Reachable only by a raw Drift/SQL write or a column-at-a-time migration (the O-QA-6 residual class). Probe H3 |
| **D-QA-15** | Medium | The FX block is carried as **four independent gap-fills**, so a survivor can end up stating a converted amount from one row and a contradicting rate/date/source from another. `MoneyColumns` gets whole-or-nothing treatment; `(converted, rate, rateDate, rateSource)` does not. Headline total unaffected (ADR-009 case 2 wins), but AC-B9.3's detail screen shows a rate that does not produce the amount beside it. Probe H4 |
| **D-QA-17** | Medium | **`MergeRefusal.chainWouldForm` is defeated by composition.** The guard reads the single scalar `merged_from_transaction_id`; D-QA-7 means it holds only the most recent merge, and `restore()`'s (correct) identity check clears it on undo — after which a survivor still holding an earlier absorbed row looks unencumbered. `first → survivor → newSurvivor` then forms. No money lost; the traceability shape the guard exists to prevent is created. Probe J1 |
| **D-QA-16** | Low | `conversion_pending` is cleared whenever a rate **string** is carried, without checking the rate converts. A row can stop claiming it is waiting for a conversion while still contributing nothing to the base total. Bounded — the "N not converted" line is derived from the conversion attempt, not the flag. Probe H6 |
| **D-QA-18** | Low | The internal-transfer carry is gated on `internal_transfer_state == null` for **both** halves, so a survivor holding a state with no group id never gains the group id the absorbed row carries — the "half a decision" the doc says the pairing prevents. Probe J6 |
| **D-QA-19** | Low | A **rule-assigned** `category_id` (not in `user_edited_fields`) on the losing row is still neither compared, carried, nor refused. The refuse-rather-than-strand rule iterates `incomingProtected` only. Not reachable until P4 assigns categories — which is the phase this PR gates. Probe J8 |
| **D-QA-20** | Low | KHA-87's done check asks for a test pinning that a **new column** cannot silently join the "neither compared nor carried" set. A8 is a hand-written four-column map, so it cannot do that. A schema-derived version (supplied in probe K1) immediately finds `provenance` and `provenance_detail` with no recorded decision |
| **O-QA-10** | Observation | D-QA-12's "an undo does not un-enrich" was decided when the enrichment carried five descriptive fields. It now also preserves money: undoing a merge that carried a 9.20 fee leaves the fee total at 18.4. Defensible (both rows are live duplicates again, and the amount doubles too — R-8's safe direction), but the doc's rationale still reads as though it only covers "a gap-filled merchant name". Probe J4 |
| **O-QA-11** | Observation | `mergeDuplicatePair` clears the survivor's `needs_review` / `review_reason` / `possible_duplicate_of_id` **unconditionally**. A survivor flagged for a *different* reason (unparsable amount, transfer candidate, or a duplicate of a third row) silently leaves the review inbox when an unrelated pair is resolved. **Pre-existing — present on `4f49513`, not introduced here** — but it lands directly in P4b's needs-review screen and should be decided before that screen ships |

### 7c. Epics C–I — not yet built

Per PRD §9: C (15 ACs), D (14), E (14), F (14), G (4), H (3), I (3) have no
implementation on `main` or on any open PR (build-plan P4–P8 have not started).
No test rows are invented for them.

---

## 7d. Epics C and D — the P4a categorization spine (PR #27, head `10df548`)

**Scope:** KHA-30 (category model, AC-C1.1/C1.2/C1.3, AC-C3.1-4) and KHA-31
(merchant→category rule store, AC-D1.1/D1.2, AC-D2.1-4, AC-D3.1/D3.2 + the
NFR-A2/AC-F5.2 audit obligation). The user-facing halves of Epics C and D are
KHA-32/33/34/97 and are **not** in this PR.

**Gates re-run by QA on head `10df548`** (not cited from the PR body — the
`docs/lessons.md` rule that a claim is evidence only for the tree it was
measured on):

| Gate | Command | Result on `10df548` |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** (5.4s) |
| Format | `dart format --output=none --set-exit-if-changed .` | **207 files, 0 changed** (PR body says 204 — count differs, result does not) |
| Unit/widget suite | `flutter test` | **1190 pass / 3 skip / 1 fail** |
| The 1 failure | `flutter test test/features/security/privacy_overlay_release_mode_test.dart --dart-define=dart.vm.product=true` | **passes** — pre-existing, environmental, CI owns it as its own step |
| ADR-002 money-type guard | `bash .github/scripts/check_money_type_ban.sh` | **clean** |
| QA probe suite (new) | `flutter test test/security/qa_pr27_probe_test.dart` | **35 pass / 0 fail** |

Toolchain: Flutter 3.44.8 · Dart 3.12.2. Evidence: `docs/evidence/qa-pr27/`.

### 7d.1 Traceability matrix

`RUNTIME` here means "executed against a real SQLite database through the real
DAOs / the real `IngestionPipeline`", which is the highest fidelity available
for a data-and-domain PR that routes no screen. No emulator run was performed
for this PR and none is claimed — P4a adds no UI, and the app shell still routes
only `HomePlaceholderScreen`.

| AC | Test(s) | Level | Status |
|---|---|---|---|
| **AC-C1.1** every transaction shows a category, never a blank | `default_categories_test.dart`; QA PROBE O (hand-corrupted id → resolves to Uncategorized, still in the sum) | RUNTIME | **PASS** (data half; the *display* half is KHA-97) |
| **AC-C1.2** low-confidence → Uncategorized + counted in review queue | `electric_bill_test.dart`; QA PROBE E (novel merchant → `flaggedUnknownMerchant`, `needs_review = 1`, `review_reason = 'unknown_merchant'`) | RUNTIME | **PASS** (data half; the count on the main screen is KHA-32) |
| **AC-C1.3** category totals incl. Uncategorized == period total | `category_sum_invariant_test.dart`; QA PROBES K, L, M, N, O, P — refund in a different category, transfer legs split across categories, unconverted-only category, empty-legend rows over an all-unconverted period, all four ops in sequence, 10 concurrent creates, corrupted id. Each asserted twice: `reconciles`, **and** an independent QA re-sum against a category-blind `LedgerTotals.spend` | RUNTIME | **PASS** |
| **AC-C2.1** change saved and reflected in breakdowns immediately | `categoriesProvider` / `categoryResolverProvider` are streams; QA PROBE O re-derives the breakdown after each write | RUNTIME | **PASS (partial)** — the "immediately on screen" half is KHA-33 |
| AC-C2.2 picker within two screens | — | — | **N/A this PR** — KHA-33 (and gated on KHA-87/88) |
| AC-C2.3 offer to apply to other transactions from the merchant | `applyUserCategory(learnRule:)` exists; QA PROBE AB verifies the `false` branch | RUNTIME (data half) | **PASS (partial)** — the offer itself is KHA-33 |
| **AC-C3.1** custom category, unique name, in every picker | `category_dao_test.dart`; QA PROBE I | RUNTIME | **PASS (partial)** — picker is KHA-97 |
| **AC-C3.2** duplicate names rejected | QA PROBE I — folded case/padding duplicate of the English seed, folded Arabic-orthography duplicate of the Arabic seed, and an injection-shaped name accepted as data then rejected as a duplicate | RUNTIME | **PASS** (message is KHA-97) |
| **AC-C3.3** delete requires a decision; no orphan reachable | `schema_v7_migration_test.dart`; QA PROBES H1–H5 — raw SQL, unfiltered bulk `DELETE`, soft-deleted referrer, `merchant_rule` referrer, protected row, and a delete→restore round trip | RUNTIME | **PASS** |
| **AC-C3.4** rename preserves historical links + history | QA PROBE J — `category_id` unchanged, `updated_at` on the transaction unchanged, exactly **one** new audit row (the category's own), not one per transaction | RUNTIME | **PASS** |
| AC-C4.1 visible needs-review indicator | data written (`needs_review`, `review_reason`); no UI | — | **N/A this PR** — KHA-32 |
| AC-C4.2 review count on the main screen | — | — | **N/A this PR** — KHA-32 |
| **AC-C4.3** confirming/correcting clears the flag | QA PROBE U | RUNTIME | **FAIL (partial)** — holds via `setUserCategory`, **not** via the already-shipped edit form → **D-QA-27-4 / KHA-101** |
| **AC-D1.1** rule M→C exists after categorizing | `merchant_dao_test.dart`; QA PROBE AA | RUNTIME | **PASS (partial)** — the visible rules list is KHA-34; the edit-form path teaches no rule (D-QA-27-4) |
| **AC-D1.2** re-categorizing updates the rule, no rival | QA PROBE AA — one rule row after two corrections | RUNTIME | **PASS** |
| **AC-D2.1** the electric-bill case, end to end | `electric_bill_test.dart` (last group — through the **real `IngestionPipeline`** with the bundled rule pack, verified by QA to be the real pipeline and not a stub); QA PROBE W | RUNTIME | **PASS** |
| **AC-D2.2** auto-categorized rows say so, and why | QA PROBE AA (`category_source = 'rule'`, `category_rule_id` set) + PROBE W (audit entry) | RUNTIME | **PASS** — with the caveat in D-QA-27-5 (the "why" can dangle after a category delete) |
| **AC-D2.3** cosmetic variants match; unrelated merchants must NOT | QA PROBES B, C, D (attack) and E, F (defence) | RUNTIME | **FAIL** — cosmetic variants and partial overlap behave correctly, but three shapes merge unrelated merchants: **D-QA-27-1 (High), D-QA-27-2, D-QA-27-3**, plus **D-QA-27-7** |
| **AC-D2.4** never-before-seen merchant is not confidently categorized | QA PROBE E; PROBE A2 (T4 refused at every confidence up to 1.0, `MerchantMatch.none` carries no category) | RUNTIME | **PASS** |
| **AC-D3.1** user's C2 wins for the next transaction | QA PROBE AA (read literally, as three transactions), PROBE Q (DAO boundary bypassing the service), PROBE R (each of the two protection signals alone), PROBE T (a seed rule cannot demote a user rule) | RUNTIME | **PASS** |
| **AC-D3.2** automatic re-learning never silently overrides | QA PROBES Q, R, S, V — including an explicit user "Uncategorized" (protected, and not learned as a rule) and a re-run of the categorizer (no double-count, no second audit entry) | RUNTIME | **PASS** |
| AC-D4.1/4.2/4.3 rules screen | `allRules` / `watchAllRules` / `deleteRule` exist; no UI | — | **N/A this PR** — KHA-34 |
| AC-D4.4 re-apply to history | deliberately **not** done by the v7 migration (asserted in `schema_v7_migration_test.dart`) | RUNTIME (the negative) | **N/A this PR** — KHA-34 |
| AC-D5.1/5.3 scope choice UI | `learnRule` parameter exists | — | **N/A this PR** — KHA-33 |
| **AC-D5.2** "this transaction only" does not become the rule | QA PROBE AB | RUNTIME | **PASS** (data half) |
| **NFR-A2 / AC-F5.2** every automatic categorization writes a SYSTEM entry naming the rule | QA PROBE W — `actor = 'system_rule'`, `action = 'categorize'`, `actor_detail = 'merchant_rule:<id>'`, before/after category and confidence in `field_changes_json`, and the named rule still resolves to its merchant and category | RUNTIME | **PASS** |
| **ADR-002** no double/num in a money path | `check_money_type_ban.sh`; QA PROBE Z | RUNTIME | **PASS** — `categoryConfidence` as `REAL` is explicitly sanctioned by architecture §4.2 and cannot reach an amount |
| **ADR-008** `autoApplyThreshold` boundary behaviour | QA PROBES A1, A2 — the IEEE-754 identity `0.60 + 0.25 == 0.85` that makes the T3 tier reachable at all, and the gate probed directly at 0.84 / 0.85 / 0.86 | RUNTIME | **PASS** |

### 7d.2 Adversarial security pass — attacks attempted, including the ones that failed

Recorded per this role's audit rule: an attack that failed is evidence, not a
non-event.

| Attack | Probe | Outcome |
|---|---|---|
| SQL injection via a category name | I | **Repelled** — stored as data; the named table survives; still counted as a duplicate on retry |
| SQL injection via merchant text into the key pipeline | I | **Repelled** — 14 categories still present after ingesting `QANDA'); DELETE FROM category;--` |
| Bypass the category-delete guard with raw SQL | H1 | **Repelled** (live, soft-deleted and rule referrers) |
| Bypass it with an unfiltered bulk `DELETE` | H2 | **Repelled**, and the abort rolled back completely |
| Destroy AC-C1.1's fallback (`Uncategorized`) | H3 | **Repelled** via DAO **and** raw SQL |
| Mass-assignment: write a category straight at the DAO over a user's choice | Q | **Repelled**; nothing written, not even the merchant link |
| Defeat protection by scrubbing one of the two signals | R | **Repelled** — each defends alone |
| Demote a user rule to a seed rule | T | **Repelled** |
| Get T4 to auto-apply by pushing its confidence over the threshold | A2 | **Repelled** — the tier is refused structurally, at 0.84/0.85/0.86/0.99/1.0 |
| Concurrency: 10 simultaneous creates of one category name | P | **Repelled** — exactly one row, no raw constraint error escaping the DAO contract |
| Concurrency/ordering: delete a category while a transaction points at it | P, H5 | **Repelled** — repointed inside one transaction, including soft-deleted rows |
| Break the sum invariant with a cross-category refund | K | **Repelled** |
| Break it by splitting a transfer's legs across categories | L | **Repelled** |
| Break it with an unconvertible-only category / all-unconvertible period | M, N | **Repelled** |
| Break it with a dangling `category_id` written behind the DAO | O | **Repelled** |
| Make one merchant identity swallow every transaction with no merchant | G1 | **Repelled** for null/blank… |
| …the same, using a punctuation-only placeholder | G2 | **SUCCEEDED → D-QA-27-7** |
| Merge two unrelated merchants at auto-apply confidence | B, C, D | **SUCCEEDED → D-QA-27-1, D-QA-27-2, D-QA-27-3** |
| Get an automatic path to overwrite a user's category | Q, R, S, V, AA | **Repelled on every path found** |
| Unlink a merchant through the automatic write path | AC | **SUCCEEDED → D-QA-27-8** (no caller today) |
| Apply a category that does not exist | Y | **SUCCEEDED → D-QA-27-6** (money-safe) |

### 7d.3 Tracking check (the `docs/lessons.md` "deferred work does not exist" rule)

- **KHA-97 exists, and is correct.** P4 milestone, `blockedBy` KHA-30,
  `owner-mobile-engineer`, `epic-C-categorization`, scoped to exactly the three
  surfaces (S-14, S-15, inline "+ New category") and to AC-C3.2's message, and
  it explicitly checks that KHA-32/33/34 do not already own them. This is the
  behaviour the lesson asked for, done unprompted.
- **Nothing else in KHA-30/KHA-31 was found deferred without a ticket.** QA
  walked both issues' ACs independently (matrix above); every "N/A this PR" row
  lands on an existing P4 issue.
- **One thing for the reviewer to confirm rather than assume:** the PR body says
  *"Closes KHA-30"*, so the GitHub↔Linear integration will auto-close KHA-30 on
  merge while its UI half lives on in KHA-97. That is the KHA-64 failure mode
  from `docs/lessons.md` — with the mitigation already in place (KHA-97 exists
  and is linked), so QA reads it as acceptable rather than as a defect, but it
  should be a conscious decision at merge, not a surprise afterwards.
- **All eight new defects were filed with a milestone at creation** (P4 — KHA-98 through KHA-105), per
  the standing reconciliation lesson, and the four conditional ones carry
  `blocks` links onto KHA-32/33/97 rather than living only in this document.

---

## 7e. Seventh pass — P4a-1, PR #30 (`fix/p4a-1-merge-undo-and-merchant-identity`, head `3620388`)

**Scope:** the eleven issues PR #30 closes. This is the **third** adversarial
round on `MerchantKey`/`MerchantMatcher` and the **third** on the merge/undo
link, so the pass is run against each issue's **own done-check** (written during
the PR #20/#24/#27 gates) rather than against the PR's self-description — the
`docs/lessons.md` rule that a done-check narrower than its ACs hides unshipped
work cuts both ways.

**Commands run, on `3620388` itself** (evidence: `docs/evidence/pr30/`):

```
flutter analyze                                  # No issues found! (6.3s)
dart format --set-exit-if-changed --output=none . # 208 files, 0 changed
flutter test                                     # 1242 passing / 3 skipped / 1 failing
flutter test --dart-define=dart.vm.product=true \
  test/features/security/privacy_overlay_release_mode_test.dart   # All tests passed
flutter test test/security/qa_pr30_probe_test.dart # 18 passing (16 HOLDS, 2 DEFECT)
```

Every figure the PR body claims reproduces exactly. The single failure is the
disclosed environmental one and was **verified to pass** under the dart-define CI
supplies, rather than accepted on the PR's word.

### 7e.1 Done-check traceability — the eleven issues

| Issue | Sev | Done-check (from the issue, not the PR) | Test / probe | Status |
|---|---|---|---|---|
| **KHA-88** | High | `restore()` clears the survivor pointer only when it names the restored row; audit entry against the survivor; the link becomes a set or the doc stops claiming bidirectionality; B2/B3/B4/B6/F6 inverted | `qa_pr20` B2 (inverted), `qa_pr24` J1/J1b, `transaction_merge_test` set-link group, **probes N1/N2/N5** | **PASS** |
| **KHA-94** | High | The link becomes set-valued **or** the guard asks the DB directly; J1 inverted; pr20 B6/B6b untouched | `qa_pr24` J1 (inverted) + **J1b** (raw-SQL corruption), **probes N1–N5** | **PASS** — both remedies shipped, not one |
| **KHA-96** | Low | K1's column enumeration promoted to `transaction_merge_test` expecting `isEmpty`; a recorded decision for `provenance`/`provenance_detail`; O-QA-10 doc sentence; O-QA-11 narrowing | `transaction_merge_test` (schema-derived forcing function, `$columns`), provenance-noop test, `transaction_merge.dart` property 1, **probe P3** | **PASS** |
| **KHA-98** | High | `of('MAKKAH BAKERY') != of('MADINAH BAKERY')`; `PANDA RIYADH`/`JEDDAH` merged **or flagged**, not silently split into unrelated shops; PROBE B inverted in place | `qa_pr27` B (inverted), **probes M3, M6** | **PASS** — and M6 confirms refusal at **every** tier, not only T1 |
| **KHA-99** | Med | `of('QAMART 100') != of('QAMART 200')` while `PANDA STORE 1234` still → `PANDA`; PROBE C inverted | `qa_pr27` C (inverted), **probe M2** | **PASS as written** — see **D-QA-30-2**: the same defect is open at ≥4 digits |
| **KHA-100** | Low | `QAFE QAFE` no longer auto-applies **or** the config comment names multiplicity; PROBE D updated | `qa_pr27` D (inverted), **probes M5, M7** | **PASS** — both remedies shipped; M5 confirms T3 was not simply disabled |
| **KHA-101** | Med | After correcting from the edit form: `needsReview == false`, `reviewReason == null`, a rule exists; a flag from a *different* question still **not** cleared; PROBE U inverted | `qa_pr27` U (inverted), `transaction_edit_test` KHA-101 seam group (4 tests) | **PASS** — the "does not fire on an untouched category" and "no learner bound" cases are real and adversarially framed |
| **KHA-102** | Med | `ofOrNull('***') == null` and `ofOrNull('-*-') == null`, while `Riyadh Store` still gets a usable key; PROBE G2 inverted | `qa_pr27` G2 (inverted), `merchant_key_test`, **probe M3** | **PASS** — M3 sweeps *every* noise token, not the two the issue names |
| **KHA-103** | Low | After `SetToUncategorized()`, no row holds a `category_rule_id` for a missing rule and none says `source = 'rule'` with NULL `category_id`; AC-C1.3 reconciles; PROBE X inverted | `qa_pr27` X (inverted), `category_dao_test`, **probes P1, P2** | **PASS** — P1 attacked the `isUserOwnedCategory` widening and could not reach the bad state (**O-QA-30-1**) |
| **KHA-104** | Low | `upsertRule` with an unknown category throws or writes nothing, **or** the matcher never applies it; the dangling-id read path still renders Uncategorized; PROBE Y inverted | `qa_pr27` Y (inverted), `merchant_dao_test`, **probes Q1, Q2** | **PASS** — Q2 proves the **read** side independently by inserting a dangling rule via raw SQL, bypassing the write guard entirely |
| **KHA-105** | Low | `applyAutomaticCategory` with no `merchantId` leaves an existing link untouched; PROBE AC inverted | `qa_pr27` AC (inverted), **probe Q3** | **PASS** |

### 7e.2 Adversarial pass — attacks attempted, including the ones that failed

Recorded so the audit evidence shows these were **run**, not assumed. 18 probes
in `test/security/qa_pr30_probe_test.dart`, all passing.

| Probe | Attack | Outcome |
|---|---|---|
| **M1** | Is `of` idempotent, as its doc comment claims? Feed a digit run that only becomes trailing after noise removal | **DEFECT D-QA-30-1** — `of(of(x)) != of(x)`; effect is a split (safe direction) |
| **M2** | Does the KHA-99 bound hold one digit past the done-check's example? | **DEFECT D-QA-30-2** — `QAMART 1000` == `QAMART 2000`, T1, 1.00, auto-applied |
| **M3** | Sweep **every** noise token: can any of them remove more than itself? Sweep 10 proper-noun-shaped distinguishing tokens (city, district, mall, person shapes) | **HOLDS** — all 10 keys distinct; every noise token removes only itself; each alone yields no identity |
| **M4** | Can `referenceMarkerTokens` be widened past the reviewed noise allow-list, smuggling a proper noun into digit corroboration? | **HOLDS** — it is a strict subset. *(Asserted nowhere in the engineer's suite; this probe is the only thing pinning it.)* |
| **M5** | Beat the multiset fix: 3× repetition, and repetition in the **candidate** rather than the query (the mirror direction) | **HOLDS** — all refused; a genuine permutation still auto-applies, so the fix is not "disable T3" |
| **M6** | KHA-98's pair differs in key — but can T3 or T4 reunite it? | **HOLDS** — `MatchTier.none`, no "did you mean" leak |
| **M7** | Is the PR's **self-correction** about its own ADR accurate? | **HOLDS** — `QAFE QAFE` falls past T4; ratio 1−5/9 ≈ 0.44 as stated |
| **N1** | KHA-94's composition end to end through the public service: merge → merge → undo → re-merge | **HOLDS** — `chainWouldForm`, for the right reason; invariant asserted after every step |
| **N2** | Three-deep absorb, undo the **middle** one, then undo all — does the guard release, or lock out forever? | **HOLDS** — scalar re-points correctly at each step; refusal is reversible |
| **N3** | merge → undo → **re-merge the same pair** → chain: does the guard re-arm? | **HOLDS** |
| **N4** | **Concurrency**: two different rows merged into one survivor simultaneously (pr20's B7 raced the other direction) | **HOLDS** — both land, set holds both, scalar names exactly one, chain intact |
| **N5** | Ghost back-pointer: does `restore` move `is_deleted` and `merged_into_id` together, or can a restored row haunt / vanish from the set? | **HOLDS** — both move together |
| **P1** | Separate AC-D3.1's two redundant signals via the merge, to reach `source='rule'` on a protected row and defeat KHA-103 | **HOLDS** — unreachable, two independent reasons (**O-QA-30-1**) |
| **P2** | KHA-103's two ordinary branches | **HOLDS** |
| **P3** | O-QA-11 both ways, **and** across an undo — is the review flag loss merely moved to the undo path? | **HOLDS** |
| **Q1** | KHA-104 **write** side | **HOLDS** — sentinel returned, nothing written, audit chain intact |
| **Q2** | KHA-104 **read** side, proved independently: dangling rule inserted by **raw SQL**, bypassing `upsertRule` | **HOLDS** — dropped from candidates; shop still identified; row flagged for review, not stamped |
| **Q3** | KHA-105 | **HOLDS** |

### 7e.3 Claims checked rather than accepted

- **R-16 sequencing** (*"this must land before any device install populates
  `merchant` rows; the categorizer is already wired into live ingestion with no
  screen required"*) — **verified true and still true.** `git diff 42db8ff HEAD`
  over `lib/` shows PR #30 touches **no** provider wiring for ingestion:
  `ingestion_providers.dart` and `categorization_providers.dart` are not in the
  diff at all. The wiring itself is real on this head —
  `ingestion_providers.dart` watches `ingestionCategorizerProvider` and passes it
  to the pipeline as `categorizer:`, which calls
  `CategorizationService.categorizeTransaction`. So one ingested SMS on an
  unlocked schema-v7 install does populate `merchant` with no screen involved.
- **KHA-101's reachability correction** — **accurate.** `lib/app.dart` routes only
  `LockGateScreen` and `HomePlaceholderScreen`.
- **ADR-008 v1.3's `QAFE QAFE` footnote** — **accurate** (probe M7).
- **ADR-008 v1.3's `PANDA RIYADH`/`PANDA JEDDAH` Jaccard = 1/3** — **accurate**;
  correctly overrides QA's own earlier 0.5 figure from the pass-6 report.
- **What the ADR does *not* say** — settled answer 2's "consequences on synthetic
  input" list never states a 4-digit sibling pair, so **D-QA-30-2 is an
  undisclosed consequence rather than an accepted cost**.

### 7e.4 Tracking check (the `docs/lessons.md` milestone/`blocks` rules)

- Both new issues filed with the **P4 milestone set at creation**, per the
  standing reconciliation lesson.
- D-QA-30-2's conditional gate is a **`blocks` link in Linear**, not prose in a
  merge commit — the PR #20 lesson about gates that live only in a commit
  message.
- **Nothing in PR #30 is deferred without a ticket.** The one downstream item,
  **H-15** (the "this is a different shop" alias-split affordance), is a human
  design-gate item already tracked in `docs/architecture.md` §8.1 alongside
  H-6/H-13/H-14, and the ADR is explicit it must not block this fix landing.

---

## 7f. Eighth pass — P4b, PR #34 (`feature/p4b-categorization-ui`, head `0585fd4`)

**Scope:** the six issues PR #34 closes — KHA-106/107 (the ADR-008 v1.4 code
fix, commit `eb14a10`) and KHA-32/33/34/97 (the categorization UI, commit
`0585fd4`).

### 7f.0 Calibration — why this pass is deliberately asymmetric

`docs/PRD.md` now declares **`TIER: personal`**, which per the team's own rules
means journeys plus **~5–10** highest-value probes and one review round, not a
30-probe suite. That trim was applied to the **new UI/CRUD work** (category
management, learned rules, picker sheet, correction flow, navigation) — PROBES
U1–U5, five probes.

**The merchant-matching engine was exempted, on purpose.**
`lib/features/categorization/merchant_key.dart` has now required **four**
adversarial rounds to catch real money-correctness bugs — KHA-98, KHA-99,
KHA-106, KHA-107 — and *every one of them was missed by a pass that checked
worked examples*. KHA-106 is the clearest case: ADR-008 v1.3's consequences list
enumerated five examples and simply never stated a pair of 4-digit siblings, so
three consecutive readers signed it off.

So this round did not check examples. It checked **properties, mechanically**:

* a **generated corpus** of 7,290 strings (all ordered 2–4 token strings over an
  alphabet spanning every token *kind* the pipeline distinguishes: two proper
  nouns, an ordinary word, two reference markers, a non-marker noise word, and
  digit runs at three lengths straddling the deleted `>= 4` boundary);
* a **differential** against ADR-008 v1.3's algorithm, transcribed verbatim from
  `git show dc3f362:lib/features/categorization/merchant_key.dart`, so the
  behaviour change is *enumerated* rather than described.

### 7f.1 Commands run, on `0585fd4` itself

Per the `docs/lessons.md` rule that a gate result is evidence only for the exact
tree it was measured on. Evidence: `docs/evidence/qa-pr34-*.txt`.

```
flutter analyze                                        # No issues found!
dart format --set-exit-if-changed --output=none lib test  # 215 files, 0 changed
flutter test                                           # 1340 passing / 3 skipped / 1 failing
flutter test --dart-define=dart.vm.product=true \
  test/features/security/privacy_overlay_release_mode_test.dart  # All tests passed
flutter test test/security/qa_pr34_probe_test.dart     # 12 passing
flutter test    # with the QA probe file added: 1352 passing / 3 skipped / 1 failing
```

Every figure the PR body claims **reproduces exactly**, including the single
failure: `privacy_overlay_release_mode_test` needs CI's dedicated dart-define
step, and QA **verified it passes** under that define rather than accepting the
disclosure on the PR's word.

### 7f.2 Done-check traceability — the six issues

| Issue | Sev | Done-check (from the issue, not the PR) | Test / probe | Status |
|---|---|---|---|---|
| **KHA-106** | High | `of('QAMART 1000') != of('QAMART 2000')`, **or** the residual is stated in ADR-008 + the constant's doc comment. PROBE M2 **inverted in place** | `CategorizationConfig.referenceDigitRunMinLength` **deleted**, with a comment in its place explaining why it must not return; `qa_pr30` M2 inverted (verified in the diff — same fixtures, same comments, flipped assertions), and it now also executes the end-to-end tier (T4, `canAutoApply` false); QA **PROBE E2/E4** | **PASS** |
| **KHA-107** | Low | `of(of(x)) == of(x)` for all `x` including `'PANDA 1234 STORE'`, **or** the doc drops the claim. PROBE M1 **inverted in place** | Invariant made **true**, not withdrawn; `qa_pr30` M1 inverted; QA **PROBE E1 — 0 violations / 7,290 strings**, and **E1b** asserts the premise (`referenceMarkerTokens ⊆ noiseTokens`) the proof rests on | **PASS** |
| **KHA-32** | High | Corpus tests show the three outcomes; the review count equals flagged ∪ uncategorized, **verified against the data layer** | `ReviewCounts.fromRows` is a pure function over rows; `p4b_screens_test` AC-C4.1 (icon **and** words, NFR-U4); QA **PROBE U4** recomputes the figure by an independent path and pins the literal answer (2 / 2 / **3**, not 4) | **PASS** |
| **KHA-33** | Urgent | Tap-count test for AC-C2.2; explicit AC-D5.2 test; bulk undo restores each transaction's **individual** prior category | Correction is a bottom sheet, so AC-C2.2 holds by construction; AC-D5.2 tested end to end; AC-C5.2 restores six columns via `CategorySnapshot`, with a test proving the automatic path can write again after undo. QA **PROBE U5** constructs the genuinely-mixed-prior case the shipped test names but does not build — **production code passes** (see G-QA-34-2) | **PASS** |
| **KHA-34** | Medium | Re-apply updates history **and** writes one audit entry per affected transaction; declining leaves history untouched; deleting a rule stops future auto-categorization only | Re-apply **loops** rather than issuing one `UPDATE`, so each row gets its own entry; N computed **before** the dialog opens and the button stays disabled until it arrives; **KHA-104's write-side guard verified on this S-17 path**, including the category-deleted-while-dialog-open case, and **no history rewrite runs against a rejected category** | **PASS** |
| **KHA-97** | Medium | Duplicate name shows a message and creates nothing; delete cannot complete without a decision; **both decisions leave AC-C1.3 intact (widget-level path)**; Uncategorized offers no affordance | Duplicate + protected-category behaviour tested; AC-C3.3 is a property of the widget tree; *Uncategorized* affordance **absent, not disabled**. **The widget-level AC-C1.3 half was missing** — supplied by QA **PROBES U1/U2**, both pass | **PASS** (gap closed by QA — **G-QA-34-1**) |

### 7f.3 Adversarial pass — attacks attempted, including the ones that failed

Recorded as audit evidence whether or not they succeeded, per the standing rule.

| # | Attack | Result |
|---|---|---|
| **E1** | Break idempotence anywhere in a 7,290-string generated corpus (`of(of(x)) != of(x)`) | **FAILED to break it — 0 violations.** KHA-107 genuinely closed, not just for the pinned examples |
| **E1b** | Find a corroborator that survives step 7 and so re-fires step 6 on a second pass | **FAILED** — `referenceMarkerTokens ⊆ noiseTokens` holds; the doc comment's warning is now enforced by a test rather than written down |
| **E2** | Find **any** two strings with different *name content* that share a key (the KHA-98/99/106 class), by partitioning the whole corpus rather than testing pairs | **FAILED — 0 classes span more than one name.** The strongest single result of this pass |
| **E3** | Buy order-insensitivity by over-collapsing: make `X MARKER D` == `X D MARKER` *and* accidentally equal to a different name | **FAILED** — swept over every one of the 10 reference markers, both orders; `ZORBA` never collides with `QANDA` |
| **E4** | Find a **third** cost, the way KHA-109 was found last round: a merge v1.4 introduces that v1.3 did not have, joining two different names | **FAILED to find a dangerous one.** v1.4 introduces **818** new merges and **not one joins two different names** — every one is `NAME <digits> <MARKER>` folding into the `NAME` class, the intended consequence |
| **E4b** | Check whether the two disclosed costs are *"correctly and only those costs"* | **SUCCEEDED (Low)** — the cost class is **wider than the example that documents it**; the sub-4-digit, marker-after half is new in v1.4 and undisclosed. **D-QA-34-1** |
| **E5** | Check the KHA-109 all-digit-key residual was not enlarged | **FAILED to find enlargement — it shrank** (−48 / +4). Recorded as **O-QA-34-1** because an undisclosed *improvement* is still an undisclosed change |
| **U1/U2** | Break the AC-C1.3 category-sum invariant through a **UI-triggered** category delete (both sealed decisions), driving the real screen against the real DAO | **FAILED to break it.** Total holds at **175.00**; reassignment moves the money into `groceries` (**165.00** exactly), it does not merely detach it |
| **U3** | SQL injection (`'; DROP TABLE category;--`, `' OR '1'='1`), RTL-override display spoofing (U+202E), embedded NUL — on the new category-name CRUD path | **FAILED.** Stored as data or refused; the `category` table and seed rows survive. Drift parameterises. Name folding still refuses a case/spacing duplicate (AC-C3.2) |
| **U4** | Make the review badge over-count by feeding it a row that is *both* flagged and uncategorized | **FAILED** — the figure is a **union** (3), not a sum (4), verified against an independent recount |
| **U5** | Make the undo reset rows to a default instead of their own priors, using genuinely different priors | **FAILED** — target returns to `dining`, the two blanks to `null`; audit chain still verifies |
| **N1** | Reach any P4b screen **before unlock** | **FAILED.** `app.dart` renders `HomePlaceholderScreen` only on the unlocked branch and `LockGateScreen` otherwise; every P4b route hangs off `HomePlaceholderScreen`. Nothing is constructed above the lock gate |

### 7f.4 Reachability — verified by grepping the construction site

`docs/lessons.md`: *"verify a reachability claim by grepping for the
construction site, never from the fact that the widget exists in the tree."*
Done, and it holds — this is the first phase where the app is genuinely
navigable:

```
app.dart  (unlocked branch only)
  └── HomePlaceholderScreen
        ├── openNeedsReview        → NeedsReviewHost → NeedsReviewScreen
        │     ├── openTransactionDetail → TransactionDetailScreen   (S-11)
        │     └── _openCompleteUnparsed → CompleteUnparsedScreen    (S-19)
        ├── openCategoryManagement → CategoryManagementScreen       (S-14/S-15)
        ├── openLearnedRules       → LearnedRulesScreen             (S-16/S-17)
        └── openRecentlyDeleted    → RecentlyDeletedScreen          (S-44)
```

`showCategoryPickerSheet` is constructed from `correctTransactionCategory` in
the same routes file. **The conditional merge gate is correctly discharged:**
the gate said KHA-87/88/94/96/98–105 were merge-blocking for any PR routing
`NeedsReviewScreen` / `RecentlyDeletedScreen` / `TransactionDetailScreen`; this
PR routes all three, and all fourteen issues are `Done`.

### 7f.5 Claims checked rather than accepted

| Claim | Verdict |
|---|---|
| "1340 tests passing, one pre-existing environment-dependent failure" | **Accurate.** Reproduced exactly; the failure verified to pass under CI's dart-define |
| "`flutter analyze` clean, format clean (215 files, 0 changed)" | **Accurate** on `0585fd4` |
| "Two defects found by the new tests, fixed here" (`setState` arrow body returning a Future; unhandled async error in the provenance loader) | **Both genuinely fixed, not caught-then-left.** `transaction_detail_screen.dart` starts the future *outside* the callback and uses a block body; `_load()` catches `on Object` into a nullable result so a rejected future never exists, and `!snapshot.hasData` renders the error state — an error never renders as an *empty* history, which is the claim that matters |
| "KHA-104's write-side guard verified on this path, not assumed" | **Accurate**, and stronger than claimed — the tests also assert **no history rewrite runs** against the rejected category, and cover the category-deleted-while-the-dialog-is-open race |
| "KHA-110 (the unpopulated 'Recent' row) is deferred and non-blocking" | **Correct and correctly scoped.** The row hides itself when empty, so the shipped app renders no broken affordance; the picker is fully usable (search + full grid). Filed with owner, labels, priority **and milestone** — the standing `docs/lessons.md` failure did not recur. It hides nothing that should block |
| PROBE M1/M2 "inverted in place rather than deleted" | **Verified in the diff** — same fixtures, same raw strings, same reasoning comments, assertions flipped. Neither was weakened or renamed to pass trivially |

### 7f.6 Tracking check

- **D-QA-34-1** filed as a Linear issue with the **P4 milestone set at
  creation**; **G-QA-34-1** and **G-QA-34-2** are recorded in `docs/defects.md`
  as gaps QA closed in the same pass (the tests now exist and pass), so they
  need no separate ticket.
- **KHA-110** was filed by the engineer with milestone — correctly.
- **KHA-109** remains open and is **not** this PR's problem; E5 confirms this PR
  shrinks rather than grows its class.

---

## 7g. Ninth pass — P5a, PR #41 (`feature/p5a-shell-home-transactions`, head `d9fac9e`)

**Scope:** KHA-35 (Home dashboard), KHA-36 (transaction list + bank/instrument
screens), and the three High defects from the P5 entry gate — KHA-113 (SMS
permission never requested), KHA-114 (soft delete unreachable), KHA-115 (the
immortal correction snackbar).

### 7g.0 Calibration

`TIER: personal`. Journeys first, then a small number of high-value probes —
**nine**, not thirty. The one place depth was *not* trimmed is **NFR-A6**, the
instrument → bank → period reconciliation chain: it is real money logic, this
build has repeatedly found bugs behind shallow tests of exactly this invariant,
and the shipped test's own doc comment overstates its coverage (see 7g.3).

### 7g.1 Commands re-run on `d9fac9e` itself

`docs/lessons.md`: *"any pass/fail claim must name the commit SHA it was measured
on, and a reviewer must re-run the gate on the CURRENT head."* All four measured
by QA on `d9fac9e`, not cited from the PR body:

| Gate | Engineer claimed | QA measured on `d9fac9e` | Verdict |
|---|---|---|---|
| `dart format --set-exit-if-changed lib test` | clean | **234 files, 0 changed**, exit 0 | reproduced |
| `flutter analyze` | clean | **No issues found** (6.2s), exit 0 | reproduced |
| `flutter test --exclude-tags=release_mode_guard` | 1434 pass / 3 skip / 0 fail | **+1434 ~3, All tests passed** | reproduced exactly |
| Flutter floor `>=3.44.0` (KHA-115 needs `SnackBar.persist`) | satisfied by `stable` | local toolchain **3.44.8**, compiles | satisfied, with **0.0.8 of headroom** — noted in O-QA-41-3 |

### 7g.2 Traceability — the five issues' acceptance criteria

| AC / done-check | Where verified | Status |
|---|---|---|
| **AC-A1.2** rationale + a way to grant, never an unexplained empty state | `p5a_onboarding_gate_test` (fresh install → S-02; denied → S-04 carrying "still intact") | PASS |
| **AC-A1.3** revoked → warns, data intact | `p5a_onboarding_gate_test` (flag set → app + `SmsAccessRevokedBanner`); copy checked in `app_en.arb` | PASS |
| **AC-A3.1/A3.2** initial import + progress | `foregroundSweepProvider` → `HistoricalImporter.runOrResume`; **QA probe B1/B3** (previously untested — see 7g.4) | PASS |
| **AC-B1.2** original SMS text viewable | `p5a_transaction_detail_actions_test`; `originalMessageTextProvider` wired at the one construction site | PASS |
| **AC-B2.1/2.2/2.3** bank + per-instrument totals | `p3_screens_test` (screens) + `p5a_shell_navigation_test` (wiring) + `totals_reconciliation_test` + **QA probes A1–A5** | PASS |
| **AC-B3.1** rename | `p5a_shell_navigation_test` ("an instrument can be renamed from its detail…") | PASS |
| **AC-B4.3** manual vs SMS-derived | `p5a_screens_test`, `p5a_greyscale_test` | PASS |
| **AC-B6.1/6.2/6.4** soft delete after explicit confirmation | `p5a_transaction_detail_actions_test` (offer, confirm, cancel-writes-nothing) | PASS |
| **AC-B7.3 / NFR-U4** credit vs debit without colour | `p5a_greyscale_test`, with a real negative control (see 7g.5) | PASS |
| **AC-B8.1/8.2** restore, S-44 can hold something | `p5a_transaction_detail_actions_test` | PASS |
| **AC-B11.1** internal transfer carries no sign, excluded from spend | `p5a_screens_test`; **QA probe A1** (two-bank case) | PASS |
| **AC-B12.2 / B13.3 / B14.2 / B14.3** | `p3_screens_test` (screens) + P5a wiring test | PASS |
| **AC-C4.1 / C4.2** review indicator + count from the main screen | `p5a_screens_test`, `ReviewCountCard` on Home | PASS |
| **AC-E1.1** total on the first screen, no navigation | `p5a_shell_navigation_test`, `p5a_screens_test` | PASS |
| **AC-E1.2** reflects an added/corrected transaction | `p5a_shell_navigation_test` (Drift stream, moves with no navigation at all) | PASS |
| **AC-E1.3** zero/empty state, not blank or error | `p5a_screens_test` (explicit `0.00` **and** caption; loading shows no figure) | PASS |
| **AC-E1.4** calendar months, resets on the 1st, prior month viewable | `period_range_notifier_test` — 13 tests incl. Riyadh-midnight boundary, half-open window, **both halves**, and no drift on repeated shifts | PASS |
| **AC-E5.3** filtered-empty state | **absent, correctly** — there is no filter until KHA-38, which owns AC-E5.3 explicitly | N/A (owned) |
| **NFR-A6** instrument → bank → period reconciliation | `totals_reconciliation_test` + **QA probes A1–A5** | PASS (see 7g.3) |
| **NFR-R2** no perceptible wait, responsive during background work | every Home section reads a Drift stream; nothing awaits ingestion | PASS by construction |
| **NFR-S2** masked identifiers | `p5a_shell_navigation_test` asserts last-four only | PASS |
| **NFR-S3** every screen behind the lock; nothing above the gate | one ternary in `app.dart`; **QA probe C1** on the real `MassrofyApp` (see 7g.6) | PASS |
| **NFR-U3/U8** Arabic RTL, 2.0 text scale | both locales throughout; dense screens at 2.0 | PASS |

### 7g.3 NFR-A6 given genuine scrutiny — the three claimed layers are real, and one claim is overstated

The PR claims three independent layers. **All three exist and all three are
sound**: the hand-computed literal `3550.50` was re-derived by QA from the
fixture comment and is correct; the chain is asserted as exact `Money` equality
(not `closeTo`), which is right because `Money` wraps `Decimal`; the 200
generated ledgers use a fixed seed and reconcile.

**But the test's own doc comment claims the generated sweep covers *"an internal
transfer split across two banks"*, and it does not.** Its generator emits only
`posPurchase` and `refund`, all in `SAR`. That is the one gap that matters,
because `LedgerTotals.report`'s own doc names transfer-slicing as *"the most
plausible way to reintroduce AC-B11.1 as a bug"*.

QA proved the gap by mutation, not by reading:

> Removing `transfers: transfers` from `BankTreeBuilder._nodeFor` — i.e.
> reverting to a per-instrument detector run, which counts every internal
> transfer as spend at the sending bank — leaves
> **`totals_reconciliation_test.dart` passing 5/5**. QA probes **A1** and **A3**
> both fail on that mutation.

The shipped behaviour is **correct**; this is a coverage gap, not a defect, and
it is **closed inside this pass** by `test/security/qa_pr41_probe_test.dart`
(recorded as G-QA-41-1). Probes added:

- **A1** — a proven internal transfer whose two legs sit at *different* banks:
  excluded from both bank totals and the period total, chain still exact.
- **A2** — the chain under **currency conversion**, plus the *"N not converted"*
  counts reconciling. (Additivity holds structurally: `_add` converts each
  transaction individually and sums the converted values, so sum-of-rounded and
  rounded-of-sum cannot diverge. Now pinned rather than reasoned.)
- **A3** — 200 generated ledgers, different seed, with the nine debit types,
  three credit types, three currencies, fees, undated/out-of-period rows, cash,
  and 0–2 internal transfer pairs per run.
- **A4** — a **business oracle**: a realistic 17-transaction month recomputed by
  a hand-written fold that re-derives "what counts" from the PRD, cross-checked
  against a hand-written literal (`5,436.55 SAR`), then asserted equal to
  `LedgerTotals.spend`. The drill-down sums to `5,376.55` — exactly `60.00` less,
  the cash row that sits under no bank.
- **A5** — the inverse of A1: a *candidate* pair (no matching reference) **keeps
  counting** and is flagged. This pins the deliberate over-statement bias so a
  future "fix" cannot silently under-state spend (risk R-7).

One residual, non-blocking: the period total includes cash (no instrument) and
the sum of bank totals cannot. `BanksScreen` shows **no grand total**, so the app
never displays two figures that claim to agree — acceptable at this tier, logged
as **O-QA-41-1**.

### 7g.4 KHA-113 — the fresh-install journey, including the case the human actually hit

The shipped gate tests are good and cover: fresh install → S-02; Grant →
`request()` called exactly once; denied → S-04; "Not now" → S-04 with
`request()` **not** called (Android gives one prompt); permanentlyDenied → deep
link to Settings; the flag written **on decline as well as grant**, so a relaunch
shows the app rather than a screen already read; already-granted → no onboarding;
revoked-after-onboarding → app + banner; Arabic RTL.

**What none of them covered:** nothing anywhere in `test/` referenced
`foregroundSweepProvider` — the provider that actually turns a granted permission
into a ledger. So *"I granted it in Android Settings, does the import run?"* was
untested, which is the same never-exercised-wiring shape KHA-113 itself was.
QA probes:

- **B1** — permission `granted` out of band, `request()` never called: the sweep
  runs and **three inbox messages become three transactions**. The human's
  scenario works.
- **B2** — the control: `denied` → sweep returns null, nothing written. So B1 is
  known to be about the permission.
- **B3** — denied, then granted out of band, then the pair of `invalidate` calls
  `app.dart`'s resume handler makes: the import starts on the **very next
  sweep**, with no relaunch and no onboarding replay.

`onboarding_complete` does distinguish "never asked" from "granted once, since
revoked" (AC-A1.3), as claimed — verified by the shipped test and by reading
`AppSettingsDao`. One honest edge, logged as **O-QA-41-2**: after an *out-of-band*
grant the flag is never written, so a later Android auto-revoke shows S-02 rather
than the AC-A1.3 banner. That leads somewhere sensible (re-grant) and the banner
copy is written to be true either way (*"**Any** data you already have is still
intact"*), so it is an observation, not a defect.

### 7g.5 NFR-U4 — the greyscale test is a real negative-control test

`signalsOf` reads **only** `Text.data` and `Icon.codePoint` — no `Color` — and
the fourth test proves the harness cannot read a colour by feeding it two rows
that differ *only* by hue and asserting the signal sets are equal. Without that
control the other three assertions would prove nothing. The PR's argument for not
using a golden file is correct: a golden proves two renders are identical, not
that two rows are distinguishable. Amounts are deliberately the same magnitude
(`45.00` both sides) so the rows cannot pass on the number alone.

Nit, not a defect: the `ColorFiltered`/flattened-palette wrapper does nothing for
this reading method, since `signalsOf` inspects the widget tree rather than
pixels. The load-bearing part is the negative control, and it is there.

### 7g.6 KHA-115 and the two undisclosed-but-fixed defects

**KHA-115 — verified, and the diagnosis is correct.** `SnackBar`'s constructor
really does `persist = persist ?? action != null`, so an actionable bar is
immortal; `scoped_snack_bar.dart` passes `persist: false` explicitly. Six shipped
tests cover auto-dismiss, a no-action control, dismissal on push, dismissal on
pop (a genuinely separate path — a pop does not move `secondaryAnimation`), the
Undo being **inert** once its route is not current (staged through a
`DialogRoute`, which a `MaterialPageRoute` cannot transition to, so the bar
really does survive), a **positive control** proving the Undo *does* fire while
current, and replacement rather than queueing.

**The `source_hygiene_test` guard is real.** QA grepped `lib/` independently:
four other `showSnackBar` call sites exist (`categorization_routes.dart:477`,
`category_management_screen.dart` ×2, `learned_rules_screen.dart` ×2) and **none
carries an action**, so all default to `persist: false` and dismiss normally. No
snackbar-with-action slipped past the guard.

**Hero-tag collision — fixed.** `home_screen.dart` uses `heroTag: 'fab.home'`,
`transaction_list_screen.dart` uses `'fab.transactionList'`; these are the two
FABs alive together in the `IndexedStack`. A third FAB in
`category_management_screen.dart` still uses the default tag but lives on its own
pushed route, so it cannot collide today — a latent trap only if it is ever moved
into the shell (**O-QA-41-4**).

**NFR-S3 route-stacking — fixed in production, but its regression test does not
protect it.** `p5a_lock_collapses_stack_test.dart` re-implements the gateway's
collapse *inside the test file* and drives the copy. Proved by mutation:

> Commenting out `_collapseToLockGate()` in `lib/app.dart` leaves
> **`p5a_lock_collapses_stack_test.dart` passing 2/2**. QA probe **C1**, which
> pumps the real `MassrofyApp`, fails on that mutation with exactly the intended
> message.

Filed as **D-QA-41-1** (low; the shipped code is correct, the test is not
load-bearing on a security NFR). QA's C1 supplies the real coverage in this pass.

### 7g.7 RUNTIME VERIFICATION — the app was actually run, on a device, as a new user

Full log and screenshots: `docs/evidence/qa-pr41/README.md`. Debug APK built from
`d9fac9e` (Flutter 3.44.8), installed on the `massrofy_test` AVD (API 35) after
`pm clear`, with `READ_SMS`/`RECEIVE_SMS`/`POST_NOTIFICATIONS` confirmed
`granted=false` first.

One deviation, stated rather than implied: `locksettings get-disabled` was `true`
on this AVD, so a PIN had to be set before ADR-005's gate had any credential to
authenticate against. Without it **no journey is reachable at all**.

| Journey | Result |
|---|---|
| Fresh install → lock gate → **S-02 rationale** | **RUNTIME-VERIFIED** — the screen KHA-113 said had no construction site |
| *Grant SMS access* → the real OS permission dialog | **RUNTIME-VERIFIED** — `request()` has a caller |
| Allow → `READ_SMS`/`RECEIVE_SMS` `granted=true` | **RUNTIME-VERIFIED** |
| Unlock → Home renders, 3 tabs, **AC-E1.3** explicit `0.00` + caption | **RUNTIME-VERIFIED** |
| More menu → all **six** screens KHA-113 called dead code are reachable | **RUNTIME-VERIFIED** |
| SMS → ledger → **month total = `−972.40 SAR`** | **RUNTIME-VERIFIED**, business oracle: `312.40 + 660.00`, exact |
| **AC-C4.1/C4.2** flag icon + words on the row, "2 items need review" on Home | **RUNTIME-VERIFIED** |
| **S-11** with its Edit/Delete row, masked `•••• 9002`, original-message panel | **RUNTIME-VERIFIED** — KHA-114's core fix |
| **AC-B6.2** confirm dialog, "Keep it" first | **RUNTIME-VERIFIED** |
| Delete → row stays, **deleted banner + Restore** | **RUNTIME-VERIFIED** — KHA-114's second, undisclosed fix (`watchById`) |
| **AC-E1.2** total drops to `−312.40`, review count 2 → 1 | **RUNTIME-VERIFIED**, oracle: `972.40 − 660.00`, exact |
| **NFR-A6 on device** — Banks shows `Bank Aljazira · −312.40 SAR` = Home's total | **RUNTIME-VERIFIED** |
| Snackbar auto-dismissed within 9 s | **RUNTIME-VERIFIED** (KHA-115) |
| **NFR-S3** — pushed Banks route gone after a lock; unlock lands on Home | **RUNTIME-VERIFIED** |

**Two things the walk found that no test did:**

- **KHA-122 (Medium, Epic A, not a PR #41 blocker).** Two rule-pack-matching SMS
  arrived while the app was open and unlocked with permission granted, and did
  **not** appear — `0.00 SAR` for ~2 minutes across several rebuilds — until a
  background/foreground cycle. AC-A1.1 says *"without any user action"*.
  Root cause composes two documented facts: ADR-018 makes
  `runBackgroundIngestion()` a ratified no-op, and `foregroundSweepProvider` is
  only re-armed on `resumed`. And `SmsPermissionService.requestImmediateSweep()`
  — the one method that would close this — **has no caller in `lib/`**, the same
  shape as KHA-113 itself. Either the wiring or AC-A1.1's wording needs to move.
- **KHA-123 (Low).** S-11 reads *"SMS · Unknown bank"* for every transaction
  because `bankDisplayName` has no production caller — while the Banks screen
  names the same bank correctly. Fifth omitted-optional-parameter on that one
  screen; PR #41 fixed four of them.

**Not covered, stated honestly:** POST_NOTIFICATIONS (not needed by P5a), Arabic
*UI* at runtime (widget-tested in both locales; the Arabic *message bodies* were
parsed correctly on device), fingerprint auth (none enrolled — every unlock used
the device credential), and S-05's import progress screen (five messages
completed too fast to observe; AC-A3.2 stays test-verified only).

### 7g.8 Disclosure and tracking checks

- **Three tabs, not four** — accurately disclosed, not silently dropped.
  `docs/design.md` line 77/108/366 does specify a four-tab BottomNav
  (Home/Transactions/Reports/More); `KHA-37` exists, is in the P5 milestone, and
  owns the Reports hub (S-28, AC-E2/E3/E4). The `More` menu carries an honest
  line (`moreReportsComingSoon`) rather than a dead tab. One thin spot:
  KHA-37's `Do`/`Done check` names the reports *content* but never the
  BottomNav entry itself, so QA added a comment to KHA-37 naming it — per
  `docs/lessons.md`, *"documented in the PR is not tracking."*
- **AC-E5.3** — deferred to KHA-38, which names AC-E5.3 explicitly. Correctly owned.
- **`SpentVsKeptCard` on Home** — design.md files S-32 under the Reports hub; it
  sits on Home in the meantime and the PR says so. Not a scope leak: removing a
  shipped call site would be the regression.
- **Nothing else is deferred in the PR body**, as it claims. QA re-checked by
  grepping the diff for `TODO`/`later`/`P5b` and found only the two forward
  references above, both owned.

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
| B — instruments/transactions, **P3a slice only** | 20 AC rows | 17 | 3 (each waiting on KHA-26/28/40, not on P3a) | 0 | Merged (PR #11) — verified against head `51bb730` |
| B — **P3b-1 slice** (KHA-27/28/29/70) | 15 AC/invariant rows | 9 | 6 (P4 categories, P5 income view, KHA-26, KHA-78, D-QA-4) | 0 | Merged (PR #18) — verified against head `3ba320d` |
| B — **P3b-2 mutation surface** (KHA-26/64/66/74/78/79/80 + KHA-69) | 25 AC/invariant rows | 17 | 6 | 1 not tested (AC-B8.3, disclosed → KHA-86) | Merged (PR #20) — verified against head `61efd7b` |
| B — **P3b-3 merge-safety gate** (KHA-87/88/89 + KHA-90 O-QA-5/7/8) | 22 AC/invariant rows | 16 | 5 | 0 | **PR #24 open** — verified against head `8761e3e` |
| **C + D — the P4a categorization spine** (KHA-30, KHA-31) | 27 AC/invariant rows | 15 | 9 (each waiting on KHA-32/33/34/97, not on P4a) | 2 FAIL (AC-D2.3, AC-C4.3 — both non-blocking, both ticketed) | **PR #27 open** — verified against head `10df548` |
| B — remainder + C–I remainder | ~110 ACs | — | — | — | Not yet built |

**Overall (pass 6, PR #27): `QA: PASS 27`.** Every gate re-run by QA on head
`10df548` itself (§7d): analyze clean, format clean at **207** files, **1190
passing / 3 skipped / 1 failing** — the failure pre-existing and proven so by
re-running it green with the `--dart-define` it requires — money-type guard
clean. A 35-probe adversarial suite
(`test/security/qa_pr27_probe_test.dart`, all passing) found **eight defects,
none merge-blocking for this PR and four merge-blocking for the P4b surfaces**.
The two invariants this phase actually risks both held under every attack QA
could construct: **AC-C1.3's category-sum reconciliation** (eleven adversarial
compositions, each cross-checked independently of the type's own `reconciles`)
and **AC-D3.1's "user correction always wins"** (repelled on every write path
found, including at the DAO boundary with the service bypassed, and with either
protection signal scrubbed). What did **not** hold is **AC-D2.3's "never
silently merge unrelated merchants"**: normalisation can collapse two unrelated
businesses into one merchant identity at confidence 1.00, which sits above every
tier gate and above any value `autoApplyThreshold` could take (D-QA-27-1,
D-QA-27-7). Because P4a routes no surface that can create a rule, none of it can
fire in a build of this branch — but the *merchant rows* are already being
created from live ingestion, so this is a data-shape decision that P4b inherits
and it is escalated to solution-architect now rather than at P4b.

**Overall (pass 5, PR #24): `QA: PASS 24`.** All five claimed local gates were
reproduced on head `8761e3e` (analyze clean, format clean at 183 files, **1040
passing / 3 skipped / 0 failing**, money-type guard clean, debug APK built —
`docs/evidence/qa-pr24/gate-reproduction-8761e3e.md`). A second, 17-probe
adversarial round aimed specifically at the new hybrid rule found **seven
defects and two observations, none merge-blocking, and none of them a
regression of what this PR fixed**.

**Both PR #20 High-severity findings are genuinely closed, verified by
execution, not by reading the diff.** `report.fees.base` stays `9.2` and
`report.spend.base` stays `150` across the merges that used to null them; the
`merge_undo` audit entry exists with a real `b → null` before/after and is
written from the same timestamp as the survivor row it describes, i.e. inside
one `transaction()` block; `restore()`'s identity check holds and a dangling
survivor id no longer aborts an undo. The QA probes that asserted the defects
were **inverted in place**, keeping the original fixtures and the original
comment — verified by diff, not taken on trust.

**On the design question the review turned on** — the engineer implemented a
*hybrid* (refuse on genuine disagreement, gap-fill on absence) where the
dispatch asked for a pure refusal. QA's finding is that **the hybrid is sound
and the reasoning for it is correct**: a null is an absence, the null-then-value
pair is the D2 shape ADR-017 exists to resolve (QA's own A1/A2 are exactly that
shape), and pure refuse-on-any-difference would have made the merge safe and
useless. Zero is defended as a value rather than read as a gap (KHA-25 survives,
probe H1), and a carried value becomes the survivor's own for the next
comparison (probe J3).

Its weak point is **not the rule but the granularity it is applied at.** Where a
value is one object — `MoneyColumns` — the hybrid is airtight: probe H2 confirms
amount, currency and `_minor` always move as one unit, so the verbatim-copy
justification holds and cannot pair one row's minor with another's amount. Where
a value is spread across independent columns, the same rule runs field-by-field
and composes badly: the FX block is four separate gap-fills (**D-QA-15**), the
transfer verdict's group id is gated on its state (**D-QA-18**), and a triple
missing one column reads as absent and is overwritten (**D-QA-14**). The
"one value = one unit" discipline the money triple gets should extend to both.

The one finding worth a reviewer's attention beyond the list is **D-QA-17**: the
new `chainWouldForm` guard is correct in isolation and **defeated by
composition** with the D-QA-7 scalar-pointer degradation this PR explicitly
disclosed and deferred. That disclosure argues the degradation is "reduced
convenience, not lost traceability" — accurate as far as it goes, but the same
scalar is the *input to the chain guard*, so the deferral has a safety
consequence the disclosure does not name. It loses no money and creates no
unreachable row; it recreates the traceability shape the guard was added to
prevent. KHA-88 must stay open, and its remaining scope is now larger than the
PR states.

**Overall (pass 4, PR #20):** **QA: PASS 20.** All five claimed local gates were
reproduced exactly (analyze clean, format clean at 181 files, **986 passing / 3
skipped**, money-type guard clean, debug APK built). A 37-probe adversarial suite
weighted two-thirds toward the merge operation found **nine defects and five
observations, none merge-blocking**.

The R-8 standard — *"silently deleting a real transaction is worse than an
inflated total"* — **is upheld.** No probe made a transaction row disappear, no
probe reached a merge without confirmation, and no probe got a negative magnitude
past any DAO write path. The soft-delete-with-pointers design does what it claims
for the single-merge case, verified by execution rather than by reading the doc
comment.

What the probes found is a **different failure mode than the one the file was
hardened against**: not a lost row, but a lost *figure*. `MergeEnrichment`
genuinely cannot write null — and the safety conclusion drawn from that is wider
than the type, because the money columns it does **not** carry (`fee_amount_*`,
`converted_amount_*`, `fx_rate`) ride out of the ledger on the soft-deleted row.
A merge can therefore reduce the reported FX-fee total to nothing (**D-QA-5**) or
drop a foreign purchase out of the base-currency spend figure entirely
(**D-QA-6**). Both are user-initiated and reversible, and both are the exact
shape KHA-74 was filed to close, arriving through the new write path KHA-74's own
fix anticipated.

Second cluster: the merge's "pointers both ways" property is written for a
one-to-one merge and degrades under repetition. A second absorption overwrites
the first pointer (**D-QA-7**), and `restore()` clears the survivor's pointer
without checking which row it refers to — leaving the two halves of the link
contradicting each other, and doing it **with no audit entry against the
survivor at all** (**D-QA-8**, the highest-value finding after the two money
ones, because it is an NFR-A2 hole on every undo, not only the multi-merge case).

Third: AC-B5.3 is implemented as *"do not overwrite the survivor"*, which is
narrower than *"user intent outranks the parser, always"*. A user's correction
loses if it happens to be on the row they merged away (**D-QA-10**), and a user
value the merge copies onto the survivor arrives unprotected (**D-QA-11**).

Everything else verified clean and was checked by execution rather than accepted:
KHA-79's previously-green wrong-invariant test is genuinely **inverted, not
skipped**; AC-B6.3's re-scan test runs the **real** `IngestionPipeline` and rule
pack; KHA-78's confirm/reject both persist and survive re-derivation; KHA-80's
near-match flag fires on evidence and correctly does *not* fire on a lone
transfer; KHA-66 flips AC-A4.3 from GAP to PASS. The KHA-69 decision's
load-bearing claim (*"the first real-device unlock was on `56e9cbaa`, which
already contains the P3a fix"*) was **checked against git and is true** —
`8e549d8` is an ancestor and `_toWholeSecondsUtc` is present in that tree.

**Overall (pass 3, PR #18):** **QA: PASS.** No defect found in P3b-1's own scope
that blocks merge. All five claimed local results were reproduced exactly
(analyze clean, format clean at 159 files, **784 passing / 3 skipped**, money-type
guard clean, debug APK built). The two claims that correct previously-filed
defects were verified by *executing* code, not by reading doc comments: the
sign-convention rejection was probed at three DAO write paths, and every
hand-calculated figure in `combined_totals_test.dart` was re-derived
independently and found correct. The per-instrument exclusion assertion was
specifically checked for weak-pass and is genuinely load-bearing. An 11-test
QA probe suite (`test/security/qa_pr18_probe_test.dart`) found one real gap
(D-QA-3) and one AC-B11.2 sub-case (D-QA-4); neither is exploitable from
shipped code paths today.

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
