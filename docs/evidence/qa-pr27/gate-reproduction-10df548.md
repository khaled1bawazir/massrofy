# QA gate reproduction — PR #27 (P4a), head `10df548`

Every number below was measured by qa-tester, locally, on
`10df5481c6ee0e9d8abe5c8c98cc7e71e2a78791` — not read from the PR body.
`docs/lessons.md`: *"a gate result is only evidence for the exact tree it was
measured on"*, and *"a reviewer must re-run the gate on the CURRENT head rather
than citing an earlier verdict"*.

- **Toolchain:** Flutter 3.44.8 (stable, revision `058e0af2c2`) · Dart 3.12.2 ·
  Windows 11.
- **Working tree:** clean at `10df548` plus additive QA artifacts only.

## Zero production diff, proven by tree hash (not asserted)

```
$ git rev-parse 'HEAD^{tree}:lib'      # PR #27 head, 10df548
b57828345bd6cfa90dd761902b09c6a55b830104
$ git rev-parse '<qa staged tree>:lib' # the QA commit
b57828345bd6cfa90dd761902b09c6a55b830104
```

The `lib/` subtree is byte-identical. `git diff --cached --stat -- lib android
.github pubspec.yaml pubspec.lock integration_test` is empty. This QA pass adds
one test file and three documents and changes no production code — which is also
what makes every number below reproducible from the code PR's own head.

## Gates

| # | Command | Result | Engineer's claim |
|---|---|---|---|
| 1 | `dart format --output=none --set-exit-if-changed .` | `Formatted 207 files (0 changed) in 1.47 seconds.` — **clean** | "204 files, 0 changed" — same result, different count |
| 2 | `flutter analyze` | `No issues found! (ran in 5.4s)` | "clean" — reproduced |
| 3 | `flutter test` | `+1190 ~3 -1` — **1190 pass / 3 skip / 1 fail** | "1190 passing / 3 skipped / 1 failing" — reproduced exactly |
| 4 | `flutter test test/features/security/privacy_overlay_release_mode_test.dart --dart-define=dart.vm.product=true` | `+1: All tests passed!` | claim that the single failure is pre-existing and environmental — **verified independently, not accepted** |
| 5 | `bash .github/scripts/check_money_type_ban.sh` | `ADR-002 money-type guard: no banned double/num/SQL-aggregation usage found.` | not claimed; run anyway (P4a introduces a sanctioned `REAL` column) |
| 6 | `flutter test test/security/qa_pr27_probe_test.dart` | `+35: All tests passed!` | new — QA's own adversarial suite |
| 7 | `flutter test` **with** the probe suite present | `+1225 ~3 -1` (1190 + 35) | new |

## Note on gate 1

The file count differs from the PR body (207 vs 204) while the *result* is
identical (0 changed). The count is not itself a correctness claim, but it is
recorded here because a stale count is exactly the shape of the PR #20 → #22
incident in `docs/lessons.md`: a true-when-written number read later as if it
covered a different tree. 207 is what `10df548` contains.

## Note on gate 3's single failure

`privacy_overlay_release_mode_test.dart` asserts there is no reachable bypass of
the privacy overlay in a release build. It requires
`--dart-define=dart.vm.product=true`, which CI supplies as a dedicated step and
a bare `flutter test` does not. Gate 4 above re-runs it with that define and it
passes. It is unrelated to P4a: it touches no file this PR changes.

## What was NOT run, and why

- **No emulator / device run.** P4a adds no UI and routes no screen; the app
  shell still routes only `HomePlaceholderScreen`. There is no user journey in
  this PR to drive. Runtime journey verification remains owed at the point a
  categorization surface ships (KHA-32/33/34/97) — recorded here so the omission
  is explicit rather than silently absent.
- **No `check_no_network_permission.sh`.** Needs a release build and a merged
  manifest; CI owns it. Unchanged from previous passes.
- **No SQLCipher-on-device check.** Same standing constraint as passes 1-5
  (`test/support/plain_test_database.dart` explains it); CI's
  `android-sqlcipher-integration-test` job owns it.
