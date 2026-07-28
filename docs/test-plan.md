STATUS: IN PROGRESS — covers Epic 0 (Foundation) and Epic A (SMS ingestion) only

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

---

## 7. Epics B–I — not yet built

Per PRD §9, epics B (46 ACs), C (15), D (14), E (14), F (14), G (4), H (3), I (3)
— **113 ACs total** — have no implementation on `main` or on any open PR as of
this report (build-plan.md P3–P8 have not started). No test rows are invented for
them. A handful of Epic B acceptance criteria have **incidental, non-authoritative**
partial coverage that fell out of P2's parsing layer before the P3 domain model
exists — noted here so they are not silently forgotten, not counted as done:

- AC-B1.2 (original SMS viewable) — referenced in `sms_sanitizer_adr013_v11_test.dart` and `ingestion_pipeline_test.dart:469` in the sense that the sanitised text is retrievable; the actual detail-view UI does not exist yet.
- AC-B1.3 (an absent optional field reads as explicitly unknown, never zero/blank) — `rule_pack_corpus_test.dart:254` "AC-B1.3 — an absent field is null, never zero or blank" tests this at the **parser output** level; the full `Transaction` entity (P3) does not exist yet.
- AC-B9.3 (conversion rate + rate date visible) — `money_converter_test.dart`'s `ExchangeRate` traceability group tests the **value type**; there is no UI yet.
- AC-B13.1/B13.2/B14.1 (account vs. card typing; card-to-account link) — `rule_pack_loader_test.dart` and `rule_pack_corpus_test.dart` confirm the **parser** correctly reports `kind` and the settlement-account hint from a message; entity resolution into real `Instrument` rows is P3 work.

These four rows will move into a proper Epic B section, re-tested against the real
domain model, once P3 lands. They are recorded here only so nobody mistakes
"the parser reports the right field" for "the acceptance criterion is met."

---

## 8. Untestable-as-written criteria

None found in Epic 0 or Epic A. Every AC in the built scope is either
automatable (and mostly is) or requires a real device (§5) — which is a
verification-environment constraint, not a wording problem with the AC. No AC is
being sent back to product-owner from this pass.

---

## 9. Summary

| Epic | ACs / done-checks in scope | PASS | PASS (partial) | GAP | Status |
|---|---|---|---|---|---|
| 0 — Foundation (P1) | 8 done-checks | 7 | 1 (SQLCipher desktop-vs-emulator split) | 0 | Merged, main — verified |
| A — SMS ingestion (P2) | 19 ACs | 13 | 3 | 3 (1 by-design/P3, 1 device, 1 QA-found test gap) | **PR #2 open, not yet merged** — verified against the branch |
| B–I | 113 ACs | — | — | — | Not yet built |

**Overall:** nothing found in this pass rises to the level of a functional defect
worth blocking PR #2's merge on. The two device-verification gaps are real,
already disclosed by the PR itself, and independently confirmed still open — they
belong on the P10/KHA-52 device-test critical path, not as a merge blocker for P2.
The one new item this pass surfaced — AC-A4.3's missing DAO-level regression test
— is a coverage gap, not a defect; see `docs/defects.md`.
