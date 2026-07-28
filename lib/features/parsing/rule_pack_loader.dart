/// Turns a rule-pack JSON document into the validated in-memory [RulePack]
/// the engine evaluates — and rejects anything it cannot fully honour.
///
/// ## The three §5.2 compatibility rules, and why each is a *rejection*
///
/// `docs/architecture.md` §5.2 says to treat this schema as you would API
/// versioning:
///
/// 1. **A newer `schemaVersion` is rejected outright, never partially
///    applied.** Partially applying an unknown schema means silently ignoring
///    the parts you did not understand — in a parser, that is silently
///    getting amounts wrong.
/// 2. **Unknown *fields* inside a known version are ignored**, so packs can
///    carry forward-compatible hints. Note the asymmetry with (1): unknown
///    *version* is fatal, unknown *field* is not.
/// 3. **An unrecognised `messageType` is `unknown` → review queue, never
///    discarded** (NFR-A7). Handled in the engine, not here — the loader
///    keeps the string verbatim rather than coercing it.
///
/// ## Why the loader screens regexes at all
///
/// ADR-007 permits the user to **import** a pack (the answer to R-11:
/// parser rules that update without reinstalling an APK on a side-loaded
/// build). That makes a rule pack semi-untrusted input. The ADR's stated
/// mitigations are: declarative-only, a per-rule timeout, mandatory user
/// review of the diff, and no network permission.
///
/// The timeout half of that is weaker than it sounds — Dart's `RegExp`
/// cannot be interrupted mid-match (see `rule_pack_message_parser.dart`). So
/// this loader adds the mitigation that actually works: it **refuses to load**
/// patterns containing nested unbounded quantifiers such as `(a+)+` or
/// `(a*)*`, which is the shape that causes catastrophic backtracking. Cheap,
/// static, and it stops the problem before a hostile pattern is ever run.
///
/// It is a heuristic, not a proof, and it is described as one. A determined
/// adversary who can already convince the user to import a file has other
/// avenues; this closes the accidental and the lazy-malicious cases.
library;

import 'dart:convert';

import 'field_transforms.dart';
import 'rule_pack.dart';

/// Raised when a pack cannot be loaded. Carries a message intended to be
/// shown **to the user** (they are the one who imported the file), so it
/// names what is wrong and where, in plain language.
final class RulePackFormatException implements Exception {
  final String message;
  const RulePackFormatException(this.message);

  @override
  String toString() => 'RulePackFormatException: $message';
}

abstract final class RulePackLoader {
  /// The highest `schemaVersion` this build understands.
  static const int supportedSchemaVersion = 1;

  /// Nested unbounded quantifier: a group whose body ends in `+`/`*`/`{n,}`
  /// and which is *itself* quantified the same way. This is the classic
  /// catastrophic-backtracking shape.
  static final RegExp _nestedQuantifier = RegExp(
    r'\([^)]*[+*]\s*\)\s*[+*]|\([^)]*\{\d+,\}[^)]*\)\s*[+*{]',
  );

