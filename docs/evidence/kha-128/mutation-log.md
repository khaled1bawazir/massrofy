# Mutation-test evidence — PR #43 (KHA-128), head `b93250f`

Every mutation below was applied to `assets/rule_packs/sa-core.json` (or
`pubspec.yaml`) in a scratch worktree, the named suite was run, and the file was
restored with `git checkout --`. Restoration verified by blob hash:
`assets/rule_packs/sa-core.json` = `5adfff862646e2c3183452fb17300ae2978e88d5`
both before and after, matching the PR diff's `index 6cf1ff5..5adfff8`.
`git rev-parse 'HEAD^{tree}:lib'` = `f0b8531cf7ce2dff8063df840a25f752ea85ffaa`,
identical to `b93250f`.

The point of this file: `docs/lessons.md` warns this build has been burned by
tests that pass without testing what they claim. Reading a test is not evidence
it fires. Each row below is a deliberate break plus the observed failure.

| # | Mutation | Suite run | Result | What it proves |
|---|---|---|---|---|
| **M1** | `bank-aljazira.messageRules` set to `[]` | `rule_pack_corpus_test.dart` | **FAILS**, 20 failures; the new assertion fails first with `Expected: contains all of Set:['bank-aljazira', 'd360'] / Actual: Set:['d360']` | The PR's new "the sampled banks still have templates" assertion is real, not decoration. |
| **M1b** | same mutation | only the three *filtered* whole-pack assertions (`--plain-name "every sampled bank"`) | **PASS (+2, "All tests passed!")** | Confirms the escape hatch the new assertion exists to close: without it, emptying a sampled bank's rules would silently reclassify it as sender-only and skip every whole-pack check. The engineer's stated rationale is empirically correct. |
| **M2** | `^Jazira\s*Bank$` removed from `bank-aljazira.senderPatterns` | `sender_recognition_test.dart` | **FAILS**, `+40 -3`, incl. `"Jazira Bank" never yields NotFinancialSender` → `Actual: <Instance of 'NotFinancialSender'>` | The PR's own sender tests are load-bearing: delete the fix, the tests go red. |
| **M2b** | same mutation | `test/qa/kha_128_sender_gate_qa_probes_test.dart` | **FAILS**, `+89 -6` | QA's independent probes are load-bearing too, and they fail on the same break through a different code path (production `parse()` outcome rather than a re-walk of `pack.banks`). |
| **M3** | `d360.senderPatterns` replaced with ONLY the new `^D360\s*Bank$` — i.e. the "silent narrowing" mistake this PR was specifically asked not to make | `sender_recognition_test.dart` + QA probes | **FAILS**, `+133 -5`: `"D360" still resolves to d360` → `Actual: <null>`, `"D-360"` likewise, plus QA-P8's one-claimant assertion | The additive-not-replacing property is *enforced*, not just intended. A future tidy-up that deletes the old alternatives cannot pass CI. |
| **M4** | the whole `nera` bank entry deleted | corpus + sender + pipeline suites | **FAILS**, `+126 -6`, incl. `loads, and declares every configured bank` and the AC-A6.5 structural test | Removing a newly added bank cannot pass silently. |
| **M5** | `- assets/rule_packs/sa-core.json` commented out of `pubspec.yaml` | `test/qa/kha_128_bundled_asset_runtime_test.dart` | **FAILS**, `Unable to load asset: "assets/rule_packs/sa-core.json"` | QA's new runtime-path probe genuinely covers the one link no other rule-pack test covers — pubspec declaration → asset bundle → `rootBundle`. Every other rule-pack test uses a plain `File` read and would keep passing while the shipped app threw on first ingestion. |
| **M6** | `saib.aliases` gains `"S A B"`, which `normalizeBankName` folds to `sab` | QA-P9 | **FAILS**, `Actual: {'sab': Set:['saib', 'sab']}` | QA-P9's `BankDirectory` collision guard is not vacuous. It is unbroken on `b93250f`, and it will guard KHA-136 when more banks are added to the same map-literal index. |

## Gates re-measured by QA on `b93250f` itself (not cited from the PR body)

| Gate | Engineer claimed | QA measured | Verdict |
|---|---|---|---|
| `dart format --output=none --set-exit-if-changed .` | clean, 240 files, 0 changed | **240 files, 0 changed**, exit 0 | reproduced exactly |
| `flutter analyze` | clean | **No issues found!** (6.0s) | reproduced |
| `flutter test --exclude-tags=release_mode_guard` | 1490 pass / 3 skip / 0 fail | **1490 pass / 3 skip / 0 fail**, exit 0 | reproduced exactly |

With QA's 101 probes added (`test/qa/`, zero production diff):
**1591 pass / 3 skip / 0 fail** = 1490 + 101, exactly. `dart format` 242 files
0 changed; `flutter analyze` clean. See `full-suite-final-qa-tree.log`.

Toolchain: Flutter 3.44.8 stable, Dart 3.12.2, Windows 11.

## Stated skips (no coverage claimed)

- **No on-device or emulator run.** `flutter devices` reported only Windows /
  Chrome / Edge; `adb devices` empty; `flutter emulators` lists none. The app is
  Android-only (ADR-001, no `windows/` runner), so `integration_test` could not
  run. Release-mode on-device behaviour stays covered by **KHA-127** and the
  unrun **KHA-7** spike (risk **R-12**).
- **Whether Jazira/D360 messages actually *parse* into transactions on the
  human's real phone is not verified by this PR and is not claimed to be.** This
  PR fixes gate 1 (sender recognition) only. A Jazira or D360 message landing in
  Needs Review rather than the ledger after this ships is **this fix working as
  designed**, and would additionally tell us the body templates are wrong too —
  a separate, still-open assumption.
