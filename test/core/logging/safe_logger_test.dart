import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/log_event.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/money/money.dart';

void main() {
  group('SafeLogger — the only permitted logging entry point (ADR-015)', () {
    test('records a LogEvent into the ring buffer', () {
      final DiagnosticRingBuffer buffer = DiagnosticRingBuffer();
      final SafeLogger logger = SafeLogger(buffer);

      logger.info(
        const LogEvent(category: 'ingestion.sms_processed', count: 3),
      );

      expect(logger.entries, hasLength(1));
      expect(
        logger.entries.single.message,
        contains('ingestion.sms_processed'),
      );
      expect(logger.entries.single.message, contains('count=3'));
      expect(logger.entries.single.level, LogLevel.info);
    });

    test('error() stores the stack trace separately from the message', () {
      final DiagnosticRingBuffer buffer = DiagnosticRingBuffer();
      final SafeLogger logger = SafeLogger(buffer);
      final StackTrace trace = StackTrace.current;

      logger.error(
        const LogEvent(category: 'db.migration_failed'),
        stackTrace: trace,
      );

      expect(logger.entries.single.stackTrace, trace.toString());
      expect(logger.entries.single.level, LogLevel.error);
    });

    test(
      'LogEvent.toLogString() only ever contains ids/enums/counts/durations, '
      'never free text (this is what the LogSafe contract promises)',
      () {
        const LogEvent event = LogEvent(
          category: 'lock.auth_failed',
          entityId: 'txn-42',
          count: 2,
          duration: Duration(milliseconds: 150),
        );
        final String message = event.toLogString();
        expect(message, 'lock.auth_failed id=txn-42 count=2 durationMs=150');
      },
    );
  });

  group(
    'DiagnosticRingBuffer — bounded size (ADR-015: "last 2,000 events")',
    () {
      test('evicts the oldest entry once maxEntries is exceeded', () {
        final DiagnosticRingBuffer buffer = DiagnosticRingBuffer(maxEntries: 3);
        for (int i = 0; i < 5; i++) {
          buffer.add(
            DiagnosticLogEntry(
              timestamp: DateTime(2026, 1, 1),
              level: LogLevel.debug,
              message: 'event-$i',
            ),
          );
        }
        expect(buffer.length, 3);
        expect(
          buffer.entries.map((DiagnosticLogEntry e) => e.message),
          <String>['event-2', 'event-3', 'event-4'],
        );
      });
    },
  );

  group(
    'Money.toString() cannot leak a value even through SafeLogger-adjacent '
    'code that forgets to use SafeLogger properly (defence in depth, NFR-S4)',
    () {
      test('interpolating a Money directly never reveals the amount', () {
        final Money m = Money.parse('9999.99', currency: 'SAR');
        final String accidentalInterpolation = 'Total: $m';
        expect(accidentalInterpolation, isNot(contains('9999')));
        expect(accidentalInterpolation, 'Total: Money(<redacted>, SAR)');
      });
    },
  );
}
