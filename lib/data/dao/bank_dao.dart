import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables/bank_table.dart';
import 'audit_log_dao.dart';

part 'bank_dao.g.dart';

/// Reads and writes the `bank` table (US-B12, US-B15, AC-B12.1/B12.3).
///
/// ## Why there is no plain `insert`
///
/// The only creation method here is [ensure], an idempotent
/// resolve-or-create keyed on `canonicalKey`. That shape is deliberate:
/// ingestion calls it on **every** message from a known bank, dozens of times
/// a day, and any API that could create a second row for the same bank would
/// eventually be called twice — which is precisely the AC-B12.3 failure.
/// Making "create" unreachable except through "resolve first" removes the
/// possibility rather than documenting against it.
@DriftAccessor(tables: [Banks])
class BankDao extends DatabaseAccessor<AppDatabase> with _$BankDaoMixin {
  final AuditLogDao auditLogDao;

  BankDao(super.attachedDatabase, this.auditLogDao);

  /// Resolves the bank with [canonicalKey], creating it on first mention
  /// (US-B15, AC-B15.1 — "no setup step required from the user").
  ///
  /// Returns the row id either way. Never creates a duplicate: the read and
  /// the write happen inside one Drift `transaction()` (which nests as a
  /// savepoint when a caller already opened one), and `canonicalKey` is
  /// `UNIQUE` in the schema as the second line of defence.
  ///
  /// [actor] follows ADR-010's vocabulary — `parser` when a rule recognised
  /// the sender, `user` when the person added the bank by hand.
  Future<int> ensure({
    required String canonicalKey,
    required String displayNameAr,
    required String displayNameEn,
    List<String> aliases = const <String>[],
    String source = 'rule_pack',
    int? firstSeenMessageId,
    String actor = 'parser',
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final BankRow? existing = await byCanonicalKey(canonicalKey);
      if (existing != null) {
        return existing.id;
      }

      final int id = await into(banks).insert(
        BanksCompanion.insert(
          canonicalKey: canonicalKey,
          displayNameAr: displayNameAr,
          displayNameEn: displayNameEn,
          aliasesJson: Value<String>(jsonEncode(aliases)),
          source: Value<String>(source),
          firstSeenMessageId: Value<int?>(firstSeenMessageId),
          createdAt: Value<DateTime>(timestamp),
        ),
      );

      // NFR-A2: auto-creation is a mutation the user never asked for, so it
      // is exactly the kind of thing the change history exists to explain
      // ("where did this bank come from?"). The display names are not
      // sensitive — a bank's own public name is not PII (NFR-S4 is about
      // amounts, merchants and identifiers).
      await auditLogDao.append(
        entityType: 'bank',
        entityId: id.toString(),
        action: 'create',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(field: 'canonicalKey', from: null, to: canonicalKey),
          AuditFieldChange(field: 'source', from: null, to: source),
        ],
      );
      return id;
    });
  }

  Future<BankRow?> byCanonicalKey(String canonicalKey) {
    return (select(banks)
          ..where((Banks t) => t.canonicalKey.equals(canonicalKey)))
        .getSingleOrNull();
  }

  Future<BankRow?> byId(int id) =>
      (select(banks)..where((Banks t) => t.id.equals(id))).getSingleOrNull();

  Future<List<BankRow>> all() =>
      (select(banks)..orderBy(<OrderClauseGenerator<Banks>>[
            (Banks t) => OrderingTerm.asc(t.id),
          ]))
          .get();

  /// The banks screen (S-21) as a stream, so a newly auto-created bank
  /// appears without a manual refresh (architecture §7.5).
  Stream<List<BankRow>> watchAll() =>
      (select(banks)..orderBy(<OrderClauseGenerator<Banks>>[
            (Banks t) => OrderingTerm.asc(t.id),
          ]))
          .watch();

  /// Decodes [BankRow.aliasesJson]. Kept here so no caller has to know the
  /// column is JSON-encoded.
  List<String> decodeAliases(BankRow row) =>
      (jsonDecode(row.aliasesJson) as List<dynamic>).cast<String>();
}
