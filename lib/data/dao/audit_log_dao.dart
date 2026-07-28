import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables/audit_entry_table.dart';

part 'audit_log_dao.g.dart';

/// One `{field, from, to}` entry in an audit row's `fieldChanges` list —
/// matches the shape `docs/architecture.md` ADR-010 specifies verbatim.
class AuditFieldChange {
  final String field;
  final String? from;
  final String? to;

  const AuditFieldChange({required this.field, this.from, this.to});

  Map<String, Object?> toJson() => <String, Object?>{
    'field': field,
    'from': from,
    'to': to,
  };

  factory AuditFieldChange.fromJson(Map<String, Object?> json) =>
      AuditFieldChange(
        field: json['field'] as String,
        from: json['from'] as String?,
        to: json['to'] as String?,
      );
}

/// ADR-010's audit trail DAO.
///
/// This class's public surface is **exactly** [append] and [queryFor] (plus
/// [verifyChainIntegrity], which only reads). There is no `update`/`delete`
/// method anywhere below — on purpose, per ADR-010: *"AuditLogDao exposes
/// exactly two operations: append(entry) and queryFor(entityType,
/// entityId). There is no update or delete method to call."* Even if a
/// future change to this file tried to add one, the `BEFORE UPDATE`/
/// `BEFORE DELETE` triggers `AppDatabase` installs on the underlying table
/// would abort it at the SQL layer regardless (see `app_database.dart`).
///
/// **Enforcement boundary, stated honestly (ADR-010):** this is
/// tamper-evident, not tamper-proof, against the device's own owner — see
/// the ADR for why a stronger claim isn't attempted. [verifyChainIntegrity]
/// is precisely the "Settings → Verify history integrity" action the ADR
/// describes.
@DriftAccessor(tables: [AuditEntries])
class AuditLogDao extends DatabaseAccessor<AppDatabase>
    with _$AuditLogDaoMixin {
  /// The HMAC-SHA256 key for the tamper-evidence hash chain — ADR-010's
  /// `auditChainKey`, a separate Keystore-held key in production (see
  /// `lib/core/crypto/key_manager.dart`). Tests supply a fixed key of their
  /// own since they don't exercise the real Android Keystore.
  final List<int> auditChainKey;

  /// The fixed marker used as `prevHash` for the very first entry ever
  /// written — there is no "previous" entry to chain to yet.
  static const String genesisHash = 'GENESIS';

  AuditLogDao(super.attachedDatabase, {required this.auditChainKey});

  /// Appends one immutable audit entry, chained to the previous entry's
  /// hash. There is deliberately no parameter for supplying an id or a
  /// hash — both are always freshly computed here, never trusted from a
  /// caller.
  Future<int> append({
    required String entityType,
    required String entityId,
    required String action,
    required String actor,
    String? actorDetail,
    required DateTime changedAt,
    required List<AuditFieldChange> fieldChanges,
  }) async {
    // Read-latest-hash-then-insert is two separate statements, and without
    // wrapping them together, either of two things could break the hash
    // chain: (a) a crash/kill between the read and the write leaves nothing
    // committed, which is actually fine on its own — but (b) two concurrent
    // `append()` calls could both read the *same* `prevHash` before either
    // insert commits, then both insert rows chained to that same
    // now-stale predecessor, silently forking the chain instead of forming
    // a single linear one. Wrapping both steps in Drift's `transaction()`
    // closes both gaps: SQLite serialises concurrent writers against the
    // same connection, and a crash mid-way rolls the whole unit back
    // instead of leaving a half-written entry. Drift transactions nest via
    // savepoints automatically, so this is equally correct whether `append`
    // is called on its own or (as `TransactionDao` already does) from
    // inside a caller's own `transaction()` block alongside the ledger row
    // it accompanies.
    // ## Why the timestamp is truncated to whole seconds before anything else
    //
    // **This is a correctness fix, not tidiness (found by P3a's tests).**
    // Drift's sqlite3 backend stores a `DateTimeColumn` as a Unix timestamp
    // in **whole seconds**, so any sub-second component is discarded on
    // write. The hash chain, however, was computed over the *un*truncated
    // value — which meant every entry written with a real `DateTime.now()`
    // (i.e. every entry the running app has ever written, all of which carry
    // milliseconds) hashed over a timestamp that could never be read back.
    // [verifyChainIntegrity] then recomputed from the stored, truncated value
    // and got a different hash.
    //
    // The user-visible effect was as bad as it sounds: ADR-010's "Settings →
    // Verify history integrity" action would report **tampering** on a
    // perfectly intact history. The existing tests never caught it because
    // they all pass whole-second literals such as `DateTime.utc(2026, 1, 1)`.
    //
    // Truncating here — once, before both the hash and the insert — makes the
    // hashed value and the stored value the same value by construction.
    final DateTime storedChangedAt = _toWholeSecondsUtc(changedAt);

    return transaction<int>(() async {
      final String prevHash = await _latestHash();
      final String canonicalPayload = _canonicalize(
        entityType: entityType,
        entityId: entityId,
        action: action,
        actor: actor,
        actorDetail: actorDetail,
        changedAt: storedChangedAt,
        fieldChanges: fieldChanges,
      );
      final String entryHash = _computeHash(prevHash, canonicalPayload);

      return into(auditEntries).insert(
        AuditEntriesCompanion.insert(
          entityType: entityType,
          entityId: entityId,
          action: action,
          actor: actor,
          actorDetail: Value<String?>(actorDetail),
          changedAt: storedChangedAt,
          fieldChangesJson: jsonEncode(
            fieldChanges.map((AuditFieldChange c) => c.toJson()).toList(),
          ),
          prevHash: prevHash,
          entryHash: entryHash,
        ),
      );
    });
  }

  /// All audit entries for one entity, oldest first — matches ADR-010's
  /// `queryFor(entityType, entityId)`.
  Future<List<AuditEntryRow>> queryFor(String entityType, String entityId) {
    return (select(auditEntries)
          ..where(
            (AuditEntries t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId),
          )
          ..orderBy([(AuditEntries t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Decodes the `fieldChangesJson` column for one row back into
  /// [AuditFieldChange]s — a small convenience so callers never touch the
  /// JSON encoding directly.
  List<AuditFieldChange> decodeFieldChanges(AuditEntryRow row) {
    final List<dynamic> decoded =
        jsonDecode(row.fieldChangesJson) as List<dynamic>;
    return decoded
        .cast<Map<String, Object?>>()
        .map(AuditFieldChange.fromJson)
        .toList();
  }

  /// Walks the whole chain and returns `true` iff every entry's
  /// `entryHash` still matches a fresh recomputation from its `prevHash`
  /// and its own canonical payload. This is what detects a row tampered
  /// with outside the app (e.g. via a raw database editor on a rooted
  /// device) — see the enforcement-boundary note on this class.
  Future<bool> verifyChainIntegrity() async {
    final List<AuditEntryRow> rows = await (select(
      auditEntries,
    )..orderBy([(AuditEntries t) => OrderingTerm.asc(t.id)])).get();

    String expectedPrevHash = genesisHash;
    for (final AuditEntryRow row in rows) {
      if (row.prevHash != expectedPrevHash) {
        return false;
      }
      final String recomputed = _computeHash(
        row.prevHash,
        _canonicalizeRow(row),
      );
      if (recomputed != row.entryHash) {
        return false;
      }
      expectedPrevHash = row.entryHash;
    }
    return true;
  }

  /// Drops the sub-second component the storage layer cannot keep.
  ///
  /// Truncation, never rounding: rounding up would place an entry a fraction
  /// of a second in the future relative to the change it records, and the
  /// audit trail's ordering is the one thing it must not get wrong.
  static DateTime _toWholeSecondsUtc(DateTime value) {
    final DateTime utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
  }

  Future<String> _latestHash() async {
    final AuditEntryRow? latest =
        await (select(auditEntries)
              ..orderBy([(AuditEntries t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull();
    return latest?.entryHash ?? genesisHash;
  }

  String _computeHash(String prevHash, String canonicalPayload) {
    final crypto.Hmac hmac = crypto.Hmac(crypto.sha256, auditChainKey);
    final crypto.Digest digest = hmac.convert(
      utf8.encode('$prevHash|$canonicalPayload'),
    );
    return digest.toString();
  }

  String _canonicalize({
    required String entityType,
    required String entityId,
    required String action,
    required String actor,
    String? actorDetail,
    required DateTime changedAt,
    required List<AuditFieldChange> fieldChanges,
  }) {
    // A deterministic JSON encoding: keys are written in a fixed order
    // below (Dart's Map literal preserves insertion order, and
    // `jsonEncode` walks the map in that order), and the timestamp is
    // normalised to UTC ISO-8601 so the same logical entry always
    // canonicalises identically regardless of the device's local timezone.
    return jsonEncode(<String, Object?>{
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'actor': actor,
      'actorDetail': actorDetail,
      'changedAt': changedAt.toUtc().toIso8601String(),
      'fieldChanges': fieldChanges
          .map((AuditFieldChange c) => c.toJson())
          .toList(),
    });
  }

  String _canonicalizeRow(AuditEntryRow row) {
    return _canonicalize(
      entityType: row.entityType,
      entityId: row.entityId,
      action: row.action,
      actor: row.actor,
      actorDetail: row.actorDetail,
      changedAt: row.changedAt,
      fieldChanges: decodeFieldChanges(row),
    );
  }
}
