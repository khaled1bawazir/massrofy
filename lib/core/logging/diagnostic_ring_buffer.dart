import 'dart:collection';

/// Severity of a [DiagnosticLogEntry] — deliberately a small closed enum
/// (not a free-text "level" string), so nothing here can carry PII either.
enum LogLevel { debug, info, warning, error }

/// One recorded, already-redaction-safe log line.
class DiagnosticLogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? stackTrace;

  DiagnosticLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.stackTrace,
  });
}

/// A bounded, in-memory ring buffer of the last [maxEntries] diagnostic log
/// entries — the "local, redaction-safe ring buffer the user deliberately
/// shares. No telemetry." from `docs/architecture.md` ADR-015.
///
/// **P1 scope note:** ADR-015 describes this buffer as ultimately living
/// *inside the encrypted database* (so it survives app restarts and is
/// covered by erase-all). This P1 foundation slice implements the
/// in-memory ring-buffer mechanics and its size-bounding behaviour, which is
/// the part every later phase depends on; wiring it to a Drift table is
/// deferred to the phase that actually builds the Settings → Diagnostics
/// screen (P5), so this class is written to be trivially backed by
/// persistent storage later (e.g. `DiagnosticRingBuffer.hydrate(entries)`)
/// without changing its public API.
///
/// For readers new to Dart: [Queue] here comes from `dart:collection` and
/// gives us efficient `addLast`/`removeFirst` — exactly what a ring buffer
/// needs — without hand-rolling a circular array.
class DiagnosticRingBuffer {
  final int maxEntries;
  final Queue<DiagnosticLogEntry> _entries = Queue<DiagnosticLogEntry>();

  DiagnosticRingBuffer({this.maxEntries = 2000});

  /// Appends [entry], evicting the oldest entry once [maxEntries] is
  /// exceeded — the buffer never grows without bound, by construction.
  void add(DiagnosticLogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
  }

  /// A read-only snapshot of the buffer, oldest first.
  List<DiagnosticLogEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  void clear() => _entries.clear();
}
