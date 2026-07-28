import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables/instrument_table.dart';
import 'audit_log_dao.dart';

part 'instrument_dao.g.dart';

/// Reads and writes the `instrument` table — US-B2/B3/B13/B14/B15.
///
/// Like [BankDao], creation is only reachable through the idempotent
/// [ensure], keyed on `refKey`. See `instrument_table.dart` for why `refKey`
/// (and not the friendly name, and not the masked identifier as displayed) is
/// the match key: it is what makes AC-B3.2 — "a later message carrying that
/// instrument's raw identifier attaches to the RENAMED instrument, not a new
/// one" — structurally true rather than carefully maintained.
@DriftAccessor(tables: [Instruments])
class InstrumentDao extends DatabaseAccessor<AppDatabase>
    with _$InstrumentDaoMixin {
  final AuditLogDao auditLogDao;

  InstrumentDao(super.attachedDatabase, this.auditLogDao);

  /// Resolves the instrument with [refKey] under [bankId], creating it on
  /// first mention (AC-B15.1).
  ///
  /// On an existing row this **enriches but never overwrites**: a later
  /// message that names the card network fills in a network we did not have,
  /// but a message that names a *different* network does not silently
  /// rewrite the old one — the first observation stands and the difference is
  /// left for the user to resolve. Overwriting would make the record's
  /// history depend on message arrival order, which is not a property anyone
  /// can reason about later.
  Future<int> ensure({
    required int bankId,
    required String kind,
    required String maskedIdentifier,
    required String refKey,
    String? network,
    String? cardType,
    String? currencyCode,
    int? firstSeenMessageId,
    String actor = 'parser',
    String? actorDetail,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final InstrumentRow? existing = await byRefKey(refKey);
      if (existing != null) {
        await _enrich(
          existing: existing,
          network: network,
          cardType: cardType,
          currencyCode: currencyCode,
          timestamp: timestamp,
        );
        return existing.id;
      }

      final int id = await into(instruments).insert(
        InstrumentsCompanion.insert(
          bankId: bankId,
          kind: kind,
          maskedIdentifier: maskedIdentifier,
          refKey: refKey,
          network: Value<String?>(network),
          cardType: Value<String?>(cardType),
          currencyCode: Value<String?>(currencyCode),
          firstSeenMessageId: Value<int?>(firstSeenMessageId),
          createdAt: Value<DateTime>(timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'instrument',
        entityId: id.toString(),
        action: 'create',
        actor: actor,
        actorDetail: actorDetail,
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(field: 'kind', from: null, to: kind),
          // The masked identifier is the strongest thing about this row that
          // could be called sensitive, and it is four digits the bank itself
          // prints in a plaintext SMS. NFR-S2 is satisfied by there being no
          // fuller form anywhere in the app to leak.
          AuditFieldChange(
            field: 'maskedIdentifier',
            from: null,
            to: maskedIdentifier,
          ),
        ],
      );
      return id;
    });
  }

  /// Fills in fields the first message did not state. Writes an audit entry
  /// only when something actually changed, so the history stays readable.
  Future<void> _enrich({
    required InstrumentRow existing,
    required String? network,
    required String? cardType,
    required String? currencyCode,
    required DateTime timestamp,
  }) async {
    final List<AuditFieldChange> changes = <AuditFieldChange>[
      if (existing.network == null && network != null)
        AuditFieldChange(field: 'network', from: null, to: network),
      if (existing.cardType == null && cardType != null)
        AuditFieldChange(field: 'cardType', from: null, to: cardType),
      if (existing.currencyCode == null && currencyCode != null)
        AuditFieldChange(field: 'currencyCode', from: null, to: currencyCode),
    ];
    if (changes.isEmpty) {
      return;
    }

    await (update(
      instruments,
    )..where((Instruments t) => t.id.equals(existing.id))).write(
      InstrumentsCompanion(
        network: Value<String?>(existing.network ?? network),
        cardType: Value<String?>(existing.cardType ?? cardType),
        currencyCode: Value<String?>(existing.currencyCode ?? currencyCode),
        updatedAt: Value<DateTime>(timestamp),
      ),
    );

    await auditLogDao.append(
      entityType: 'instrument',
      entityId: existing.id.toString(),
      action: 'update',
      actor: 'parser',
      actorDetail: 'observed_from_message',
      changedAt: timestamp,
      fieldChanges: changes,
    );
  }

  /// US-B3's rename. Only [friendlyName] changes — `refKey` is untouched,
  /// which is why AC-B3.2 holds (the next SMS for this card still matches).
  ///
  /// [newName] is trimmed; an empty result clears the friendly name and the
  /// instrument falls back to being labelled by its masked identifier
  /// (AC-B15.2). That is a deliberate escape hatch: a user who regrets a name
  /// can get back to the bank's own labelling without deleting anything.
  Future<void> rename({
    required int id,
    required String? newName,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    final String? cleaned = (newName ?? '').trim().isEmpty
        ? null
        : newName!.trim();

    return transaction<void>(() async {
      final InstrumentRow existing = await byId(id);
      if (existing.friendlyName == cleaned) {
        return;
      }

      await (update(
        instruments,
      )..where((Instruments t) => t.id.equals(id))).write(
        InstrumentsCompanion(
          friendlyName: Value<String?>(cleaned),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'instrument',
        entityId: id.toString(),
        action: 'update',
        actor: 'user',
        actorDetail: 'rename',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'friendlyName',
            from: existing.friendlyName,
            to: cleaned,
          ),
        ],
      );
    });
  }

  /// **AC-B14.1** — records that [cardId] settles from [accountId].
  ///
  /// Refuses to change an existing link automatically: `linkSource == 'user'`
  /// always wins over an SMS observation, and an SMS observation never
  /// replaces an earlier SMS observation. AC-B14.3's "shown as unlinked
  /// rather than guessed" is the *absence* case of the same principle — the
  /// app states what it saw and nothing more.
  Future<bool> linkSettlementAccount({
    required int cardId,
    required int accountId,
    required String linkSource,
    DateTime? observedAt,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<bool>(() async {
      final InstrumentRow card = await byId(cardId);
      if (card.settlementAccountId == accountId) {
        return false;
      }
      if (card.settlementAccountId != null && linkSource != 'user') {
        // A contradicting observation. Keep the first; do not thrash.
        return false;
      }

      await (update(
        instruments,
      )..where((Instruments t) => t.id.equals(cardId))).write(
        InstrumentsCompanion(
          settlementAccountId: Value<int?>(accountId),
          linkSource: Value<String?>(linkSource),
          linkObservedAt: Value<DateTime?>(observedAt ?? timestamp),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'instrument',
        entityId: cardId.toString(),
        action: 'update',
        actor: linkSource == 'user' ? 'user' : 'parser',
        actorDetail: 'settlement_link',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'settlementAccountId',
            from: card.settlementAccountId?.toString(),
            to: accountId.toString(),
          ),
        ],
      );
      return true;
    });
  }

  Future<InstrumentRow?> byRefKey(String refKey) {
    return (select(
      instruments,
    )..where((Instruments t) => t.refKey.equals(refKey))).getSingleOrNull();
  }

  Future<InstrumentRow> byId(int id) => (select(
    instruments,
  )..where((Instruments t) => t.id.equals(id))).getSingle();

  Future<InstrumentRow?> byIdOrNull(int id) => (select(
    instruments,
  )..where((Instruments t) => t.id.equals(id))).getSingleOrNull();

  /// Every instrument at one bank — the query behind AC-B2.1's "drilling into
  /// a bank shows only its own accounts/cards".
  Future<List<InstrumentRow>> forBank(int bankId) =>
      (select(instruments)
            ..where((Instruments t) => t.bankId.equals(bankId))
            ..orderBy(<OrderClauseGenerator<Instruments>>[
              (Instruments t) => OrderingTerm.asc(t.kind),
              (Instruments t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<List<InstrumentRow>> all() =>
      (select(instruments)..orderBy(<OrderClauseGenerator<Instruments>>[
            (Instruments t) => OrderingTerm.asc(t.id),
          ]))
          .get();

  Stream<List<InstrumentRow>> watchAll() =>
      (select(instruments)..orderBy(<OrderClauseGenerator<Instruments>>[
            (Instruments t) => OrderingTerm.asc(t.id),
          ]))
          .watch();
}
