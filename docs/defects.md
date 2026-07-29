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

### Pass 9 (PR #41, P5a — home dashboard, transaction list, bank/instrument screens, and the three P5-entry-gate High defects)

**Nothing found that blocks merge. Verdict: `QA: PASS 41`.** Head `d9fac9e`.
Scope: KHA-35, KHA-36, KHA-113, KHA-114, KHA-115.

**This is the PR that makes the app usable end to end for a new user, so the
question that got the most attention was the plainest one: would a real fresh
install actually work?** It would. The chain that was broken — nothing in `lib/`
called `SmsPermissionService.request()`, so a fresh install never activated —
is now closed at both ends: the onboarding gate calls it, and (verified
separately, because nothing tested it) the foreground sweep converts a granted
permission into a ledger *however* the permission arrived, including the
out-of-band Android-Settings grant a human hit in practice.

All four engineer-claimed gates were **re-measured on `d9fac9e`** rather than
cited: format clean (234 files, 0 changed), analyze clean, **1434 pass / 3 skip /
0 fail**, Flutter floor satisfied. See `docs/test-plan.md` §7g.1.

**Two claims were checked by mutation rather than by reading, and both mutations
found something:**

1. **NFR-A6's generated sweep does not cover what its doc comment says it does.**
   Removing `transfers: transfers` from `BankTreeBuilder._nodeFor` — the change
   that makes every internal transfer count as spend at the sending bank, which
   `LedgerTotals.report`'s own doc calls *"the most plausible way to reintroduce
   AC-B11.1 as a bug"* — leaves `totals_reconciliation_test.dart` **passing
   5/5**. The shipped behaviour is correct; the test simply cannot see it,
   because its generator emits only `posPurchase`/`refund` in `SAR`. Recorded as
   **G-QA-41-1** and **closed in this pass** by probes A1–A3.
2. **NFR-S3's regression test is not load-bearing.** Commenting out
   `_collapseToLockGate()` in `lib/app.dart` leaves
   `p5a_lock_collapses_stack_test.dart` **passing 2/2**, because that test
   re-implements the collapse inside the test file and drives the copy. Filed as
   **D-QA-41-1** (low). QA's probe C1 pumps the real `MassrofyApp` and does fail
   on the mutation.

**Nine QA probes** (`test/security/qa_pr41_probe_test.dart`), all passing on
`d9fac9e`, zero production diff:

| Probe | What it attacks | Result |
|---|---|---|
| A1 | internal transfer split across **two banks** — the slicing trap | chain exact; transfer excluded from both bank totals and the period total |
| A2 | additivity **under currency conversion**, incl. the "N not converted" counts | exact; counts reconcile at both levels |
| A3 | 200 generated ledgers, different seed, 9 debit types + 3 credit types + 3 currencies + fees + cash + transfer pairs | chain holds every run |
| A4 | **business oracle** — 17-transaction realistic month recomputed by an independent fold and a hand-written literal | `5,436.55 SAR` exactly; drill-down `5,376.55`, i.e. −60.00 cash, as designed |
| A5 | a **candidate** transfer must keep counting (the deliberate over-statement bias, risk R-7) | counts and flags — a future "fix" that excluded it would now fail |
| B1 | permission granted **outside the app** (Android Settings), rationale screen bypassed | sweep runs, 3 inbox messages → 3 transactions |
| B2 | control: permission denied | sweep null, nothing written |
| B3 | granted later + the resume handler's two `invalidate` calls | import starts on the very next sweep, no relaunch |
| C1 | NFR-S3 on the **real** `MassrofyApp`, not a copy | pushed route with a figure on it is gone after a lock |

**Also verified rather than accepted:** the KHA-115 diagnosis is genuinely the
SDK's `persist = persist ?? action != null`, and QA grepped `lib/` independently
— the four other `showSnackBar` call sites carry **no action**, so none of them
can persist, and nothing slipped past the new `source_hygiene_test` guard. The
hero-tag fix is real (`fab.home` / `fab.transactionList`). The NFR-U4 greyscale
test is a real negative-control test, not a token check. `KHA-37` genuinely
exists and owns the deferred Reports tab, and `KHA-38` genuinely owns AC-E5.3;
neither is silently dropped scope.

**The app was RUN, on a device, as a new user — and the fresh-install journey
works.** Debug APK from `d9fac9e` on the `massrofy_test` AVD (API 35) after
`pm clear`, with both SMS permissions confirmed `granted=false` first. Fourteen
journeys `RUNTIME-VERIFIED`, sixteen screenshots in
`docs/evidence/qa-pr41/`. The two that matter most:

- **KHA-113's fix works end to end.** Fresh install → lock gate → **S-02
  rationale** → the real OS dialog → granted → Home. Then two rule-pack-matching
  Arabic BAJ messages became a ledger, and Home showed **`−972.40 SAR`** — which
  is exactly `312.40 + 660.00`, the hand-computed sum of what was seeded. Deleting
  the 660.00 row moved it to **`−312.40 SAR`** (`972.40 − 660.00`) and the Banks
  screen agreed to the halala (`Bank Aljazira · −312.40 SAR`). **NFR-A6's chain
  and AC-E1.2 verified on hardware, not only in tests.**
- **KHA-114's fix works, including its undisclosed half.** S-11 offers Edit and
  Delete; Delete raises AC-B6.2's confirmation; and after confirming, the row
  **stays on screen** with the deleted banner and a Restore button — the
  `watchById` change, which is the part that was never filed.

