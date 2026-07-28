import 'dart:io';

import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';

/// Loads the **real** bundled rule pack from disk — the exact bytes that ship
/// in the APK — rather than an inline fixture copy.
///
/// An inline copy would drift. The first time someone fixed a regex in
/// `assets/rule_packs/sa-core.json` without touching the test copy, the suite
/// would keep passing while the shipped parser was broken, which is the
/// precise opposite of what a regression corpus is for (NFR-M2).
RulePack loadBundledRulePack() => RulePackLoader.parse(
  File('assets/rule_packs/sa-core.json').readAsStringSync(),
);
