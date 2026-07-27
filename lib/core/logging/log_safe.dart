/// Marker interface for anything that is allowed to reach [SafeLogger].
///
/// ## The idea, for readers new to Dart
/// `abstract interface class` declares a *contract*, not a reusable
/// implementation: any class that says `implements LogSafe` is promising to
/// provide a [toLogString] method, and — this is the important part — a
/// plain `String` does **not** implement `LogSafe`. That means
/// `SafeLogger.info("some raw string")` is a **compile error**, not a lint
/// warning that a tired engineer can ignore at 2am. The only strings that
/// can ever reach the logger are ones a `LogSafe` implementation explicitly
/// hands over via [toLogString] — and every such implementation in this
/// codebase is reviewed against ADR-015's rule: *ids, enums, counts, and
/// durations only — never free text from an SMS, a merchant name, or an
/// amount.*
///
/// `docs/architecture.md` ADR-015: *"SafeLogger is the only permitted
/// logging entry point. It accepts a LogSafe marker type, not arbitrary
/// String."*
abstract interface class LogSafe {
  /// The exact text [SafeLogger] will record. Implementations must contain
  /// only: internal ids (transaction id, rule id — never a full PAN or SMS
  /// text), enum/category names, counts, and durations.
  String toLogString();
}
