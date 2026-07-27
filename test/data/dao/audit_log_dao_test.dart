import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/db/app_database.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

void main() {
  late AppDatabase db;
  late AuditLogDao dao;

  setUp(() {
    // Plain (non-encrypted) in-memory DB — this file tests DAO/trigger/
    // hash-chain logic, not encryption itself; see
    // test/support/plain_test_database.dart for why, and
    // test/data/db/app_database_encryption_test.dart for the dedicated
    // ADR-003 encryption test.
    db = openPlainTestDatabase();
    dao = AuditLogDao(db, auditChainKey: _testChainKey);
  });

  tearDown(() async {
    await db.close();
  });

  group('AuditLogDao.append / queryFor (ADR-010 API shape)', () {
    test('append writes a row retrievable via queryFor', () async {
      await dao.append(
        entityType: 'transaction',
        entityId: '1',
        action: 'create',
        actor: 'user',
        changedAt: DateTime.utc(2026, 1, 1),
        fieldChanges: const <AuditFieldChange>[
          AuditFieldChange(field: 'amount', from: null, to: '45.00'),
        ],
      );

      final List<AuditEntryRow> rows = await dao.queryFor('transaction', '1');
      expect(rows, hasLength(1));
      expect(rows.single.action, 'create');
      expect(rows.single.actor, 'user');
      expect(dao.decodeFieldChanges(rows.single).single.to, '45.00');
    });

    test('ANY transaction mutation writes an immutable history entry with '
        'actor, timestamp, before and after (P1 required assertion)', () async {
      final DateTime t1 = DateTime.utc(2026, 1, 1, 10, 0);
      await dao.append(
        entityType: 'transaction',
        entityId: '7',
        action: 'create',
        actor: 'user',
        changedAt: t1,
        fieldChanges: const <AuditFieldChange>[
          AuditFieldChange(field: 'categoryId', from: null, to: 'groceries'),
        ],
      );
      final DateTime t2 = DateTime.utc(2026, 1, 2, 11, 30);
      await dao.append(
        entityType: 'transaction',
        entityId: '7',
        action: 'update',
        actor: 'user',
        actorDetail: null,
        changedAt: t2,
        fieldChanges: const <AuditFieldChange>[
          AuditFieldChange(
            field: 'categoryId',
            from: 'groceries',
            to: 'dining',
          ),
        ],
      );

      final List<AuditEntryRow> history = await dao.queryFor(
        'transaction',
        '7',
      );
      expect(history, hasLength(2));
      // Drift's sqlite3 backend stores DateTimeColumn values as Unix
      // timestamps and returns them in the local timezone on read back
      // (not tagged UTC) — comparing via .toUtc() on both sides is the
      // correct way to assert "the same instant", not string/kind
      // equality. (AuditLogDao's own hash-chain canonicalisation already
      // normalises to UTC ISO-8601 before hashing — see _canonicalize —
      // so the tamper-evidence chain itself is unaffected by this.)
      expect(history[0].changedAt.toUtc(), t1);
      expect(history[1].changedAt.toUtc(), t2);
      final AuditFieldChange change = dao.decodeFieldChanges(history[1]).single;
      expect(change.from, 'groceries');
      expect(change.to, 'dining');
    });

    test('queryFor never returns entries for a different entity', () async {
      await dao.append(
        entityType: 'transaction',
        entityId: '1',
        action: 'create',
        actor: 'user',
        changedAt: DateTime.utc(2026),
        fieldChanges: const <AuditFieldChange>[],
      );
      await dao.append(
        entityType: 'transaction',
        entityId: '2',
        action: 'create',
        actor: 'user',
        changedAt: DateTime.utc(2026),
        fieldChanges: const <AuditFieldChange>[],
      );
      expect(await dao.queryFor('transaction', '1'), hasLength(1));
      expect(await dao.queryFor('transaction', '2'), hasLength(1));
    });
  });

  group(
    'Append-only enforcement (ADR-010 layer 2) — attempting to UPDATE/DELETE '
    'a history row must fail (P1 required assertion)',
    () {
      test(
        'a raw SQL UPDATE against audit_entry is aborted by the trigger',
        () async {
          await dao.append(
            entityType: 'transaction',
            entityId: '1',
            action: 'create',
            actor: 'user',
            changedAt: DateTime.utc(2026),
            fieldChanges: const <AuditFieldChange>[],
          );
          await expectLater(
            db.customStatement(
              "UPDATE audit_entry SET actor = 'tampered' WHERE id = 1",
            ),
            throwsA(anything),
          );
          final AuditEntryRow row = (await dao.queryFor(
            'transaction',
            '1',
          )).single;
          expect(row.actor, 'user'); // unchanged
        },
      );

      test(
        'a raw SQL DELETE against audit_entry is aborted by the trigger',
        () async {
          await dao.append(
            entityType: 'transaction',
            entityId: '1',
            action: 'create',
            actor: 'user',
            changedAt: DateTime.utc(2026),
            fieldChanges: const <AuditFieldChange>[],
          );
          await expectLater(
            db.customStatement('DELETE FROM audit_entry WHERE id = 1'),
            throwsA(anything),
          );
          expect(await dao.queryFor('transaction', '1'), hasLength(1));
        },
      );

      test(
        "AuditLogDao itself exposes no update/delete method — there is "
        'nothing to call even if a future edit wanted to (this test simply '
        'documents that fact; see the class source for the actual guarantee)',
        () {
          expect(dao, isA<AuditLogDao>());
        },
      );
    },
  );

  group('Hash chain (ADR-010 tamper evidence)', () {
    test('a freshly written chain verifies as intact', () async {
      for (int i = 0; i < 5; i++) {
        await dao.append(
          entityType: 'transaction',
          entityId: '$i',
          action: 'create',
          actor: 'user',
          changedAt: DateTime.utc(2026, 1, i + 1),
          fieldChanges: const <AuditFieldChange>[],
        );
      }
      expect(await dao.verifyChainIntegrity(), isTrue);
    });

    test('directly tampering with a stored field is detected', () async {
      await dao.append(
        entityType: 'transaction',
        entityId: '1',
        action: 'create',
        actor: 'user',
        changedAt: DateTime.utc(2026),
        fieldChanges: const <AuditFieldChange>[],
      );
      // The append-only triggers block UPDATE via the DAO/ORM layer, but we
      // want to simulate an out-of-band tamper (e.g. a rooted device with a
      // raw DB editor, per ADR-010's stated enforcement boundary) to prove
      // verifyChainIntegrity() would actually notice. We do this by
      // temporarily dropping the trigger, mutating the row, and checking
      // the chain now reports as broken.
      await db.customStatement('DROP TRIGGER audit_no_update;');
      await db.customStatement(
        "UPDATE audit_entry SET actor = 'tampered' WHERE id = 1",
      );
      expect(await dao.verifyChainIntegrity(), isFalse);
    });

    test('two independently-seeded chains never collide', () async {
      final AuditLogDao daoWithDifferentKey = AuditLogDao(
        db,
        auditChainKey: List<int>.generate(32, (int i) => 255 - i),
      );
      await dao.append(
        entityType: 'transaction',
        entityId: '1',
        action: 'create',
        actor: 'user',
        changedAt: DateTime.utc(2026),
        fieldChanges: const <AuditFieldChange>[],
      );
      final AuditEntryRow row = (await dao.queryFor('transaction', '1')).single;
      // Recomputing verification with a *different* chain key must not
      // consider the existing (correctly-chained) row valid, because the
      // hash was produced under a different HMAC key.
      expect(await daoWithDifferentKey.verifyChainIntegrity(), isFalse);
      expect(row.entryHash, isNotEmpty);
    });
  });
}
