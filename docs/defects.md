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

### Pass 5 (PR #24, P3b-3 — the merge-safety gate)

**No defect was found that blocks merge. Verdict: `QA: PASS 24`.** Head
`8761e3e`. All five claimed gates reproduced: analyze clean (5.5s), format clean
(183 files, 0 changed), **1040 passing / 3 skipped / 0 failing**, money-type
guard clean, debug APK built (75.1s). Flutter 3.44.8 / Dart 3.12.2. Evidence:
`docs/evidence/qa-pr24/`. `check_no_network_permission.sh` not run locally
(needs a release build + merged manifest) — CI owns it.

**Both PR #20 High-severity findings are genuinely closed, verified by
execution.** D-QA-5: `report.fees.base` stays `9.2` across the merge that used
to null it. D-QA-6: `report.spend.base` stays `150`. D-QA-8: `restore()`'s
identity check holds, and the survivor now gets a `merge_undo` entry with a real
`b → null` before/after, written from the **same timestamp** as the row it
describes — i.e. inside one `transaction()` block, corroborated behaviourally,
not only by reading the diff. The QA probes that asserted the defects were
**inverted in place** (same fixtures, same message ids, same amounts, original
comment retained) — verified by diff, not taken on trust.

**On the hybrid design.** The engineer diverged from the dispatch: instead of a
pure "refuse if any money column differs", they built refuse-on-disagreement
**plus** gap-fill-on-absence. QA's independent finding is that **the hybrid is
sound and the justification is correct** — a null is an absence, the
null-then-value pair is exactly the D2 shape ADR-017 exists to resolve (QA's own
A1/A2 reproductions are that shape), and pure refusal would have made the merge
safe and useless. Probe H1 confirms the KHA-25 distinction survives: a stored
**zero** is a value, not a gap, and is defended in both directions. Probe H2
confirms the verbatim `MoneyColumns` copy always moves amount + currency +
`_minor` as one unit, so it cannot pair one row's minor with another's amount.

Its weak point is **granularity, not the rule**. Where a value is one object the
hybrid is airtight; where a value is spread over independent columns the rule
runs field-by-field and composes badly — the FX block (**D-QA-15**), the
transfer verdict pair (**D-QA-18**), and a triple missing one column
(**D-QA-14**).

**A 17-probe second adversarial round** (`test/security/qa_pr24_probe_test.dart`)
raised **seven defects and two observations, none blocking**. Three are Medium;
none removes money from a total, none is a regression of what this PR fixed, and
the highest-value one (**D-QA-17**) is a *guard defeated by composition* with a
degradation this PR explicitly disclosed and deferred.

### Pass 4 (PR #20, P3b-2 — the mutation surface)

**No defect was found that blocks merge. Verdict: QA: PASS 20.** Head `61efd7b`.
All five claimed gates reproduced exactly: analyze clean, format clean (181 files,
0 changed), **986 passing / 3 skipped / 0 failing**, money-type guard clean, debug
APK built. `check_no_network_permission.sh` not run locally (needs a release build
and a merged manifest) — CI owns it, and the PR says so.

A **37-probe adversarial suite** was written and run
(`test/security/qa_pr20_probe_test.dart`, 33 probes;
`test/security/qa_pr20_probe_rescan_test.dart`, 4). Roughly two thirds of it
attacks the enrichment merge, because `docs/build-plan.md` names that the single
highest-risk operation in P3 and risk R-8 sets the standard it must meet.

**R-8 is upheld.** No probe made a transaction row disappear; no probe reached a
merge without confirmation; no probe got a negative magnitude past any DAO write
path. The soft-delete-with-pointers design does what it claims for the
single-merge case, verified by execution.

What the probes found is a **different failure mode than the one the file was
hardened against: not a lost row, but a lost figure.** `MergeEnrichment` genuinely
cannot express "write null" — that type-level property holds — but the safety
conclusion drawn from it is wider than the type, because the money columns it
does *not* carry (`fee_amount_*`, `converted_amount_*`, `fx_rate`) ride out of the
ledger on the soft-deleted row.

Nine defects and five observations raised, **none blocking**. Two are High
(**D-QA-5**, **D-QA-6**) because they remove money from a reported figure with no
signal — the KHA-74 shape, arriving through the very write path KHA-74's fix
anticipated. One more is High (**D-QA-8**) because it is an NFR-A2 audit hole on
*every* merge undo, not just an edge case.

They are not merge-blockers: each requires a deliberate, user-confirmed,
reversible action; the two money defects reduce *derived figures* while both
underlying rows remain intact and readable; and the whole screen layer is
unrouted today, so none is reachable by a user before the next phase wires
navigation. Fixing them is P3b-3/P4 work, and they should be fixed before any
build reaches a device.

### Pass 3 (PR #18, P3b-1 — multi-currency, refunds, income/transfers)

**No defect was found in P3b-1's own scope that blocks its merge. Verdict: QA: PASS 18.**
All five claimed gates were reproduced against the PR head `3ba320d`, not read
from the description: `flutter analyze --fatal-infos` (0 issues),
`dart format --set-exit-if-changed lib test integration_test` (159 files, 0
changed), `flutter test --exclude-tags=release_mode_guard` (**784 passed, 3
skipped**), `check_money_type_ban.sh` (pass), `flutter build apk --debug`
(built). Every figure matches.

Because two of this PR's claims are corrections to previously-filed defects, they
were verified by **executing** code rather than reading doc comments. An
11-test QA probe suite (`test/security/qa_pr18_probe_test.dart`) attacked the
sign convention at all three DAO write paths and probed five money-math /
transfer edge cases the engineer's `combined_totals_test.dart` does not cover.
Separately, every hand-calculated figure in that test's comments was re-derived
independently — **no arithmetic error found** — and its per-instrument
"slicing" assertion was specifically checked for weak-pass and found genuinely
load-bearing (see `docs/test-plan.md` §7d).

