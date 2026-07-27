import 'diagnostic_ring_buffer.dart';
import 'log_safe.dart';

/// The **only** permitted logging entry point in Massrofy (ADR-015, NFR-S4).
///
/// Every method here takes a [LogSafe], never a `String` — see
/// `log_safe.dart` for why that is a compile-time guarantee, not a
/// convention. `.github/scripts/` also greps for stray `print(`/
/// `debugPrint(` calls outside this file in later phases (ADR-015); the
/// `avoid_print` analyzer rule in `analysis_options.yaml` is this PR's part
/// of that enforcement.
///
/// This class writes into a [DiagnosticRingBuffer] — nothing here ever
/// touches the network (there is none, per ADR-001) or a third-party crash
/// reporter (there is none, per NFR-S6).
class SafeLogger {
  final DiagnosticRingBuffer _buffer;

  SafeLogger(this._buffer);

  void debug(LogSafe event) => _record(LogLevel.debug, event);

  void info(LogSafe event) => _record(LogLevel.info, event);

  void warning(LogSafe event) => _record(LogLevel.warning, event);

  /// Records an error. [stackTrace] is stored verbatim (per ADR-015, crash
  /// capture keeps "stack traces only — no captured values"), never
  /// interpolated into [event]'s own message.
  void error(LogSafe event, {StackTrace? stackTrace}) {
    _buffer.add(
      DiagnosticLogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: event.toLogString(),
        stackTrace: stackTrace?.toString(),
      ),
    );
  }

  void _record(LogLevel level, LogSafe event) {
    _buffer.add(
      DiagnosticLogEntry(
        timestamp: DateTime.now(),
        level: level,
        message: event.toLogString(),
      ),
    );
  }

  /// A read-only view of everything recorded so far — this is what the
  /// (future, P5) Settings → Diagnostics screen and "Share diagnostics"
  /// export read from; nothing here ever leaves the device on its own.
  List<DiagnosticLogEntry> get entries => _buffer.entries;
}
