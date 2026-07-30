# KHA-133 / PR #46 — QA gate evidence

All figures below were measured by QA on **`17e3444`** (the PR head at the time
of the gate), with the QA probe file `test/qa/kha133_rescan_probes_test.dart`
present in the tree. The PR body's own figures were measured on `8f7e47f`, one
commit earlier — per `docs/lessons.md` (2026-07-29), a gate result is only
evidence for the exact tree it was measured on, so every claim was re-run rather
than cited.

Toolchain: Flutter 3.44.8 stable, framework `058e0af2c2`, on Windows.

## Static gates

```
$ flutter analyze
No issues found! (ran in 9.7s)

$ dart format --set-exit-if-changed .
Formatted test\qa\kha133_rescan_probes_test.dart
Formatted 249 files (1 changed) in 2.38 seconds.
```

The single reformatted file is QA's own probe file, reformatted before commit.
The production tree is format-clean on `17e3444`.

## Test suite

```
$ flutter test
01:45 +1641 ~3 -1: Some tests failed.

Failing tests:
  test/features/security/privacy_overlay_release_mode_test.dart
```

```
$ flutter test --exclude-tags=release_mode_guard
01:47 +1641 ~3: All tests passed!
```

The plain-run failure is expected and pre-existing. `.github/workflows/ci.yml`
L132 runs the main suite as
`flutter test --coverage --exclude-tags=release_mode_guard`, and L134–150 runs
that one file in a separate step with `--dart-define=dart.vm.product=true`.
QA read the workflow to confirm this rather than accepting the PR body's claim.

1641 = the engineer's 1632 on `8f7e47f` + QA's 9 probes.

## CI

GitHub Actions run **30543017203** on `17e3444`. The aggregate `ci` fan-in check
is the signal used here, per `docs/lessons.md` (2026-07-30) — individual job
`status` fields on this repo have been stale for 40–70 minutes repeatedly.

| Check | Conclusion |
|---|---|
| **`ci` (aggregate fan-in)** | **success** |
| flutter build & test | success |
| On-device integration tests (Android emulator): ADR-003 SQLCipher + ADR-004 Keystore channel | success |
| dependency & security scan | success |
| ADR-002: money-type guard (double/num ban) | success |
| ADR-001: no-network release manifest guard | success |

## QA probe suite

Full run output: `kha133-qa-probes-17e3444.txt` — **9 probes, all passing**.
See `docs/test-plan.md` §7i for what each probe attacks and why the engineer's
own 23 tests do not already cover it.

## What was NOT run, stated honestly

- **No local device or emulator run of the KHA-133 journey.** No Android
  emulator is available in this QA environment. The user-facing journey
  (More → App → "Check my banks again" → run → result) is covered by 18 widget
  tests including two that drive the **real `AppShell`** through the More menu to
  the route, host and providers — that is construction-site reachability
  evidence, not a device run. CI's own on-device emulator job passed on this
  head, but it exercises ADR-003/ADR-004 storage and Keystore, not this screen.
- **No Playwright / browser evidence.** Not applicable: Massrofy is a Flutter
  Android app with no web surface.
- **No mutation run against production code.** QA does not edit production code.
  The equivalent assurance — that the item (F) fix is genuinely load-bearing
  rather than inert — was obtained instead by probes **P1** (the hmac drift is
  real, the content-hmac lookup misses, the provider-id lookup hits) and **P5**
  (the new key exercised through a live pipeline run, against a `UNIQUE`
  constraint verified to exist).
