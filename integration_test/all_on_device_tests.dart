// The single entry point CI uses for every on-device integration suite.
//
// ## Why this file exists (KHA-75) — read before adding a new suite
//
// `flutter test <device>` rebuilds and reinstalls the whole app **once per
// test file**. On a GitHub-hosted 2-vCPU runner a cold `assembleDebug` for
// this project measured **900.5s (15.0 min)** on run 30396986689 — against a
// per-attempt script budget of 960s. So the first file consumed 94% of the
// budget on its own, and adding a *second* file (which triggers a second
// full build) blew straight through it:
//
//   Running Gradle task 'assembleDebug'...   900.5s
//   ✓ Built build/app/outputs/flutter-apk/app-debug.apk
//   🎉 6 tests passed.                        <- db_encryption_test.dart
//   Running Gradle task 'assembleDebug'...    <- keystore_channel_test.dart
//   ##[error]The process '/usr/bin/sh' failed with exit code 124
//
// The tests themselves cost ~50 seconds. Essentially the entire cost of an
// extra suite was a second app build that bought nothing.
//
// This file removes that cost: CI points at *this* file, so there is exactly
// **one** build and **one** install no matter how many suites exist, and a
// new suite costs only the seconds its assertions actually take.
//
// ## The rule, so the next suite is not silently un-run
//
// **Every file in `integration_test/` must be registered below.** That is a
// convention, and conventions rot — so it is stated here, next to the list,
// rather than in a workflow file nobody opens. The two alternatives were
// both worse:
//   - CI naming one file (what it did before KHA-75): a new suite is
//     invisible until someone remembers to edit `ci.yml`.
//   - CI running the whole directory (what KHA-75 tried first): correct, but
//     it pays a full app build per file and, as measured above, that is not
//     affordable on these runners.
//
// Each suite also stays runnable on its own during development:
//   flutter test integration_test/keystore_channel_test.dart -d <deviceId>
// Only CI goes through this aggregator.
//
// Note there is deliberately no `IntegrationTestWidgetsFlutterBinding
// .ensureInitialized()` here — each suite's own `main()` already calls it,
// and it is idempotent.
import 'db_encryption_test.dart' as db_encryption;
import 'keystore_channel_test.dart' as keystore_channel;

void main() {
  // ADR-003 — SQLCipher genuinely encrypts on a real device.
  db_encryption.main();

  // ADR-004 — the Keystore MethodChannel's Dart<->Kotlin wire contract.
  // This is the one that only a real device can check: a fake MethodChannel
  // never crosses the codec boundary where KHA-75 lived.
  keystore_channel.main();
}
