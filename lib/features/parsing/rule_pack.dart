/// The in-memory form of `docs/architecture.md` §5.2 Contract A — the
/// **rule pack schema v1**.
///
/// ## The one idea this whole file exists to enforce (ADR-007)
///
/// > *"Parsing rules are declarative, versioned JSON documents. There is no
/// > per-bank Dart code. The engine is generic; banks are data."*
///
/// PRD §3.4 observed two Saudi banks producing **structurally different**
/// messages across nine transaction types, in two languages. The tempting
/// shape — a `BankAljaziraParser` class and a `D360Parser` class — fails on
/// three counts that matter for this specific product:
///
///  1. **NFR-M1** requires rules to be updatable when a bank changes its
///     template. Per-bank code makes that an APK release.
///  2. The app is **side-loaded** (R-11), so an APK release means the user
///     manually installing a file. Rules-as-data means importing a JSON file
///     instead — the difference between a fix that ships and one that doesn't.
///  3. Adding a tenth message type must not require touching the engine. It
///     is the acceptance bar on Linear KHA-19: *"adding a rule for a new
///     message type requires no change to the engine itself."*
///
/// **Safety consequence, and it is load-bearing:** a rule pack is *data*, not
/// code. There is no expression language, no `eval`, no callback. The only
/// thing an imported pack can express is "match these regexes, name these
/// capture groups". That, plus the per-rule timeout in the engine and the
/// absence of any network permission, is the entire mitigation for a hostile
/// imported pack (ADR-007 "Safety"). **Do not add a general-purpose hook to
/// this schema** without re-opening that reasoning.
///
/// ## A note for readers new to Dart
///
/// Every class here is immutable: all fields are `final` and every
/// constructor is `const`-capable. Immutability is what makes it safe to
/// share one parsed rule pack across the UI isolate and the background
/// ingestion isolate without any locking — there is nothing to mutate, so
/// there is nothing to race on.
library;

/// A whole pack: one JSON document, one version, N banks.
final class RulePack {
  /// The schema version of the *document format* (not the content). The
  /// loader refuses anything above [supportedSchemaVersion] outright rather
  /// than partially applying it — see `rule_pack_loader.dart`.
  final int schemaVersion;

  /// Stable identity of the pack, e.g. `sa-core`. Recorded on every
  /// transaction this pack produces (NFR-A1 provenance).
  final String packId;

  /// Human-meaningful version, e.g. `2026.07.28`. Also recorded per
  /// transaction, so "why did this parse change?" is answerable later.
  final String packVersion;

  final List<String> locales;
  final List<BankRule> banks;

  const RulePack({
    required this.schemaVersion,
    required this.packId,
    required this.packVersion,
    required this.locales,
    required this.banks,
  });
}

/// One bank (or card issuer): how to recognise it, and how to read it.
final class BankRule {
  /// Stable key used for entity resolution. AC-B12.3 requires that a bank
  /// named in Arabic in one message and abbreviated in another resolves to
  /// **one** bank — that is achieved by resolving on this key, never on a
  /// display string.
  final String bankId;

  final String displayNameAr;
  final String displayNameEn;
  final List<String> aliases;

  /// Regexes matched against the SMS **originating address** (the sender ID).
  /// No match against any bank in any active pack means "not a financial
  /// sender", and per NFR-P4 the message is then discarded with **nothing
  /// retained at all** — not even a counter row.
  final List<RegExp> senderPatterns;

  /// Evaluated in descending [MessageRule.priority]; first match wins.
  /// Pre-sorted by the loader so the engine never has to re-sort per message.
  final List<MessageRule> messageRules;

  const BankRule({
    required this.bankId,
    required this.displayNameAr,
    required this.displayNameEn,
    required this.aliases,
    required this.senderPatterns,
    required this.messageRules,
  });
}

/// What a rule does with a message it matches.
enum RuleIntent {
  /// Produce a transaction (subject to `requiredFields`).
  transaction,

  /// Recognise and **discard the body** — OTP, marketing, balance info.
  /// A counter row with `sanitizedBody = NULL` is still written so the
  /// parser-health panel can show "we saw 14 OTPs this month" without
  /// retaining a single character of them (NFR-P4, ADR-015).
  ignore,
}

/// Debit or credit. Refunds and incoming transfers are `credit`; a credit
/// **reduces** period spend, never increases it (US-B7).
enum RuleSign { debit, credit }

/// One message template for one bank.
final class MessageRule {
  final String ruleId;

  /// Higher wins. Ties are broken by declaration order (§5.2). This is why
  /// `ignore` rules for OTP are given a high priority in the bundled pack:
  /// an OTP message that happens to contain the word "purchase" must be
  /// recognised as an OTP *first*, or the app invents a transaction from a
  /// security code (AC-A2.1).
  final int priority;

