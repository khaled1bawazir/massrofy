QA pass 8 — PR #34 (P4b), head 0585fd4
======================================

WHAT WAS RUN (all on 0585fd4, or on the QA branch whose lib/ tree is
byte-identical to it — see the tree-hash check in the QA PR body).

  qa-pr34-gates.txt
      flutter analyze                       -> No issues found!
      dart format --set-exit-if-changed lib test
                                            -> 215 files, 0 changed
      Measured BEFORE the QA probe file was added, so these are the
      engineer's own claimed figures, reproduced exactly.

  qa-pr34-fulltest.txt
      flutter test  -> 1340 passing / 3 skipped / 1 failing
      The engineer's claimed count, reproduced exactly. The single
      failure is privacy_overlay_release_mode_test.

  qa-pr34-fulltest-with-probes.txt
      flutter test  -> 1352 passing / 3 skipped / 1 failing
      Same tree PLUS test/security/qa_pr34_probe_test.dart (12 probes).
      Same single failure, so the QA probes add no new failure.

  The disclosed environmental failure was VERIFIED rather than accepted:
      flutter test --dart-define=dart.vm.product=true \
        test/features/security/privacy_overlay_release_mode_test.dart
                                            -> All tests passed!

  qa-pr34-build.txt
      flutter build apk --debug             -> BUILD_EXIT=0
      "Built build\app\outputs\flutter-apk\app-debug.apk"
      Real Android artifact, containing every P4b screen. This is the
      strongest runtime evidence available on this machine.


WHAT WAS *NOT* RUN — stated rather than implied
-----------------------------------------------

  NO ON-DEVICE / EMULATOR JOURNEY WALK.

  `flutter devices` reports only Windows desktop, Chrome and Edge; no
  Android emulator exists and no physical device is attached
  (`flutter emulators` lists none). Massrofy is Android-only by
  construction — it reads SMS, and its storage layer is SQLCipher behind
  the Android Keystore (ADR-005/ADR-010) — so running it on the Windows
  or web targets would exercise neither the real storage path nor the
  real lock gate, and a "journey" walked there would be evidence of
  nothing.

  So this pass proves, for the P4b screens:
    - they COMPILE into a shippable Android artifact (build above);
    - they RENDER, in both locales and at 2.0 text scale, through every
      design.md §3.4 state — loading, empty, error, locked, populated —
      via 1352 widget/unit tests;
    - they are REACHABLE from the app's only root, verified by grepping
      the construction sites in lib/ (see docs/test-plan.md §7f.4);
    - nothing is reachable ABOVE the lock gate.

  It does NOT prove the app launches and behaves correctly on real
  Android hardware. That gap is not new and is already tracked as risk
  R-12 / the unrun KHA-7 device spike; P4b is the first phase where a
  device run would actually show a human something, which is worth
  raising when P5 is planned.
