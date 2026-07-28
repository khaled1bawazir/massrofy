STATUS: living document — updated every QA pass

# Massrofy — Defects Log

**Author:** qa-tester agent
**Date:** 2026-07-28
**Scope of this pass:** Epic 0 (Foundation, P1, merged `main`) and Epic A (SMS
ingestion, P2, PR #2 — open). See `docs/test-plan.md` for the full traceability
matrix and the exact commands run to produce these findings.

---

## Summary

**No functional code defects were found in this pass.** Both `main` (P1) and
`feature/p2-sms-ingestion-parsing` (P2, PR #2) pass `flutter analyze --fatal-infos`
cleanly, `dart format --set-exit-if-changed .` cleanly, and their full test suites
(146 and 476 tests respectively) with zero failures. The CI-enforced ADR
guardrails (`check_money_type_ban.sh`, `check_no_network_permission.sh`) both
pass, the latter independently re-verified against a freshly built, genuinely
merged release manifest.

This is a QA verification pass, not a rubber stamp: I ran every check myself
against the real code (see `docs/test-plan.md` §1) rather than trusting PR
descriptions, and I specifically went looking for gaps in the two areas flagged
as banking-domain-critical (money math, authz/audit) plus the two areas PR #2
itself flagged as unverified. Nothing found there rises to "defect" — see below
for what did surface, correctly classified as risks and gaps rather than defects.

---

## Confirmed defects

**None.** No row in this section as of 2026-07-28.

*(Convention for future entries: ID, title, severity, steps to reproduce with
synthetic — never real — data per NFR-M3, expected vs. actual, story/AC broken,
linked Linear issue.)*

---

## Open risks (not defects — recorded for traceability, already tracked)

These were independently verified as still-open by this QA pass. Neither is new;
both were disclosed by PR #2 itself. I am recording my independent confirmation
here rather than filing duplicate Linear issues.

### R-QA-1 — KHA-7 background-SMS latency spike has never been run

- **Severity:** Medium (product-promise risk, not a code defect; bounded by
  design — see below).
- **What:** NFR-R1 ("single-digit seconds from SMS arrival to visible in-app")
  and ADR-006's latency table are explicitly "provisional on the P0 spike
  (KHA-7)." KHA-7 is still in Backlog with no recorded finding.
- **Impact if never closed:** the product's central trust promise — "the numbers
  are right and current when you open the app" — is unverified on the user's
  actual device/OEM. Because ADR-006/ADR-018 made ingestion watermark-based and
  self-healing, a suppressed broadcast degrades **latency**, not **correctness**:
  no transaction is lost, it just arrives later (at most ~15 minutes via the
  periodic sweep, or at next unlock while the app is locked, per ADR-018).
- **Recommendation:** run before or during P10's device test; do not block P2's
  merge or P3's start on it, per the architecture's own risk assessment.
- **Linear:** already tracked as **KHA-7**. I added a QA-confirmation comment
  there rather than opening a duplicate.

### R-QA-2 — No automated test of the real Kotlin SMS receiver / permission flow

- **Severity:** Medium.
- **What:** `SmsReceiver.kt`, `SmsChannel.kt`, `IngestWorker.kt`,
  `IngestScheduler.kt`, `BootReceiver.kt`, and `ForegroundIngestService.kt` have
  no unit, widget, or CI-integration coverage. Contrast: the encrypted-storage
  claim (ADR-003) has a real CI job (`android-sqlcipher-integration-test`) that
  boots a genuine Android emulator; the SMS-ingestion wake path has no
  equivalent. The Dart pipeline that runs *after* a message reaches the content
  provider is thoroughly tested; the OS-level delivery *into* that pipeline is
  not tested at all in this repository.
- **Impact:** runtime permission behaviour for a side-loaded APK, real
  broadcast-to-worker latency, and headless-`FlutterEngine` startup in a release
  build are all unverified claims, same class of risk as R-QA-1.
- **Recommendation:** add an `integration_test/` job analogous to
  `db_encryption_test.dart` — e.g. grant `RECEIVE_SMS`/`READ_SMS` on a headless
  emulator, inject a synthetic SMS via `adb emu sms send`, and assert a
  transaction/review-queue row appears within a bounded time. This closes the gap
  without waiting on the real device (KHA-7 still separately needed for the
  OEM-battery-manager conditions no emulator can reproduce).
- **Linear:** not filed as a new issue — it is implicit in KHA-7's scope and
  explicitly disclosed in PR #2's "Honest limits" section already. Recommend
  the mobile-engineer split it out as its own issue (owner: mobile-engineer,
  epic-A-sms-ingestion) if it should be tracked independently of KHA-7's
  device-specific latency measurement; I'm flagging the recommendation here
  rather than creating the split myself, since creating Linear issues that
  aren't genuine defects is out of scope for this pass.

---

## Coverage gaps found by this QA pass (not defects — code reads correct, untested)

### G-QA-1 — AC-A4.3 (dismiss unparsed SMS) has no DAO/pipeline-level regression test

- **Severity:** Low.
- **What:** `RawMessageDao.dismissAsNotTransaction()` (`lib/data/dao/raw_message_dao.dart`)
  and the review-queue's `dismissedAsNotTransaction = 0` filter both exist and
  read correctly by inspection. `test/widget/p2_screens_test.dart` proves the
  "not a transaction" button invokes the dismiss callback with the right id, but
  no test — DAO-level or pipeline-level — actually calls
  `dismissAsNotTransaction()` and then asserts (a) the item leaves the review
  queue and (b) re-ingesting the identical message (same `contentHmac`) does not
  resurrect it, which is the full text of AC-A4.3.
- **Why this is a gap, not a defect:** I read `dismissAsNotTransaction()`, the
  review-queue query, and `raw_message_dao_test.dart` in full. The
  implementation is correct as written (the DAO updates a flag rather than
  deleting the row, exactly per the documented rationale in
  `review_queue.dart`), and ADR-017 D1's `UNIQUE(contentHmac)` constraint would
  independently prevent a literal re-insert on re-scan. There is no observed
  wrong behaviour — only an untested path for a correctness-adjacent feature.
- **Recommendation:** a short regression test in `raw_message_dao_test.dart`:
  insert a message → dismiss it → assert it is excluded from the queue query →
  re-insert the identical `contentHmac` (simulating a re-scan) → assert it
  remains excluded and the second insert is rejected/no-ops per D1. Handed back
  to mobile-engineer; QA does not write production or test code per its
  operating rules.
- **Linear:** not filed as `bug` (no defect observed) — recommendation recorded
  here and in `docs/test-plan.md` §4 for mobile-engineer follow-up.

---

## Verified NOT defects (checked because they looked suspicious, confirmed correct/intentional)

Recorded so the next QA pass doesn't re-investigate the same things from
scratch.

- **`runBackgroundIngestion()` is a hard-coded `return true;` no-op.** Confirmed
  intentional — this is ADR-018's ratified design (background ingestion is
  suspended while the app is locked; the watermark does not advance; nothing is
  lost because the SMS provider is the durable queue). Not a stub masquerading
  as done. The diagnostic event ADR-018 also calls for
  (`ingest.skipped.locked`) is explicitly deferred and tracked as **KHA-58**,
  correctly, not silently dropped.
- **ADR-017 D2's "enrichment merge" is not implemented; P2 flags instead.**
  Confirmed intentional and disclosed — `duplicate_policy_test.dart` group "D2 —
  the bank's own reference number" tests the flagging behaviour that actually
  ships, and `DuplicateAction` has no `delete`/`merge` case, enforced by a test
  asserting the enum's shape.
- **AC-A4.2's "fill in missing fields → create transaction" is a UI callback
  stub, not a working flow.** Confirmed intentional and disclosed (needs the P3
  domain model). Recorded as a scoped GAP in `docs/test-plan.md`, not a defect.
- **Asia/Riyadh is a hard-coded `+03:00` constant, not `package:timezone`.**
  Confirmed correct for this one zone (no DST, ever) and explicitly named so the
  assumption is greppable if the app ever needs a second timezone.

---

## Defects fixed since the previous pass

N/A — this is the first QA pass on this repository.
