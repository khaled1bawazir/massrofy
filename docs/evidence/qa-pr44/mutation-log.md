# PR #44 QA — mutation log

Every mutation below was applied to a clean checkout of
`feature/p5b-reports-search-immediate-sweep` @ **`4308d7a`**, run, then reverted
with `git checkout --`. `git status` was verified empty after each revert.

Toolchain: Flutter 3.44.8 / Dart 3.12.2, Windows.

> **A correction QA owes on its own gate, recorded rather than quietly fixed.**
> My first `dart format --set-exit-if-changed .` reported clean and it was not.
> `dart format .` walks `build/`, which exists locally after an APK build, and it
> **crashed** on a stale Gradle transform path
> (`PathNotFoundException: ... bundleLibRuntimeToDirDebug/...`) *before* reaching
> `test/`, exiting 0 anyway. So the run proved nothing and the QA PR's first CI
> attempt failed on formatting. The gate that actually means something on this
> repo is `dart format --set-exit-if-changed lib test`, which excludes `build/`
> and is what CI effectively checks on a clean checkout. This is the
> `docs/lessons.md` rule about stale/unfounded gate claims, applied to QA.

---

## Baseline (no mutation)

```
$ flutter test --exclude-tags=release_mode_guard
+1540 ~3: All other tests passed!
```

Matches the engineer's PR-body claim exactly. Measured on `4308d7a`.

---

## M2 — remove KHA-122's only production call site  → **NOT DETECTED**

Feeds **KHA-138**.

```diff
--- a/lib/app.dart
+++ b/lib/app.dart
@@ unlocked branch of _AppLockGatewayState.build
-      ref.watch(foregroundSmsSignalProvider);
+      // QA MUTATION M2 (temporary): the KHA-122 keep-alive removed.
+      // ref.watch(foregroundSmsSignalProvider);
```

Targeted run first (the five files most likely to catch it):

```
$ flutter test test/features/ingestion/immediate_sweep_wiring_test.dart \
               test/features/ingestion/immediate_sweep_race_test.dart \
               test/platform/sms_foreground_bridge_test.dart \
               test/widget/p5b_shell_navigation_test.dart \
               test/widget/p5a_shell_navigation_test.dart
+37: All tests passed!
```

Then the whole suite:

```
$ flutter test --exclude-tags=release_mode_guard
+1540 ~3: All other tests passed!
```

Full log: `m2-app-dart-mutation-full-suite.log`.

**Conclusion.** The line that makes KHA-122 work in production is unguarded.
`immediate_sweep_wiring_test.dart`'s header claims removing it turns the positive
test red; it does not. (The *Kotlin* half of that same claim is true — it is held
by `test/platform/sms_foreground_bridge_test.dart`, a different file.)

---

## M1a — drop the shared internal-transfer analysis  → **NOT DETECTED**

Feeds **KHA-139**, Finding 2. This is verbatim the regression
`instrument_breakdown_test.dart`'s docstring says these tests catch.

```diff
--- a/lib/features/ledger/instrument_breakdown.dart
+++ b/lib/features/ledger/instrument_breakdown.dart
@@ InstrumentBreakdown.of → BankTreeBuilder.build(...)
       baseCurrencyCode: baseCurrencyCode,
-      transfers: transfers,
+      // QA MUTATION M1a (temporary)
```

```
$ flutter test test/features/ledger/instrument_breakdown_test.dart \
               test/features/ledger/totals_reconciliation_test.dart \
               test/widget/p5b_reconciliation_widget_test.dart
+27: All tests passed!
```

**Conclusion, and it is benign.** `InstrumentBreakdown.of` hands
`BankTreeBuilder.build` the **whole** live list, and `build` falls back to
`transfers ?? InternalTransferDetector.analyze(transactions)` — so the fallback
re-derives the same answer over the same set. The `transfers:` argument is a
consistency/efficiency aid at this call site, **not** a correctness requirement,
and no test can catch its removal. The docstring should say that rather than
claim a guard that cannot exist.

---

## M1b — make the planted transfer's `affectsSpend` match production → **8 FAILURES**

Feeds **KHA-139**, Finding 1. **No production code was mutated for this run**
(M1a had been reverted); only the test fixture changed.

```diff
--- a/test/features/ledger/instrument_breakdown_test.dart
 tx(
   id: 6,                       // and id: 5000, the 200-run planted pair
   type: TransactionType.transferOut,
-  affectsSpend: false,
+  affectsSpend: true,          // assets/rule_packs/sa-core.json's value
```

```
$ flutter test test/features/ledger/instrument_breakdown_test.dart
+3 -8: Some tests failed.
  ... EVERY one of them contains a cross-bank internal transfer [E]
  run 0: the internal-transfer pair changed the period total, so it was not
         excluded (AC-B11.1)
```

**Conclusion.** The planted pair's exclusion never came from
`InternalTransferDetector`. With no shared reference number the detector can only
rate it `candidate`, and a candidate is deliberately **still counted as spend**
(AC-B11.2). What removed it from the total was `_spendOrVeto`'s
`packDeclaredNonSpend` branch — a flag the shipped rule pack does not set for
`transfer_out` (`baj-transfer-out-ar` and `d360-transfer-out-en` both say
`"affectsSpend": true`). So the 200-run corpus does not exercise the
internal-transfer path at all, which is the gap it was written to close.

---

## M1c — M1b plus a shared bank reference number → **GREEN, and now load-bearing**

The suggested fix, verified achievable. Production code untouched.

```diff
 tx(id: 5000, ..., affectsSpend: true,  reference: 'QA-XFER-$run', on: outLeg),
 tx(id: 5001, ...,                      reference: 'QA-XFER-$run', on: inLeg),
```

```
$ flutter test test/features/ledger/instrument_breakdown_test.dart
+11: All tests passed!
```

The shared reference promotes the pair to `InternalTransferEvidence.referenceMatch`
→ `InternalTransferState.internal` → excluded by the **analysis**, which is the
property AC-E3.2 is supposed to rest on. QA's own probe suite
(`test/qa/pr44_p5b_qa_probes_test.dart`, group *KHA-139*) carries this shape
permanently, including a direct `expect(analysis.stateFor(outgoing),
InternalTransferState.internal)` — the assertion the existing
`expect(runsWithPlantedPair, 200)` "guard the guard" was meant to be but is not
(it counts plantings, not detections, i.e. `200 == 200`).

---

## Merge-candidate check against current `main`

`main` had moved to `7f000e4` (PRD Addendum A, architecture v1.6, design v2.2,
and KHA-128's sender-pattern fix in PR #43).

```
$ git merge-base origin/main origin/feature/p5b-reports-search-immediate-sweep
01c0baa...

$ git diff --name-only 01c0baa origin/main            # 22 files
$ git diff --name-only 01c0baa origin/feature/...     # 38 files
$ comm -12 <sorted> <sorted>                          # (empty)
```

**Zero file overlap.** KHA-128 touched `assets/rule_packs/sa-core.json`,
`docs/**` and four ingestion/parsing test files; PR #44 touches none of them.

Textual cleanliness is not semantic cleanliness, so the merged tree was run:

```
$ git merge origin/main --no-edit      # clean, no conflicts
$ flutter test --exclude-tags=release_mode_guard
+1688 ~3: All other tests passed!
```

1688 = PR #44's 1540 + KHA-128's 148. Full log:
`merged-with-main-full-suite.log`. No regression from the sender-pattern change.
