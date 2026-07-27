import 'log_safe.dart';

/// A structured, redaction-safe log event — the "boring" shape ADR-015
/// deliberately restricts logging to: a category label, an optional
/// internal id (never a raw value), an optional count, and an optional
/// duration. There is no field here that can hold free text, which is the
/// point: you cannot accidentally construct a [LogEvent] that leaks an SMS
/// body or a merchant name, because there is nowhere to put one.
///
/// Example: `LogEvent(category: 'ingestion.watermark_advanced', count: 3)`
/// — genuinely useful for the parser-health panel (ADR-015) without
/// exposing a single character of message content.
class LogEvent implements LogSafe {
  /// A short, fixed, non-PII category label (e.g.
  /// `'db.migration.completed'`, `'lock.auth_failed'`). This must always be
  /// a compile-time string constant at the call site, never built from
  /// runtime user data.
  final String category;

  /// An internal identifier this event relates to (a transaction id, a rule
  /// id) — never a value that could itself be sensitive.
  final String? entityId;

  final int? count;
  final Duration? duration;

  const LogEvent({
    required this.category,
    this.entityId,
    this.count,
    this.duration,
  });

  @override
  String toLogString() {
    final StringBuffer buffer = StringBuffer(category);
    if (entityId != null) {
      buffer.write(' id=$entityId');
    }
    if (count != null) {
      buffer.write(' count=$count');
    }
    if (duration != null) {
      buffer.write(' durationMs=${duration!.inMilliseconds}');
    }
    return buffer.toString();
  }
}