  /// Parses [jsonText]. Throws [RulePackFormatException] on any problem —
  /// never returns a partially-populated pack.
  static RulePack parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw RulePackFormatException('not valid JSON: ${error.message}');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const RulePackFormatException(
        'the top level of a rule pack must be a JSON object',
      );
    }

    final int schemaVersion = _requireInt(decoded, 'schemaVersion');
    if (schemaVersion > supportedSchemaVersion) {
      // Rule 1. Deliberately worded for the user, who imported this file and
      // can act on it, rather than for a developer reading a stack trace.
      throw RulePackFormatException(
        'this rule pack uses schema version $schemaVersion, but this version '
        'of Massrofy understands up to $supportedSchemaVersion. Update the '
        'app before importing it. The pack has not been applied.',
      );
    }

    final List<Object?> bankNodes = _requireList(decoded, 'banks');
    if (bankNodes.isEmpty) {
      throw const RulePackFormatException('a rule pack must declare a bank');
    }

    return RulePack(
      schemaVersion: schemaVersion,
      packId: _requireString(decoded, 'packId'),
      packVersion: _requireString(decoded, 'packVersion'),
      locales: _optionalStringList(decoded, 'locales'),
      banks: <BankRule>[for (final Object? node in bankNodes) _parseBank(node)],
    );
  }

  static BankRule _parseBank(Object? node) {
    if (node is! Map<String, dynamic>) {
      throw const RulePackFormatException('each entry of "banks" is an object');
    }

    final String bankId = _requireString(node, 'bankId');
    final Map<String, dynamic> displayName = _requireMap(node, 'displayName');

    final List<MessageRule> rules = <MessageRule>[
      for (final Object? ruleNode in _requireList(node, 'messageRules'))
        _parseRule(ruleNode, bankId),
    ];

    // Sort once, here, rather than on every message. Descending priority;
    // §5.2 breaks ties by declaration order, and Dart's `sort` is *not*
    // guaranteed stable, so the index is folded into the comparison
    // explicitly. Without that, two rules of equal priority could swap on a
    // different Dart version and change which one wins — a genuinely nasty,
    // non-reproducible class of parser bug.
    final List<({int index, MessageRule rule})> indexed =
        <({int index, MessageRule rule})>[
          for (int i = 0; i < rules.length; i++) (index: i, rule: rules[i]),
        ];
    indexed.sort((
      ({int index, MessageRule rule}) a,
      ({int index, MessageRule rule}) b,
    ) {
      final int byPriority = b.rule.priority.compareTo(a.rule.priority);
      return byPriority != 0 ? byPriority : a.index.compareTo(b.index);
    });

    return BankRule(
      bankId: bankId,
      displayNameAr: _requireString(displayName, 'ar'),
      displayNameEn: _requireString(displayName, 'en'),
      aliases: _optionalStringList(node, 'aliases'),
      senderPatterns: <RegExp>[
        for (final String pattern in _optionalStringList(
          node,
          'senderPatterns',
        ))
          _compile(pattern, 'senderPatterns of "$bankId"'),
      ],
      messageRules: <MessageRule>[
        for (final ({int index, MessageRule rule}) entry in indexed) entry.rule,
      ],
    );
  }

  static MessageRule _parseRule(Object? node, String bankId) {
    if (node is! Map<String, dynamic>) {
      throw RulePackFormatException(
        'each entry of "messageRules" in "$bankId" is an object',
      );
    }

    final String ruleId = _requireString(node, 'ruleId');
    final String where = 'rule "$ruleId"';

    final String intentName = _requireString(node, 'intent');
    final RuleIntent intent = switch (intentName) {
      'transaction' => RuleIntent.transaction,
      'ignore' => RuleIntent.ignore,
      _ => throw RulePackFormatException(
        '$where has intent "$intentName"; expected "transaction" or "ignore"',
      ),
    };

    final String signName = (node['sign'] as String?) ?? 'debit';
    final RuleSign sign = switch (signName) {
      'debit' => RuleSign.debit,
      'credit' => RuleSign.credit,
      _ => throw RulePackFormatException(
        '$where has sign "$signName"; expected "debit" or "credit"',
      ),
    };

    final String? regexSource = node['regex'] as String?;

    return MessageRule(
      ruleId: ruleId,
      priority: _requireInt(node, 'priority'),
      messageType: _requireString(node, 'messageType'),
      intent: intent,
      match: _parseMatch(node['match'], where),
      regex: regexSource == null
          ? null
          : _compile(regexSource, '$where extraction regex'),
      extract: _parseExtract(node['extract'], where),
      sign: sign,
      // Defaults to `true` only for debits: a rule author who forgets the
      // flag on a credit (salary, refund) would otherwise silently inflate
      // "money spent". Defaulting in the safe direction per field type is
      // better than one global default that is wrong half the time.
      affectsSpend: (node['affectsSpend'] as bool?) ?? (sign == RuleSign.debit),
      requiredFields: _optionalStringList(node, 'requiredFields'),
      redact: <RegExp>[
        for (final String pattern in _optionalStringList(node, 'redact'))
          _compile(pattern, '$where redact pattern'),
      ],
    );
  }

  static RuleMatch _parseMatch(Object? node, String where) {
    if (node == null) {
      return const RuleMatch();
    }
    if (node is! Map<String, dynamic>) {
      throw RulePackFormatException('$where has a non-object "match"');
    }
    List<RegExp> clause(String key) => <RegExp>[
      for (final String pattern in _optionalStringList(node, key))
        _compile(pattern, '$where match.$key'),
    ];
    return RuleMatch(
      anyOf: clause('anyOf'),
      allOf: clause('allOf'),
      noneOf: clause('noneOf'),
    );
  }

  static Map<String, FieldExtraction> _parseExtract(
    Object? node,
    String where,
  ) {
    if (node == null) {
      return const <String, FieldExtraction>{};
    }
    if (node is! Map<String, dynamic>) {
      throw RulePackFormatException('$where has a non-object "extract"');
    }

    final Map<String, FieldExtraction> result = <String, FieldExtraction>{};
    node.forEach((String field, Object? spec) {
      if (spec is! Map<String, dynamic>) {
        throw RulePackFormatException('$where extract.$field is not an object');
      }

      final List<String> transforms = _optionalStringList(spec, 'transform');
      for (final String name in transforms) {
        // See `field_transforms.dart` for why a typo'd transform is fatal
        // rather than a silent no-op.
        if (FieldTransforms.lookup(name) == null) {
          throw RulePackFormatException(
            '$where extract.$field names unknown transform "$name". '
            'Known transforms: ${FieldTransforms.knownNames.join(", ")}',
          );
        }
      }

      final String? maskPolicy = spec['maskPolicy'] as String?;
      if (maskPolicy != null && maskPolicy != InstrumentMask.last4Policy) {
        // NFR-S2 is not negotiable by data. A pack cannot ask the app to
        // keep more of an identifier than last-4, however it is worded.
        throw RulePackFormatException(
          '$where extract.$field uses maskPolicy "$maskPolicy". Only '
          '"${InstrumentMask.last4Policy}" is permitted — Massrofy never '
          'stores more of a card or account number than its last four digits.',
        );
      }

      final String? instrumentKind = spec['kind'] as String?;
      if (instrumentKind != null &&
          instrumentKind != 'card' &&
          instrumentKind != 'account') {
        throw RulePackFormatException(
          '$where extract.$field has kind "$instrumentKind"; expected "card" '
          'or "account"',
        );
      }

      final String? timezone = spec['timezone'] as String?;
      if (timezone != null && timezone != 'Asia/Riyadh') {
        // Narrow on purpose — `core/time/clock.dart` explains why this build
        // models exactly one zone, and refusing others is more honest than
        // accepting a value we would then ignore.
        throw RulePackFormatException(
          '$where extract.$field requests timezone "$timezone"; this build '
          'supports only "Asia/Riyadh"',
        );
      }

      result[field] = FieldExtraction(
        group: (spec['group'] as String?) ?? field,
        transforms: transforms,
        format: spec['format'] as String?,
        timezone: timezone,
        instrumentKind: instrumentKind,
        maskPolicy: maskPolicy,
        literal: spec['literal'] as String?,
      );
    });
    return result;
  }

  /// Compiles [source], first screening it for the nested-unbounded-quantifier
  /// shape that causes catastrophic backtracking. See the library doc comment
  /// for the honest scope of this check.
  static RegExp _compile(String source, String where) {
    if (_nestedQuantifier.hasMatch(source)) {
      throw RulePackFormatException(
        '$where contains a nested unbounded quantifier, which can make '
        'matching take exponential time. Rewrite it with bounded '
        'quantifiers. Pattern rejected, pack not applied.',
      );
    }
    try {
      // `unicode: true` so that character classes behave predictably against
      // the Arabic text this app is built for; `caseSensitive: false`
      // because bank templates are inconsistent about case in the Latin
      // half of their messages and no rule should have to care.
      return RegExp(source, unicode: true, caseSensitive: false);
    } on FormatException catch (error) {
      throw RulePackFormatException('$where is not a valid regex: $error');
    }
  }

  // --- Small typed accessors, so every error message names its field -------

  static String _requireString(Map<String, dynamic> node, String key) {
    final Object? value = node[key];
    if (value is! String || value.isEmpty) {
      throw RulePackFormatException('missing or empty string field "$key"');
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> node, String key) {
    final Object? value = node[key];
    if (value is! int) {
      throw RulePackFormatException('missing or non-integer field "$key"');
    }
    return value;
  }

  static List<Object?> _requireList(Map<String, dynamic> node, String key) {
    final Object? value = node[key];
    if (value is! List) {
      throw RulePackFormatException('missing or non-array field "$key"');
    }
    return value;
  }

  static Map<String, dynamic> _requireMap(Map<String, dynamic> node, String k) {
    final Object? value = node[k];
    if (value is! Map<String, dynamic>) {
      throw RulePackFormatException('missing or non-object field "$k"');
    }
    return value;
  }

  static List<String> _optionalStringList(
    Map<String, dynamic> node,
    String key,
  ) {
    final Object? value = node[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw RulePackFormatException('field "$key" must be an array of strings');
    }
    return <String>[
      for (final Object? entry in value)
        if (entry is String)
          entry
        else
          throw RulePackFormatException('field "$key" must contain strings'),
    ];
  }
}
