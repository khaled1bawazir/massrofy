# QA evidence — PR #24 (P3b-3), gate reproduction

All commands run by **qa-tester** on 2026-07-29 in a clean checkout of
`fix/p3b-3-merge-money-invariants` at head **`8761e3e`** (merge-base with `main`:
`4f49513`). Toolchain: **Flutter 3.44.8 stable, Dart 3.12.2** — the same version
the PR body names.

Per `docs/lessons.md` (2026-07-29): a pass/fail claim is only evidence for the
tree it was measured on. Every number below was measured, not quoted.

---

## 1. `flutter analyze --fatal-infos`

```
Analyzing agent-afa7640b0a3a87393...
No issues found! (ran in 5.5s)
```

**MATCH** with the PR's claim (`No issues found! (ran in 3.8s)`).

Re-run after adding `test/security/qa_pr24_probe_test.dart`: still
`No issues found! (ran in 4.2s)`.

## 2. `dart format --set-exit-if-changed .`

```
Formatted 183 files (0 changed) in 1.23 seconds.
exit 0
```

**MATCH** (PR claimed 183 files, 0 changed). With the QA probe file added:
`Formatted 184 files (0 changed)`, exit 0.

## 3. `flutter test --exclude-tags=release_mode_guard`

```
00:49 +1040 ~3: All tests passed!
```

**MATCH** — 1040 passing, 3 skipped, 0 failing, exactly as claimed.
(Baseline on `4f49513` per PR body: 1035.)

With QA's 17 new probes added:

```
00:52 +1057 ~3: All tests passed!
```

## 4. `flutter build apk --debug`

```
Running Gradle task 'assembleDebug'...  75.1s
✓ Built build\app\outputs\flutter-apk\app-debug.apk
exit 0
```

**MATCH.** (Three `javac` "target value 8 is obsolete" warnings — pre-existing,
unrelated to this PR.)

## 5. `bash .github/scripts/check_money_type_ban.sh`

```
No .drift files yet — nothing to check for banned SQL aggregation.
ADR-002 money-type guard: no banned double/num/SQL-aggregation usage found.
exit 0
```

**MATCH.**

---

## Not run, and why

- **`check_no_network_permission.sh`** — requires a *release* build and a merged
  Android manifest. CI owns this job; the PR does not claim it.
- **On-device / emulator run.** No Android emulator or connected device is
  available in this environment, so `integration_test/` (including
  `db_encryption_test.dart`) was **not** executed. This PR touches no
  platform-channel, storage-encryption or lifecycle code — it changes a pure
  decision function, one DAO method, one screen's confirmation dialog and
  localisation — so the risk of a device-only regression is low, but this is
  stated rather than implied. Runtime journey verification for the merge screen
  belongs to **P4b**, which is the phase this PR gates: nothing routes to
  `NeedsReviewScreen` yet (O-QA-9), so there is no journey to walk.

## QA probe suite

`test/security/qa_pr24_probe_test.dart` — 17 probes, all passing.
8 are executed reproductions of defects (D-QA-14/15/16/17/18/19/20, O-QA-10);
9 assert that a claimed property survives an attack.

```
+17: All tests passed!
```
