/// Tests for the rule-pack loader — ADR-007's §5.2 compatibility rules and
/// the screening it applies to a pack the **user may have imported**.
///
/// Imported packs are the answer to risk R-11 (a side-loaded build has no
/// update channel, so parser fixes must ship as data). That makes a rule pack
/// semi-untrusted input, and every rejection below exists because a
/// permissive alternative would fail in a way the user could not see.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';

/// A minimal, valid pack. Each test mutates one thing, so a failure names
/// exactly the rule that fired.
String packWith({
  int schemaVersion = 1,
  String extractBody = '"amount": { "group": "amt" }',
  String ruleBody = '',
}) =>
    '''
{
  "schemaVersion": $schemaVersion,
  "packId": "test",
  "packVersion": "1",
  "banks": [{
    "bankId": "b1",
    "displayName": { "ar": "بنك", "en": "Bank" },
    "senderPatterns": ["^B1\$"],
    "messageRules": [{
      "ruleId": "r1",
      "priority": 100,
      "messageType": "pos_purchase",
      "intent": "transaction",
      "regex": "(?<amt>[0-9.]+)",
      "extract": { $extractBody }
      $ruleBody
    }]
  }]
}
''';

void main() {
  group('§5.2 compatibility rule 1 — a newer schema is REJECTED, not partly '
      'applied', () {
    test('a higher schemaVersion is refused with a user-facing message', () {
      expect(
        () => RulePackLoader.parse(packWith(schemaVersion: 99)),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            allOf(
              contains('99'),
              // The message is addressed to the person who imported the file,
              // not to a developer reading a stack trace.
              contains('Update the app'),
              contains('has not been applied'),
            ),
          ),
        ),
        reason:
            'partially applying an unknown schema means silently ignoring the '
            'parts you did not understand — in a parser, that is silently '
            'getting amounts wrong',
      );
    });

    test('the current schemaVersion loads', () {
      expect(RulePackLoader.parse(packWith()).schemaVersion, 1);
    });
  });

  group('§5.2 compatibility rule 2 — unknown FIELDS are ignored', () {
    test('a forward-compatible hint does not break the load', () {
      const String withHint = '''
{
  "schemaVersion": 1,
  "packId": "test",
  "packVersion": "1",
  "someFutureHint": { "anything": true },
  "banks": [{
    "bankId": "b1",
    "displayName": { "ar": "بنك", "en": "Bank" },
    "senderPatterns": ["^B1\$"],
    "unknownBankField": 42,
    "messageRules": [{
      "ruleId": "r1",
      "priority": 100,
      "messageType": "pos_purchase",
      "intent": "transaction",
      "unknownRuleField": "ignored"
    }]
  }]
}
''';
      // Note the asymmetry with rule 1, and it is deliberate: unknown
      // *version* is fatal, unknown *field* is not.
      expect(RulePackLoader.parse(withHint).banks, hasLength(1));
    });
  });

  group('a typo must fail loudly at load time, not silently at parse time', () {
    test('an unknown transform name is rejected, and the message lists the '
        'valid ones', () {
      expect(
        () => RulePackLoader.parse(
          packWith(
            extractBody:
                '"amount": { "group": "amt", "transform": ["nomalizeNumerals"] }',
          ),
        ),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            allOf(contains('nomalizeNumerals'), contains('normalizeNumerals')),
          ),
        ),
        reason:
            'a silently-ignored transform would send an Arabic-numeral amount '
            'to Money.parse unconverted; the user would see "could not parse" '
            'and never learn their pack has a one-letter typo in it',
      );
    });
  });

  group('NFR-S2 is not negotiable by data', () {
    test('a pack cannot ask to keep more than the last four digits', () {
      expect(
        () => RulePackLoader.parse(
          packWith(
            extractBody:
                '"instrumentRef": { "group": "amt", "kind": "card", '
                '"maskPolicy": "full" }',
          ),
        ),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            contains('never stores more of a card or account number'),
          ),
        ),
      );
    });

    test('an instrument kind must be declared, not invented', () {
      // AC-B13.1/2: `kind` comes from the matched rule, never from a guess
      // about digit length.
      expect(
        () => RulePackLoader.parse(
          packWith(
            extractBody:
                '"instrumentRef": { "group": "amt", "kind": "wallet" }',
          ),
        ),
        throwsA(isA<RulePackFormatException>()),
      );
    });
  });

  group('hostile / malformed pattern screening (ADR-007 "Safety")', () {
    test('a nested unbounded quantifier is refused before it can ever run', () {
      // `(a+)+` is the classic catastrophic-backtracking shape. Dart's RegExp
      // cannot be interrupted mid-match, so a timeout alone is not a real
      // mitigation — refusing to load is (see rule_pack_loader.dart).
      expect(
        () => RulePackLoader.parse(
          packWith(ruleBody: '').replaceFirst(r'(?<amt>[0-9.]+)', r'(a+)+b'),
        ),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            contains('exponential time'),
          ),
        ),
      );
    });

    test('an invalid regex is a load-time error with the offending rule '
        'named', () {
      expect(
        () => RulePackLoader.parse(
          packWith().replaceFirst(r'(?<amt>[0-9.]+)', r'(?<amt>[0-9.'),
        ),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            contains('rule "r1"'),
          ),
        ),
      );
    });

    test('an unsupported timezone is refused rather than quietly ignored', () {
      expect(
        () => RulePackLoader.parse(
          packWith(
            extractBody:
                '"occurredAt": { "group": "amt", "format": "dd/MM/yyyy", '
                '"timezone": "Europe/London" }',
          ),
        ),
        throwsA(
          isA<RulePackFormatException>().having(
            (RulePackFormatException e) => e.message,
            'message',
            contains('Asia/Riyadh'),
          ),
        ),
        reason:
            'accepting a value we would then ignore is worse than refusing '
            'it — the pack author would believe their timezone was applied',
      );
    });
  });

  group('rule ordering', () {
    test('rules are pre-sorted by descending priority, ties broken by '
        'declaration order', () {
      const String multi = '''
{
  "schemaVersion": 1,
  "packId": "test",
  "packVersion": "1",
  "banks": [{
    "bankId": "b1",
    "displayName": { "ar": "بنك", "en": "Bank" },
    "senderPatterns": ["^B1\$"],
    "messageRules": [
      { "ruleId": "low",      "priority": 10,  "messageType": "x", "intent": "ignore" },
      { "ruleId": "tie-first","priority": 100, "messageType": "x", "intent": "ignore" },
      { "ruleId": "tie-second","priority": 100,"messageType": "x", "intent": "ignore" },
      { "ruleId": "high",     "priority": 900, "messageType": "otp", "intent": "ignore" }
    ]
  }]
}
''';
      final RulePack pack = RulePackLoader.parse(multi);
      expect(
        pack.banks.single.messageRules.map((MessageRule r) => r.ruleId),
        <String>['high', 'tie-first', 'tie-second', 'low'],
        reason:
            "Dart's sort is not stable, so declaration order has to be folded "
            'into the comparison explicitly — otherwise two equal-priority '
            'rules could swap on a different Dart version and change which '
            'one wins, which is a genuinely non-reproducible parser bug',
      );
    });
  });

  group('affectsSpend defaults in the safe direction per sign', () {
    test('a credit rule that omits affectsSpend does NOT count as spend', () {
      const String credit = '''
{
  "schemaVersion": 1,
  "packId": "test",
  "packVersion": "1",
  "banks": [{
    "bankId": "b1",
    "displayName": { "ar": "بنك", "en": "Bank" },
    "senderPatterns": ["^B1\$"],
    "messageRules": [
      { "ruleId": "r", "priority": 1, "messageType": "transfer_in",
        "intent": "transaction", "sign": "credit" }
    ]
  }]
}
''';
      expect(
        RulePackLoader.parse(
          credit,
        ).banks.single.messageRules.single.affectsSpend,
        isFalse,
        reason:
            'one global default would be wrong half the time; a forgotten '
            'flag on a salary credit would silently inflate "money spent"',
      );
    });
  });
}
