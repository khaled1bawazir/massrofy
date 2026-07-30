KHA-146 / PR #49 — runtime journey verification evidence
========================================================

Device      : Android emulator (AVD massrofy_test), Android 15, 1080x2400
Build       : debug APK built from fix/kha-146-partial-extraction-prefill @ 3f29086
              (clean install; package lastUpdateTime pinned at 2026-07-30 21:21:12
              and re-checked before and after every screenshot below, because a
              second process on the same machine was concurrently reinstalling the
              app — an earlier, contaminated observation set was discarded)
Fixtures    : synthetic, NFR-M3 — bank-SHAPED messages invented by QA and injected
              with `adb emu sms send`. No real bank SMS was used, quoted or stored.
              Merchants (CLOVER HILL OPTICS, SILVERPINE PHARMACY, GREENFIELD BAKERY,
              WILLOW LANE GROCER) and card last-4s are fabricated.

Files, in journey order
-----------------------
35-clean-first-screen.png            Journey #0 — app boots, unlocks, home renders, no error state
36-queue-clean.png                   Both cases routed correctly: "Some details were missing"
                                     (case b) vs "did not match any known format" (case a)
37-JOURNEY1-case-b-form.png          Case (b) PRE-FILLED: notice + amount + currency + merchant
                                     + type + the matched card. The defect this PR closes.
38-JOURNEY3-instrument-dropdown.png  The control for "matched, not defaulted": four cards
                                     (1111, 4821, 9911, 2244) and the selected one is the LAST
                                     — the one the message named.
39-JOURNEY3-user-changed-card.png    User overrides the match: picks ****9911
45-JOURNEY3-choice-survived-rebuild.png  After a rotation (fresh instruments List ->
                                     didUpdateWidget re-match), the user's ****9911 survives
47-JOURNEY4-after-save.png           Saved transaction: -64.40 SAR, correct merchant/type/date
49-baj-cards.png                     Oracle: card ****9911 = -76.40 = 12.00 + 64.40 exactly,
                                     i.e. the USER's card was written, not the pre-filled one
51-JOURNEY2-case-a-blank-form.png    Case (a) correctly blank, no pre-fill notice (no regression)
52-PROBE-empty-save-blocked.png      AC-B4.2 intact: empty save blocked, errors name their fields
56-PROBE-saved-typed-amount.png      Overwriting a pre-filled 87.25 with 10.00 saves -10.00
                                     (no stale/ghost pre-fill value)
61-ORACLE-total-after.png            Period total -371.90 = 210.00 + 45.50 + 12.00 + 30.00
                                     + 64.40 + 10.00, recomputed by hand. No double count.

Gates measured on 3f29086
-------------------------
flutter analyze .............. No issues found
dart format (lib/test/integration_test) ... clean, 255 files, 0 changed
flutter test ................. 1676 passed, 3 skipped, 1 failed
                               (the failure is privacy_overlay_release_mode_test.dart, which
                                requires --dart-define=dart.vm.product=true and has its own
                                green CI job — pre-existing and expected)
GitHub aggregate `ci` check .. success (run 30550953917, 6/6 jobs green)

Verdict: QA: PASS 49
