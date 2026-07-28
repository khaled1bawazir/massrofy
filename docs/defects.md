STATUS: living document — updated every QA pass

# Massrofy — Defects Log

**Author:** qa-tester agent
**Date:** 2026-07-28
**Scope of pass 1 (2026-07-28):** Epic 0 (Foundation, P1) and Epic A (SMS
ingestion, P2, PR #2).
**Scope of pass 2 (2026-07-28):** Epic B — the P3a domain spine (KHA-23, KHA-25,
KHA-64 first half), PR #11, head `51bb730`. See `docs/test-plan.md` §1a, §6a and
§7 for the full traceability matrix and the exact commands run.

---

## Summary

### Pass 2 (PR #11, P3a domain spine)

**No defect was found in P3a's own scope that blocks its merge.** All four gates
were reproduced against the PR head, not read from the description: `flutter
analyze --fatal-infos` (0 issues), `dart format --set-exit-if-changed lib test
integration_test` (142 files, 0 changed), `check_money_type_ban.sh` (pass), and
`flutter test --exclude-tags=release_mode_guard` (**628 passed, 3 skipped**) —
exactly the engineer's claimed numbers. 18 QA-authored attacks
(`test/security/p3a_adversarial_test.dart`) were all repelled.

Two defects were raised, **neither in P3a's scope and neither blocking**: D-QA-1
(pre-P3a audit history stays un-verifiable after the timestamp fix) and D-QA-2
(AC-B9.3's rate date has no column and no display). Two low observations, O-QA-1
and O-QA-2. Details below.

### Pass 1 (P1 and PR #2)

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

*(Convention: ID, title, severity, steps to reproduce with synthetic — never real
— data per NFR-M3, expected vs. actual, story/AC broken, linked Linear issue.)*

### D-QA-1 — audit history written before P3a stays permanently un-verifiable after the fix

- **Severity:** Medium. (The underlying write-path bug was **High** and PR #11
  fixes it. What remains is the *data already on disk*, which the fix does not
  touch.)
- **Found in:** pass 2, while verifying PR #11's own defect claim.
- **Affects:** NFR-A3, ADR-010's "Settings → Verify history integrity" action.
- **Background (verified, not taken on trust).** `AuditLogDao.append` on `main`
  (`c6879f3`) hashed the untruncated `changedAt` while Drift persists a
  `DateTimeColumn` as whole Unix seconds, so every entry written with a real
  `DateTime.now()` hashed a value that could never be read back. I confirmed this
  by checking the pre-PR file out over PR #11's test file: both new regression
  tests fail with `Expected: true / Actual: <false>`, and pass with the fix.
- **The residual defect.** PR #11 changes `append` only; `verifyChainIntegrity()`
  and `_canonicalize` are byte-identical before and after (confirmed from the
  diff). So an entry written by *any* pre-P3a build still recomputes to a
  different hash and still reports tampering — permanently, on an install that is
  otherwise fully patched. The fix is forward-only and the PR does not say so.
- **Steps to reproduce:** install a build at `main@c6879f3`; perform any audited
  mutation (the app writes `changedAt: DateTime.now()`); upgrade to the P3a build;
  run Settings → Verify history integrity.
- **Expected:** intact history verifies.
- **Actual:** verification fails, and — because the chain is sequential — the
  first bad entry poisons every entry after it, so the user is told their entire
  history was tampered with.
- **Why it is not a merge blocker:** blocking PR #11 leaves the *worse* bug (all
  future entries un-verifiable too) in place. But it must be decided before any
  build reaches a real device (P10 / KHA-52). Options for the engineer, in
  ascending honesty cost: (a) confirm no install with pre-P3a audit rows exists
  and note it in the migration; (b) a v3→v4 migration that re-chains legacy rows
  from their stored (truncated) values and records that re-chaining in the trail
  itself; (c) a genesis marker so verification reports "verified from <date>"
  rather than "tampered".
- **Linear:** **KHA-69** (`Bug`, `security-sensitive`). Owner: mobile-engineer.

### D-QA-2 — AC-B9.3: the FX rate is displayed with no rate date or source

- **Severity:** Medium.
- **Found in:** pass 2, reading `transaction_detail_screen.dart` against the PRD.
- **Affects:** AC-B9.3 (*"the conversion rate **and rate date** used are
  visible"*), architecture §4.2.
- **What:** `transaction_detail_screen.dart:331` renders
  `l10n.txnFieldExchangeRate` from `txn.fxRate`. Schema v3 adds eight columns to
  `transactions` but not §4.2's `fxRateDate`, `fxRateSource` or
  `conversionPending`, so no date or source exists to render. A rate the user
  cannot date is precisely the traceability AC-B9.3 exists to require.
- **Expected:** rate **and** rate date visible wherever a converted amount is
  shown.
- **Actual:** rate only.
- **Why it is not a P3a merge blocker:** AC-B9.x is **KHA-27**'s scope, KHA-27 has
  not started, and what P3a displays is honest about showing only what the message
  stated. Recording it here (rather than letting it live in a PR body) follows
  `docs/lessons.md`' rule that deferred work needs a ticket. It also corrects the
  PR's claim that schema v3 "completes the record against architecture §4.2" —
  three §4.2 columns are still absent.
- **Linear:** **KHA-70** (`Bug`), related to KHA-27 and KHA-25. Owner:
  mobile-engineer.

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

## Observations from the pass-2 adversarial suite (low severity, recorded for audit)

Both surfaced from `test/security/p3a_adversarial_test.dart` and are pinned by a
passing test that documents the current behaviour, so a future change to either
is a deliberate change rather than a silent one.

### O-QA-1 — a row whose amount column cannot be parsed vanishes from every list and total, with no signal

- **Severity:** Low. **Reachability:** only by editing the database outside the
  app — the write path stores `Money.toCanonicalString()`, which always parses
  back. Same threat model ADR-010 already answers with tamper-*evidence*.
- **What:** `toLedgerTransactionOrNull` (`lib/features/ledger/ledger_mapping.dart:64`)
  returns `null` for an unparseable amount, and `toLedgerTransactions` drops it.
  The row survives in the database; it is simply invisible everywhere, including
  in totals. The file documents the reasoning (a zero-rendered row would be worse)
  and I agree with the choice — but NFR-A7's principle is that nothing disappears
  without a trace, and today nothing counts or reports these rows.
- **Recommendation (not a fix demand):** count them and surface the count where
  the parser-health panel already lives. Handed to mobile-engineer as a note, not
  filed as a `bug`.

### O-QA-2 — a negative amount typed on S-19 is accepted and inverts the movement

- **Severity:** Low. Self-inflicted only (single-user, offline app); no fraud
  vector exists.
- **What:** the S-19 form has an explicit debit/credit control, so a typed `-50`
  is a second, redundant way to say "credit": a `debit` of `-50.00` *reduces* the
  period total. Two different inputs produce the same ledger effect, and the
  transaction detail then shows a negative debit.
- **Expected:** either reject a negative amount and point at the direction
  control, or normalise sign + direction on save.
- **Routed to:** KHA-26 (manual entry / edit — the issue that owns form
  validation, AC-B4.2). Not filed as a separate `bug`.

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
  **Closed in pass 2** — PR #11 implements it for real
  (`UnparsedCompletionService`); re-tested and now PASS (test-plan §7a).

Added in pass 2 (P3a):

- **A bank row is created only when a message produces a transaction**, not when
  any recognised sender is seen. Checked against AC-B12.1's wording ("…**and** the
  account or card mentioned is placed under it") — the implementation's reading is
  the right one, and creating a bank from a marketing SMS would put an empty bank
  in the user's tree. Documented at the source in `ledger_entity_resolver.dart`.
- **`customConstraint('… REFERENCES …')` instead of `.references(Table, #id)`.**
  Not a workaround hiding a problem: I confirmed the generated
  `app_database.g.dart` carries the constraint, `PRAGMA foreign_key_list` proves
  SQLite knows about it on fresh *and* upgraded databases, and my own adversarial
  test proves it is **enforced** (an insert naming a non-existent instrument is
  rejected and the enclosing unit rolls back).
- **Period boundaries computed in UTC while the product's day boundary is
  Asia/Riyadh.** Real three-hour skew at month edges, disclosed by the PR and
  documented at the call site. P5 owns the period selector; not a P3a defect, but
  it must not be forgotten — the same class of thing as the Asia/Riyadh constant
  noted above.
- **`ledger_providers.dart` has no test of its own** (needs platform plugins),
  matching P2's precedent. Every component it wires is tested directly and
  `ingestion_ledger_test.dart` constructs the *production* resolver shape, so this
  is a thin, honestly-stated seam rather than an untested feature.
- **Asia/Riyadh is a hard-coded `+03:00` constant, not `package:timezone`.**
  Confirmed correct for this one zone (no DST, ever) and explicitly named so the
  assumption is greppable if the app ever needs a second timezone.

---

## Defects fixed since the previous pass

N/A — this is the first QA pass on this repository.