**Two things the walk found that no test could**, both filed, neither blocking:
**KHA-122** (Medium, Epic A — an SMS arriving while the app is *open* is not
ingested until the next foreground cycle, so AC-A1.1's *"without any user
action"* does not hold on a device; `requestImmediateSweep()` has no caller) and
**KHA-123** (Low — S-11 reads *"SMS · Unknown bank"* because `bankDisplayName`
has no production caller, the fifth omitted-optional-parameter on that screen).

Five observations recorded below (O-QA-41-1..5), none blocking.

### Pass 8 (PR #34, P4b — the categorization UI + ADR-008 v1.4 code fix)

**No defect was found that blocks merge. Verdict: `QA: PASS 34`.** Head
`0585fd4`.

**Depth was deliberately asymmetric**, and that is a decision worth recording
rather than a shortcut. `docs/PRD.md` now declares `TIER: personal`, so the new
UI/CRUD surfaces got journeys plus five highest-value attack probes rather than
a 30-probe sweep. **The merchant-matching engine was exempted from that
trim**: `merchant_key.dart` has now needed *four* adversarial rounds to catch
real money-correctness bugs (KHA-98, KHA-99, KHA-106, KHA-107), and every one of
those was missed by a pass that checked *worked examples*. So this round
attacked it **mechanically over a generated corpus** instead — 7,290 strings
over a token alphabet spanning every kind the pipeline distinguishes, plus a
**differential against ADR-008 v1.3's algorithm transcribed verbatim from
`dc3f362`**, so the behaviour change could be *enumerated* rather than
described.

**The headline result: the fix is sound, and it is sound in the strong sense.**

| Property | Evidence |
|---|---|
| **KHA-107 idempotence** — `of(of(x)) == of(x)` | **0 violations / 7,290 strings** (PROBE E1). The premise the proof rests on (`referenceMarkerTokens ⊆ noiseTokens`) asserted directly (E1b) |
| **KHA-106 / KHA-98 / KHA-99 collision class** | **0 key classes span more than one name**, over the whole corpus (PROBE E2). This is the property all three defects violated, checked as a partition rather than as a pair |
| **No THIRD dangerous cost** | v1.4 introduces **818 new merges** over the corpus and **not one joins two different names** (PROBE E4) |
| **KHA-109 all-digit residual not worsened** | v1.4 **shrinks** it — 48 strings lose an all-digit key, 4 gain one (PROBE E5) |

Both **KHA-106 and KHA-107 done-checks are met**, verified against the code and
against the **inverted-in-place** PROBE M1/M2 (read in the diff — same fixtures,
same comments, flipped assertions; neither was weakened or renamed to pass).

**Three items raised, none merge-blocking:** one Low documentation-accuracy
defect (**D-QA-34-1**), one test-strength gap (**G-QA-34-1**), one observation
(**O-QA-34-1**). All three are below.

**Reachability was verified by grepping the construction site**, per the
`docs/lessons.md` rule — not from the fact that the widgets exist:
`app.dart` → `HomePlaceholderScreen` (unlocked branch only) →
`openNeedsReview` / `openCategoryManagement` / `openLearnedRules` /
`openRecentlyDeleted`, and `NeedsReviewHost` → `openTransactionDetail` /
`CompleteUnparsedHost`. **`app.dart` still routes nothing above the lock gate**,
so no P4b screen is reachable before unlock. The conditional merge gate
recorded in `docs/lessons.md` (KHA-87/88/94/96/98–105) is therefore correctly
discharged: this PR routes all three named screens and all fourteen issues are
closed.

**Gates re-run by QA on `0585fd4` itself**, per the rule that a gate result is
evidence only for the tree it was measured on:

| Gate | Result on `0585fd4` |
|---|---|
| `flutter analyze` | clean — `No issues found!` |
| `dart format --set-exit-if-changed lib test` | clean — **215 files, 0 changed** (216 / 0 with the QA probe added) |
| `flutter test` | **1340 passing / 3 skipped / 1 failing** |

The single failure is `privacy_overlay_release_mode_test`, which needs CI's
dedicated `--dart-define=dart.vm.product=true` step. **QA confirms the
engineer's disclosure is exact** — same count, same single environment-dependent
test.

---

### D-QA-34-1 — ADR-008 v1.4's disclosed cost is **wider than the example that documents it** (Low, documentation-accuracy)

**Found by:** PROBE E4b, `test/security/qa_pr34_probe_test.dart`. Executed.
**Severity:** Low. **Not merge-blocking.** **Owner:** solution-architect.

The PR and ADR-008 v1.4 disclose cost #2 with one worked example — a **4-digit**
pair, `QAMART 1000 STORE` == `QAMART 2000 STORE` — and pin it as a test.

The real class is **any digit run adjacent to a reference marker on either
side, at any length**, and the sub-4-digit half of it is **genuinely new in
v1.4**. The differential shows it directly:

```
ofV13('QANDA 100 STORE')  ->  'QANDA 100'   // v1.3: two identities
ofV13('QANDA 200 STORE')  ->  'QANDA 200'
of   ('QANDA 100 STORE')  ->  'QANDA'       // v1.4: ONE identity
of   ('QANDA 200 STORE')  ->  'QANDA'
```

v1.3 read adjacency on the **left only**, so a right-hand marker did not
corroborate and the run survived; the length signal only reached runs of >= 4.
So three-digit numbered siblings with a trailing marker were two merchants
before this PR and are one after it.

**Why this is Low and not High.** It merges numbered siblings **of one name**,
never two names — PROBES E2 and E4 prove that mechanically over 7,290 strings.
And it is the **necessary consequence of order-insensitivity**: `QANDA STORE
100` and `QANDA STORE 200` already merged under v1.3, so the permutation
`QANDA 100 STORE` / `QANDA 200 STORE` *must* merge too, or KHA-107 is not fixed.
The behaviour is right.

**The defect is the disclosure, not the behaviour** — and that is exactly
KHA-106's own filing rationale, quoted from that issue: *"the trade may well be
the right one … but it was not **decided**"*. A future reader comparing the
consequences list against the code will find the list narrower than the rule.

**Fix (one sentence, no code):** state the cost as the *class* rather than the
*example* — "a digit run adjacent to a reference marker on either side is
stripped at any length, so numbered siblings carrying a marker share one key" —
in ADR-008 settled answer 8 and in `referenceMarkerTokens`' doc comment.

**Done check:** ADR-008 v1.4's consequences state the length-independence, or a
test pins a sub-4-digit pair alongside the existing 4-digit one.

---

### G-QA-34-1 — KHA-97's done-check asks for the AC-C1.3 invariant on the **widget** path; no P4b test asserts it (coverage gap, Low)

**Found by:** reading KHA-97's done-check against the shipped tests.
**Severity:** Low — **the behaviour is correct; only the evidence was missing.**
**Not merge-blocking.** **Owner:** mobile-engineer (or closeable as done).

KHA-97's done-check says, verbatim:

> both decisions leave the AC-C1.3 category-sum invariant intact (already
> covered by `test/features/categorization/category_sum_invariant_test.dart` at
> the data layer — **this adds the widget-level path**)

Grepping `reconciles` / `AC-C1.3` in `test/widget/p4b_screens_test.dart` and
`test/features/categorization/category_correction_test.dart` returns **nothing**.
The widget-level half was not added. This is the KHA-22 shape from
`docs/lessons.md` — a done-check that is not fully met while the issue reads as
shipped.

**QA supplied the missing coverage rather than only reporting it.** PROBES U1
and U2 wire the **real `CategoryDao`** behind the real `CategoryManagementScreen`'s
`onDelete` callback and drive the S-15 dialog with taps, so what is verified is
the production write the button actually performs. **Both pass**, with the money
figures checked as business oracles rather than self-consistency:

* delete-with-uncategorize: total stays **175.00** (= 100 + 40 + 25 + 10 by
  hand), `uncategorizedCount` goes 1 → 3, the category row is gone;
* delete-with-reassign: `groceries` becomes **165.00** exactly (= 100 + 40 + 25),
  i.e. the money **moved into the target**, not merely detached from the deleted
  category;
* AC-C3.3 verified as a property of the widget tree — `deleteConfirm.onPressed`
  is `null` until a decision exists.

**Done check:** met by `test/security/qa_pr34_probe_test.dart` PROBES U1/U2 as
of this pass. The issue can be closed on that basis, or the tests moved into
`p4b_screens_test.dart` if the engineer prefers them beside their siblings.

---

### G-QA-34-2 — the shipped AC-C5.2 undo test names the failure mode it must construct, and does not construct it (test-strength gap, Low)

**Found by:** reading `category_correction_test.dart` against AC-C5.2.
**Severity:** Low — **the production code is correct.** **Not merge-blocking.**

The test *"rows that had DIFFERENT prior categories each get their own back,
not a default"* states the risk exactly right in its own comment — *"this is the
case a 'reset to Uncategorized' undo destroys"* — and then seeds **three rows
whose prior category is all `null`**, asserting all three back to `null`. **A
buggy undo that reset every row to Uncategorized would pass it unchanged.**

The mixed case *is* reachable: the bulk fill only touches **uncategorized** rows
(AC-C5.1), but the **target** row may already carry a category — a user
correcting a wrong category is the product's highest-frequency interaction
(NFR-U7).

**QA constructed it (PROBE U5) and the production code passes**: one row
starting at `dining` plus two blanks, corrected merchant-wide to `groceries`,
then undone — the target returns to **`dining`** and the other two to **`null`**.
Three rows, two different answers, neither a default. The audit chain still
verifies. So `CategorySnapshot`'s six-column restore genuinely works; only the
shipped test was weak.

---

### O-QA-34-1 — v1.4 also *improves* an undisclosed case (observation, not a defect)

The differential surfaced a change in the safe direction that the PR does not
mention: a bare number beside a marker used to key as that number, and now has
**no identity at all**.

```
ofV13('100 STORE')      ->  '100'
MerchantKey.ofOrNull('100 STORE')  ->  null
```

This is KHA-102's reasoning applied correctly — a string of nothing but
structural tokens and a number cannot distinguish two businesses — and it
**shrinks the KHA-109 all-digit-key residual** (48 strings lose an all-digit key
across the corpus; 4 gain one, e.g. `LLC 2000` → `2000`, net −44). Recorded
because an *undisclosed improvement* is still an undisclosed behaviour change,
and KHA-109 remains open.

---

### Pass 7 (PR #30, P4a-1 — merge-undo fixes + merchant-identity corroboration)

**No defect was found that blocks merge. Verdict: `QA: PASS 30`.** Head
`3620388`. This is the **third** adversarial round on `MerchantKey`/
`MerchantMatcher` and the **third** on the merge/undo link, so the pass was run
against the eleven issues' own **done-checks** rather than against the PR's
self-description.

**All eleven done-checks are met.** KHA-88, KHA-94, KHA-96, KHA-98, KHA-99,
KHA-100, KHA-101, KHA-102, KHA-103, KHA-104, KHA-105 — each verified by
executing the reproduction the issue specifies. Both corrections the PR
discloses about its own upstream claims (the ADR-008 v1.3 `QAFE QAFE`
Jaccard-vs-DL footnote; KHA-101's reachability premise) were **checked rather
than accepted**, and both are accurate.

**Gates re-run by QA on `3620388` itself**, per the `docs/lessons.md` rule that a
gate result is evidence only for the tree it was measured on:

| Gate | Result on `3620388` |
|---|---|
| `flutter analyze` | clean — `No issues found! (ran in 6.3s)` |
| `dart format --set-exit-if-changed .` | clean — **208 files, 0 changed** |
| `flutter test` | **1242 passing / 3 skipped / 1 failing** |
| ADR-002 money-type guard | clean |

Every number the PR body claims reproduces exactly. The one failure is
`privacy_overlay_release_mode_test.dart`, confirmed environmental **by
execution, not by trust**: re-run with the `--dart-define=dart.vm.product=true`
CI supplies as its own step, it passes. Flutter 3.44.8. Evidence:
`docs/evidence/pr30/`.

**QA's own adversarial suite for this round:** `test/security/qa_pr30_probe_test.dart`
— **18 probes, all passing** (16 `HOLDS`, 2 `DEFECT`). The suite deliberately
does *not* re-run the inverted probes in `qa_pr20/24/27_probe_test.dart`; it only
asks questions those files do not.

**Two new defects, both strictly NARROWER residuals of defects this PR closes,
and neither merge-blocking for PR #30.** Blocking this PR would leave the wider
originals (KHA-98/99) in place, which is plainly worse:

- **D-QA-30-2 (High, and R-16-gated)** — the KHA-99 trailing-digit collision is
  closed at 3 digits and **open at 4**: `QAMART 1000` and `QAMART 2000` still
  key as one merchant and auto-apply at T1/1.00. Undisclosed by ADR-008 v1.3.
- **D-QA-30-1 (Low)** — `MerchantKey.of` is not idempotent, which its own doc
  comment states as a load-bearing invariant. Effect is a *split*, the
  recoverable direction, and no shipped call site double-applies it.

**One observation:** O-QA-30-1 — KHA-103's `isUserOwnedCategory` guard reads
wider than the comment beside it. The dangerous state was attacked and is
**unreachable** (probe P1), so this is a comment-accuracy note, not a defect.

**Merge-undo: nothing left standing.** Five composition probes past what J1/J1b
cover — three-deep absorbs, an undo in the middle of a chain, merge→undo→
re-merge, concurrent merges into one survivor, and the restored-row ghost case —
**all hold**, with the "scalar is null iff the set is empty" invariant asserted
after *every* mutation rather than once at the end. KHA-88/94/96 are closed
properly, not narrowly.

### Pass 6 (PR #27, P4a — the categorization spine)

**No defect was found that blocks merge. Verdict: `QA: PASS 27`.** Head
`10df548`. Every claimed gate reproduced **on that exact SHA, by QA, locally**
(the `docs/lessons.md` rule that a gate result is evidence only for the tree it
was measured on): `flutter analyze` clean (5.4s), `dart format --set-exit-if-changed`
clean — **207 files, 0 changed** (the PR body says 204; the discrepancy is in the
count, not the result, and 207 is what head `10df548` actually contains),
`flutter test` **1190 passing / 3 skipped / 1 failing**, ADR-002 money-type guard
clean. Flutter 3.44.8 / Dart 3.12.2. The one failure is
`privacy_overlay_release_mode_test.dart`, confirmed pre-existing and
environmental rather than taken on trust: it **passes** when re-run with the
`--dart-define=dart.vm.product=true` it requires, which CI supplies as its own
step. Evidence: `docs/evidence/qa-pr27/`.

**AC-C1.3 — the money-correctness invariant — holds under every attack QA could
construct.** Eleven adversarial compositions the engineer's fixture did not
cover: a refund filed under a *different* category from the purchase it reverses
(the slice must go negative, and does), the two legs of an internal transfer
split across two categories, a category holding only unconvertible foreign
money, `includeEmptyCategories: true` over an entirely unconvertible period, all
four category operations applied in sequence to the same live money, ten
concurrent creates of one name, and a hand-corrupted `category_id`. Each was
checked twice — once via `CategoryBreakdown.reconciles`, and once by QA
re-summing the slices independently against a category-blind `LedgerTotals.spend`.

**AC-C3.3's trigger genuinely replaces `FK RESTRICT`.** Attacked with raw SQL
that never touches the DAO, an unfiltered `DELETE FROM category` (the case a
DAO-only guard would miss), a *soft-deleted* referring transaction, a referring
`merchant_rule` with no transaction involved, and the protected *Uncategorized*
row. All five refused; the bulk delete rolled back completely rather than
partially wiping the table.

**Eight defects, none merge-blocking for this PR, four of them merge-blocking
for the P4b surfaces** (KHA-98/99/101/102 → conditions recorded as `blocks`
links in Linear, not only in prose — the `docs/lessons.md` lesson from PR #20).
The two that matter most are the same shape and both contradict AC-D2.3's
absolute bar: **normalisation can collapse two unrelated merchants into one
identity at confidence 1.00**, above every tier gate and above any value
`autoApplyThreshold` could take — via city-name noise stripping (D-QA-27-1) and
via a punctuation-only placeholder key (D-QA-27-7). The mechanism in the first
case is mandated by ADR-008, so it is escalated to solution-architect rather
than filed as an engineer error.

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

### Pass 9 (PR #41, P5a), head `d9fac9e`

#### D-QA-41-1 — NFR-S3's lock-collapse regression test drives a copy of the production logic, so it cannot catch the regression it was written for

**Severity: LOW.** The shipped code is **correct** — probe C1 confirms the real
`MassrofyApp` collapses the stack on lock. What is wrong is the *test*, which
gives a security NFR the appearance of protection it does not have. Filed
because the next person to touch `app.dart` will reasonably believe a green
suite means NFR-S3 is still held.

**Steps to reproduce**

1. In `lib/app.dart`, comment out the `_collapseToLockGate();` call inside
   `_AppLockGatewayState.build`'s `ref.listen` callback.
2. `flutter test test/widget/p5a_lock_collapses_stack_test.dart`

**Expected:** at least one test fails — the file's own header says it exists to
pin *"the gateway therefore collapses the stack on every lock."*

**Actual:** `00:03 +2: All tests passed!`

**Root cause.** The test declares its own `_Gateway`/`_GatewayState` with its own
copy of the `popUntil((route) => route.isFirst)` post-frame callback, and pumps
that. `_AppLockGateway` is private to `app.dart`, so the author could not
construct it directly — but `MassrofyApp` is public and can be pumped with
`appLockControllerProvider`, `unlockedDatabaseSessionProvider`,
`smsPermissionServiceProvider`, `smsSourceProvider` and
`activeRulePacksProvider` overridden. Probe C1 in
`test/security/qa_pr41_probe_test.dart` does exactly that and **fails** on the
mutation above with the intended message.

**Broken:** none of the NFR's behaviour; its regression protection.
**Suggested fix (mobile-engineer):** keep C1 (or fold it into
`p5a_lock_collapses_stack_test.dart`) and delete the duplicated `_Gateway`, or
mark the duplicate explicitly as a pattern demo so nobody reads it as coverage.
**Linear:** KHA-121 (P5 milestone set at creation).

### Pass 6 (PR #27, P4a — KHA-30 categories + KHA-31 merchant rule store), head `10df548`

**Verdict: `QA: PASS 27` — no merge-blocking defect.** Eight defects found, all
reproduced by executed probes in `test/security/qa_pr27_probe_test.dart`
(35 probes, all passing on head `10df548`; log:
`docs/evidence/qa-pr27/probe-suite.log`).

**Why none of them blocks this PR, stated precisely rather than assumed.** P4a
routes no screen. Rules are created *only* by an explicit user action
(`CategorizationService.applyUserCategory` / `MerchantDao.upsertRule`), and
there is no shipped surface that calls either. So in a build of this branch, the
matcher can never find a rule to apply, and the auto-categorization defects
below (D-QA-27-1/2/3/6/7) cannot fire. **One consequence of P4a *is* live in a
shipped build**: the categorizer is wired into ingestion
(`ingestion_providers.dart`), so `merchant` rows are created and keyed from real
SMS from this branch onward — which is why the merchant-identity half of
D-QA-27-1/2/7 is recorded as a **data-shape** consequence that later phases
inherit, not merely a future risk.

**Conditional gate (the `docs/lessons.md` rule about gates that live only in
prose — these are `blocks` links in Linear, not just this paragraph):**
D-QA-27-1, D-QA-27-2, D-QA-27-4 and D-QA-27-7 are **merge-blocking for any PR
that routes a categorization surface** — KHA-32 (review inbox), KHA-33
(correction flow), KHA-34 (rules screen) or KHA-97 (category management) —
because each of those is the first build in which a user can create a rule and
therefore the first in which an automatic categorization can be wrong.

## Defects found in pass 7 (PR #30, P4a-1, head `3620388`)

Both are **residuals of defects PR #30 closes**, both strictly narrower than the
original, and **neither blocks PR #30** — blocking it would leave the wider
KHA-98/99 defects in place. Reproductions: `test/security/qa_pr30_probe_test.dart`.

**Conditional gate (a `blocks` link in Linear, not only this paragraph):**
D-QA-30-2 is **merge-blocking for the P3b-3 device run and for any build that
reaches a device**, for the same R-16 reason PR #30 itself argues: every
`MerchantKey.of` change is free while no install holds a `merchant` row, and
needs a **splitting** re-key migration afterwards. It is *not* merge-blocking
for PR #30, and it does **not** require a P4a-2 PR — it is a one-condition
change or one ADR paragraph, and can ride with the first P4b PR provided that
PR lands before the device run.

### D-QA-30-2 — KHA-99's trailing-digit collision is closed at 3 digits and OPEN at 4: numbered sibling outlets still merge at confidence 1.00

- **Severity:** High (behaviour), **not merge-blocking for PR #30**;
  **merge-blocking for the P3b-3 device run / R-16 premise expiry** (above).
- **Reproduction:** probe **M2**, `test/security/qa_pr30_probe_test.dart`. Passes
  on `3620388` (it asserts the defect).

KHA-99's done-check names `QAMART 100` / `QAMART 200`, and that pair is
genuinely fixed. But corroboration signal **(ii)**, length, fires on *any*
trailing run of `referenceDigitRunMinLength` = 4 or more digits **with no other
corroboration at all**. So the identical defect survives one digit further
along:

```
MerchantKey.of('QAMART 100')   ->  'QAMART 100'   // KHA-99: fixed
MerchantKey.of('QAMART 200')   ->  'QAMART 200'   // KHA-99: fixed
MerchantKey.of('QAMART 1000')  ->  'QAMART'       // still collapses
MerchantKey.of('QAMART 2000')  ->  'QAMART'       // ...onto the same key
```

Executed end to end, not merely as a key comparison: `MerchantMatcher.match`
returns `MatchTier.userRule`, confidence **1.00**, `canAutoApply == true`. This
is the exact shape KHA-98/KHA-99 describe — a collision manufactured by
normalisation, **upstream of every tier**, where no threshold can reach it — and
`merchant.merchant_key` is `UNIQUE`, so the two outlets become one row whose
`canonical_name` is whichever arrived first.

**Expected vs actual.** ADR-008 v1.3's own corroboration rule, condition 3
(*residue-safety*): *"Stripping must never be able to reduce two strings that
differ only in a proper noun, **or only in a number that is part of a name**, to
the same key."* `QAMART 1000` / `QAMART 2000` differ only in a number that is
part of a name. The shipped length signal does not satisfy the rule the same
amendment states normatively.

**Why this is filed rather than waved through.** The ADR's "consequences on
synthetic input" list under settled answer 2 enumerates `QAMART 100` /
`QAMART 200`, `CAFE 1` / `CAFE 2`, `QAMART 100 200 300`, `PANDA STORE 1234` and
`PANDA 1234` — **it never states a pair of 4-digit siblings**. So this is not a
disclosed accepted cost; it is an undisclosed consequence. The trade may well be
the right one (it is the price of keeping `PANDA 1234` == `PANDA`, which the PR
lists as preserved), but it was not decided, and the *point* of v1.3 was to
replace a list nobody could review with a rule anyone can.

**Fix directions (a decision, not necessarily code):**
1. Require adjacency corroboration **always**, dropping signal (ii). Costs
   `PANDA 1234` == `PANDA`; keeps `PANDA STORE 1234` == `PANDA`, which is
   PRD §3.4's actual observed shape.
2. Add a residue condition to signal (ii): strip only when no *other* stored key
   differs from the result solely by a trailing digit run — but note ADR-008 v1.3
   rejected database-dependent stripping under condition 1 (purity), so this
   would reopen that argument.
3. **Accept it explicitly**: state the 4-digit sibling case in ADR-008's
   consequences list and in `referenceDigitRunMinLength`'s doc comment, so the
   next reader sees the cost the way they now see the `PANDA RIYADH` cost.

Any of the three closes this. What is not acceptable is leaving the rule and the
code disagreeing silently — that is precisely how KHA-98 survived three readers.

- **Done check:** `MerchantKey.of('QAMART 1000') != MerchantKey.of('QAMART 2000')`,
  **or** ADR-008 settled answer 2 and `CategorizationConfig.referenceDigitRunMinLength`
  both state the residual explicitly. Probe M2 inverted in place.

### D-QA-30-1 — `MerchantKey.of` is not idempotent, and its own doc comment says the invariant is load-bearing

- **Severity:** Low. **Not merge-blocking for anything.** Recorded now rather
  than later only because it is an R-16-cheap decision today and an R-16-costly
  one after a device run.
- **Reproduction:** probe **M1**, `test/security/qa_pr30_probe_test.dart`.

`of`'s doc comment states:

> Idempotent — `of(of(x)) == of(x)` — which matters because a key is computed
> when a merchant is created and recomputed on every later message. A pipeline
> that changed its own output on a second pass would stop matching the very rows
> it wrote.

The pipeline runs step 6 (digit strip) **before** step 7 (noise strip). So a
digit run that is not last when step 6 looks becomes last after step 7 removes
the token behind it:

```
MerchantKey.of('PANDA 1234 STORE')   ->  'PANDA 1234'   // STORE removed; 1234 was not trailing
MerchantKey.of('PANDA 1234')         ->  'PANDA'        // now it is
```

so `of(of(x)) != of(x)`.

**Actual user-visible consequence, which is not the double-application.** No
shipped call site ever feeds a key back into `of` — every `MerchantKey.of*` call
in `lib/` takes `merchantRawText` or an alias string (verified by grep over all
call sites), so the stated failure mode cannot fire today. What *does* fire is
**token-order sensitivity**: `PANDA 1234 STORE` and `PANDA STORE 1234` are two
different merchant identities for what is plainly one shop, which contradicts
PRD §3.4's "all renderings of one shop produce one key".

That is a **split**, not a merge — the recoverable direction ADR-008 v1.3
explicitly prefers, fixed by one `MerchantAlias` link — which is why this is Low
and not High.

- **Done check:** either the noise strip runs before the digit strip (making the
  invariant true), or `of`'s doc comment stops claiming idempotence and states
  the ordering dependence instead. Probe M1 inverted in place.

## Coverage gaps and observations from the pass-9 probe suite (PR #41, P5a)

### G-QA-41-1 — the NFR-A6 generated sweep never emits an internal transfer, income, cash, a fee, or a non-SAR currency (closed in this pass)

`test/features/ledger/totals_reconciliation_test.dart`'s doc comment claims its
200 generated ledgers cover *"refunds outnumbering purchases, a bank with no
instruments, an instrument with no transactions, **an internal transfer split
across two banks**"*. The first three are covered. The fourth is not: the
generator's type selection is
`credit ? TransactionType.refund : TransactionType.posPurchase`, all in `SAR`.

**Why it matters and not merely tidiness.** `LedgerTotals.report`'s own doc says
of the `transfers` parameter: *"a per-instrument slice contains one leg of a
transfer and not the other, so callers that slice must analyse the full set first
and pass the result down; `BankTreeBuilder` does exactly that, and **getting it
wrong is the most plausible way to reintroduce AC-B11.1 as a bug**."* That exact
regression is invisible to the test suite as shipped — verified by mutation, see
the pass-9 summary.

**Closed in this pass**, not deferred: probes A1 (the two-bank fixture), A2 (FX
additivity plus reconciling unconverted counts) and A3 (a richer 200-run sweep)
all fail on the mutation and pass on `d9fac9e`. No Linear issue — the tests now
exist and land with this PR. The engineer-owned residue is one **doc comment**
that overstates its own generator; worth a one-line correction next time that
file is touched, not a ticket.

### O-QA-41-1 — the period total includes cash; the sum of bank totals structurally cannot

`LedgerTotals.spend` counts a transaction with no instrument (US-B4 cash,
OQ-19), and `BankTreeBuilder` has nowhere to put one. Probe A4 measures the gap
concretely: the same 17-transaction month totals `5,436.55 SAR` on Home and
`5,376.55 SAR` across the banks, differing by exactly the `60.00` cash row.

**Not a defect at this tier, and here is the specific reason:** `BanksScreen`
renders per-bank totals and **no grand total**, so the app never displays two
figures that claim to agree and do not. A user who adds the rows up by hand could
notice, and there is no line explaining cash. Worth a sentence when the Reports
hub (KHA-37) lands, since AC-E3.2 asks for card-breakdown totals that *do* sum to
the period total — that is where the gap becomes user-visible arithmetic rather
than a private property. The shipped test pins the gap deliberately, which is the
right treatment for now.

### O-QA-41-2 — an out-of-band permission grant never writes `onboarding_complete`, so a later Android auto-revoke shows S-02 instead of the AC-A1.3 banner

`OnboardingGate` short-circuits to the app when `permission.allowsIngestion`,
without calling `markOnboardingComplete()`. So a user who granted SMS access in
Android Settings before ever seeing the rationale carries
`onboarding_complete = false` indefinitely. If Android 11+ later auto-revokes
(ADR-006), the gate reads *"never asked"* and shows S-02 rather than AC-A1.3's
banner-over-the-app.

**Why this is an observation and not a defect:** S-02 is not a dead end — Grant
re-raises the OS dialog and lands the user back in the app with their history
intact — and it is arguably the *better* screen for someone who has genuinely
never read the rationale. Ingestion is unaffected either way (probe B1).

Two related, and deliberately grouped here so a future refactor sees them:

- The AC-A1.3 banner on Home is gated on `permission.value != null &&
  !allowsIngestion` — the live permission only. Its doc comment says it is
  *"deliberately NOT shown before the user has been through onboarding at all"*,
  but there is **no `onboardingComplete` check in the code**. Today that is
  unreachable except through the gate's two error fall-throughs (`hasError` →
  `AppShell`), and the copy is written to survive it: *"**Any** data you already
  have is still intact"* claims nothing false to a user with no data. The comment
  asserting a guard the code does not have is the part worth fixing.
- A user who **declines** at S-04 and continues into the app also gets the
  banner, titled *"SMS access was turned off"*. Accurate, if slightly odd
  immediately after a decline.

### O-QA-41-3 — the Flutter floor moved to `>=3.44.0`, which is very close to current stable

`pubspec.yaml` raises the floor because `SnackBar.persist` must exist for
`scoped_snack_bar.dart` to compile. Local toolchain is **3.44.8**; the floor is
`3.44.0`, i.e. roughly one patch series of headroom. This is deliberate and
argued in the pubspec comment (*"a build below this line would not compile rather
than silently regressing"*), and CI tracks `stable`, so it is correct — but it
does mean the project can no longer be built on any Flutter older than a
very recent release. Recorded so nobody is surprised by it on a fresh machine.

### O-QA-41-5 — after granting SMS access, the first-run journey lands on a red "Authentication failed. Try again."

Observed on the emulator walk (`docs/evidence/qa-pr41/05-after-grant.png`), on
the single most important journey in this PR.

Sequence: S-02 → *Grant SMS access* → the OS permission activity takes focus →
ADR-005's grace-0 policy re-locks the app on `paused` → on `resumed`,
`app.dart` calls `controller.authenticate()` while the permission dialog is
still up, so the `BiometricPrompt` is cancelled by the system and reported as a
failure. The user, having just done exactly the right thing, is looking at a red
error banner.

**Not a dead end, and that is why this is an observation rather than a defect:**
`lock_gate_screen.dart` renders a *"Use device passcode instead"* `TextButton`
that calls `authenticate()` again, and one tap on it recovered cleanly every
time (`docs/evidence/qa-pr41/06-home-first-real-data.png`). But the label
describes a *fallback method* rather than the *retry* it actually is in this
state, and the fingerprint circle beside it is decorative — QA tapped it and
nothing happened.

**Pre-existing, and P5a is only the PR that makes it reachable.** Before this
PR the app launched no external activity, so nothing ever stole focus mid-auth.
That is the `docs/lessons.md` expiry pattern again. Not filed as its own issue
because the fix is a P1 lock-gate concern and the P5 milestone already carries
enough; worth folding into whichever issue next touches `lock_gate_screen.dart`,
as either "re-raise the prompt on resume if the last attempt was cancelled
rather than genuinely rejected" or "label the retry as a retry".

### O-QA-41-4 — a third FAB still carries Flutter's default hero tag

`category_management_screen.dart:112` constructs a `FloatingActionButton` with no
`heroTag`. It cannot collide today: it lives on its own pushed route, while the
two FABs alive together in `AppShell`'s `IndexedStack` now carry `'fab.home'` and
`'fab.transactionList'`. It becomes an assertion failure the moment that screen
is moved into the shell or shown beside another default-tagged FAB — the same
shape the PR just fixed. A one-word change if anyone is in the file.

---

## Observations from the pass-7 probe suite (recorded for audit, not defects)

### O-QA-30-1 — KHA-103's `isUserOwnedCategory` guard reads wider than the comment beside it, but the state it would admit is unreachable

`CategoryDao.deleteCategory`'s uncategorize branch guards the
`category_source` / `category_confidence` clear on `isUserOwnedCategory(row)`,
and the comment explains the exception as *"a row whose category a **person**
chose keeps `category_source = 'user'`"*. But `isUserOwnedCategory` is an **OR**
of two deliberately-redundant AC-D3.1 signals (`category_source == 'user'` **or**
`user_edited_fields` contains `categoryId`). If only the second disjunct were
ever true, the row would keep `category_source = 'rule'` with a NULL
`category_id` — which is the second clause of KHA-103's own done-check.

**QA attacked this and it does not work** (probe **P1**, a `HOLDS`). Two
independent reasons, both verified by execution:

1. The merge unions protected fields from `MergeEnrichment.protectedFields`,
   which holds only fields actually **carried into a gap**. A rule-categorized
   survivor has no gap in `category_id`, so it inherits no protection marking;
   and in the one shape where `category_id` *is* carried, the survivor by
   definition had no category, so its source was never `'rule'`.
2. Structurally: `TransactionDao.applyAutomaticCategory` returns `false` and
   **writes nothing at all** for a user-owned row, so the automatic path can
   never stamp `'rule'` onto a protected row in the first place.

So KHA-103 is correctly closed. Recorded because the comment predicts `'user'`
while the function it calls does not guarantee it — the two agree only via an
invariant enforced in a different file (`transaction_dao.dart:481`), and a future
edit to either could separate them without any test noticing. A one-line comment
naming that dependency would close it.

### D-QA-27-1 — the city-name noise list silently merges two unrelated businesses into ONE merchant, then auto-categorizes at confidence 1.00

- **Severity:** High (behaviour), **not merge-blocking for PR #27** — see the
  gate above. Design/architecture-level: the mechanism is mandated by ADR-008,
  so the fix is an architecture decision, not an engineer error.
- **Found in:** pass 6 (PR #27), PROBE B in `test/security/qa_pr27_probe_test.dart`.
- **Affects:** `MerchantKey.noiseTokens`; ADR-008's normalisation pipeline
  ("strip a configurable noise-token list (`BRANCH`, `STORE`, `FRC`, city names,
  terminal ids)"); **AC-D2.3**, risk R-5, KHA-31's own done check ("an unrelated
  merchant not matching").
- **Root cause.** The noise list removes six Saudi city names in both scripts.
  The implementation defends this as *"a chain's branches are the chain"*, which
  is right for `PANDA RIYADH` / `PANDA JEDDAH`. It is wrong whenever the city
  name is the **distinguishing** token of two independent businesses — an
  entirely ordinary Saudi retail naming shape. Both then produce the *same*
  `merchant_key`, so the collision happens at **T1**, above every tier gate and
  above any value `autoApplyThreshold` could take.
- **Steps to reproduce** (synthetic):
  1. `MerchantKey.of('MAKKAH BAKERY')` → `'BAKERY'`.
  2. `MerchantKey.of('MADINAH BAKERY')` → `'BAKERY'` — the same key.
  3. Ingest a purchase from `MAKKAH BAKERY`; user categorizes it as Dining
     (`applyUserCategory`), which creates rule M→Dining.
  4. Ingest a purchase from `MADINAH BAKERY` and run `categorizeTransaction`.
- **Expected (AC-D2.3):** match, or flag as low-confidence. Two unrelated
  merchants must not be matched.
- **Actual:** `CategorizationResult.applied`, tier `userRule`, confidence
  `1.00`, no review flag. `merchant` holds **one** row for both businesses
  (`merchant_key` is `UNIQUE`), whose `canonical_name` is the first raw string
  seen — so the user is shown "MAKKAH BAKERY" for money spent at the other shop.
- **Why this is worse than a wrong category.** A wrong category is one tap to
  fix. Here the *identity* is merged permanently and there is no split
  affordance anywhere in the plan, so correcting one shop re-points the other's
  future messages too. The codebase argues at length (`merchant_table.dart`,
  `categorization_service.dart`) that it never asserts identity on a guess —
  and this is not a guess, it is a deterministic collision manufactured by
  normalisation, which is exactly why no confidence gate catches it.
- **Fix direction (for solution-architect, not the engineer alone):** strip a
  city token only when at least one *other* significant token survives **and**
  the resulting key is already a known merchant; or drop city names from the
  noise list and let T3's token-set tier handle `PANDA RIYADH` ↔ `PANDA JEDDAH`
  (Jaccard 0.5 there, so it would flag rather than apply — which is the AC's
  stated preference). Either way P4b needs a "these are two different shops"
  affordance, because P4a is already creating the merged rows.
- **Linear:** KHA-98.

### D-QA-27-2 — unconditional trailing-digit stripping merges numbered sibling merchants at confidence 1.00

- **Severity:** Medium, not merge-blocking (same gate as D-QA-27-1).
- **Found in:** pass 6, PROBE C.
- **Affects:** `MerchantKey.of` step 6; ADR-008; AC-D2.3.
- **Root cause.** The trailing-digit strip is a `while` loop with no length,
  count or context condition, so every trailing numeric token is removed no
  matter how many there are or what proportion of the name they were. A merchant
  whose identity *is* its number becomes indistinguishable from its siblings.
- **Steps to reproduce:** `MerchantKey.of('QAMART 100')`,
  `MerchantKey.of('QAMART 200')` and `MerchantKey.of('QAMART 100 200 300')` all
  return `'QAMART'`. Teach a rule from the first; the second auto-applies at
  T1/1.00.
- **Expected:** the shapes ADR-008 names (a *store/terminal/reference* number
  appended to a name) collapse; a number that is part of the name does not.
- **Actual:** all numeric suffixes collapse unconditionally.
- **Note.** The code correctly protects *leading* digits (`7 ELEVEN` survives),
  so the asymmetry is deliberate and documented; what is undocumented is that
  the trailing case has no bound.
- **Linear:** KHA-99.

### D-QA-27-3 — a repeated-token brand name reaches Jaccard 1.0 and auto-applies another merchant's rule at exactly the threshold

- **Severity:** Low.
- **Found in:** pass 6, PROBE D.
- **Affects:** `MerchantMatcher._jaccard` / `_tokenSetConfidence`;
  `CategorizationConfig.autoApplyThreshold`'s documented tuning rationale.
- **Root cause.** The PR defends 0.85 with *"a token-set match applies only at
  Jaccard 1.0 — i.e. the two strings contain the same tokens and differ only in
  order, spacing, case, store number or noise words"*. Jaccard is computed over
  **sets**, so token multiplicity is invisible: `QAFE QAFE` and `QAFE` have
  identical token sets and therefore Jaccard 1.0, though they are two different
  names rather than one name rearranged.
- **Steps to reproduce:** `MerchantMatcher.match('QAFE QAFE', [candidate with
  merchantKey 'QAFE' and a user rule])` → tier `tokenSet`, confidence `0.85`,
  `canAutoApply == true`.
- **Expected:** the documented rationale to hold literally, i.e. T3 auto-apply
  only for a *permutation* of the same tokens.
- **Actual:** it also fires for a multiset difference.
- **Fix direction:** either compare multisets, or state the multiplicity case in
  the rationale so a later tuner is not misled by it. Genuinely marginal in
  effect — recorded because the *documented reason for the shipped threshold*
  is slightly stronger than what the code does, and that rationale is what a
  future tuner will read.
- **Linear:** KHA-100.

### D-QA-27-4 — categorizing through the edit form leaves the review flag raised and teaches no rule, so the two correction surfaces disagree

- **Severity:** Medium. **Merge-blocking for KHA-32/33/97** (see gate above).
- **Found in:** pass 6, PROBE U.
- **Affects:** `TransactionDao.applyUserEdit` (P3b-2's shipped, already-routed
  edit form, S-16) vs `TransactionDao.setUserCategory` /
  `CategorizationService.applyUserCategory`; **AC-C4.3**, **AC-D1.1**,
  **AC-D2.1**.
- **Root cause.** Two user-facing writes can set a category. `applyUserEdit`
  correctly moves the three provenance columns and marks the field user-owned,
  but it does **not** call `_clearCategoryReviewFlag` and it does not go through
  the service, so no rule is learned.
- **Steps to reproduce** (synthetic):
  1. Ingest a purchase from `QANDA`; run `categorizeTransaction` → the row is
     flagged `needs_review = 1`, `review_reason = 'unknown_merchant'`.
  2. `transactionDao.applyUserEdit(id: …, categoryId: Edited('dining'))`.
- **Expected:** AC-C4.3 — *"when the user confirms or corrects the category, the
  flag is cleared"*. AC-D1.1 — a rule M→C exists afterwards.
- **Actual:** `needs_review` is still `1` with `review_reason =
  'unknown_merchant'`, and `merchant_rule` is empty. A user who corrects the
  category from the transaction detail screen gets neither the flag cleared nor
  the learning loop.
- **Reachability today:** the edit form is routed and shipped (P3b-2), but the
  *categorizer* that raises the flag only started running in P4a, so the
  combination first becomes user-visible when a categorization surface ships.
- **Fix direction:** route every category write through one path. Simplest
  correct shape: `applyUserEdit` calls `_clearCategoryReviewFlag`, and the
  detail-screen category control calls `applyUserCategory` rather than
  `applyUserEdit`.
- **Linear:** KHA-101.

### D-QA-27-5 — deleting a category with "set to Uncategorized" leaves transactions pointing at a `category_rule_id` that no longer exists

- **Severity:** Low (no money effect; AC-C1.3 verified intact by the same probe).
- **Found in:** pass 6, PROBE X.
- **Affects:** `CategoryDao.deleteCategory`'s `replacementId == null` branch;
  AC-D2.2 ("and, ideally, why"), NFR-A2.
- **Root cause.** The branch deletes every `merchant_rule` naming the doomed
  category (defensible and documented), but does not clear the
  `category_rule_id` / `category_source` those rules wrote onto transactions.
- **Steps to reproduce:** create a custom category; categorize one transaction
  into it (creating a rule); let a second transaction auto-categorize from that
  rule; delete the category with `SetToUncategorized()`.
- **Expected:** a row whose category was cleared should not still claim a rule
  as its provenance.
- **Actual:** the row has `category_id = NULL`, `category_source = 'rule'` and
  `category_rule_id = <deleted rule id>`. A detail screen answering *"why is
  this categorized this way"* dereferences a rule that does not exist, and the
  audit entry's `merchant_rule:<id>` is likewise unresolvable — literally *"a
  rule put nothing here"*.
- **Fix direction:** in the uncategorize branch, null `category_rule_id` and set
  `category_source = 'none'` on the repointed rows, in the same statement that
  already rewrites `category_id`.
- **Linear:** KHA-103.

### D-QA-27-6 — a merchant rule may name a category that does not exist, and the matcher will confidently apply it

- **Severity:** Low (money-safe; the resolver renders it as Uncategorized and
  AC-C1.3 was verified to hold with the dangling id present).
- **Found in:** pass 6, PROBE Y.
- **Affects:** `MerchantDao.upsertRule`, `TransactionDao.setUserCategory` — no
  validation of `category_id` against `category` on **write**. The
  `category_no_delete_while_in_use` trigger guards only the delete direction,
  which the PR states plainly; what it does not state is that the write
  direction has no validation at *any* layer, only a convention that callers
  resolve first.
- **Steps to reproduce:** `merchantDao.upsertRule(merchantId: …, categoryId:
  'no_such_category', source: 'user', actor: 'user')`, then ingest a matching
  transaction and run `categorizeTransaction`.
- **Expected:** either the rule is rejected, or the match declines to apply an
  unresolvable category.
- **Actual:** `CategorizationResult.applied`; the row stores
  `category_id = 'no_such_category'` and renders as Uncategorized. The row now
  says "categorized" while displaying "Uncategorized" — AC-C1.1's *explicit*
  state reached by accident rather than by decision.
- **Fix direction:** validate in `upsertRule` (it already runs inside a
  transaction and can `SELECT` the category), or have the matcher drop
  candidates whose `categoryId` the resolver does not know.
- **Linear:** KHA-104.

### D-QA-27-7 — a punctuation-only merchant string forms a merchant identity, so every masked-merchant message collapses onto one rule

- **Severity:** Medium. **Merge-blocking for KHA-32/33/97** (same gate).
- **Found in:** pass 6, PROBE G2.
- **Affects:** `MerchantKey.ofOrNull` / `MerchantKey.of`'s all-noise fallback.
- **Root cause.** `ofOrNull` documents itself as the guard against *"inventing
  an empty-string key [which] would make every such transaction the same
  merchant — the single most damaging silent merge available in this design"*.
  The guard tests `key.isEmpty`, but `of()` falls back to the **folded string**
  when every token was noise or digits, and a string made only of separator
  characters tokenises to nothing while folding to itself. It is therefore
  non-empty and the guard misses it.
- **Steps to reproduce:** `MerchantKey.ofOrNull('***')` returns `'***'`;
  `MerchantKey.ofOrNull('-*-')` returns `'-*-'`. Ingest two unrelated purchases
  whose merchant field is `***`, categorize the first, run the categorizer on
  the second → `applied` at confidence `1.00`, and `merchant` holds one row.
- **Expected:** the same treatment as no merchant text at all
  (`skippedNoMerchant`), which is what the method's own doc promises.
- **Actual:** a placeholder becomes an identity. Acquirer strings routinely
  carry a placeholder where the merchant name was masked or absent, so one rule
  would categorize every masked transaction across every bank.
- **Fix direction:** require the fallback key to contain at least one letter or
  digit before returning it; otherwise return null.
- **Linear:** KHA-102.

### D-QA-27-8 — `applyAutomaticCategory` unlinks an existing merchant when a caller omits `merchantId`

- **Severity:** Low. No caller does this today.
- **Found in:** pass 6, PROBE AC.
- **Affects:** `TransactionDao.applyAutomaticCategory`.
- **Root cause.** Its user-path sibling is careful — `setUserCategory` uses
  `Value.absent()` when `merchantId` is null *"so a caller with no merchant
  cannot accidentally unlink one that is already there"* — but the automatic
  path writes `merchantId: Value<int?>(merchantId)` unconditionally, so the same
  omission clears the link instead of leaving it alone.
- **Steps to reproduce:** categorize a transaction so it carries a
  `merchant_id`, then call `applyAutomaticCategory(id: …, categoryId: null,
  confidence: 0.0, actorDetail: 'no_rule_matched')` with no `merchantId`.
- **Expected:** the existing link is preserved.
- **Actual:** `merchant_id` becomes `NULL`.
- **Note.** Recorded now precisely because it is the *"unguarded path with no
  caller yet"* shape KHA-79 was about — this codebase's own stated reason for
  guarding both layers.
- **Linear:** KHA-105.

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
