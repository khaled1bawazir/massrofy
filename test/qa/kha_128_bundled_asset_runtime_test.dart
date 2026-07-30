/// **QA runtime-path probe for KHA-128 / PR #43.**
///
/// Every other test of the rule pack — including the two the PR adds — reads
/// `assets/rule_packs/sa-core.json` with a plain `File` read. That is a
/// deliberate, well-documented choice (fast, no widget binding), and it does
/// exercise the exact bytes on disk. But it skips one link in the chain that
/// only exists at runtime:
///
/// ```
/// pubspec.yaml `assets:` entry  ->  the built asset bundle
///                               ->  rootBundle.loadString(bundledRulePackAsset)
///                               ->  RulePackLoader.parse
/// ```
///
/// A `File` read passes even if the asset were never declared in `pubspec.yaml`
/// — in which case the shipped app would throw on first ingestion and every
/// message from all seven banks would be lost again, which is precisely the
/// class of failure KHA-128 exists to close. The `flutter test` binding serves
/// declared assets through `rootBundle`, so that link CAN be checked on a
/// laptop, and this file checks it.
///
/// ## What this is NOT
///
/// This is not on-device verification. No Android emulator or device was
/// available on the machine that ran this (`flutter devices` reported only
/// Windows/Chrome/Edge; the app is Android-only, ADR-001). Release-mode
/// on-device behaviour remains covered by KHA-127 and the unrun KHA-7 spike
/// (risk R-12) — see `docs/test-plan.md`. What this file adds is: the asset is
/// declared, bundled, reachable through the production symbol, and parses into
/// exactly the seven banks KHA-128 promises.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';
import 'package:massrofy/presentation/providers/ingestion_providers.dart'
    show bundledRulePackAsset;

void main() {
  // The binding is what makes `rootBundle` resolve against the test asset
  // bundle built from `pubspec.yaml`.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled pack is reachable through the production asset path and '
      'parses to all seven banks', () async {
    // Loaded exactly the way `activeRulePacksProvider` loads it — same
    // constant, same API — rather than by a path this test made up.
    final String json = await rootBundle.loadString(bundledRulePackAsset);
    final RulePack pack = RulePackLoader.parse(json);

    expect(pack.packId, 'sa-core');
    expect(
      pack.banks.map((BankRule b) => b.bankId).toSet(),
      <String>{
        'bank-aljazira',
        'd360',
        'nera',
        'al-rajhi',
        'stc-bank',
        'saib',
        'sab',
      },
      reason:
          'if the asset entry in pubspec.yaml were ever dropped or the path '
          'changed, this is the only test that would notice — every other '
          'rule-pack test reads the file directly from disk and would keep '
          'passing while the shipped app threw on first ingestion.',
    );
  });

  test('packVersion was bumped, so per-transaction provenance can tell '
      'pre-fix output from post-fix output', () async {
    // `rulePackVersion` is stored on every transaction and in the audit
    // `actorDetail`. If the version had not moved, rows produced before and
    // after this fix would be indistinguishable — which matters here because
    // the fix changes WHICH messages get ingested at all.
    final RulePack pack = RulePackLoader.parse(
      await rootBundle.loadString(bundledRulePackAsset),
    );
    expect(pack.packVersion, '2026.07.30');
  });
}
