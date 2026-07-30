# PR #44 re-gate evidence — measured on `037d810`

Second QA gate on PR #44, after mobile-engineer's fixes for KHA-137, KHA-138 and
KHA-139. The first gate (`QA: FAIL 44`, PR #47) was measured on `4308d7a`;
**nothing below is carried over from it** — every gate, mutation and journey was
re-run on the current head, per `docs/lessons.md`'s rule that a pass/fail claim
is only evidence for the tree it was measured on.

## 1. The merge of `main` actually happened, verified not assumed

The KHA-137 decision's item (D) makes KHA-133's `sms_provider_id` pre-check
**non-negotiable in the same PR**. It arrived by merging `main`, not by being
written here, so it was checked at three levels:

| Check | Result |
|---|---|
| `main` merged into the branch | `5e93ea6` merges `origin/main`, which carries `086ba77` (KHA-133, PR #46) |
| `findBySmsProviderId` exists | `lib/data/dao/raw_message_dao.dart:192` |
| …and is wired into `_withDedupGuard` | `lib/features/ingestion/ingestion_pipeline.dart:606` — second arm of the `??` after `findByContentHmac` |
| …and is load-bearing | Mutation 3 below |

## 2. Gates, re-run on `037d810`

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed lib test docs` | exit 0, 0 files changed |
| `flutter analyze --fatal-infos` | **No issues found!** (8.4 s) |
| `flutter test --exclude-tags=release_mode_guard` | **1763 passed, 3 skipped, 0 failed** |
| PR #44 aggregate `ci` check run | **completed / success** — run `30549701298`, all five constituent jobs green (build & test, ADR-001 manifest guard, ADR-002 money-type guard, on-device emulator integration, dependency & security scan) |

> **These numbers are corrected.** This gate was interrupted and resumed; the
> interrupted draft recorded `format` exit 0 / `analyze` clean / **1745** passed,
> and none of the three held on the tree it left behind — the QA probe file was
> missing four imports and did not compile. The failures were entirely in **QA's
> own artifacts** (none of those files exist at `037d810`), not in PR #44. Full
> account, including the corrected figures and the fixes, in
> `docs/test-plan.md` §R1a.
>
> A whole-repo `dart format .` additionally crashes on this machine with a
> `PathNotFoundException` under `build/` (a stale Gradle transform directory
> whose path no longer resolves). That is a local working-tree artifact, not a
> repo defect — CI formats a clean checkout with no `build/` — hence the
> `lib test docs` scoping above.

### 2a. The ADR guard scripts

Both ADR guards are reported here **from CI**, which ran them on this exact head
(`037d810`), rather than re-run locally: they are shell scripts driven by the
workflow, and CI's run is the authoritative one. Both green.

The earlier note that ADR-001 was **"Layer 1 only"** applies to a *local*
invocation with no release APK to inspect. It does **not** apply to CI, and that
was worth checking rather than assuming: `check_no_network_permission.sh`
performs Layer 2 itself — if it finds no merged release manifest under `build/`
it runs `flutter build apk --release --target-platform android-arm64` to force
the manifest merger, and if it *still* finds none it hard-fails with
*"Treating as a hard failure rather than silently passing (ADR-001 is
non-negotiable)"* rather than skipping. So the green
`ADR-001: no-network release manifest guard` job on run `30549701298` is
**both layers passing against the real merged release manifest**, not a static
check that quietly degraded.

Full log: `../../../docs/evidence/qa-pr44-regate/regression-suites-037d810.log` (targeted
re-run of the eight P5b-relevant suites: **87 passed**).

## 3. Mutation verification — every engineer claim reproduced independently

Each mutation applied **alone**, to a clean `037d810` tree, then reverted.

| # | Mutation | Engineer claimed | QA measured |
|---|---|---|---|
| 1 | Fold `receivedAt` back into the digest (restore the KHA-137 defect) | 4 red | **4 red** — the 43 s case in `immediate_sweep_race_test`, and the 43 s / 1 hour / sender-case cases in `ingestion_pipeline_test` |
| 2 | Drop `SmsTextNormalizer.normalize(sender).toLowerCase()` | 1 red | **1 red** — the sender-case test |
| 3 | Remove the `findBySmsProviderId` pre-check from `_withDedupGuard` | 1 red (migration test) | **3 red** — the KHA-137 (D) migration test *plus* two of KHA-133's own tests. Stronger than claimed. |
| 4 | Comment out `ref.watch(foregroundSmsSignalProvider)` in `app.dart`'s unlocked branch (the original M2) | red | **1 red**, with the intended message. The extracted branch dump confirms the guard reads real code, not the comment block. |
| 5 | Move that watch *outside* the branch | — | **2 red** |
| 6 | *Duplicate* it (one inside, one hoisted) | `Expected: <1>, Actual: <2>` | **exactly `Expected: <1>, Actual: <2>`** |
| 7 | Restore KHA-139's old inert fixture (`affectsSpend: false`, no reference) | reconciliation stays green, guard fails `200` vs `0` | **exactly that** — 1 red, `Expected: <200> / Actual: <0>`, message *"every run must contain a cross-bank pair that the ANALYSIS rates internal — not merely a pair that was planted"*. The old fixture really was inert. |

## 4. Runtime device journeys — AVD `massrofy_test`, API 35, `emulator-5554`

Debug APK built from `037d810`, **fresh install** (`adb uninstall` first), SMS
permissions granted, PIN credential enrolled for ADR-005's Keystore gate.

> Screenshots `02` and `03` are black. That is **not** a broken screen — it is
> ADR-014's `FLAG_SECURE` blanking `screencap` while the `BiometricPrompt`
> window is up. Confirmed via `dumpsys window windows`; the app renders
> correctly the moment authentication completes (`04`).

### 4a. KHA-137 over the *original field data* — the strongest single piece of evidence

The AVD's SMS inbox survived the app uninstall, so it still held **the exact two
messages that produced the original defect**:

```
Row: 2 _id=2, address=BAJ, date=1785414447656, body=... QANDA FOODS ... 312.40 SAR
Row: 3 _id=1, address=BAJ, date=1785414404369, body=... QANDA FOODS ... 312.40 SAR
                                               ^ byte-identical, 43,287 ms apart
```

The fixed build ingested that pair into **one** transaction (`04-unlocked-home.png`):
`QANDA FOODS −312.40 SAR`, once. Under the defect this was two rows and `−624.80`.

### 4b. Live redelivery, app open and idle (KHA-122 + KHA-137 together)

| Step | Screenshot | Result |
|---|---|---|
| Fresh SMS `TAMIMI MARKETS 199.50` delivered, app **never left the foreground** | `05-after-first-sms.png` | Row appeared within 12 s. Total `−912.40` → `−1111.90`. **AC-A1.1 holds.** |
| Byte-identical redelivery, `_id=6`, **46,597 ms** later | `06-after-redelivery.png` | Total **unchanged at −1111.90 SAR**, one `TAMIMI MARKETS` row, still "4 items need review". **AC-A5.1 holds.** |
| Background → re-lock → re-auth → resume sweep (retest step 5) | `07-after-resume-sweep.png` | Still `−1111.90`, 4 items. Resume sweep added nothing. No regression. |

Under the KHA-137 defect step 2 would have read `−1311.40 SAR` with two TAMIMI rows.

### 4c. Business oracles — recomputed by hand from the six raw inbox rows

```
_id=1,2  QANDA FOODS      312.40 debit   (identical pair -> ONE transaction)
_id=3    NOON.COM         660.00 debit
_id=4    NOON.COM          60.00 credit  (refund, reduces spend, US-B7)
_id=5,6  TAMIMI MARKETS   199.50 debit   (identical pair -> ONE transaction)

distinct transactions = 4                      -> "4 items need review"      OK
net spend = 312.40 + 660.00 + 199.50 - 60.00
          = 1111.90                            -> "-1111.90 SAR"             OK
```

| Criterion | Screenshot | Independent recomputation | Displayed |
|---|---|---|---|
| **AC-E3.2** card breakdown reconciles | `09-card-breakdown.png` | `****4472` = 312.40 + 199.50 = **511.90**; `****9002` = 660.00 − 60.00 = **600.00**; sum = **1111.90** | `−511.90`, `−600.00`, Total `−1111.90` — identical to Home, no mismatch banner |
| **AC-C1.3** category totals reconcile | `08-reports-tab.png` | all four rows Uncategorized ⇒ category total == period total | "Top category: Uncategorized — 1111.90 SAR" |
| **AC-E5.2** filtered total | `11-filtered-total.png` | search `NOON` ⇒ 660.00 − 60.00 = **600.00** | "2 transactions", label changed to **"Filtered total"**, `−600.00 SAR` |
| **AC-E4.2** insufficient history | `08-reports-tab.png` | one month of data only | "Month over month — Not enough history yet" — no chart, no delta, not zeroed |

## 5. Attack probe — the item referred to QA for a decision

`bidi_sender_probe.dart` reproduces `_resolveBank`'s `trim()`-then-match against
the shipped `senderPatterns`. A U+200F/U+200E/U+202A/U+200B mark in the sender id
causes a legitimate bank SMS to be **silently discarded as non-financial**
(U+FEFF is trimmed; the others are not). Filed as **KHA-151 (Medium)**.
**Not blocking** — a sender carrying such a mark never reaches the content hash,
so it can neither mask nor be masked by the KHA-137 change. mobile-engineer was
right to keep it out of KHA-137's scope.

## 6. Files

| File | What it is |
|---|---|
| `01-first-screen.png` | first launch, Flutter splash |
| `02-after-warmup.png`, `03-lock-gate.png` | black — `FLAG_SECURE` under `BiometricPrompt`, see note above |
| `04-unlocked-home.png` | S-03 Home; the original 43 s duplicate pair as **one** row |
| `05-after-first-sms.png` | KHA-122 immediate sweep, app never backgrounded |
| `06-after-redelivery.png` | **the KHA-137 retest** — total unchanged |
| `07-after-resume-sweep.png` | retest step 5, no regression |
| `08-reports-tab.png` | S-30 Reports, the new fourth tab |
| `09-card-breakdown.png` | AC-E3.2 footer identity |
| `10-transactions-list.png` | S-10, four rows, no duplicates |
| `11-filtered-total.png` | AC-E5.2 filtered total |
| `bidi_sender_probe.dart` | KHA-151 reproduction |
| `regression-suites-037d810.log` | targeted 87-test re-run |