  /// Free-form in the schema on purpose — an unrecognised value is treated
  /// as `unknown` and routed to the **review queue**, never discarded
  /// (§5.2 compatibility rules, NFR-A7). That is what lets a newer imported
  /// pack introduce a message type an older app has never heard of without
  /// losing the message.
  final String messageType;

  final RuleIntent intent;
  final RuleMatch match;

  /// The extraction regex, with named capture groups referenced by [extract].
  /// `null` for `intent: ignore` rules, which extract nothing.
  final RegExp? regex;

  final Map<String, FieldExtraction> extract;
  final RuleSign sign;

  /// Whether this message's amount counts toward "money spent".
  ///
  /// `false` for internal transfers, salary income, and **credit-card
  /// repayment**. Repayment is settlement of spend that was already counted
  /// when the card was used; counting it again is the single easiest way to
  /// make every total in the app wrong (architecture §4.2).
  final bool affectsSpend;

  /// If any of these is missing after extraction, the message goes to the
  /// **review queue** with its sanitised text — it is never dropped, and a
  /// half-populated transaction is never invented (AC-A4.1, NFR-A7).
  final List<String> requiredFields;

  /// Per-bank redaction patterns handed to `SmsSanitizer` (ADR-013) before
  /// anything is persisted.
  final List<RegExp> redact;

  const MessageRule({
    required this.ruleId,
    required this.priority,
    required this.messageType,
    required this.intent,
    required this.match,
    required this.regex,
    required this.extract,
    required this.sign,
    required this.affectsSpend,
    required this.requiredFields,
    required this.redact,
  });
}

/// The gate that decides whether a rule is even considered for a message.
///
/// Split from [MessageRule.regex] deliberately: the gate is cheap and
/// literal-ish, the extraction regex is expensive and precise. Evaluating the
/// gate first means a bank's twelve rules cost twelve substring-ish checks,
/// not twelve full backtracking regex runs, on a background isolate with a
/// ~10-second budget (ADR-006).
final class RuleMatch {
  /// At least one must match.
  final List<RegExp> anyOf;

  /// All must match.
  final List<RegExp> allOf;

  /// None may match. This is where "…but not if it's an OTP" lives.
  final List<RegExp> noneOf;

  const RuleMatch({
    this.anyOf = const <RegExp>[],
    this.allOf = const <RegExp>[],
    this.noneOf = const <RegExp>[],
  });

  /// True when [normalizedText] satisfies every clause.
  ///
  /// An empty `anyOf` is vacuously satisfied — a rule may gate purely on
  /// `allOf`/`noneOf`. An empty [RuleMatch] entirely matches everything,
  /// which is legal and is how a bank can declare a low-priority catch-all
  /// that routes anything unrecognised into the review queue.
  bool matches(String normalizedText) {
    if (anyOf.isNotEmpty &&
        !anyOf.any((RegExp r) => r.hasMatch(normalizedText))) {
      return false;
    }
    if (!allOf.every((RegExp r) => r.hasMatch(normalizedText))) {
      return false;
    }
    if (noneOf.any((RegExp r) => r.hasMatch(normalizedText))) {
      return false;
    }
    return true;
  }
}

/// How one named capture group becomes one domain field.
final class FieldExtraction {
  /// The named group in [MessageRule.regex] to read.
  final String group;

  /// Ordered list of transform names (see `field_transforms.dart`). An
  /// unknown transform name is a **load-time** error, not a silent no-op:
  /// a typo'd transform that quietly does nothing would corrupt amounts
  /// while looking like it worked.
  final List<String> transforms;

  /// For `occurredAt` only — the layout string understood by
  /// `SmsDateParser` (e.g. `dd/MM/yy HH:mm`).
  final String? format;

  /// For `occurredAt` only. `Asia/Riyadh` is the only supported value in v1;
  /// see `core/time/clock.dart` for why that is a deliberate, documented
  /// narrowing rather than an oversight.
  final String? timezone;

  /// For instrument fields only: `card` or `account` (architecture §4.2
  /// `Instrument.kind`). AC-B13.1/2 require this to come from the matched
  /// rule, **not** from a guess about digit length.
  final String? instrumentKind;

  /// For instrument fields only: how to reduce the captured identifier to a
  /// storable form. `last4` is the only policy, and it is not configurable
  /// downward — see `field_transforms.dart`.
  final String? maskPolicy;

  /// A literal value used when the group is absent from the regex. This is
  /// how a rule states "this template is always SAR" without inventing a
  /// capture group for a currency the bank never prints.
  final String? literal;

  const FieldExtraction({
    required this.group,
    this.transforms = const <String>[],
    this.format,
    this.timezone,
    this.instrumentKind,
    this.maskPolicy,
    this.literal,
  });
}
