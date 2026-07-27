import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';

void main() {
  late AppDatabase db;
  late RawMessageDao dao;

  setUp(() {
    // Plain (non-encrypted) in-memory DB — see
    // test/support/plain_test_database.dart for why.
    db = openPlainTestDatabase();
    dao = RawMessageDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'insert() only accepts a SanitizedSmsText, never a raw String',
    () async {
      final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
        'Purchase of 45.00 SAR at Panda Foods',
      );
      final int id = await dao.insert(
        sender: 'BAJ',
        receivedAt: DateTime.utc(2026, 1, 1),
        sanitizedText: sanitized,
        contentHmac: 'hmac-1',
        classification: 'financial_parsed',
      );

      final RawMessageRow? row = await dao.findByContentHmac('hmac-1');
      expect(row, isNotNull);
      expect(row!.id, id);
      expect(row.sanitizedBody, sanitized.value);
      expect(row.panRedacted, isFalse);
    },
  );

  test('a message containing a PAN is stored already redacted — the PAN never '
      'reaches the row at all', () async {
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      'Purchase on card 4111111111111111',
    );
    await dao.insert(
      sender: 'BAJ',
      receivedAt: DateTime.utc(2026, 1, 1),
      sanitizedText: sanitized,
      contentHmac: 'hmac-pan',
      classification: 'financial_parsed',
    );

    final RawMessageRow? row = await dao.findByContentHmac('hmac-pan');
    expect(row!.sanitizedBody, isNot(contains('4111111111111111')));
    expect(row.panRedacted, isTrue);
  });

  test('insertIgnoredNoContent stores NO body text (NFR-P4 — ignored messages '
      'keep only bank/classification/timestamp)', () async {
    await dao.insertIgnoredNoContent(
      sender: 'BAJ',
      receivedAt: DateTime.utc(2026, 1, 1),
      contentHmac: 'hmac-otp',
      classification: 'ignored_otp',
    );

    final RawMessageRow? row = await dao.findByContentHmac('hmac-otp');
    expect(row!.sanitizedBody, isNull);
    expect(row.classification, 'ignored_otp');
  });

  test(
    'contentHmac is unique — a duplicate insert is rejected (ADR-017 D1)',
    () async {
      final SanitizedSmsText sanitized = SmsSanitizer.sanitize('hello');
      await dao.insert(
        sender: 'BAJ',
        receivedAt: DateTime.utc(2026),
        sanitizedText: sanitized,
        contentHmac: 'dup',
        classification: 'financial_parsed',
      );
      await expectLater(
        dao.insert(
          sender: 'BAJ',
          receivedAt: DateTime.utc(2026),
          sanitizedText: sanitized,
          contentHmac: 'dup',
          classification: 'financial_parsed',
        ),
        throwsA(anything),
      );
    },
  );
}