Three items raised, **none blocking**: **D-QA-3** (medium, KHA-79 — a third DAO
write path escapes the sign guard, with a green test pinning the wrong
invariant), **D-QA-4** (low–medium, KHA-80 — an *unpairable* transfer is counted
as spend with no AC-B11.2 review flag), and **O-QA-3/O-QA-4** (low, KHA-81 — a
doc comment contradicting the "zero is valid" decision, and an untested
ingestion branch). Details below.

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

### D-QA-14 — a half-written money triple reads as an ABSENCE, so the gap-fill overwrites a stored money value

- **Severity:** Medium. (The *behaviour* is High — the enrichment overwrites a
  stored money figure, which the file says is structurally impossible — but it
  is unreachable without a raw SQL write, the same residual class as O-QA-6.)
- **Found in:** pass 5 (PR #24), probe H3 in `test/security/qa_pr24_probe_test.dart`.
- **Affects:** `MoneyColumns.read`, `MergePlan.between`'s `fillMoney`;
  `transaction_merge.dart` property 3 ("enrichment fills gaps; it never
  overwrites"); PRD §3.4; risk R-8.
- **Root cause.** `MoneyColumns.read` returns `null` when **either** text column
  is null, and the fill helper treats that null as a gap. So a row holding
  `fee_amount_amount = '9.20'` with `fee_amount_currency = NULL` is
  indistinguishable, to the merge, from a row with no fee at all. The class doc
  argues correctly that "half a money triple is not a value"; it does not note
  that the *consequence* of that choice is that the stored number becomes
  silently **overwritable**.
- **Steps to reproduce** (synthetic):
  1. Insert an ordinary SAR purchase (`152.75`) as the survivor.
  2. `UPDATE transactions SET fee_amount_amount = '9.20',
     fee_amount_currency = NULL WHERE id = <survivor>`.
  3. Insert a duplicate with `fee = 5.00 SAR`.
  4. `MergePlan.between(survivor, other)` → `MergeAllowed`, no refusal.
  5. Merge with `confirmedByUser: true`.
- **Expected:** either `MergeRefusal.feeDiffers` (two rows disagree about a fee),
  or the survivor keeps `9.20`.
- **Actual:** `survivor.fee_amount_amount == '5'`. The 9.20 is gone from the
  survivor with no refusal, no flag and no count.
- **Reachability.** Not producible through any DAO write path: every money
  triple is written from a `Money?`, so all three columns move together.
  Reachable by a raw Drift/SQL write, and by a future migration that back-fills
  a currency column separately from its amount.
- **Fix direction:** treat a half-triple as a *disagreement* (refuse), not as an
  absence — it is the one case where "we cannot tell" should not fall through to
  a write. A `CHECK ((amount IS NULL) = (currency IS NULL))` on each triple
  would move the invariant to the column, and pairs naturally with O-QA-6.
- **Linear:** KHA-92.

### D-QA-15 — the FX block is carried as four independent gap-fills, so a survivor can state a converted amount and a contradicting rate

- **Severity:** Medium.
- **Found in:** pass 5 (PR #24), probe H4.
- **Affects:** `MergePlan.between` (`carriedFxRate`, `fxRateDate`,
  `fxRateSource`); AC-B9.3 (the detail screen shows rate + date + source);
  ADR-009; NFR-A6.
- **Root cause.** `_moneyDisagreement` refuses only when **both** rows hold the
  same field. `converted_amount`, `fx_rate`, `fx_rate_date` and `fx_rate_source`
  are then gap-filled **independently**. When the survivor holds one half of the
  FX record and the absorbed row holds the other, nothing collides, so nothing
  refuses — and the survivor ends up with an FX record assembled from two
  different messages. Contrast the deliberate care taken one layer down: *"each
  money triple is written whole or not at all … so a survivor can never end up
  holding an amount without its currency."* The same reasoning is not applied to
  the FX set.
- **Steps to reproduce** (synthetic):
  1. Survivor: `40.00 USD`, `converted = 150.00 SAR`, no rate.
  2. Other: `40.00 USD`, `fx_rate = '9.99'`, `fx_rate_date = 2026-07-20`,
     `fx_rate_source = 'sms_stated'`, no converted amount.
  3. Merge (allowed).
- **Expected:** either refuse (the two rows describe incompatible conversions),
  or carry the FX record as one unit.
- **Actual:** the survivor states `converted = 150 SAR` beside `fx_rate = 9.99`
  on a `40.00 USD` movement. `40 × 9.99 = 399.60`, not 150.
- **Blast radius, checked:** `report.spend.base` is **unaffected** — ADR-009
  case 2 prefers the bank's converted figure over a recomputation — so this is a
  displayed-provenance defect, not a total-corruption one. Probe H5 confirms the
  same gap-fill *does* move `spend.base` when the survivor has no converted
  amount, which is the intended KHA-87 behaviour and sets the severity floor.
- **Fix direction:** carry `(converted, rate, rateDate, source)` as one value,
  the way `MoneyColumns` already is, and refuse when the two rows' FX records
  are not equal-or-one-empty as a set.
- **Linear:** KHA-93.

### D-QA-17 — `MergeRefusal.chainWouldForm` is defeated by composing the D-QA-7 pointer overwrite with an undo

- **Severity:** Medium.
- **Found in:** pass 5 (PR #24), probe J1.
- **Affects:** `MergePlan.between`'s chain guard; `TransactionDao.restore`;
  NFR-A6; the D-QA-9 decision this PR records.
- **Root cause.** The guard reads **one scalar**,
  `mergedAway.merged_from_transaction_id`, to decide whether a row has absorbed
  anything. D-QA-7 — disclosed in this PR and deliberately deferred — means that
  scalar records only the **most recent** merge into that survivor. `restore()`'s
  new identity check then clears it when the most recent merge is undone, which
  is correct in isolation. After that, a survivor that still holds an *earlier*
  absorbed row looks, to the guard, completely unencumbered.
- **Steps to reproduce** (synthetic, all through the public service):
  1. `merge(survivor ← first)`; `merge(survivor ← second)`.
     `survivor.merged_from_transaction_id == second`; `first` is soft-deleted
     and points at `survivor`.
  2. `undo(second)` → identity check matches, pointer cleared to null.
  3. `merge(newSurvivor ← survivor)`.
- **Expected:** `MergeRejected(MergeRefusal.chainWouldForm)` — this is precisely
  the shape probe B6 asserts is refused, and the doc's stated reason for the
  guard is *"doing so would soft-delete the middle of a chain and leave the row
  it absorbed pointing at something that no longer counts."*
- **Actual:** `MergeCompleted`. The chain `first → survivor → newSurvivor`
  forms, with `first` soft-deleted and pointing at `survivor`, which is itself
  soft-deleted. Undoing the outer merge does not bring `first` back.
- **Not a money defect, checked:** `report.spend.base` is `305.5` — the correct
  figure for the two live movements — and `verifyChainIntegrity()` stays true.
- **Why it matters for the review.** The PR argues D-QA-7 is tolerable because
  the earlier link stays *readable* from `first.mergedIntoId` and from the audit
  trail — accurate as far as it goes. What the disclosure does not name is that
  the same scalar is the **input to a safety guard**, so the deferral is not
  only reduced convenience. **KHA-88's remaining scope is larger than the PR
  states.**
- **Fix direction:** either make the link set-valued (KHA-88's schema half, which
  fixes both), or have the guard ask the question directly —
  `SELECT 1 FROM transactions WHERE merged_into_id = :mergedAwayId` — which is
  authoritative regardless of what the scalar happens to hold.
- **Linear:** KHA-94.

### D-QA-16 — `conversion_pending` is cleared by a carried rate string without checking the rate converts

- **Severity:** Low.
- **Found in:** pass 5 (PR #24), probe H6.
- **Affects:** `MergePlan.between`'s `conversionPending` recompute; ADR-009
  case 4.
- **Reproduce:** survivor `40.00 USD` with `conversion_pending = true`; other row
  carries `fx_rate = 'not-a-rate'` (the malformed-legacy-row shape
  `BaseCurrencyConverter._parseRate` degrades gracefully for, per NFR-R5). Merge.
- **Expected:** the survivor is still pending — nothing arrived that converts it.
- **Actual:** `conversion_pending == false`, while `report.spend.base` is still
  `null`. The row claims it is no longer waiting for a conversion it still needs.
- **Bounded:** `spend.unconverted` is derived from the conversion *attempt*, not
  from the flag, so the "N transactions not converted" line still counts it —
  which is what keeps this Low rather than a KHA-74 repeat. The flag is used by
  `transaction_detail_screen.dart`, so the wrong state is user-visible.
- **Fix direction:** clear the flag only when the carried FX actually produces a
  base-currency figure, i.e. recompute from the post-merge row rather than from
  "a value was carried".
- **Linear:** KHA-95 (filed with D-QA-18 and D-QA-19).

### D-QA-18 — the internal-transfer group id is never gap-filled, because the carry is gated on the state

- **Severity:** Low.
- **Found in:** pass 5 (PR #24), probe J6.
- **Affects:** `MergePlan.between`'s `internalTransferGroupId`; AC-B11.2.
- **Root cause.** Both halves are gated on `survivor.internalTransferState ==
  null`. A survivor that holds a state but **no** group id therefore never gains
  one, even when the absorbed row states the same verdict and knows the group.
- **Reproduce:** set `internal` with no group id on the survivor; set `internal`
  with `groupId: 'grp-1'` on the other; merge (allowed — same verdict, no
  disagreement). `survivor.internal_transfer_group_id` is still null.
- **Expected:** the group id is a genuine gap on the survivor and the absorbed
  row holds it, so the gap-fill rule should fill it.
- **Actual:** it does not. The survivor keeps exactly the "half a decision" the
  field's own doc comment says the pairing exists to prevent.
- **Fix direction:** gate each half on *its own* emptiness, while still refusing
  when the two rows' verdicts disagree.
- **Linear:** KHA-95 (filed with D-QA-16 and D-QA-19).

### D-QA-19 — a rule-assigned `category_id` on the losing row is still silently dropped

- **Severity:** Low. (Not reachable until P4 assigns categories — which is the
  phase this PR gates.)
- **Found in:** pass 5 (PR #24), probe J8.
- **Affects:** `MergePlan.between`'s refuse-rather-than-strand loop; KHA-89's
  done check.
- **Root cause.** The loop iterates `incomingProtected` — the absorbed row's
  `user_edited_fields`. A `category_id` that was never a *user* edit is
  therefore neither compared, nor carried, nor refused: exactly the KHA-87
  shape, on a non-money column, still present after this fix. The user-edited
  case **is** correctly refused (probe J7 verifies it, including that neither
  row is mutated and no audit entry is appended).
- **Reproduce:** set `category_id = 'groceries'` on the losing row without
  touching `user_edited_fields`; merge. `survivor.category_id` is null and the
  category left the ledger with the soft-deleted row.
- **Fix direction:** when P4 lands, `categoryId` moves into
  `MergePlan.carriableFields` and is compared/carried like any other field —
  which the PR already anticipates in a comment. Until then the gap is real but
  unreachable.
- **Linear:** KHA-95 (filed with D-QA-16 and D-QA-18).

### D-QA-20 — the KHA-87 anti-regression check is a hand-written list, not a forcing function

- **Severity:** Low.
- **Found in:** pass 5 (PR #24), probe K1.
- **Affects:** KHA-87's third done-check, verbatim: *"A test pins that
  `MergePlan.between` compares every money-bearing column, so the next column
  added to `transactions` cannot silently join the 'neither compared nor
  carried' set."*
- **What was shipped.** Two checks. The one in `transaction_merge_test.dart`
  **is** a genuine forcing function — it enumerates `TransactionField.all` and
  fails by name when a value is handled by none of the three strategies. But
  `TransactionField` is the *user-editable* vocabulary and contains **no money
  column at all**. The money check is probe A8, a hand-written map of four
  columns; adding a fifth column to the schema changes nothing about whether A8
  passes.
- **Evidence it matters.** Probe K1 implements the schema-derived version, from
  Drift's own `db.transactions.$columns`. It immediately names two columns with
  no recorded merge decision anywhere: **`provenance`** and
  **`provenance_detail`** (NFR-A1's "where did this record come from" pair).
  Merging a `manual` row into an `sms` row silently rewrites which of the two
  the surviving record claims to be. Not money, hence Low — but the hand-written
  list could never have surfaced them, which is the point.
- **Fix direction:** promote probe K1's column enumeration into
  `transaction_merge_test.dart` beside the field-vocabulary check, and record a
  decision for `provenance` / `provenance_detail`.
- **Linear:** KHA-96 (filed with O-QA-10 and O-QA-11).

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
- **Status: FIXED in P3b-1** (2026-07-29). Schema **v4** adds `fx_rate_date`,
  `fx_rate_source` and `conversion_pending`; the parser writes all three from
  what the message supports and leaves them NULL where it does not; the S-11 FX
  block renders the rate date (or the literal words *"Date unknown"*) and the
  rate source beside every rate. Both halves of the done check exist:
  `test/widget/p3b_screens_test.dart` asserts a rate is never rendered without
  one of the two, and `test/features/ledger/p3b_ingestion_totals_test.dart`
  asserts a message stating no rate stores NULL rather than a default. The
  migration deliberately backfills nothing — a backfilled rate date would be
  fabricated provenance, which is this defect one level deeper
  (`test/data/db/schema_v4_migration_test.dart`).
- **QA confirmation (pass 3):** independently verified. The
  `occurredAtUtc`-not-`occurredAt` distinction — the thing that separates fixing
  this defect from papering over it — was checked in
  `ingestion_pipeline.dart:612-623`: where the pipeline fell back to the SMS
  delivery time, the rate date is left NULL rather than defaulted to that
  timestamp. **D-QA-2 / KHA-70 closed.**

### D-QA-3 — a third DAO write path escapes the sign-convention guard

- **Severity: Medium.** Found in pass 3 (PR #18, head `3ba320d`).
  **Not a merge blocker** — no production caller.
- **Linear:** KHA-79.
- **What.** PR #18 states *"There is no negative number anywhere in the
  transaction table"* and *"`TransactionDao` refuses a negative magnitude at the
  write boundary"*. Two of the DAO's three insert paths carry
  `checkMovementAmount` (`insertFromParsedSms:257`, `insertManualCompletion:413`);
  **`create():29` does not.**
- **Steps to reproduce** (synthetic data only, NFR-M3):
  `dao.create(amount: Money.parse('-1.500', currency: 'KWD'), actor: 'user')`
  → row persists with `amountAmount == '-1.5'`, `amountMinor == -1500`, and a
  well-formed audit entry, so it is indistinguishable downstream from a
  legitimate row. A debit carrying a negative magnitude then yields
  `LedgerTotals.spend(...).base == '-50'` — the O-QA-2 shape, still reachable.
  Reproduction in `test/security/qa_pr18_probe_test.dart`, probes A3/A4.
- **Expected vs actual.** Expected: every write path refuses a negative
  magnitude, per `sign_convention.dart`'s own *"failing loudly at the write
  boundary beats a negative magnitude reaching a total three screens away"*.
  Actual: one path accepts it silently.
- **Aggravating factor.** `test/data/dao/transaction_dao_test.dart:173`
  (`a negative KWD amount preserves its sign correctly`) **asserts the wrong
  invariant and is green**, so closing the gap means changing a passing test —
  the situation in which a guard tends to get reverted instead.
- **Why not blocking.** `create()` has no caller in `lib/`. It is a P1-era
  method for proving the audit mechanism. Every shipping path is guarded and QA
  verified both by execution. It matters because KHA-26 (P3b-2) is about to add
  a manual-entry write path and `create()` is the obvious method to reach for.

### D-QA-4 — an UNPAIRABLE transfer is counted as spend with no AC-B11.2 review flag

- **Severity: Low–Medium.** Found in pass 3 (PR #18). **Not a merge blocker.**
- **Linear:** KHA-80. Distinct from KHA-78 (which covers *paired* candidates
  that are flagged in the domain but do not reach the review inbox).
- **What.** `InternalTransferDetector.analyze` derives a state only for
  transfers it can pair; `SpendClassification` sets `needsReview` only for a
  derived `candidate`. A transfer it cannot pair at all yields `null`, is
  classified as ordinary spend, and carries **no flag** — though
  `internal_transfer.dart:338-341` promises such transfers *"stay visible as
  spend **and as a review item**"*.
- **Steps to reproduce** (`qa_pr18_probe_test.dart`, group PROBE C):
  (a) 2,000.00 SAR out / 533.19 USD in, same reference, 5 min apart →
  `spend.base == '2000'`, `needsReviewCount == 0`.
  (b) outgoing leg on a known instrument, incoming leg with `instrument == null`
  (too few digits to key on) → same result. Case (b) is **risk R-7's
  bootstrapping problem in its purest form**, and the common case early in the
  app's life.
- **Expected vs actual.** Expected (AC-B11.2): a transfer the app cannot
  classify is flagged for review, not silently classified. Actual: silently
  counted as spend. The *number* errs safely (over-statement, the documented
  bias); the *flag* half of the AC is not met, so the error is invisible rather
  than correctable.
- **Why not blocking.** No total is under-stated and no money is lost;
  AC-B11.2 passes for the case P3b-1 primarily targets. This is a sub-case gap.

### D-QA-5 — a merge silently removes the absorbed row's FX fee from the fee total

- **Severity: High.** Found in pass 4 (PR #20). **Not a merge blocker** (see why
  below). **Linear:** filed against KHA-64.
- **Affects:** ADR-017 D2, NFR-A6, PRD §3.4 ("the FX fee is its own figure"),
  and the PR's own claim that *"a merge is structurally incapable of deleting
  information. It fills gaps only."*
- **What.** `MergeEnrichment` carries five fields — `merchantRawText`,
  `referenceNumber`, `counterpartyName`, `occurredAt`, `instrumentId`. It has no
  `feeAmount`. `MergePlan.between` refuses a merge only on amount, currency,
  direction and type, so two rows that agree on all four but **disagree about the
  fee** are considered mergeable. The absorbed row is then soft-deleted whole,
  taking its `fee_amount_*` columns out of `LedgerTotals.feesFor` with it.
- **Steps to reproduce** (`test/security/qa_pr20_probe_test.dart`, probe A1):
  1. Ingest two alerts for one purchase, both `152.75 SAR`, `debit`,
     `pos_purchase`. Give the second a `feeAmount` of `9.20 SAR`.
  2. `LedgerTotals.report(...).fees.base` → `9.2`.
  3. `merge(survivorId: first, mergedAwayId: second, confirmedByUser: true)`
     returns `MergeCompleted`.
  4. `LedgerTotals.report(...).fees.base` → **`null`**.
- **Expected:** resolving a duplicate does not change what the bank charged. The
  fee is either carried onto the survivor, or the pair is refused as disagreeing
  about a money field, or the loss is flagged.
- **Actual:** the fee total silently drops to nothing. No error, no flag, no
  count. The survivor's `fee_amount_amount` is still `NULL`; the absorbed row
  still holds `9.2`, unreachable from any figure.
- **Why not blocking.** The row is not destroyed (R-8 holds), the action is
  user-initiated and reversible via `restore()`, and no screen routes to the
  merge yet. But it is exactly the KHA-74 failure mode — money absent from a
  total with no signal — arriving through a write path KHA-74's own fix
  anticipated, so it should not survive into P4.

### D-QA-6 — a merge can drop a foreign purchase out of the base-currency spend total

- **Severity: High.** Found in pass 4 (PR #20). **Not a merge blocker.**
  **Linear:** filed against KHA-64.
- **Affects:** AC-B9.2, ADR-009, NFR-A6.
- **What.** Same root cause as D-QA-5, on a different column.
  `convertedAmount`/`fxRate` are neither compared by `MergePlan.between` nor
  carried by `MergeEnrichment`. The natural D2 shape for a foreign card
  purchase is a terse first alert with no conversion and a second alert
  carrying the settled base-currency figure — and the review inbox offers the
  **older** row as the survivor by default, i.e. the one that cannot convert.
- **Steps to reproduce** (probe A2):
  1. Ingest `40.00 USD` with no `convertedAmount` (message 1) and `40.00 USD`
     with `convertedAmount = 150.00 SAR` (message 2).
  2. `report.spend.base` → `150` (the convertible row reaches the base total).
  3. Merge message 2 into message 1, confirmed.
  4. `report.spend.base` → **`null`**. 150 SAR left the headline figure.
- **Expected:** one movement, still worth 150 SAR in the base currency.
- **Actual:** the base figure becomes unavailable. Bounded damage — the native
  `40.00 USD` is intact and the row is reported in `unconverted`, so the user is
  *told* the figure is incomplete (probe A3 confirms this) — but the headline
  number they read dropped because they resolved a duplicate.
- **Why not blocking.** As D-QA-5: reversible, user-initiated, currently
  unroutable, and the error is disclosed via `unconverted` rather than hidden.

### D-QA-7 — a survivor that absorbs a second duplicate forgets the first

- **Severity: Medium.** Found in pass 4 (PR #20). **Linear:** filed against
  KHA-64.
- **Affects:** NFR-A6, and the PR's "pointers both ways" property.
- **What.** `merged_from_transaction_id` is a single nullable scalar.
  `mergeDuplicatePair` overwrites it on every merge into that survivor. Three
  alerts for one purchase (POS alert + "card used" alert + settlement alert) is
  not exotic and the D2 reference tier flags all of them.
- **Steps to reproduce** (probe B2): merge `first` into `survivor`, then merge
  `second` into `survivor`. `survivor.mergedFromTransactionId` is `second`; the
  link to `first` is gone from the survivor's row.
- **Expected:** the survivor records both absorptions.
- **Actual:** it records the latest. Reconstructible from `first.mergedIntoId`
  and from the audit trail (the `merge` entry records `from: first, to: second`),
  so this is degradation rather than loss — but the stated property is false
  after the second merge.

### D-QA-8 — `restore()` corrupts the survivor's merge link, and audits nothing against the survivor

- **Severity: High.** Found in pass 4 (PR #20). **Not a merge blocker.**
  **Linear:** filed against KHA-64.
- **Affects:** NFR-A2 (*"every mutation writes an append-only audit entry with
  actor and before/after"*), NFR-A6, AC-B6.4, US-F5.
- **Two problems in one method,** `TransactionDao.restore()` lines 310–323:
  1. It clears `merged_from_transaction_id` on `existing.mergedIntoId`
     **unconditionally**, without checking that the pointer it is clearing refers
     to the row being restored. After two merges into one survivor, undoing the
     *first* wipes the survivor's link to the *second*.
  2. It writes to the survivor row and appends **no audit entry against the
     survivor**. The only entry written is against the restored row's id. This
     happens on **every** merge undo, single or multiple.
- **Steps to reproduce** (probes B3 and B4):
  - B3: merge `first` then `second` into `survivor`; `survivor
    .mergedFromTransactionId == second`. Call `undo(first)`. Now
    `survivor.mergedFromTransactionId == null` while `second.mergedIntoId ==
    survivor` and `second.isDeleted == true` — the two halves of the link
    contradict each other and nothing in the app can detect it. The survivor's
    audit-entry count is **unchanged**.
  - B4 (minimal): merge `b` into `a`, then `undo(b)`. `a
    .mergedFromTransactionId` goes `b → null` silently; `a`'s change history
    still reads "merge" with no reversal, so US-F5 shows a merge that was undone
    as though it still stands.
- **Expected:** the restore clears only the pointer that names the restored row,
  and appends an entry to the survivor's history recording the reversal —
  exactly as the method's own doc comment says it does (*"records the reversal
  in the change history — an undo that left no trace would be its own audit
  failure"*). That sentence is currently true of the absorbed row only.
- **Actual:** as above. The audit chain itself stays intact
  (`verifyChainIntegrity()` is true) — this is a completeness gap, not tampering.
- **Why not blocking.** No money moves and no row is lost. But of the nine
  findings this is the one that is wrong on the *simplest* path, and it
  falsifies an NFR-A2 statement the PR makes in its own words.

### D-QA-9 — merge chains are possible in the survivor direction

- **Severity: Low.** Found in pass 4 (PR #20). **Linear:** filed against KHA-64.
- **What.** `transaction_merge_test.dart` has a test named *"an already-merged
  row cannot be merged again — no chains, no resurrection"*. It pins the
  **absorbed** direction only: merging a soft-deleted row is refused by
  `MergeRefusal.notLive`. A **survivor** is still live, so `a → b` then `b → c`
  is permitted.
- **Steps to reproduce** (probe B6): merge `a` into `b`, then merge `b` into
  `c`; the second returns `MergeCompleted`. Then `undo(b)` leaves `b` and `c`
  both live (spend `305.5` — inflation, the safe direction) with `a` still
  soft-deleted, and no flag telling the user they have a duplicate they already
  resolved once.
- **Expected:** either chains are refused, or the test name and doc comment stop
  claiming they cannot happen.

### D-QA-10 — a user edit on the losing side of a merge is discarded for the parser's value

- **Severity: Medium.** Found in pass 4 (PR #20). **Linear:** filed against
  KHA-26 (AC-B5.3).
- **What.** AC-B5.3 is *"user intent outranks the parser, always"*. The merge
  implements the narrower rule *"never overwrite the survivor"*. When the user's
  correction is on the row being merged away and the survivor still holds the
  parser's mis-read, the parser's text wins.
- **Steps to reproduce** (probe D2): two rows both parsed as
  `ALINMA*POS*3311`. Edit row `b`'s merchant to `Panda Hypermarket`. Merge `b`
  into `a`, confirmed. `a.merchantRawText` is still `ALINMA*POS*3311`; the
  correction lives only on the soft-deleted row and is off every screen.
- **Expected:** either the user-edited value is preferred, or the disagreement is
  surfaced (the file's own principle: *"two records that disagree about a value
  are not a merge candidate; they are a question for the user"* — currently
  enforced for amount/direction/type but not for merchant).
- **Actual:** silent. Nothing warns the user their correction stopped applying.

### D-QA-11 — a user value copied by a merge arrives on the survivor unprotected

- **Severity: Medium.** Found in pass 4 (PR #20). **Linear:** filed against
  KHA-26 (AC-B5.3).
- **What.** When the survivor's field is null and the absorbed row's value was a
  **user edit**, `MergePlan.between` copies it (correctly), but
  `mergeDuplicatePair` does not add the field to the survivor's
  `user_edited_fields`. The survivor now holds a user-authored value the app
  believes came from the parser, so the next automated write — a later merge, or
  P7's statement import — may overwrite it.
- **Steps to reproduce** (probe D3): `a` has no merchant; edit `b`'s merchant to
  `Panda Hypermarket`; merge `b` into `a`. `a.merchantRawText ==
  'Panda Hypermarket'` but `decodeUserEditedFields(a.userEditedFields)` is empty.
- **Expected:** protection travels with the value. The whole reason the rule
  lives in a column (per `user_edited_fields.dart`'s own doc) is that tomorrow's
  writer will not know about it.

### D-QA-12 — undoing a merge does not reverse the enrichment

- **Severity: Low.** Found in pass 4 (PR #20). **Linear:** filed against KHA-64.
- **What.** `transaction_merge.dart` says *"`restore()` reverses the entire
  operation"* and its test is named *"the merge is REVERSIBLE"*. `restore()`
  reverses the soft delete and (over-eagerly, see D-QA-8) the pointers. It does
  not reverse the field copies.
- **Steps to reproduce** (probe F6): merge a row carrying
  `EXTRA MART`/`REF-9911` into an empty one, then undo. Both rows are live and
  both now claim the same merchant and reference number.
- **Expected:** either the enrichment is reverted, or the doc stops calling the
  undo a full reversal. (Keeping the enrichment is arguably the better
  behaviour — gap-filling information is not harmful — so this may be a
  documentation fix.)

### D-QA-13 — AC-B5.3's re-scan half has no test in PR #20

- **Severity: Low** (coverage, not behaviour — the property **holds**). Found in
  pass 4. **Linear:** filed against KHA-26.
- **What.** KHA-26's done-check names four tests: *"edit-then-rescan preserves
  the edit; delete-then-rescan does not resurrect; restore returns the
  transaction with its history; erase-all leaves nothing restorable."* PR #20
  contains the second and third; the fourth is disclosed and ticketed (KHA-86);
  the **first is neither present nor disclosed**. AC-B5.3 is tested only against
  `MergePlan.between`, i.e. the merge path, not the re-scan path the AC's own
  wording names.
- **Notable because** this is the same shape of gap the engineer's self-review
  caught for AC-B6.3 and closed with `deleted_transaction_rescan_test.dart` — the
  symmetric edit case was not closed with it.
- **QA supplied the missing test:** `test/security/qa_pr20_probe_rescan_test.dart`
  (4 tests, real `IngestionPipeline` + real rule pack). All pass — an edited
  merchant, an edited amount and a user-cleared field all survive two full
  re-scans, and no second transaction row is written. Recommend the engineer
  move it to `test/features/ingestion/` alongside its sibling.

---

## Observations from the pass-5 probe suite (recorded for audit, not defects)

*(Both filed on **KHA-96**, alongside D-QA-20.)*

### O-QA-10 — the "an undo does not un-enrich" decision now preserves *money*, and the rationale predates that

D-QA-12 was resolved in PR #24 as a deliberate decision rather than a code
change, and the reasoning is sound as written: *"a gap-filled merchant name or
fee is information, the survivor's own record of it is now weeks old and may
have been categorised or corrected on top of, and stripping it would be the
merge deleting information on the way out."*

What changed underneath it is that KHA-87 made the enrichment carry **reported
money figures**. Probe J4: merge a row carrying a `9.20 SAR` fee into one with
none (`fees.base` correctly stays `9.2`), then undo — `fees.base` becomes
`18.4`.

This is **defensible and QA is not raising it as a defect**: after the undo both
rows are live duplicates again, so the *amount* doubles too (`spend.base` goes
`152.75 → 305.5`), the user is looking at two rows exactly as they were before,
and R-8 explicitly prefers an inflated total to a lost one. Recorded because the
property-1 doc comment still reads as though the decision only covers
descriptive fields, and the next reader deserves to know it also covers a number
on the fees line.

### O-QA-11 — a merge unconditionally clears the survivor's review flags, whatever they were for

`mergeDuplicatePair` writes `needsReview: false`, `reviewReason: null` and
`possibleDuplicateOfId: null` onto the survivor with no condition. A survivor
flagged for a **different** reason — an unparsable amount (KHA-74), an
internal-transfer candidate (AC-B11.2), or being a possible duplicate of a
*third* row — silently leaves the review inbox when an unrelated pair is
resolved.

**Pre-existing, not introduced by PR #24**: verified present on the merge-base
`4f49513`. Recorded here because it lands directly in **P4b's needs-review
screen**, which is the phase this PR gates, and because the failure mode is
"the review inbox quietly loses an item the user was going to be asked about" —
the same class of silence the whole merge design is built to avoid. Worth a
decision before that screen ships.

---

## Observations from the pass-4 probe suite (recorded for audit, not defects)

### O-QA-5 — `mergeDuplicatePair` is public and defaults `actor` to `'user'`

The "never automatic" control is real but lives in the service layer plus a
test, not in the type system: `TransactionDao.mergeDuplicatePair` can be called
directly, and its `actor` parameter defaults to `'user'`, so a future background
caller would write an audit entry claiming a person did it. Grep of `lib/`
confirms `TransactionMergeService` is the only caller today. Cheap hardening:
make `actor` required.

### O-QA-6 — no CHECK constraint defends `amount_amount` from a negative magnitude

KHA-79 closed the guard at all five DAO write paths (verified, probes E1–E4). A
raw Drift insert bypassing the DAO still stores `-50.00` and inverts a spend
total (probe E6). Not reachable from any app code path today. Relevant when P7
adds statement import, which is exactly the scenario `sign_convention.dart`
warns about.

### O-QA-7 — `ledger_mapping.dart` over-claims what makes a row unreadable

The library doc says a row is unreadable when *"`amount_currency` is not a
currency code this build understands"*. `Money` performs no currency validation
at all, so a row with `ZZZ` maps fine (probe G2). Behaviourally benign — such a
row lands in its own currency bucket and is reported as `unconverted`, i.e.
visible rather than dropped, which is what KHA-74 actually required. Fix the
sentence, or add the validation.

### O-QA-8 — the merge has no confirmation dialog; soft delete does

`needs_review_screen.dart` fires `onMerge!(item)` on a single tap.
`transaction_detail_screen.dart` owns a real `AlertDialog` for delete (AC-B6.2),
which is the strictly *less* dangerous operation. `confirmedByUser` would be set
by whatever caller is written later, so today the highest-risk operation in P3 is
one tap away in the UI layer while the lesser one takes two. Worth an in-screen
confirmation before the merge is ever routed — particularly given D-QA-10, where
a mis-tap silently discards a user's correction.

### O-QA-9 — none of P3b-2's providers has a production consumer yet

`transactionMergeServiceProvider`, `manualEntryServiceProvider`,
`transactionEditServiceProvider` and
`internalTransferDecisionServiceProvider` are constructed but never watched: the
app shell still routes only to `HomePlaceholderScreen`. This is consistent
across the whole screen layer, pre-existing, and honestly disclosed by the PR's
own *"nothing here has run on a device"*. Recorded only so the claim *"its only
caller is a user action in the review inbox"* is read as intent rather than as a
present fact.

---

## Observations from the pass-3 probe suite (low severity, recorded for audit)

### O-QA-3 — an ingestion comment contradicts the "zero is valid" decision

- **Severity: Low** (documentation). **Linear:** KHA-81.
- `ingestion_pipeline.dart:578` (added by PR #18) says *"a negative **or zero**
  magnitude is as unusable as a missing one"*, and the comment below it says a
  zero amount *"must never happen"*. Both contradict `sign_convention.dart`'s
  deliberate *"Accept zero"* contract (KHA-25: unknown must stay distinguishable
  from zero) and the green test that pins it.
- The **code is correct** — `violationForAmount` rejects negative only. Only the
  comment is wrong. It sits directly above the guard, telling the next reader
  that zero should be rejected, which is an invitation to "fix" the code and
  break KHA-25 — the exact failure mode `sign_convention.dart` warns about.

### O-QA-4 — the ingestion negative→review-queue branch has no test

- **Severity: Low** (coverage gap; code reads correct). **Linear:** KHA-81.
- PR #18 claims O-QA-2's domain half is closed by two mechanisms. The DAO half
  is tested and QA re-verified it by execution. The ingestion half
  (`ingestion_pipeline.dart:585` → `financial_unparsed` raw message,
  `routedToReviewQueue + 1`, no throw) is **not** exercised by any test, because
  the bundled `sa-core` pack cannot produce a negative amount and no synthetic
  pack fixture was added.
- The branch exists specifically for risk R-11 (an imported pack whose regex
  captured a leading minus) — so the one scenario it was written for is the one
  nothing verifies.

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
- **Status: half fixed in P3b-1** (2026-07-29), and the half that is fixed is the
  one that made the other half undecidable.
  - **The domain half is closed.** KHA-28 settled the sign convention and it is
    written out in full in `lib/core/money/sign_convention.dart`: an amount is a
    non-negative magnitude, the sign lives in `direction`, and **zero stays
    valid** (KHA-25 — zero and unknown are different facts). `TransactionDao`
    now refuses a negative magnitude at the write boundary, and the ingestion
    pipeline routes one to the review queue rather than storing it. The
    adversarial test that used to assert this defect
    (`test/security/p3a_adversarial_test.dart`) now asserts the fix.
  - **The form half stays with KHA-26 (P3b-2):** the field-level error message
    (`AppLocalizations.amountMustBePositive`, added here) and the "point at the
    direction control" affordance. The contract KHA-26 must satisfy is
    enumerated in the doc comment on `sign_convention.dart`, so it is building
    against a settled decision rather than guessing what "negative" means.

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

### Fixed in PR #24 (P3b-3), verified by QA on head `8761e3e`

Each row was **re-verified by execution**, not accepted from the PR body. The
"Verified by" column names the probe QA ran; every one of those probes is an
**inversion in place** of the probe that originally asserted the defect (same
fixtures, same message ids, same amounts, original comment retained with an
`INVERTED (was: ...)` marker) — confirmed by reading the diff, so none was
weakened or renamed to pass trivially.

| Defect | Severity | Fixed how | Verified by |
|---|---|---|---|
| **D-QA-5** — the FX fee leaves the ledger with the absorbed row | **High** | `MergeEnrichment` carries the fee triple; `MergeRefusal.feeDiffers` when both rows disagree | Probe A1 — `report.fees.base` is `9.2` after the merge (was null). A1b/A5/A6 pin the refusal, the no-double-count case, and the currency comparison |
| **D-QA-6** — a foreign purchase drops out of base-currency spend | **High** | `convertedAmount` / `fxRate` / `fxRateDate` / `fxRateSource` carried; `conversionDiffers` on disagreement | Probes A2/A3 — `report.spend.base` is `150` and `spend.unconverted` is empty (was null / non-empty) |
| **D-QA-8** (both halves) — `restore()` clears the wrong pointer, and audits nothing against the survivor | **High** | Identity check (`survivor.mergedFromTransactionId == id`) with `getSingleOrNull`; new `merge_undo` audit entry inside the same `transaction()` block | Probes B3/B4 + QA probes L1/L2 — the unrelated merge's pointer survives, a single-merge undo yields `create, merge, merge_undo` with a genuine `b → null`, row `updated_at` and entry `changed_at` are one instant, chain integrity holds, and a dangling survivor id no longer aborts the undo |
| **D-QA-10** — a user edit on the losing side loses to the parser | Medium | `MergeRefusal.userEditDiffers` (a refusal, not "the correction wins" — correctly, since winning would overwrite a populated field) | Probes D2/D2b + QA probe J7 — refused, and neither row is mutated (asserted against the audit log, not only `isDeleted`) |
| **D-QA-11** — a copied user value arrives unprotected | Medium | `MergeEnrichment.protectedFields`, unioned into the survivor's `user_edited_fields` **in the same write** | Probe D3 — a third row carrying parser text can no longer re-enrich the field |
| **D-QA-9** — merge chains possible in the survivor direction | Low | `MergeRefusal.chainWouldForm` | Probes B6/B6b — refused in the survivor direction, still refused in the absorbed direction, and a survivor absorbing a *second* duplicate stays legal. **Partial: see D-QA-17**, which defeats the guard by composition |
| **D-QA-12** — undo does not reverse the enrichment | Low | Resolved as a recorded **decision**, not a code change; doc and probe F6 updated | Probe F6. **See O-QA-10** — the decision now also preserves money |
| **D-QA-13** — AC-B5.3's re-scan half untested / mis-located | Low | Test moved to `test/features/ingestion/edited_transaction_rescan_test.dart` | Present beside `deleted_transaction_rescan_test.dart`; suite green |
| **O-QA-5** — `mergeDuplicatePair` defaults `actor` to `'user'` | Observation | `actor` is now **required** with no default | Probe C2 — enforced by the compiler, which is stronger than any runtime assertion |
| **O-QA-7** — `ledger_mapping.dart` over-claims what makes a row unreadable | Observation | The **sentence** was corrected and the reason the behaviour is right (visible, not dropped — KHA-74) recorded | Probe G2 |
| **O-QA-8** — the merge fired on a single tap while soft delete had a dialog | Observation | `_confirmMerge` `AlertDialog`, mirroring the delete dialog; cancel positively worded ("Keep both") and first; barrier-dismiss merges nothing; EN + AR copy | `p3b2_screens_test.dart` — three widget tests (confirm / cancel / dismiss), each asserting `actions isEmpty` on the non-merge paths |

**Deliberately NOT fixed, and disclosed in the PR body rather than implied —
QA confirms the disclosure is accurate:**

- **D-QA-7** (the set-valued `merged_from_transaction_id`). The PR fixed the
  **false doc claim** instead — `transaction_merge.dart` no longer says
  "pointers both ways" per *survivor*, it says it per *merge*, and names where
  the earlier link stays readable (`first.mergedIntoId`, plus the survivor's
  `merge` audit entry with its `from → to`). Probe B2 asserts that reachability
  by execution. QA verified all of this and agrees it is honest and correctly
  scoped. **One correction to the reasoning:** the disclosure calls the
  degradation "reduced convenience, not lost traceability", which understates
  it — the same scalar is the input to the new chain guard, so the deferral has
  a safety consequence (**D-QA-17**). KHA-88 must stay open, and its remaining
  scope is larger than the PR states.
- **KHA-90 O-QA-6 and O-QA-9** — untouched as instructed; still open.
