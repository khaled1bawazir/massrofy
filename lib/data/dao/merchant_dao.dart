import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/tables/merchant_table.dart';
import 'audit_log_dao.dart';

part 'merchant_dao.g.dart';

/// The merchant identity store and the learned-rule store — KHA-31, ADR-008.
///
/// ## The one rule this DAO's shape enforces
///
/// ADR-008: *"Rule creation is user-driven only. An automatic match never
/// creates or mutates a rule. Only explicit user actions do (AC-D3.2)."*
///
/// So the only method that can change what a rule **says** is [upsertRule],
/// which requires an `actor` and writes an audit entry naming it. The
/// automatic path calls exactly one write method here — [recordRuleApplied],
/// which touches `applied_count` and `last_applied_at` and nothing else. A
/// counter is not a claim about where the user's money belongs, so incrementing
/// it is not the mutation AC-D3.2 forbids; changing `category_id` is, and there
/// is no method that does it without an actor.
///
/// ## Reads for the matcher are deliberately dumb
///
/// [allMerchants], [allAliases] and [enabledRules] return raw rows. The
/// matching itself lives in `features/categorization/merchant_matcher.dart`
/// and is a **pure function** over those lists — no database, no clock. That
/// is what lets ADR-008's four tiers be tested as a corpus table, which is
/// what KHA-31's done check asks for, and it is why the assembly into
/// candidates happens in the feature layer rather than in a clever SQL join
/// here.
@DriftAccessor(tables: [Merchants, MerchantAliases, MerchantRules])
class MerchantDao extends DatabaseAccessor<AppDatabase>
    with _$MerchantDaoMixin {
  final AuditLogDao auditLogDao;

  MerchantDao(super.attachedDatabase, this.auditLogDao);

  /// Resolves the merchant with [merchantKey], creating it on first sight.
  ///
  /// Modelled on `BankDao.ensure`: the read and the write happen inside one
  /// drift `transaction()` (which nests as a savepoint if the caller already
  /// opened one), and `merchant_key` is `UNIQUE` as the second line of
  /// defence, so two ingestion paths racing cannot produce two rows for one
  /// shop.
  ///
  /// ## Why this does *not* write an audit entry, unlike `BankDao.ensure`
  ///
  /// The difference is what the row means. A bank appearing is a fact about
  /// the user's financial life with its own screen and its own accounts, and
  /// "where did this bank come from?" is a question the change history should
  /// answer. A merchant row is an **index over data the ledger already has**:
  /// the transaction it came from carries `merchant_raw_text`, and every
  /// change to *that* is already audited (`TransactionField.merchantRawText`).
  /// Appending a second record of the same fact would put merchant names —
  /// which NFR-S4 names explicitly as sensitive, unlike a bank's public name —
  /// into a second table for no answer the trail cannot already give.
  ///
  /// What *is* audited here is every user decision: [linkAlias] and
  /// [upsertRule].
  Future<int> ensureMerchant({
    required String merchantKey,
    required String canonicalName,
    int? firstSeenMessageId,
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final MerchantRow? existing = await byKey(merchantKey);
      if (existing != null) {
        return existing.id;
      }
      return into(merchants).insert(
        MerchantsCompanion.insert(
          canonicalName: canonicalName,
          merchantKey: merchantKey,
          firstSeenMessageId: Value<int?>(firstSeenMessageId),
          createdAt: Value<DateTime>(timestamp),
        ),
      );
    });
  }

  Future<MerchantRow?> byKey(String merchantKey) =>
      (select(merchants)
            ..where((Merchants t) => t.merchantKey.equals(merchantKey)))
          .getSingleOrNull();

  Future<MerchantRow?> byId(int id) => (select(
    merchants,
  )..where((Merchants t) => t.id.equals(id))).getSingleOrNull();

  Future<List<MerchantRow>> allMerchants() => select(merchants).get();

  Future<List<MerchantAliasRow>> allAliases() => select(merchantAliases).get();

  /// Rules the matcher is allowed to fire. Disabled rules are excluded here
  /// rather than filtered by each caller, so "disabled" cannot mean one thing
  /// in the matcher and another in the rules screen.
  Future<List<MerchantRuleRow>> enabledRules() => (select(
    merchantRules,
  )..where((MerchantRules t) => t.isEnabled.equals(true))).get();

  /// Every rule, enabled or not — AC-D1.1's learned-rules list.
  Future<List<MerchantRuleRow>> allRules() =>
      (select(merchantRules)..orderBy(<OrderClauseGenerator<MerchantRules>>[
            (MerchantRules t) => OrderingTerm.desc(t.updatedAt),
          ]))
          .get();

  /// The same list as a stream, for the P4b rules screen.
  Stream<List<MerchantRuleRow>> watchAllRules() =>
      (select(merchantRules)..orderBy(<OrderClauseGenerator<MerchantRules>>[
            (MerchantRules t) => OrderingTerm.desc(t.updatedAt),
          ]))
          .watch();

  Future<MerchantRuleRow?> ruleForMerchant(int merchantId) =>
      (select(merchantRules)
            ..where((MerchantRules t) => t.merchantId.equals(merchantId)))
          .getSingleOrNull();

  Future<MerchantRuleRow?> ruleById(int id) => (select(
    merchantRules,
  )..where((MerchantRules t) => t.id.equals(id))).getSingleOrNull();

  /// Links an alternative spelling to a merchant — ADR-008's cross-script
  /// answer (R-5).
  ///
  /// [source] is `user` for every caller that exists today; see the
  /// `MerchantAliases` class comment for why nothing writes `observed`
  /// automatically.
  ///
  /// Returns null when [aliasKey] already resolves somewhere — an alias key is
  /// `UNIQUE` precisely so one spelling cannot name two merchants, and
  /// silently repointing it would move every future transaction of one shop
  /// onto another.
  Future<int?> linkAlias({
    required int merchantId,
    required String aliasKey,
    required String script,
    String source = 'user',
    String actor = 'user',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int?>(() async {
      final MerchantAliasRow? clash =
          await (select(merchantAliases)
                ..where((MerchantAliases t) => t.aliasKey.equals(aliasKey)))
              .getSingleOrNull();
      if (clash != null) {
        return null;
      }

      final int id = await into(merchantAliases).insert(
        MerchantAliasesCompanion.insert(
          merchantId: merchantId,
          aliasKey: aliasKey,
          script: script,
          source: source,
          createdAt: Value<DateTime>(timestamp),
        ),
      );

      // Audited: this is a person asserting that two different strings are the
      // same shop. It is exactly the kind of claim they may later want to
      // understand or undo (NFR-A2), and unlike merchant auto-creation it is
      // not derivable from anything else.
      await auditLogDao.append(
        entityType: 'merchant_alias',
        entityId: id.toString(),
        action: 'create',
        actor: actor,
        actorDetail: 'merchant:$merchantId',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'merchantId',
            from: null,
            to: merchantId.toString(),
          ),
          AuditFieldChange(field: 'source', from: null, to: source),
        ],
      );
      return id;
    });
  }

  /// Creates or updates the rule for [merchantId] — **AC-D1.1 and AC-D1.2**.
  ///
  /// > *Categorizing a transaction from merchant M as category C creates rule
  /// > M→C … re-categorizing another transaction from M to C2 **updates** the
  /// > rule to M→C2.*
  ///
  /// One rule per merchant (the column is `UNIQUE`), so the second correction
  /// genuinely replaces the first rather than adding a competing one. The
  /// previous category is preserved in the audit trail, which is where the
  /// history of a rule belongs — the store holds what is true now.
  ///
  /// [actor] has no default. That is the ADR-008 constraint made mechanical:
  /// a caller must state who is changing the rule, and the automatic path has
  /// no user to name.
  Future<int> upsertRule({
    required int merchantId,
    required String categoryId,
    required String source,
    required String actor,
    String matchType = 'exact_key',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<int>(() async {
      final MerchantRuleRow? existing = await ruleForMerchant(merchantId);

      if (existing == null) {
        final int id = await into(merchantRules).insert(
          MerchantRulesCompanion.insert(
            merchantId: merchantId,
            categoryId: categoryId,
            source: source,
            matchType: Value<String>(matchType),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
          ),
        );
        await auditLogDao.append(
          entityType: 'merchant_rule',
          entityId: id.toString(),
          action: 'create',
          actor: actor,
          actorDetail: 'merchant:$merchantId',
          changedAt: timestamp,
          fieldChanges: <AuditFieldChange>[
            AuditFieldChange(field: 'categoryId', from: null, to: categoryId),
            AuditFieldChange(field: 'source', from: null, to: source),
          ],
        );
        return id;
      }

      // **AC-D3.1 — a user rule is never demoted to a seed rule.** A seed
      // source arriving over a rule the user taught would silently discard the
      // fact that a person decided this, and with it the tie-break that makes
      // "user correction always wins" true. The category still updates; only
      // the provenance is kept at its strongest.
      final String mergedSource = existing.source == 'user' ? 'user' : source;

      await (update(
        merchantRules,
      )..where((MerchantRules t) => t.id.equals(existing.id))).write(
        MerchantRulesCompanion(
          categoryId: Value<String>(categoryId),
          source: Value<String>(mergedSource),
          matchType: Value<String>(matchType),
          updatedAt: Value<DateTime>(timestamp),
        ),
      );

      await auditLogDao.append(
        entityType: 'merchant_rule',
        entityId: existing.id.toString(),
        action: 'update',
        actor: actor,
        actorDetail: 'merchant:$merchantId',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'categoryId',
            from: existing.categoryId,
            to: categoryId,
          ),
          if (existing.source != mergedSource)
            AuditFieldChange(
              field: 'source',
              from: existing.source,
              to: mergedSource,
            ),
        ],
      );
      return existing.id;
    });
  }

  /// Records that a rule fired. **The only write the automatic path performs
  /// on this table** — see the class comment for why a counter is not the
  /// mutation AC-D3.2 forbids.
  ///
  /// Not audited: the *transaction's* audit entry already names this rule
  /// (`actorDetail: 'merchant_rule:<id>'`), so the firing is recorded once,
  /// against the thing it changed. A second entry against the rule would say
  /// the same thing in a place nobody asks.
  Future<void> recordRuleApplied({required int ruleId, DateTime? at}) async {
    final DateTime timestamp = at ?? DateTime.now();
    final MerchantRuleRow? rule = await ruleById(ruleId);
    if (rule == null) {
      return;
    }
    await (update(
      merchantRules,
    )..where((MerchantRules t) => t.id.equals(ruleId))).write(
      MerchantRulesCompanion(
        appliedCount: Value<int>(rule.appliedCount + 1),
        lastAppliedAt: Value<DateTime?>(timestamp),
      ),
    );
  }

  /// Removes a learned rule (US-D4). The merchant and its transactions are
  /// untouched — forgetting a lesson is not forgetting the money.
  Future<void> deleteRule({
    required int id,
    String actor = 'user',
    DateTime? now,
  }) {
    final DateTime timestamp = now ?? DateTime.now();
    return transaction<void>(() async {
      final MerchantRuleRow? existing = await ruleById(id);
      if (existing == null) {
        return;
      }
      await (delete(
        merchantRules,
      )..where((MerchantRules t) => t.id.equals(id))).go();
      await auditLogDao.append(
        entityType: 'merchant_rule',
        entityId: id.toString(),
        action: 'delete',
        actor: actor,
        actorDetail: 'merchant:${existing.merchantId}',
        changedAt: timestamp,
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(
            field: 'categoryId',
            from: existing.categoryId,
            to: null,
          ),
        ],
      );
    });
  }
}
