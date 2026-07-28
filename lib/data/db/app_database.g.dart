// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AuditEntriesTable extends AuditEntries
    with TableInfo<$AuditEntriesTable, AuditEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorMeta = const VerificationMeta('actor');
  @override
  late final GeneratedColumn<String> actor = GeneratedColumn<String>(
    'actor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorDetailMeta = const VerificationMeta(
    'actorDetail',
  );
  @override
  late final GeneratedColumn<String> actorDetail = GeneratedColumn<String>(
    'actor_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldChangesJsonMeta = const VerificationMeta(
    'fieldChangesJson',
  );
  @override
  late final GeneratedColumn<String> fieldChangesJson = GeneratedColumn<String>(
    'field_changes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prevHashMeta = const VerificationMeta(
    'prevHash',
  );
  @override
  late final GeneratedColumn<String> prevHash = GeneratedColumn<String>(
    'prev_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryHashMeta = const VerificationMeta(
    'entryHash',
  );
  @override
  late final GeneratedColumn<String> entryHash = GeneratedColumn<String>(
    'entry_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    action,
    actor,
    actorDetail,
    changedAt,
    fieldChangesJson,
    prevHash,
    entryHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_entry';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('actor')) {
      context.handle(
        _actorMeta,
        actor.isAcceptableOrUnknown(data['actor']!, _actorMeta),
      );
    } else if (isInserting) {
      context.missing(_actorMeta);
    }
    if (data.containsKey('actor_detail')) {
      context.handle(
        _actorDetailMeta,
        actorDetail.isAcceptableOrUnknown(
          data['actor_detail']!,
          _actorDetailMeta,
        ),
      );
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    if (data.containsKey('field_changes_json')) {
      context.handle(
        _fieldChangesJsonMeta,
        fieldChangesJson.isAcceptableOrUnknown(
          data['field_changes_json']!,
          _fieldChangesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fieldChangesJsonMeta);
    }
    if (data.containsKey('prev_hash')) {
      context.handle(
        _prevHashMeta,
        prevHash.isAcceptableOrUnknown(data['prev_hash']!, _prevHashMeta),
      );
    } else if (isInserting) {
      context.missing(_prevHashMeta);
    }
    if (data.containsKey('entry_hash')) {
      context.handle(
        _entryHashMeta,
        entryHash.isAcceptableOrUnknown(data['entry_hash']!, _entryHashMeta),
      );
    } else if (isInserting) {
      context.missing(_entryHashMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      actor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor'],
      )!,
      actorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_detail'],
      ),
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
      fieldChangesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_changes_json'],
      )!,
      prevHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prev_hash'],
      )!,
      entryHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_hash'],
      )!,
    );
  }

  @override
  $AuditEntriesTable createAlias(String alias) {
    return $AuditEntriesTable(attachedDatabase, alias);
  }
}

class AuditEntryRow extends DataClass implements Insertable<AuditEntryRow> {
  final int id;

  /// Which kind of thing changed, e.g. `'transaction'`, `'instrument'`,
  /// `'bank'`. Kept as free text (not a foreign key) because the audit
  /// trail must be able to describe entities that no longer exist.
  final String entityType;

  /// The id of the specific row that changed, stored as text so this table
  /// stays entity-agnostic regardless of each entity's own id type.
  final String entityId;

  /// `'create' | 'update' | 'delete' | 'restore' | 'merge' | 'categorize' |
  /// 'rule_apply'` — validated by the DAO layer.
  final String action;

  /// `'user' | 'system_rule' | 'parser' | 'importer'`.
  final String actor;

  /// e.g. the `ruleId` that fired — satisfies "which rule applied"
  /// (AC-F5.2).
  final String? actorDetail;
  final DateTime changedAt;

  /// JSON-encoded `[{field, from, to}, ...]` — see `AuditFieldChange` in
  /// `lib/data/dao/audit_log_dao.dart` for the Dart-side shape.
  final String fieldChangesJson;

  /// The previous entry's [entryHash], or the fixed genesis marker for the
  /// very first entry ever written.
  final String prevHash;

  /// `HMAC-SHA256(auditChainKey, prevHash || canonicalJson(entry))`.
  final String entryHash;
  const AuditEntryRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.actor,
    this.actorDetail,
    required this.changedAt,
    required this.fieldChangesJson,
    required this.prevHash,
    required this.entryHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['actor'] = Variable<String>(actor);
    if (!nullToAbsent || actorDetail != null) {
      map['actor_detail'] = Variable<String>(actorDetail);
    }
    map['changed_at'] = Variable<DateTime>(changedAt);
    map['field_changes_json'] = Variable<String>(fieldChangesJson);
    map['prev_hash'] = Variable<String>(prevHash);
    map['entry_hash'] = Variable<String>(entryHash);
    return map;
  }

  AuditEntriesCompanion toCompanion(bool nullToAbsent) {
    return AuditEntriesCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action),
      actor: Value(actor),
      actorDetail: actorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(actorDetail),
      changedAt: Value(changedAt),
      fieldChangesJson: Value(fieldChangesJson),
      prevHash: Value(prevHash),
      entryHash: Value(entryHash),
    );
  }

  factory AuditEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEntryRow(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      actor: serializer.fromJson<String>(json['actor']),
      actorDetail: serializer.fromJson<String?>(json['actorDetail']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
      fieldChangesJson: serializer.fromJson<String>(json['fieldChangesJson']),
      prevHash: serializer.fromJson<String>(json['prevHash']),
      entryHash: serializer.fromJson<String>(json['entryHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'actor': serializer.toJson<String>(actor),
      'actorDetail': serializer.toJson<String?>(actorDetail),
      'changedAt': serializer.toJson<DateTime>(changedAt),
      'fieldChangesJson': serializer.toJson<String>(fieldChangesJson),
      'prevHash': serializer.toJson<String>(prevHash),
      'entryHash': serializer.toJson<String>(entryHash),
    };
  }

  AuditEntryRow copyWith({
    int? id,
    String? entityType,
    String? entityId,
    String? action,
    String? actor,
    Value<String?> actorDetail = const Value.absent(),
    DateTime? changedAt,
    String? fieldChangesJson,
    String? prevHash,
    String? entryHash,
  }) => AuditEntryRow(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    actor: actor ?? this.actor,
    actorDetail: actorDetail.present ? actorDetail.value : this.actorDetail,
    changedAt: changedAt ?? this.changedAt,
    fieldChangesJson: fieldChangesJson ?? this.fieldChangesJson,
    prevHash: prevHash ?? this.prevHash,
    entryHash: entryHash ?? this.entryHash,
  );
  AuditEntryRow copyWithCompanion(AuditEntriesCompanion data) {
    return AuditEntryRow(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      actor: data.actor.present ? data.actor.value : this.actor,
      actorDetail: data.actorDetail.present
          ? data.actorDetail.value
          : this.actorDetail,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
      fieldChangesJson: data.fieldChangesJson.present
          ? data.fieldChangesJson.value
          : this.fieldChangesJson,
      prevHash: data.prevHash.present ? data.prevHash.value : this.prevHash,
      entryHash: data.entryHash.present ? data.entryHash.value : this.entryHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEntryRow(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('actor: $actor, ')
          ..write('actorDetail: $actorDetail, ')
          ..write('changedAt: $changedAt, ')
          ..write('fieldChangesJson: $fieldChangesJson, ')
          ..write('prevHash: $prevHash, ')
          ..write('entryHash: $entryHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    action,
    actor,
    actorDetail,
    changedAt,
    fieldChangesJson,
    prevHash,
    entryHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEntryRow &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.actor == this.actor &&
          other.actorDetail == this.actorDetail &&
          other.changedAt == this.changedAt &&
          other.fieldChangesJson == this.fieldChangesJson &&
          other.prevHash == this.prevHash &&
          other.entryHash == this.entryHash);
}

class AuditEntriesCompanion extends UpdateCompanion<AuditEntryRow> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String> actor;
  final Value<String?> actorDetail;
  final Value<DateTime> changedAt;
  final Value<String> fieldChangesJson;
  final Value<String> prevHash;
  final Value<String> entryHash;
  const AuditEntriesCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.actor = const Value.absent(),
    this.actorDetail = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.fieldChangesJson = const Value.absent(),
    this.prevHash = const Value.absent(),
    this.entryHash = const Value.absent(),
  });
  AuditEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String action,
    required String actor,
    this.actorDetail = const Value.absent(),
    required DateTime changedAt,
    required String fieldChangesJson,
    required String prevHash,
    required String entryHash,
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       action = Value(action),
       actor = Value(actor),
       changedAt = Value(changedAt),
       fieldChangesJson = Value(fieldChangesJson),
       prevHash = Value(prevHash),
       entryHash = Value(entryHash);
  static Insertable<AuditEntryRow> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? actor,
    Expression<String>? actorDetail,
    Expression<DateTime>? changedAt,
    Expression<String>? fieldChangesJson,
    Expression<String>? prevHash,
    Expression<String>? entryHash,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (actor != null) 'actor': actor,
      if (actorDetail != null) 'actor_detail': actorDetail,
      if (changedAt != null) 'changed_at': changedAt,
      if (fieldChangesJson != null) 'field_changes_json': fieldChangesJson,
      if (prevHash != null) 'prev_hash': prevHash,
      if (entryHash != null) 'entry_hash': entryHash,
    });
  }

  AuditEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? action,
    Value<String>? actor,
    Value<String?>? actorDetail,
    Value<DateTime>? changedAt,
    Value<String>? fieldChangesJson,
    Value<String>? prevHash,
    Value<String>? entryHash,
  }) {
    return AuditEntriesCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      actor: actor ?? this.actor,
      actorDetail: actorDetail ?? this.actorDetail,
      changedAt: changedAt ?? this.changedAt,
      fieldChangesJson: fieldChangesJson ?? this.fieldChangesJson,
      prevHash: prevHash ?? this.prevHash,
      entryHash: entryHash ?? this.entryHash,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (actor.present) {
      map['actor'] = Variable<String>(actor.value);
    }
    if (actorDetail.present) {
      map['actor_detail'] = Variable<String>(actorDetail.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (fieldChangesJson.present) {
      map['field_changes_json'] = Variable<String>(fieldChangesJson.value);
    }
    if (prevHash.present) {
      map['prev_hash'] = Variable<String>(prevHash.value);
    }
    if (entryHash.present) {
      map['entry_hash'] = Variable<String>(entryHash.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEntriesCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('actor: $actor, ')
          ..write('actorDetail: $actorDetail, ')
          ..write('changedAt: $changedAt, ')
          ..write('fieldChangesJson: $fieldChangesJson, ')
          ..write('prevHash: $prevHash, ')
          ..write('entryHash: $entryHash')
          ..write(')'))
        .toString();
  }
}

class $RawMessagesTable extends RawMessages
    with TableInfo<$RawMessagesTable, RawMessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _smsProviderIdMeta = const VerificationMeta(
    'smsProviderId',
  );
  @override
  late final GeneratedColumn<String> smsProviderId = GeneratedColumn<String>(
    'sms_provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sanitizedBodyMeta = const VerificationMeta(
    'sanitizedBody',
  );
  @override
  late final GeneratedColumn<String> sanitizedBody = GeneratedColumn<String>(
    'sanitized_body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHmacMeta = const VerificationMeta(
    'contentHmac',
  );
  @override
  late final GeneratedColumn<String> contentHmac = GeneratedColumn<String>(
    'content_hmac',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _bankIdMeta = const VerificationMeta('bankId');
  @override
  late final GeneratedColumn<String> bankId = GeneratedColumn<String>(
    'bank_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationMeta = const VerificationMeta(
    'classification',
  );
  @override
  late final GeneratedColumn<String> classification = GeneratedColumn<String>(
    'classification',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _panRedactedMeta = const VerificationMeta(
    'panRedacted',
  );
  @override
  late final GeneratedColumn<bool> panRedacted = GeneratedColumn<bool>(
    'pan_redacted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pan_redacted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dismissedAsNotTransactionMeta =
      const VerificationMeta('dismissedAsNotTransaction');
  @override
  late final GeneratedColumn<bool> dismissedAsNotTransaction =
      GeneratedColumn<bool>(
        'dismissed_as_not_transaction',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("dismissed_as_not_transaction" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _unparsedReasonMeta = const VerificationMeta(
    'unparsedReason',
  );
  @override
  late final GeneratedColumn<String> unparsedReason = GeneratedColumn<String>(
    'unparsed_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unparsedRuleIdMeta = const VerificationMeta(
    'unparsedRuleId',
  );
  @override
  late final GeneratedColumn<String> unparsedRuleId = GeneratedColumn<String>(
    'unparsed_rule_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    smsProviderId,
    sender,
    receivedAt,
    sanitizedBody,
    contentHmac,
    bankId,
    classification,
    panRedacted,
    dismissedAsNotTransaction,
    unparsedReason,
    unparsedRuleId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_message';
  @override
  VerificationContext validateIntegrity(
    Insertable<RawMessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sms_provider_id')) {
      context.handle(
        _smsProviderIdMeta,
        smsProviderId.isAcceptableOrUnknown(
          data['sms_provider_id']!,
          _smsProviderIdMeta,
        ),
      );
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('sanitized_body')) {
      context.handle(
        _sanitizedBodyMeta,
        sanitizedBody.isAcceptableOrUnknown(
          data['sanitized_body']!,
          _sanitizedBodyMeta,
        ),
      );
    }
    if (data.containsKey('content_hmac')) {
      context.handle(
        _contentHmacMeta,
        contentHmac.isAcceptableOrUnknown(
          data['content_hmac']!,
          _contentHmacMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHmacMeta);
    }
    if (data.containsKey('bank_id')) {
      context.handle(
        _bankIdMeta,
        bankId.isAcceptableOrUnknown(data['bank_id']!, _bankIdMeta),
      );
    }
    if (data.containsKey('classification')) {
      context.handle(
        _classificationMeta,
        classification.isAcceptableOrUnknown(
          data['classification']!,
          _classificationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_classificationMeta);
    }
    if (data.containsKey('pan_redacted')) {
      context.handle(
        _panRedactedMeta,
        panRedacted.isAcceptableOrUnknown(
          data['pan_redacted']!,
          _panRedactedMeta,
        ),
      );
    }
    if (data.containsKey('dismissed_as_not_transaction')) {
      context.handle(
        _dismissedAsNotTransactionMeta,
        dismissedAsNotTransaction.isAcceptableOrUnknown(
          data['dismissed_as_not_transaction']!,
          _dismissedAsNotTransactionMeta,
        ),
      );
    }
    if (data.containsKey('unparsed_reason')) {
      context.handle(
        _unparsedReasonMeta,
        unparsedReason.isAcceptableOrUnknown(
          data['unparsed_reason']!,
          _unparsedReasonMeta,
        ),
      );
    }
    if (data.containsKey('unparsed_rule_id')) {
      context.handle(
        _unparsedRuleIdMeta,
        unparsedRuleId.isAcceptableOrUnknown(
          data['unparsed_rule_id']!,
          _unparsedRuleIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawMessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawMessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      smsProviderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sms_provider_id'],
      ),
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
      sanitizedBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sanitized_body'],
      ),
      contentHmac: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hmac'],
      )!,
      bankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bank_id'],
      ),
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      )!,
      panRedacted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pan_redacted'],
      )!,
      dismissedAsNotTransaction: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dismissed_as_not_transaction'],
      )!,
      unparsedReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unparsed_reason'],
      ),
      unparsedRuleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unparsed_rule_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RawMessagesTable createAlias(String alias) {
    return $RawMessagesTable(attachedDatabase, alias);
  }
}

class RawMessageRow extends DataClass implements Insertable<RawMessageRow> {
  final int id;

  /// The Android SMS content-provider row id, when known — `UNIQUE` so a
  /// re-scan (AC-A3.3) can never create a duplicate row for the same
  /// underlying message.
  final String? smsProviderId;
  final String sender;
  final DateTime receivedAt;

  /// Redacted text, or `NULL`.
  ///
  /// Per ADR-013/NFR-P4's precise retention rule: a message from a **known
  /// financial sender** classified `intent: ignore` (OTP/marketing/info)
  /// gets a row with `sanitizedBody = NULL` — bank, classification, and
  /// timestamp only, for the parser-health panel, with **no content at
  /// all**. A message that was parsed or is unparsed-but-financial keeps
  /// its (already redacted) text, because AC-B1.2 lets the user verify a
  /// parse and AC-A4.1 needs the raw-but-sanitised text in the review
  /// queue. (A non-financial sender gets **no row at all** — that decision
  /// happens before this DAO is ever called, in the P2 ingestion pipeline.)
  final String? sanitizedBody;

  /// `HMAC-SHA256(k, normalisedBody‖sender‖smsTimestamp)`, `UNIQUE` — the
  /// D1-exact carrier-retry dedup key (ADR-017). Storing an HMAC rather
  /// than the text keeps this dedup index non-reversible.
  final String contentHmac;
  final String? bankId;

  /// `'financial_parsed' | 'financial_unparsed' | 'ignored_otp' |
  /// 'ignored_marketing' | 'ignored_info'`.
  final String classification;
  final bool panRedacted;

  /// US-A4's "not a transaction" dismissal. A dismissed row leaves the review
  /// queue but is **kept**, so the same message re-read from the provider on
  /// a later sweep is not resurrected as a new review item.
  final bool dismissedAsNotTransaction;

  /// One of `UnparsedReason`'s constants, or `NULL` when the message parsed
  /// or was ignored.
  final String? unparsedReason;

  /// The `ruleId` that matched but could not complete, when there was one.
  /// `NULL` when no rule matched at all.
  final String? unparsedRuleId;
  final DateTime createdAt;
  const RawMessageRow({
    required this.id,
    this.smsProviderId,
    required this.sender,
    required this.receivedAt,
    this.sanitizedBody,
    required this.contentHmac,
    this.bankId,
    required this.classification,
    required this.panRedacted,
    required this.dismissedAsNotTransaction,
    this.unparsedReason,
    this.unparsedRuleId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || smsProviderId != null) {
      map['sms_provider_id'] = Variable<String>(smsProviderId);
    }
    map['sender'] = Variable<String>(sender);
    map['received_at'] = Variable<DateTime>(receivedAt);
    if (!nullToAbsent || sanitizedBody != null) {
      map['sanitized_body'] = Variable<String>(sanitizedBody);
    }
    map['content_hmac'] = Variable<String>(contentHmac);
    if (!nullToAbsent || bankId != null) {
      map['bank_id'] = Variable<String>(bankId);
    }
    map['classification'] = Variable<String>(classification);
    map['pan_redacted'] = Variable<bool>(panRedacted);
    map['dismissed_as_not_transaction'] = Variable<bool>(
      dismissedAsNotTransaction,
    );
    if (!nullToAbsent || unparsedReason != null) {
      map['unparsed_reason'] = Variable<String>(unparsedReason);
    }
    if (!nullToAbsent || unparsedRuleId != null) {
      map['unparsed_rule_id'] = Variable<String>(unparsedRuleId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RawMessagesCompanion toCompanion(bool nullToAbsent) {
    return RawMessagesCompanion(
      id: Value(id),
      smsProviderId: smsProviderId == null && nullToAbsent
          ? const Value.absent()
          : Value(smsProviderId),
      sender: Value(sender),
      receivedAt: Value(receivedAt),
      sanitizedBody: sanitizedBody == null && nullToAbsent
          ? const Value.absent()
          : Value(sanitizedBody),
      contentHmac: Value(contentHmac),
      bankId: bankId == null && nullToAbsent
          ? const Value.absent()
          : Value(bankId),
      classification: Value(classification),
      panRedacted: Value(panRedacted),
      dismissedAsNotTransaction: Value(dismissedAsNotTransaction),
      unparsedReason: unparsedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(unparsedReason),
      unparsedRuleId: unparsedRuleId == null && nullToAbsent
          ? const Value.absent()
          : Value(unparsedRuleId),
      createdAt: Value(createdAt),
    );
  }

  factory RawMessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawMessageRow(
      id: serializer.fromJson<int>(json['id']),
      smsProviderId: serializer.fromJson<String?>(json['smsProviderId']),
      sender: serializer.fromJson<String>(json['sender']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      sanitizedBody: serializer.fromJson<String?>(json['sanitizedBody']),
      contentHmac: serializer.fromJson<String>(json['contentHmac']),
      bankId: serializer.fromJson<String?>(json['bankId']),
      classification: serializer.fromJson<String>(json['classification']),
      panRedacted: serializer.fromJson<bool>(json['panRedacted']),
      dismissedAsNotTransaction: serializer.fromJson<bool>(
        json['dismissedAsNotTransaction'],
      ),
      unparsedReason: serializer.fromJson<String?>(json['unparsedReason']),
      unparsedRuleId: serializer.fromJson<String?>(json['unparsedRuleId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'smsProviderId': serializer.toJson<String?>(smsProviderId),
      'sender': serializer.toJson<String>(sender),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'sanitizedBody': serializer.toJson<String?>(sanitizedBody),
      'contentHmac': serializer.toJson<String>(contentHmac),
      'bankId': serializer.toJson<String?>(bankId),
      'classification': serializer.toJson<String>(classification),
      'panRedacted': serializer.toJson<bool>(panRedacted),
      'dismissedAsNotTransaction': serializer.toJson<bool>(
        dismissedAsNotTransaction,
      ),
      'unparsedReason': serializer.toJson<String?>(unparsedReason),
      'unparsedRuleId': serializer.toJson<String?>(unparsedRuleId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RawMessageRow copyWith({
    int? id,
    Value<String?> smsProviderId = const Value.absent(),
    String? sender,
    DateTime? receivedAt,
    Value<String?> sanitizedBody = const Value.absent(),
    String? contentHmac,
    Value<String?> bankId = const Value.absent(),
    String? classification,
    bool? panRedacted,
    bool? dismissedAsNotTransaction,
    Value<String?> unparsedReason = const Value.absent(),
    Value<String?> unparsedRuleId = const Value.absent(),
    DateTime? createdAt,
  }) => RawMessageRow(
    id: id ?? this.id,
    smsProviderId: smsProviderId.present
        ? smsProviderId.value
        : this.smsProviderId,
    sender: sender ?? this.sender,
    receivedAt: receivedAt ?? this.receivedAt,
    sanitizedBody: sanitizedBody.present
        ? sanitizedBody.value
        : this.sanitizedBody,
    contentHmac: contentHmac ?? this.contentHmac,
    bankId: bankId.present ? bankId.value : this.bankId,
    classification: classification ?? this.classification,
    panRedacted: panRedacted ?? this.panRedacted,
    dismissedAsNotTransaction:
        dismissedAsNotTransaction ?? this.dismissedAsNotTransaction,
    unparsedReason: unparsedReason.present
        ? unparsedReason.value
        : this.unparsedReason,
    unparsedRuleId: unparsedRuleId.present
        ? unparsedRuleId.value
        : this.unparsedRuleId,
    createdAt: createdAt ?? this.createdAt,
  );
  RawMessageRow copyWithCompanion(RawMessagesCompanion data) {
    return RawMessageRow(
      id: data.id.present ? data.id.value : this.id,
      smsProviderId: data.smsProviderId.present
          ? data.smsProviderId.value
          : this.smsProviderId,
      sender: data.sender.present ? data.sender.value : this.sender,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      sanitizedBody: data.sanitizedBody.present
          ? data.sanitizedBody.value
          : this.sanitizedBody,
      contentHmac: data.contentHmac.present
          ? data.contentHmac.value
          : this.contentHmac,
      bankId: data.bankId.present ? data.bankId.value : this.bankId,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      panRedacted: data.panRedacted.present
          ? data.panRedacted.value
          : this.panRedacted,
      dismissedAsNotTransaction: data.dismissedAsNotTransaction.present
          ? data.dismissedAsNotTransaction.value
          : this.dismissedAsNotTransaction,
      unparsedReason: data.unparsedReason.present
          ? data.unparsedReason.value
          : this.unparsedReason,
      unparsedRuleId: data.unparsedRuleId.present
          ? data.unparsedRuleId.value
          : this.unparsedRuleId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawMessageRow(')
          ..write('id: $id, ')
          ..write('smsProviderId: $smsProviderId, ')
          ..write('sender: $sender, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sanitizedBody: $sanitizedBody, ')
          ..write('contentHmac: $contentHmac, ')
          ..write('bankId: $bankId, ')
          ..write('classification: $classification, ')
          ..write('panRedacted: $panRedacted, ')
          ..write('dismissedAsNotTransaction: $dismissedAsNotTransaction, ')
          ..write('unparsedReason: $unparsedReason, ')
          ..write('unparsedRuleId: $unparsedRuleId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    smsProviderId,
    sender,
    receivedAt,
    sanitizedBody,
    contentHmac,
    bankId,
    classification,
    panRedacted,
    dismissedAsNotTransaction,
    unparsedReason,
    unparsedRuleId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawMessageRow &&
          other.id == this.id &&
          other.smsProviderId == this.smsProviderId &&
          other.sender == this.sender &&
          other.receivedAt == this.receivedAt &&
          other.sanitizedBody == this.sanitizedBody &&
          other.contentHmac == this.contentHmac &&
          other.bankId == this.bankId &&
          other.classification == this.classification &&
          other.panRedacted == this.panRedacted &&
          other.dismissedAsNotTransaction == this.dismissedAsNotTransaction &&
          other.unparsedReason == this.unparsedReason &&
          other.unparsedRuleId == this.unparsedRuleId &&
          other.createdAt == this.createdAt);
}

class RawMessagesCompanion extends UpdateCompanion<RawMessageRow> {
  final Value<int> id;
  final Value<String?> smsProviderId;
  final Value<String> sender;
  final Value<DateTime> receivedAt;
  final Value<String?> sanitizedBody;
  final Value<String> contentHmac;
  final Value<String?> bankId;
  final Value<String> classification;
  final Value<bool> panRedacted;
  final Value<bool> dismissedAsNotTransaction;
  final Value<String?> unparsedReason;
  final Value<String?> unparsedRuleId;
  final Value<DateTime> createdAt;
  const RawMessagesCompanion({
    this.id = const Value.absent(),
    this.smsProviderId = const Value.absent(),
    this.sender = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.sanitizedBody = const Value.absent(),
    this.contentHmac = const Value.absent(),
    this.bankId = const Value.absent(),
    this.classification = const Value.absent(),
    this.panRedacted = const Value.absent(),
    this.dismissedAsNotTransaction = const Value.absent(),
    this.unparsedReason = const Value.absent(),
    this.unparsedRuleId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  RawMessagesCompanion.insert({
    this.id = const Value.absent(),
    this.smsProviderId = const Value.absent(),
    required String sender,
    required DateTime receivedAt,
    this.sanitizedBody = const Value.absent(),
    required String contentHmac,
    this.bankId = const Value.absent(),
    required String classification,
    this.panRedacted = const Value.absent(),
    this.dismissedAsNotTransaction = const Value.absent(),
    this.unparsedReason = const Value.absent(),
    this.unparsedRuleId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : sender = Value(sender),
       receivedAt = Value(receivedAt),
       contentHmac = Value(contentHmac),
       classification = Value(classification);
  static Insertable<RawMessageRow> custom({
    Expression<int>? id,
    Expression<String>? smsProviderId,
    Expression<String>? sender,
    Expression<DateTime>? receivedAt,
    Expression<String>? sanitizedBody,
    Expression<String>? contentHmac,
    Expression<String>? bankId,
    Expression<String>? classification,
    Expression<bool>? panRedacted,
    Expression<bool>? dismissedAsNotTransaction,
    Expression<String>? unparsedReason,
    Expression<String>? unparsedRuleId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (smsProviderId != null) 'sms_provider_id': smsProviderId,
      if (sender != null) 'sender': sender,
      if (receivedAt != null) 'received_at': receivedAt,
      if (sanitizedBody != null) 'sanitized_body': sanitizedBody,
      if (contentHmac != null) 'content_hmac': contentHmac,
      if (bankId != null) 'bank_id': bankId,
      if (classification != null) 'classification': classification,
      if (panRedacted != null) 'pan_redacted': panRedacted,
      if (dismissedAsNotTransaction != null)
        'dismissed_as_not_transaction': dismissedAsNotTransaction,
      if (unparsedReason != null) 'unparsed_reason': unparsedReason,
      if (unparsedRuleId != null) 'unparsed_rule_id': unparsedRuleId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  RawMessagesCompanion copyWith({
    Value<int>? id,
    Value<String?>? smsProviderId,
    Value<String>? sender,
    Value<DateTime>? receivedAt,
    Value<String?>? sanitizedBody,
    Value<String>? contentHmac,
    Value<String?>? bankId,
    Value<String>? classification,
    Value<bool>? panRedacted,
    Value<bool>? dismissedAsNotTransaction,
    Value<String?>? unparsedReason,
    Value<String?>? unparsedRuleId,
    Value<DateTime>? createdAt,
  }) {
    return RawMessagesCompanion(
      id: id ?? this.id,
      smsProviderId: smsProviderId ?? this.smsProviderId,
      sender: sender ?? this.sender,
      receivedAt: receivedAt ?? this.receivedAt,
      sanitizedBody: sanitizedBody ?? this.sanitizedBody,
      contentHmac: contentHmac ?? this.contentHmac,
      bankId: bankId ?? this.bankId,
      classification: classification ?? this.classification,
      panRedacted: panRedacted ?? this.panRedacted,
      dismissedAsNotTransaction:
          dismissedAsNotTransaction ?? this.dismissedAsNotTransaction,
      unparsedReason: unparsedReason ?? this.unparsedReason,
      unparsedRuleId: unparsedRuleId ?? this.unparsedRuleId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (smsProviderId.present) {
      map['sms_provider_id'] = Variable<String>(smsProviderId.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (sanitizedBody.present) {
      map['sanitized_body'] = Variable<String>(sanitizedBody.value);
    }
    if (contentHmac.present) {
      map['content_hmac'] = Variable<String>(contentHmac.value);
    }
    if (bankId.present) {
      map['bank_id'] = Variable<String>(bankId.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (panRedacted.present) {
      map['pan_redacted'] = Variable<bool>(panRedacted.value);
    }
    if (dismissedAsNotTransaction.present) {
      map['dismissed_as_not_transaction'] = Variable<bool>(
        dismissedAsNotTransaction.value,
      );
    }
    if (unparsedReason.present) {
      map['unparsed_reason'] = Variable<String>(unparsedReason.value);
    }
    if (unparsedRuleId.present) {
      map['unparsed_rule_id'] = Variable<String>(unparsedRuleId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawMessagesCompanion(')
          ..write('id: $id, ')
          ..write('smsProviderId: $smsProviderId, ')
          ..write('sender: $sender, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sanitizedBody: $sanitizedBody, ')
          ..write('contentHmac: $contentHmac, ')
          ..write('bankId: $bankId, ')
          ..write('classification: $classification, ')
          ..write('panRedacted: $panRedacted, ')
          ..write('dismissedAsNotTransaction: $dismissedAsNotTransaction, ')
          ..write('unparsedReason: $unparsedReason, ')
          ..write('unparsedRuleId: $unparsedRuleId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $BanksTable extends Banks with TableInfo<$BanksTable, BankRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BanksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _canonicalKeyMeta = const VerificationMeta(
    'canonicalKey',
  );
  @override
  late final GeneratedColumn<String> canonicalKey = GeneratedColumn<String>(
    'canonical_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameArMeta = const VerificationMeta(
    'displayNameAr',
  );
  @override
  late final GeneratedColumn<String> displayNameAr = GeneratedColumn<String>(
    'display_name_ar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameEnMeta = const VerificationMeta(
    'displayNameEn',
  );
  @override
  late final GeneratedColumn<String> displayNameEn = GeneratedColumn<String>(
    'display_name_en',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasesJsonMeta = const VerificationMeta(
    'aliasesJson',
  );
  @override
  late final GeneratedColumn<String> aliasesJson = GeneratedColumn<String>(
    'aliases_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('rule_pack'),
  );
  static const VerificationMeta _firstSeenMessageIdMeta =
      const VerificationMeta('firstSeenMessageId');
  @override
  late final GeneratedColumn<int> firstSeenMessageId = GeneratedColumn<int>(
    'first_seen_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    canonicalKey,
    displayNameAr,
    displayNameEn,
    aliasesJson,
    source,
    firstSeenMessageId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bank';
  @override
  VerificationContext validateIntegrity(
    Insertable<BankRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('canonical_key')) {
      context.handle(
        _canonicalKeyMeta,
        canonicalKey.isAcceptableOrUnknown(
          data['canonical_key']!,
          _canonicalKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalKeyMeta);
    }
    if (data.containsKey('display_name_ar')) {
      context.handle(
        _displayNameArMeta,
        displayNameAr.isAcceptableOrUnknown(
          data['display_name_ar']!,
          _displayNameArMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameArMeta);
    }
    if (data.containsKey('display_name_en')) {
      context.handle(
        _displayNameEnMeta,
        displayNameEn.isAcceptableOrUnknown(
          data['display_name_en']!,
          _displayNameEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameEnMeta);
    }
    if (data.containsKey('aliases_json')) {
      context.handle(
        _aliasesJsonMeta,
        aliasesJson.isAcceptableOrUnknown(
          data['aliases_json']!,
          _aliasesJsonMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('first_seen_message_id')) {
      context.handle(
        _firstSeenMessageIdMeta,
        firstSeenMessageId.isAcceptableOrUnknown(
          data['first_seen_message_id']!,
          _firstSeenMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BankRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BankRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      canonicalKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_key'],
      )!,
      displayNameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name_ar'],
      )!,
      displayNameEn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name_en'],
      )!,
      aliasesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aliases_json'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      firstSeenMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_message_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BanksTable createAlias(String alias) {
    return $BanksTable(attachedDatabase, alias);
  }
}

class BankRow extends DataClass implements Insertable<BankRow> {
  final int id;

  /// The stable identity — the rule pack's `bankId`. **`UNIQUE`, and that
  /// uniqueness is the database-level guarantee behind AC-B12.3**: even if
  /// two ingestion runs raced, SQLite would reject the second insert rather
  /// than let a duplicate bank exist.
  final String canonicalKey;

  /// Display names, both scripts, from the pack. Stored (rather than looked
  /// up from the pack at render time) so a bank stays labelled correctly even
  /// if a later pack drops it — a bank that disappears from the UI because its
  /// rules were retired would take its transactions' context with it.
  final String displayNameAr;
  final String displayNameEn;

  /// The alias set observed for this bank, as a JSON array of strings. Used
  /// for name-based resolution (a message that names its bank in text rather
  /// than only in the sender id) and for manual add later (S-48/S-49).
  ///
  /// JSON in a `TEXT` column rather than a child table: aliases are read as a
  /// whole set, never queried individually, and a child table would add a join
  /// to every bank read for no query we actually make.
  final String aliasesJson;

  /// `rule_pack` | `user`. A bank the user typed in by hand is a different
  /// fact from one the pack recognised, and the parser-health panel should
  /// never blame a rule for a bank no rule created.
  final String source;

  /// The `raw_message.id` that first mentioned this bank (US-B15 / NFR-A1).
  /// Nullable because a user-created bank has no originating message.
  final int? firstSeenMessageId;
  final DateTime createdAt;
  const BankRow({
    required this.id,
    required this.canonicalKey,
    required this.displayNameAr,
    required this.displayNameEn,
    required this.aliasesJson,
    required this.source,
    this.firstSeenMessageId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['canonical_key'] = Variable<String>(canonicalKey);
    map['display_name_ar'] = Variable<String>(displayNameAr);
    map['display_name_en'] = Variable<String>(displayNameEn);
    map['aliases_json'] = Variable<String>(aliasesJson);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || firstSeenMessageId != null) {
      map['first_seen_message_id'] = Variable<int>(firstSeenMessageId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BanksCompanion toCompanion(bool nullToAbsent) {
    return BanksCompanion(
      id: Value(id),
      canonicalKey: Value(canonicalKey),
      displayNameAr: Value(displayNameAr),
      displayNameEn: Value(displayNameEn),
      aliasesJson: Value(aliasesJson),
      source: Value(source),
      firstSeenMessageId: firstSeenMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(firstSeenMessageId),
      createdAt: Value(createdAt),
    );
  }

  factory BankRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BankRow(
      id: serializer.fromJson<int>(json['id']),
      canonicalKey: serializer.fromJson<String>(json['canonicalKey']),
      displayNameAr: serializer.fromJson<String>(json['displayNameAr']),
      displayNameEn: serializer.fromJson<String>(json['displayNameEn']),
      aliasesJson: serializer.fromJson<String>(json['aliasesJson']),
      source: serializer.fromJson<String>(json['source']),
      firstSeenMessageId: serializer.fromJson<int?>(json['firstSeenMessageId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'canonicalKey': serializer.toJson<String>(canonicalKey),
      'displayNameAr': serializer.toJson<String>(displayNameAr),
      'displayNameEn': serializer.toJson<String>(displayNameEn),
      'aliasesJson': serializer.toJson<String>(aliasesJson),
      'source': serializer.toJson<String>(source),
      'firstSeenMessageId': serializer.toJson<int?>(firstSeenMessageId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  BankRow copyWith({
    int? id,
    String? canonicalKey,
    String? displayNameAr,
    String? displayNameEn,
    String? aliasesJson,
    String? source,
    Value<int?> firstSeenMessageId = const Value.absent(),
    DateTime? createdAt,
  }) => BankRow(
    id: id ?? this.id,
    canonicalKey: canonicalKey ?? this.canonicalKey,
    displayNameAr: displayNameAr ?? this.displayNameAr,
    displayNameEn: displayNameEn ?? this.displayNameEn,
    aliasesJson: aliasesJson ?? this.aliasesJson,
    source: source ?? this.source,
    firstSeenMessageId: firstSeenMessageId.present
        ? firstSeenMessageId.value
        : this.firstSeenMessageId,
    createdAt: createdAt ?? this.createdAt,
  );
  BankRow copyWithCompanion(BanksCompanion data) {
    return BankRow(
      id: data.id.present ? data.id.value : this.id,
      canonicalKey: data.canonicalKey.present
          ? data.canonicalKey.value
          : this.canonicalKey,
      displayNameAr: data.displayNameAr.present
          ? data.displayNameAr.value
          : this.displayNameAr,
      displayNameEn: data.displayNameEn.present
          ? data.displayNameEn.value
          : this.displayNameEn,
      aliasesJson: data.aliasesJson.present
          ? data.aliasesJson.value
          : this.aliasesJson,
      source: data.source.present ? data.source.value : this.source,
      firstSeenMessageId: data.firstSeenMessageId.present
          ? data.firstSeenMessageId.value
          : this.firstSeenMessageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BankRow(')
          ..write('id: $id, ')
          ..write('canonicalKey: $canonicalKey, ')
          ..write('displayNameAr: $displayNameAr, ')
          ..write('displayNameEn: $displayNameEn, ')
          ..write('aliasesJson: $aliasesJson, ')
          ..write('source: $source, ')
          ..write('firstSeenMessageId: $firstSeenMessageId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    canonicalKey,
    displayNameAr,
    displayNameEn,
    aliasesJson,
    source,
    firstSeenMessageId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BankRow &&
          other.id == this.id &&
          other.canonicalKey == this.canonicalKey &&
          other.displayNameAr == this.displayNameAr &&
          other.displayNameEn == this.displayNameEn &&
          other.aliasesJson == this.aliasesJson &&
          other.source == this.source &&
          other.firstSeenMessageId == this.firstSeenMessageId &&
          other.createdAt == this.createdAt);
}

class BanksCompanion extends UpdateCompanion<BankRow> {
  final Value<int> id;
  final Value<String> canonicalKey;
  final Value<String> displayNameAr;
  final Value<String> displayNameEn;
  final Value<String> aliasesJson;
  final Value<String> source;
  final Value<int?> firstSeenMessageId;
  final Value<DateTime> createdAt;
  const BanksCompanion({
    this.id = const Value.absent(),
    this.canonicalKey = const Value.absent(),
    this.displayNameAr = const Value.absent(),
    this.displayNameEn = const Value.absent(),
    this.aliasesJson = const Value.absent(),
    this.source = const Value.absent(),
    this.firstSeenMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BanksCompanion.insert({
    this.id = const Value.absent(),
    required String canonicalKey,
    required String displayNameAr,
    required String displayNameEn,
    this.aliasesJson = const Value.absent(),
    this.source = const Value.absent(),
    this.firstSeenMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : canonicalKey = Value(canonicalKey),
       displayNameAr = Value(displayNameAr),
       displayNameEn = Value(displayNameEn);
  static Insertable<BankRow> custom({
    Expression<int>? id,
    Expression<String>? canonicalKey,
    Expression<String>? displayNameAr,
    Expression<String>? displayNameEn,
    Expression<String>? aliasesJson,
    Expression<String>? source,
    Expression<int>? firstSeenMessageId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (canonicalKey != null) 'canonical_key': canonicalKey,
      if (displayNameAr != null) 'display_name_ar': displayNameAr,
      if (displayNameEn != null) 'display_name_en': displayNameEn,
      if (aliasesJson != null) 'aliases_json': aliasesJson,
      if (source != null) 'source': source,
      if (firstSeenMessageId != null)
        'first_seen_message_id': firstSeenMessageId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BanksCompanion copyWith({
    Value<int>? id,
    Value<String>? canonicalKey,
    Value<String>? displayNameAr,
    Value<String>? displayNameEn,
    Value<String>? aliasesJson,
    Value<String>? source,
    Value<int?>? firstSeenMessageId,
    Value<DateTime>? createdAt,
  }) {
    return BanksCompanion(
      id: id ?? this.id,
      canonicalKey: canonicalKey ?? this.canonicalKey,
      displayNameAr: displayNameAr ?? this.displayNameAr,
      displayNameEn: displayNameEn ?? this.displayNameEn,
      aliasesJson: aliasesJson ?? this.aliasesJson,
      source: source ?? this.source,
      firstSeenMessageId: firstSeenMessageId ?? this.firstSeenMessageId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (canonicalKey.present) {
      map['canonical_key'] = Variable<String>(canonicalKey.value);
    }
    if (displayNameAr.present) {
      map['display_name_ar'] = Variable<String>(displayNameAr.value);
    }
    if (displayNameEn.present) {
      map['display_name_en'] = Variable<String>(displayNameEn.value);
    }
    if (aliasesJson.present) {
      map['aliases_json'] = Variable<String>(aliasesJson.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (firstSeenMessageId.present) {
      map['first_seen_message_id'] = Variable<int>(firstSeenMessageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BanksCompanion(')
          ..write('id: $id, ')
          ..write('canonicalKey: $canonicalKey, ')
          ..write('displayNameAr: $displayNameAr, ')
          ..write('displayNameEn: $displayNameEn, ')
          ..write('aliasesJson: $aliasesJson, ')
          ..write('source: $source, ')
          ..write('firstSeenMessageId: $firstSeenMessageId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $InstrumentsTable extends Instruments
    with TableInfo<$InstrumentsTable, InstrumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstrumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bankIdMeta = const VerificationMeta('bankId');
  @override
  late final GeneratedColumn<int> bankId = GeneratedColumn<int>(
    'bank_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES bank(id)',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maskedIdentifierMeta = const VerificationMeta(
    'maskedIdentifier',
  );
  @override
  late final GeneratedColumn<String> maskedIdentifier = GeneratedColumn<String>(
    'masked_identifier',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refKeyMeta = const VerificationMeta('refKey');
  @override
  late final GeneratedColumn<String> refKey = GeneratedColumn<String>(
    'ref_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardTypeMeta = const VerificationMeta(
    'cardType',
  );
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
    'card_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _friendlyNameMeta = const VerificationMeta(
    'friendlyName',
  );
  @override
  late final GeneratedColumn<String> friendlyName = GeneratedColumn<String>(
    'friendly_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settlementAccountIdMeta =
      const VerificationMeta('settlementAccountId');
  @override
  late final GeneratedColumn<int> settlementAccountId = GeneratedColumn<int>(
    'settlement_account_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES instrument(id)',
  );
  static const VerificationMeta _linkSourceMeta = const VerificationMeta(
    'linkSource',
  );
  @override
  late final GeneratedColumn<String> linkSource = GeneratedColumn<String>(
    'link_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkObservedAtMeta = const VerificationMeta(
    'linkObservedAt',
  );
  @override
  late final GeneratedColumn<DateTime> linkObservedAt =
      GeneratedColumn<DateTime>(
        'link_observed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _firstSeenMessageIdMeta =
      const VerificationMeta('firstSeenMessageId');
  @override
  late final GeneratedColumn<int> firstSeenMessageId = GeneratedColumn<int>(
    'first_seen_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bankId,
    kind,
    maskedIdentifier,
    refKey,
    network,
    cardType,
    friendlyName,
    currencyCode,
    settlementAccountId,
    linkSource,
    linkObservedAt,
    isArchived,
    firstSeenMessageId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'instrument';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstrumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bank_id')) {
      context.handle(
        _bankIdMeta,
        bankId.isAcceptableOrUnknown(data['bank_id']!, _bankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bankIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('masked_identifier')) {
      context.handle(
        _maskedIdentifierMeta,
        maskedIdentifier.isAcceptableOrUnknown(
          data['masked_identifier']!,
          _maskedIdentifierMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maskedIdentifierMeta);
    }
    if (data.containsKey('ref_key')) {
      context.handle(
        _refKeyMeta,
        refKey.isAcceptableOrUnknown(data['ref_key']!, _refKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_refKeyMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    }
    if (data.containsKey('card_type')) {
      context.handle(
        _cardTypeMeta,
        cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta),
      );
    }
    if (data.containsKey('friendly_name')) {
      context.handle(
        _friendlyNameMeta,
        friendlyName.isAcceptableOrUnknown(
          data['friendly_name']!,
          _friendlyNameMeta,
        ),
      );
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    }
    if (data.containsKey('settlement_account_id')) {
      context.handle(
        _settlementAccountIdMeta,
        settlementAccountId.isAcceptableOrUnknown(
          data['settlement_account_id']!,
          _settlementAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('link_source')) {
      context.handle(
        _linkSourceMeta,
        linkSource.isAcceptableOrUnknown(data['link_source']!, _linkSourceMeta),
      );
    }
    if (data.containsKey('link_observed_at')) {
      context.handle(
        _linkObservedAtMeta,
        linkObservedAt.isAcceptableOrUnknown(
          data['link_observed_at']!,
          _linkObservedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('first_seen_message_id')) {
      context.handle(
        _firstSeenMessageIdMeta,
        firstSeenMessageId.isAcceptableOrUnknown(
          data['first_seen_message_id']!,
          _firstSeenMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InstrumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstrumentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bankId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bank_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      maskedIdentifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}masked_identifier'],
      )!,
      refKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_key'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      ),
      cardType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_type'],
      ),
      friendlyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friendly_name'],
      ),
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      ),
      settlementAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}settlement_account_id'],
      ),
      linkSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_source'],
      ),
      linkObservedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}link_observed_at'],
      ),
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      firstSeenMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_message_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InstrumentsTable createAlias(String alias) {
    return $InstrumentsTable(attachedDatabase, alias);
  }
}

class InstrumentRow extends DataClass implements Insertable<InstrumentRow> {
  final int id;

  /// The owning bank. A real foreign key, and `PRAGMA foreign_keys = ON` is
  /// set on every connection (see `AppDatabase.migration.beforeOpen`), so an
  /// instrument can never be orphaned from its bank — which is what makes
  /// "drilling into a bank shows only its own instruments" (AC-B2.1) a
  /// structural fact rather than a query convention.
  ///
  /// **Why `customConstraint` and not `.references(Banks, #id)`:** drift
  /// 2.31's Dart-side reference resolver does not recognise the class
  /// argument under this project's pinned analyzer (it reports *"This
  /// parameter should be a simple class name"* and then emits **no** foreign
  /// key at all — a constraint you believe you have and do not). Writing the
  /// SQL constraint explicitly produces the real `REFERENCES` clause in the
  /// generated `CREATE TABLE`, which is verified by a migration test. Note
  /// that a column-level custom constraint replaces the generated one, so
  /// `NOT NULL` has to be stated here too.
  final int bankId;

  /// `account` | `card`. See point 1 in the class doc comment.
  final String kind;

  /// The storable, already-masked identifier, e.g. `****4821`. Before the user
  /// renames an instrument this is also its *label* (AC-B15.2), which is why
  /// it is required rather than nullable: an auto-created instrument with no
  /// identifier would be unidentifiable in the UI.
  final String maskedIdentifier;

  /// The normalised match key — `<bank>:<kind>:<digits>`. `UNIQUE`, so a
  /// duplicate instrument cannot exist even if two ingestion paths raced.
  final String refKey;

  /// `visa` | `mada` | `mastercard`, or null when the message did not say.
  /// Null means **unknown**, never "no network" (AC-B1.3's rule applied to
  /// instruments).
  final String? network;

  /// `credit` | `debit` | `prepaid`, or null when unstated.
  final String? cardType;

  /// The user's own name for this instrument (US-B3). Null until they rename
  /// it, at which point [maskedIdentifier] steps down from label to detail.
  final String? friendlyName;

  /// The currency this instrument transacts in, when observed. Informational;
  /// no total is ever computed from it (totals are computed from the
  /// transactions' own currencies — ADR-009 forbids assuming).
  final String? currencyCode;

  /// **US-B14 — the card → settlement account link.**
  ///
  /// A self-reference: a card points at the account that settles it. Null
  /// means **"not linked"**, and AC-B14.3 is explicit that null is displayed
  /// as unlinked and never inferred — a guess here would tell the user their
  /// money flows somewhere it does not.
  final int? settlementAccountId;

  /// `sms_repayment` | `user`, or null when unlinked. AC-B14.1 makes a card
  /// repayment message — which names both the card and the debiting account —
  /// the only *automatic* source of this link.
  final String? linkSource;

  /// When the link was observed, so a later contradicting message can be
  /// judged newer or older rather than simply overwriting.
  final DateTime? linkObservedAt;

  /// Hidden from pickers and lists but retained, so its historic transactions
  /// keep their instrument context (there is no hard delete outside
  /// erase-all — ADR-011).
  final bool isArchived;

  /// `raw_message.id` of the message that first mentioned this instrument
  /// (US-B15, NFR-A1). Null for a user-created instrument.
  final int? firstSeenMessageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const InstrumentRow({
    required this.id,
    required this.bankId,
    required this.kind,
    required this.maskedIdentifier,
    required this.refKey,
    this.network,
    this.cardType,
    this.friendlyName,
    this.currencyCode,
    this.settlementAccountId,
    this.linkSource,
    this.linkObservedAt,
    required this.isArchived,
    this.firstSeenMessageId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bank_id'] = Variable<int>(bankId);
    map['kind'] = Variable<String>(kind);
    map['masked_identifier'] = Variable<String>(maskedIdentifier);
    map['ref_key'] = Variable<String>(refKey);
    if (!nullToAbsent || network != null) {
      map['network'] = Variable<String>(network);
    }
    if (!nullToAbsent || cardType != null) {
      map['card_type'] = Variable<String>(cardType);
    }
    if (!nullToAbsent || friendlyName != null) {
      map['friendly_name'] = Variable<String>(friendlyName);
    }
    if (!nullToAbsent || currencyCode != null) {
      map['currency_code'] = Variable<String>(currencyCode);
    }
    if (!nullToAbsent || settlementAccountId != null) {
      map['settlement_account_id'] = Variable<int>(settlementAccountId);
    }
    if (!nullToAbsent || linkSource != null) {
      map['link_source'] = Variable<String>(linkSource);
    }
    if (!nullToAbsent || linkObservedAt != null) {
      map['link_observed_at'] = Variable<DateTime>(linkObservedAt);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    if (!nullToAbsent || firstSeenMessageId != null) {
      map['first_seen_message_id'] = Variable<int>(firstSeenMessageId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  InstrumentsCompanion toCompanion(bool nullToAbsent) {
    return InstrumentsCompanion(
      id: Value(id),
      bankId: Value(bankId),
      kind: Value(kind),
      maskedIdentifier: Value(maskedIdentifier),
      refKey: Value(refKey),
      network: network == null && nullToAbsent
          ? const Value.absent()
          : Value(network),
      cardType: cardType == null && nullToAbsent
          ? const Value.absent()
          : Value(cardType),
      friendlyName: friendlyName == null && nullToAbsent
          ? const Value.absent()
          : Value(friendlyName),
      currencyCode: currencyCode == null && nullToAbsent
          ? const Value.absent()
          : Value(currencyCode),
      settlementAccountId: settlementAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementAccountId),
      linkSource: linkSource == null && nullToAbsent
          ? const Value.absent()
          : Value(linkSource),
      linkObservedAt: linkObservedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(linkObservedAt),
      isArchived: Value(isArchived),
      firstSeenMessageId: firstSeenMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(firstSeenMessageId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory InstrumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstrumentRow(
      id: serializer.fromJson<int>(json['id']),
      bankId: serializer.fromJson<int>(json['bankId']),
      kind: serializer.fromJson<String>(json['kind']),
      maskedIdentifier: serializer.fromJson<String>(json['maskedIdentifier']),
      refKey: serializer.fromJson<String>(json['refKey']),
      network: serializer.fromJson<String?>(json['network']),
      cardType: serializer.fromJson<String?>(json['cardType']),
      friendlyName: serializer.fromJson<String?>(json['friendlyName']),
      currencyCode: serializer.fromJson<String?>(json['currencyCode']),
      settlementAccountId: serializer.fromJson<int?>(
        json['settlementAccountId'],
      ),
      linkSource: serializer.fromJson<String?>(json['linkSource']),
      linkObservedAt: serializer.fromJson<DateTime?>(json['linkObservedAt']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      firstSeenMessageId: serializer.fromJson<int?>(json['firstSeenMessageId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bankId': serializer.toJson<int>(bankId),
      'kind': serializer.toJson<String>(kind),
      'maskedIdentifier': serializer.toJson<String>(maskedIdentifier),
      'refKey': serializer.toJson<String>(refKey),
      'network': serializer.toJson<String?>(network),
      'cardType': serializer.toJson<String?>(cardType),
      'friendlyName': serializer.toJson<String?>(friendlyName),
      'currencyCode': serializer.toJson<String?>(currencyCode),
      'settlementAccountId': serializer.toJson<int?>(settlementAccountId),
      'linkSource': serializer.toJson<String?>(linkSource),
      'linkObservedAt': serializer.toJson<DateTime?>(linkObservedAt),
      'isArchived': serializer.toJson<bool>(isArchived),
      'firstSeenMessageId': serializer.toJson<int?>(firstSeenMessageId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InstrumentRow copyWith({
    int? id,
    int? bankId,
    String? kind,
    String? maskedIdentifier,
    String? refKey,
    Value<String?> network = const Value.absent(),
    Value<String?> cardType = const Value.absent(),
    Value<String?> friendlyName = const Value.absent(),
    Value<String?> currencyCode = const Value.absent(),
    Value<int?> settlementAccountId = const Value.absent(),
    Value<String?> linkSource = const Value.absent(),
    Value<DateTime?> linkObservedAt = const Value.absent(),
    bool? isArchived,
    Value<int?> firstSeenMessageId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InstrumentRow(
    id: id ?? this.id,
    bankId: bankId ?? this.bankId,
    kind: kind ?? this.kind,
    maskedIdentifier: maskedIdentifier ?? this.maskedIdentifier,
    refKey: refKey ?? this.refKey,
    network: network.present ? network.value : this.network,
    cardType: cardType.present ? cardType.value : this.cardType,
    friendlyName: friendlyName.present ? friendlyName.value : this.friendlyName,
    currencyCode: currencyCode.present ? currencyCode.value : this.currencyCode,
    settlementAccountId: settlementAccountId.present
        ? settlementAccountId.value
        : this.settlementAccountId,
    linkSource: linkSource.present ? linkSource.value : this.linkSource,
    linkObservedAt: linkObservedAt.present
        ? linkObservedAt.value
        : this.linkObservedAt,
    isArchived: isArchived ?? this.isArchived,
    firstSeenMessageId: firstSeenMessageId.present
        ? firstSeenMessageId.value
        : this.firstSeenMessageId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InstrumentRow copyWithCompanion(InstrumentsCompanion data) {
    return InstrumentRow(
      id: data.id.present ? data.id.value : this.id,
      bankId: data.bankId.present ? data.bankId.value : this.bankId,
      kind: data.kind.present ? data.kind.value : this.kind,
      maskedIdentifier: data.maskedIdentifier.present
          ? data.maskedIdentifier.value
          : this.maskedIdentifier,
      refKey: data.refKey.present ? data.refKey.value : this.refKey,
      network: data.network.present ? data.network.value : this.network,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      friendlyName: data.friendlyName.present
          ? data.friendlyName.value
          : this.friendlyName,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      settlementAccountId: data.settlementAccountId.present
          ? data.settlementAccountId.value
          : this.settlementAccountId,
      linkSource: data.linkSource.present
          ? data.linkSource.value
          : this.linkSource,
      linkObservedAt: data.linkObservedAt.present
          ? data.linkObservedAt.value
          : this.linkObservedAt,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      firstSeenMessageId: data.firstSeenMessageId.present
          ? data.firstSeenMessageId.value
          : this.firstSeenMessageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstrumentRow(')
          ..write('id: $id, ')
          ..write('bankId: $bankId, ')
          ..write('kind: $kind, ')
          ..write('maskedIdentifier: $maskedIdentifier, ')
          ..write('refKey: $refKey, ')
          ..write('network: $network, ')
          ..write('cardType: $cardType, ')
          ..write('friendlyName: $friendlyName, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('settlementAccountId: $settlementAccountId, ')
          ..write('linkSource: $linkSource, ')
          ..write('linkObservedAt: $linkObservedAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('firstSeenMessageId: $firstSeenMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bankId,
    kind,
    maskedIdentifier,
    refKey,
    network,
    cardType,
    friendlyName,
    currencyCode,
    settlementAccountId,
    linkSource,
    linkObservedAt,
    isArchived,
    firstSeenMessageId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstrumentRow &&
          other.id == this.id &&
          other.bankId == this.bankId &&
          other.kind == this.kind &&
          other.maskedIdentifier == this.maskedIdentifier &&
          other.refKey == this.refKey &&
          other.network == this.network &&
          other.cardType == this.cardType &&
          other.friendlyName == this.friendlyName &&
          other.currencyCode == this.currencyCode &&
          other.settlementAccountId == this.settlementAccountId &&
          other.linkSource == this.linkSource &&
          other.linkObservedAt == this.linkObservedAt &&
          other.isArchived == this.isArchived &&
          other.firstSeenMessageId == this.firstSeenMessageId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class InstrumentsCompanion extends UpdateCompanion<InstrumentRow> {
  final Value<int> id;
  final Value<int> bankId;
  final Value<String> kind;
  final Value<String> maskedIdentifier;
  final Value<String> refKey;
  final Value<String?> network;
  final Value<String?> cardType;
  final Value<String?> friendlyName;
  final Value<String?> currencyCode;
  final Value<int?> settlementAccountId;
  final Value<String?> linkSource;
  final Value<DateTime?> linkObservedAt;
  final Value<bool> isArchived;
  final Value<int?> firstSeenMessageId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const InstrumentsCompanion({
    this.id = const Value.absent(),
    this.bankId = const Value.absent(),
    this.kind = const Value.absent(),
    this.maskedIdentifier = const Value.absent(),
    this.refKey = const Value.absent(),
    this.network = const Value.absent(),
    this.cardType = const Value.absent(),
    this.friendlyName = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.settlementAccountId = const Value.absent(),
    this.linkSource = const Value.absent(),
    this.linkObservedAt = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.firstSeenMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  InstrumentsCompanion.insert({
    this.id = const Value.absent(),
    required int bankId,
    required String kind,
    required String maskedIdentifier,
    required String refKey,
    this.network = const Value.absent(),
    this.cardType = const Value.absent(),
    this.friendlyName = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.settlementAccountId = const Value.absent(),
    this.linkSource = const Value.absent(),
    this.linkObservedAt = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.firstSeenMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : bankId = Value(bankId),
       kind = Value(kind),
       maskedIdentifier = Value(maskedIdentifier),
       refKey = Value(refKey);
  static Insertable<InstrumentRow> custom({
    Expression<int>? id,
    Expression<int>? bankId,
    Expression<String>? kind,
    Expression<String>? maskedIdentifier,
    Expression<String>? refKey,
    Expression<String>? network,
    Expression<String>? cardType,
    Expression<String>? friendlyName,
    Expression<String>? currencyCode,
    Expression<int>? settlementAccountId,
    Expression<String>? linkSource,
    Expression<DateTime>? linkObservedAt,
    Expression<bool>? isArchived,
    Expression<int>? firstSeenMessageId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bankId != null) 'bank_id': bankId,
      if (kind != null) 'kind': kind,
      if (maskedIdentifier != null) 'masked_identifier': maskedIdentifier,
      if (refKey != null) 'ref_key': refKey,
      if (network != null) 'network': network,
      if (cardType != null) 'card_type': cardType,
      if (friendlyName != null) 'friendly_name': friendlyName,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (settlementAccountId != null)
        'settlement_account_id': settlementAccountId,
      if (linkSource != null) 'link_source': linkSource,
      if (linkObservedAt != null) 'link_observed_at': linkObservedAt,
      if (isArchived != null) 'is_archived': isArchived,
      if (firstSeenMessageId != null)
        'first_seen_message_id': firstSeenMessageId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  InstrumentsCompanion copyWith({
    Value<int>? id,
    Value<int>? bankId,
    Value<String>? kind,
    Value<String>? maskedIdentifier,
    Value<String>? refKey,
    Value<String?>? network,
    Value<String?>? cardType,
    Value<String?>? friendlyName,
    Value<String?>? currencyCode,
    Value<int?>? settlementAccountId,
    Value<String?>? linkSource,
    Value<DateTime?>? linkObservedAt,
    Value<bool>? isArchived,
    Value<int?>? firstSeenMessageId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return InstrumentsCompanion(
      id: id ?? this.id,
      bankId: bankId ?? this.bankId,
      kind: kind ?? this.kind,
      maskedIdentifier: maskedIdentifier ?? this.maskedIdentifier,
      refKey: refKey ?? this.refKey,
      network: network ?? this.network,
      cardType: cardType ?? this.cardType,
      friendlyName: friendlyName ?? this.friendlyName,
      currencyCode: currencyCode ?? this.currencyCode,
      settlementAccountId: settlementAccountId ?? this.settlementAccountId,
      linkSource: linkSource ?? this.linkSource,
      linkObservedAt: linkObservedAt ?? this.linkObservedAt,
      isArchived: isArchived ?? this.isArchived,
      firstSeenMessageId: firstSeenMessageId ?? this.firstSeenMessageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bankId.present) {
      map['bank_id'] = Variable<int>(bankId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (maskedIdentifier.present) {
      map['masked_identifier'] = Variable<String>(maskedIdentifier.value);
    }
    if (refKey.present) {
      map['ref_key'] = Variable<String>(refKey.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (friendlyName.present) {
      map['friendly_name'] = Variable<String>(friendlyName.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (settlementAccountId.present) {
      map['settlement_account_id'] = Variable<int>(settlementAccountId.value);
    }
    if (linkSource.present) {
      map['link_source'] = Variable<String>(linkSource.value);
    }
    if (linkObservedAt.present) {
      map['link_observed_at'] = Variable<DateTime>(linkObservedAt.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (firstSeenMessageId.present) {
      map['first_seen_message_id'] = Variable<int>(firstSeenMessageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstrumentsCompanion(')
          ..write('id: $id, ')
          ..write('bankId: $bankId, ')
          ..write('kind: $kind, ')
          ..write('maskedIdentifier: $maskedIdentifier, ')
          ..write('refKey: $refKey, ')
          ..write('network: $network, ')
          ..write('cardType: $cardType, ')
          ..write('friendlyName: $friendlyName, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('settlementAccountId: $settlementAccountId, ')
          ..write('linkSource: $linkSource, ')
          ..write('linkObservedAt: $linkObservedAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('firstSeenMessageId: $firstSeenMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, TransactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _merchantRawTextMeta = const VerificationMeta(
    'merchantRawText',
  );
  @override
  late final GeneratedColumn<String> merchantRawText = GeneratedColumn<String>(
    'merchant_raw_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountAmountMeta = const VerificationMeta(
    'amountAmount',
  );
  @override
  late final GeneratedColumn<String> amountAmount = GeneratedColumn<String>(
    'amount_amount',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCurrencyMeta = const VerificationMeta(
    'amountCurrency',
  );
  @override
  late final GeneratedColumn<String> amountCurrency = GeneratedColumn<String>(
    'amount_currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _convertedAmountAmountMeta =
      const VerificationMeta('convertedAmountAmount');
  @override
  late final GeneratedColumn<String> convertedAmountAmount =
      GeneratedColumn<String>(
        'converted_amount_amount',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _convertedAmountCurrencyMeta =
      const VerificationMeta('convertedAmountCurrency');
  @override
  late final GeneratedColumn<String> convertedAmountCurrency =
      GeneratedColumn<String>(
        'converted_amount_currency',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _convertedAmountMinorMeta =
      const VerificationMeta('convertedAmountMinor');
  @override
  late final GeneratedColumn<int> convertedAmountMinor = GeneratedColumn<int>(
    'converted_amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feeAmountAmountMeta = const VerificationMeta(
    'feeAmountAmount',
  );
  @override
  late final GeneratedColumn<String> feeAmountAmount = GeneratedColumn<String>(
    'fee_amount_amount',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feeAmountCurrencyMeta = const VerificationMeta(
    'feeAmountCurrency',
  );
  @override
  late final GeneratedColumn<String> feeAmountCurrency =
      GeneratedColumn<String>(
        'fee_amount_currency',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _feeAmountMinorMeta = const VerificationMeta(
    'feeAmountMinor',
  );
  @override
  late final GeneratedColumn<int> feeAmountMinor = GeneratedColumn<int>(
    'fee_amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fxRateMeta = const VerificationMeta('fxRate');
  @override
  late final GeneratedColumn<String> fxRate = GeneratedColumn<String>(
    'fx_rate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeSourceMeta = const VerificationMeta(
    'timeSource',
  );
  @override
  late final GeneratedColumn<String> timeSource = GeneratedColumn<String>(
    'time_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('debit'),
  );
  static const VerificationMeta _transactionTypeMeta = const VerificationMeta(
    'transactionType',
  );
  @override
  late final GeneratedColumn<String> transactionType = GeneratedColumn<String>(
    'transaction_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _affectsSpendMeta = const VerificationMeta(
    'affectsSpend',
  );
  @override
  late final GeneratedColumn<bool> affectsSpend = GeneratedColumn<bool>(
    'affects_spend',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("affects_spend" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _instrumentKindMeta = const VerificationMeta(
    'instrumentKind',
  );
  @override
  late final GeneratedColumn<String> instrumentKind = GeneratedColumn<String>(
    'instrument_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _instrumentMaskedRefMeta =
      const VerificationMeta('instrumentMaskedRef');
  @override
  late final GeneratedColumn<String> instrumentMaskedRef =
      GeneratedColumn<String>(
        'instrument_masked_ref',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _instrumentIdMeta = const VerificationMeta(
    'instrumentId',
  );
  @override
  late final GeneratedColumn<int> instrumentId = GeneratedColumn<int>(
    'instrument_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES instrument(id)',
  );
  static const VerificationMeta _counterpartyNameMeta = const VerificationMeta(
    'counterpartyName',
  );
  @override
  late final GeneratedColumn<String> counterpartyName = GeneratedColumn<String>(
    'counterparty_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _counterpartyBankNameMeta =
      const VerificationMeta('counterpartyBankName');
  @override
  late final GeneratedColumn<String> counterpartyBankName =
      GeneratedColumn<String>(
        'counterparty_bank_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remainingBalanceAmountMeta =
      const VerificationMeta('remainingBalanceAmount');
  @override
  late final GeneratedColumn<String> remainingBalanceAmount =
      GeneratedColumn<String>(
        'remaining_balance_amount',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remainingBalanceCurrencyMeta =
      const VerificationMeta('remainingBalanceCurrency');
  @override
  late final GeneratedColumn<String> remainingBalanceCurrency =
      GeneratedColumn<String>(
        'remaining_balance_currency',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remainingBalanceMinorMeta =
      const VerificationMeta('remainingBalanceMinor');
  @override
  late final GeneratedColumn<int> remainingBalanceMinor = GeneratedColumn<int>(
    'remaining_balance_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _provenanceMeta = const VerificationMeta(
    'provenance',
  );
  @override
  late final GeneratedColumn<String> provenance = GeneratedColumn<String>(
    'provenance',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sms'),
  );
  static const VerificationMeta _provenanceDetailMeta = const VerificationMeta(
    'provenanceDetail',
  );
  @override
  late final GeneratedColumn<String> provenanceDetail = GeneratedColumn<String>(
    'provenance_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMessageIdMeta = const VerificationMeta(
    'sourceMessageId',
  );
  @override
  late final GeneratedColumn<int> sourceMessageId = GeneratedColumn<int>(
    'source_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rulePackIdMeta = const VerificationMeta(
    'rulePackId',
  );
  @override
  late final GeneratedColumn<String> rulePackId = GeneratedColumn<String>(
    'rule_pack_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rulePackVersionMeta = const VerificationMeta(
    'rulePackVersion',
  );
  @override
  late final GeneratedColumn<String> rulePackVersion = GeneratedColumn<String>(
    'rule_pack_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<String> ruleId = GeneratedColumn<String>(
    'rule_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsReviewMeta = const VerificationMeta(
    'needsReview',
  );
  @override
  late final GeneratedColumn<bool> needsReview = GeneratedColumn<bool>(
    'needs_review',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_review" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reviewReasonMeta = const VerificationMeta(
    'reviewReason',
  );
  @override
  late final GeneratedColumn<String> reviewReason = GeneratedColumn<String>(
    'review_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _possibleDuplicateOfIdMeta =
      const VerificationMeta('possibleDuplicateOfId');
  @override
  late final GeneratedColumn<int> possibleDuplicateOfId = GeneratedColumn<int>(
    'possible_duplicate_of_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    merchantRawText,
    amountAmount,
    amountCurrency,
    amountMinor,
    categoryId,
    convertedAmountAmount,
    convertedAmountCurrency,
    convertedAmountMinor,
    feeAmountAmount,
    feeAmountCurrency,
    feeAmountMinor,
    fxRate,
    occurredAt,
    timeSource,
    direction,
    transactionType,
    affectsSpend,
    referenceNumber,
    instrumentKind,
    instrumentMaskedRef,
    instrumentId,
    counterpartyName,
    counterpartyBankName,
    remainingBalanceAmount,
    remainingBalanceCurrency,
    remainingBalanceMinor,
    provenance,
    provenanceDetail,
    sourceMessageId,
    rulePackId,
    rulePackVersion,
    ruleId,
    needsReview,
    reviewReason,
    possibleDuplicateOfId,
    isDeleted,
    deletedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('merchant_raw_text')) {
      context.handle(
        _merchantRawTextMeta,
        merchantRawText.isAcceptableOrUnknown(
          data['merchant_raw_text']!,
          _merchantRawTextMeta,
        ),
      );
    }
    if (data.containsKey('amount_amount')) {
      context.handle(
        _amountAmountMeta,
        amountAmount.isAcceptableOrUnknown(
          data['amount_amount']!,
          _amountAmountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountAmountMeta);
    }
    if (data.containsKey('amount_currency')) {
      context.handle(
        _amountCurrencyMeta,
        amountCurrency.isAcceptableOrUnknown(
          data['amount_currency']!,
          _amountCurrencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCurrencyMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('converted_amount_amount')) {
      context.handle(
        _convertedAmountAmountMeta,
        convertedAmountAmount.isAcceptableOrUnknown(
          data['converted_amount_amount']!,
          _convertedAmountAmountMeta,
        ),
      );
    }
    if (data.containsKey('converted_amount_currency')) {
      context.handle(
        _convertedAmountCurrencyMeta,
        convertedAmountCurrency.isAcceptableOrUnknown(
          data['converted_amount_currency']!,
          _convertedAmountCurrencyMeta,
        ),
      );
    }
    if (data.containsKey('converted_amount_minor')) {
      context.handle(
        _convertedAmountMinorMeta,
        convertedAmountMinor.isAcceptableOrUnknown(
          data['converted_amount_minor']!,
          _convertedAmountMinorMeta,
        ),
      );
    }
    if (data.containsKey('fee_amount_amount')) {
      context.handle(
        _feeAmountAmountMeta,
        feeAmountAmount.isAcceptableOrUnknown(
          data['fee_amount_amount']!,
          _feeAmountAmountMeta,
        ),
      );
    }
    if (data.containsKey('fee_amount_currency')) {
      context.handle(
        _feeAmountCurrencyMeta,
        feeAmountCurrency.isAcceptableOrUnknown(
          data['fee_amount_currency']!,
          _feeAmountCurrencyMeta,
        ),
      );
    }
    if (data.containsKey('fee_amount_minor')) {
      context.handle(
        _feeAmountMinorMeta,
        feeAmountMinor.isAcceptableOrUnknown(
          data['fee_amount_minor']!,
          _feeAmountMinorMeta,
        ),
      );
    }
    if (data.containsKey('fx_rate')) {
      context.handle(
        _fxRateMeta,
        fxRate.isAcceptableOrUnknown(data['fx_rate']!, _fxRateMeta),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    }
    if (data.containsKey('time_source')) {
      context.handle(
        _timeSourceMeta,
        timeSource.isAcceptableOrUnknown(data['time_source']!, _timeSourceMeta),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    }
    if (data.containsKey('transaction_type')) {
      context.handle(
        _transactionTypeMeta,
        transactionType.isAcceptableOrUnknown(
          data['transaction_type']!,
          _transactionTypeMeta,
        ),
      );
    }
    if (data.containsKey('affects_spend')) {
      context.handle(
        _affectsSpendMeta,
        affectsSpend.isAcceptableOrUnknown(
          data['affects_spend']!,
          _affectsSpendMeta,
        ),
      );
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('instrument_kind')) {
      context.handle(
        _instrumentKindMeta,
        instrumentKind.isAcceptableOrUnknown(
          data['instrument_kind']!,
          _instrumentKindMeta,
        ),
      );
    }
    if (data.containsKey('instrument_masked_ref')) {
      context.handle(
        _instrumentMaskedRefMeta,
        instrumentMaskedRef.isAcceptableOrUnknown(
          data['instrument_masked_ref']!,
          _instrumentMaskedRefMeta,
        ),
      );
    }
    if (data.containsKey('instrument_id')) {
      context.handle(
        _instrumentIdMeta,
        instrumentId.isAcceptableOrUnknown(
          data['instrument_id']!,
          _instrumentIdMeta,
        ),
      );
    }
    if (data.containsKey('counterparty_name')) {
      context.handle(
        _counterpartyNameMeta,
        counterpartyName.isAcceptableOrUnknown(
          data['counterparty_name']!,
          _counterpartyNameMeta,
        ),
      );
    }
    if (data.containsKey('counterparty_bank_name')) {
      context.handle(
        _counterpartyBankNameMeta,
        counterpartyBankName.isAcceptableOrUnknown(
          data['counterparty_bank_name']!,
          _counterpartyBankNameMeta,
        ),
      );
    }
    if (data.containsKey('remaining_balance_amount')) {
      context.handle(
        _remainingBalanceAmountMeta,
        remainingBalanceAmount.isAcceptableOrUnknown(
          data['remaining_balance_amount']!,
          _remainingBalanceAmountMeta,
        ),
      );
    }
    if (data.containsKey('remaining_balance_currency')) {
      context.handle(
        _remainingBalanceCurrencyMeta,
        remainingBalanceCurrency.isAcceptableOrUnknown(
          data['remaining_balance_currency']!,
          _remainingBalanceCurrencyMeta,
        ),
      );
    }
    if (data.containsKey('remaining_balance_minor')) {
      context.handle(
        _remainingBalanceMinorMeta,
        remainingBalanceMinor.isAcceptableOrUnknown(
          data['remaining_balance_minor']!,
          _remainingBalanceMinorMeta,
        ),
      );
    }
    if (data.containsKey('provenance')) {
      context.handle(
        _provenanceMeta,
        provenance.isAcceptableOrUnknown(data['provenance']!, _provenanceMeta),
      );
    }
    if (data.containsKey('provenance_detail')) {
      context.handle(
        _provenanceDetailMeta,
        provenanceDetail.isAcceptableOrUnknown(
          data['provenance_detail']!,
          _provenanceDetailMeta,
        ),
      );
    }
    if (data.containsKey('source_message_id')) {
      context.handle(
        _sourceMessageIdMeta,
        sourceMessageId.isAcceptableOrUnknown(
          data['source_message_id']!,
          _sourceMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('rule_pack_id')) {
      context.handle(
        _rulePackIdMeta,
        rulePackId.isAcceptableOrUnknown(
          data['rule_pack_id']!,
          _rulePackIdMeta,
        ),
      );
    }
    if (data.containsKey('rule_pack_version')) {
      context.handle(
        _rulePackVersionMeta,
        rulePackVersion.isAcceptableOrUnknown(
          data['rule_pack_version']!,
          _rulePackVersionMeta,
        ),
      );
    }
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    }
    if (data.containsKey('needs_review')) {
      context.handle(
        _needsReviewMeta,
        needsReview.isAcceptableOrUnknown(
          data['needs_review']!,
          _needsReviewMeta,
        ),
      );
    }
    if (data.containsKey('review_reason')) {
      context.handle(
        _reviewReasonMeta,
        reviewReason.isAcceptableOrUnknown(
          data['review_reason']!,
          _reviewReasonMeta,
        ),
      );
    }
    if (data.containsKey('possible_duplicate_of_id')) {
      context.handle(
        _possibleDuplicateOfIdMeta,
        possibleDuplicateOfId.isAcceptableOrUnknown(
          data['possible_duplicate_of_id']!,
          _possibleDuplicateOfIdMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      merchantRawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merchant_raw_text'],
      ),
      amountAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_amount'],
      )!,
      amountCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_currency'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      convertedAmountAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}converted_amount_amount'],
      ),
      convertedAmountCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}converted_amount_currency'],
      ),
      convertedAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}converted_amount_minor'],
      ),
      feeAmountAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fee_amount_amount'],
      ),
      feeAmountCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fee_amount_currency'],
      ),
      feeAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fee_amount_minor'],
      ),
      fxRate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fx_rate'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      ),
      timeSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_source'],
      ),
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      transactionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_type'],
      )!,
      affectsSpend: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}affects_spend'],
      )!,
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      instrumentKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instrument_kind'],
      ),
      instrumentMaskedRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instrument_masked_ref'],
      ),
      instrumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}instrument_id'],
      ),
      counterpartyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counterparty_name'],
      ),
      counterpartyBankName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counterparty_bank_name'],
      ),
      remainingBalanceAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remaining_balance_amount'],
      ),
      remainingBalanceCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remaining_balance_currency'],
      ),
      remainingBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remaining_balance_minor'],
      ),
      provenance: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance'],
      )!,
      provenanceDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_detail'],
      ),
      sourceMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_message_id'],
      ),
      rulePackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_pack_id'],
      ),
      rulePackVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_pack_version'],
      ),
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_id'],
      ),
      needsReview: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_review'],
      )!,
      reviewReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_reason'],
      ),
      possibleDuplicateOfId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}possible_duplicate_of_id'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class TransactionRow extends DataClass implements Insertable<TransactionRow> {
  final int id;
  final String? merchantRawText;
  final String amountAmount;
  final String amountCurrency;
  final int amountMinor;

  /// Nullable, no FK target yet (the `Category` table is P4 work) —
  /// intentionally loose in this P1-minimal table.
  final String? categoryId;

  /// The bank's own inline conversion into the base currency, where the
  /// message supplied one. ADR-009 prefers the bank's figure over anything
  /// we could derive: it is what actually hit the account.
  final String? convertedAmountAmount;
  final String? convertedAmountCurrency;
  final int? convertedAmountMinor;
  final String? feeAmountAmount;
  final String? feeAmountCurrency;
  final int? feeAmountMinor;

  /// Exact decimal **string**, never a float (ADR-002). A rate is not an
  /// amount of money, so it is not a `Money` triple either.
  final String? fxRate;

  /// When the movement happened, per the message, in UTC.
  ///
  /// Distinct from `createdAt` (when *we* recorded it) on purpose: a
  /// historical import writes rows today for purchases made three weeks ago,
  /// and a period total keyed on `createdAt` would put every one of them in
  /// the wrong month.
  final DateTime? occurredAt;

  /// `sms_explicit` | `sms_local_assumed` | `received_at_fallback`
  /// (architecture §7.4). Recorded so an odd-looking timestamp is
  /// explainable rather than mysterious.
  final String? timeSource;

  /// `debit` | `credit`. A refund is a credit and **reduces** period spend
  /// (US-B7); it is never stored as a negative debit, because a negative
  /// amount would break every `Money` invariant that assumes sign lives in
  /// the direction field.
  final String direction;

  /// The matched rule's `messageType`, e.g. `pos_purchase`, `installment`.
  final String transactionType;

  /// Whether this counts toward "money spent" (US-B10/B11). `false` for
  /// internal transfers, salary income, and card repayment.
  final bool affectsSpend;

  /// Present on transfers and some bill payments (PRD §3.4). The reliable
  /// duplicate key when it exists (ADR-017 D2).
  final String? referenceNumber;

  /// `card` | `account`, from the matched rule's declaration — never guessed
  /// from digit length (AC-B13.1/2).
  final String? instrumentKind;

  /// Already masked, e.g. `****4821`. There is deliberately no column in this
  /// schema capable of holding a full PAN (NFR-S2, architecture §4.2).
  final String? instrumentMaskedRef;

  /// The `instrument` row this transaction hit.
  ///
  /// **Nullable on purpose** (architecture §4.2 says so explicitly): a
  /// message that named no instrument, or named one with too few digits to
  /// mask meaningfully, produces a transaction whose instrument is
  /// *explicitly unknown* (AC-B1.3). Defaulting to some "unassigned"
  /// instrument row would put real money under a fictional card.
  /// (Written as an explicit SQL constraint rather than `.references(...)` —
  /// see the same note on `instrument_table.dart`'s `bankId`. `ALTER TABLE
  /// ADD COLUMN` accepts a `REFERENCES` clause as long as the column defaults
  /// to NULL, which it does, so an upgraded database gets exactly the same
  /// constraint a fresh install does.)
  final int? instrumentId;

  /// Who the money went to or came from on a transfer (PRD §3.4). For a
  /// transfer this is the payee AC-B1.1 asks the detail view to show; for a
  /// purchase it is null and `merchantRawText` plays that role.
  final String? counterpartyName;

  /// The counterparty's bank, where the message named it.
  final String? counterpartyBankName;

  /// The balance a message reported *after* the movement — PRD §3.4 notes the
  /// installment template does this.
  ///
  /// **Informational only. It is never treated as spend and never summed**;
  /// it is stored as a `Money` triple like every other amount purely so it
  /// cannot accidentally be handled as a float on its way to the screen.
  final String? remainingBalanceAmount;
  final String? remainingBalanceCurrency;
  final int? remainingBalanceMinor;

  /// `sms` | `manual` | `statement`. P7 must not create a fourth, untracked
  /// path (build-plan §5).
  final String provenance;

  /// A refinement of [provenance], not a fourth value of it.
  ///
  /// KHA-64/AC-A4.2 creates a genuinely hybrid record: an unparsed SMS the
  /// **user** completed by hand. Recording it as `manual` would throw away
  /// the source-message reference NFR-A1 requires; recording it as plain
  /// `sms` would claim the parser produced numbers a human actually typed.
  /// So [provenance] stays `sms` (the message reference is real and is kept)
  /// and this column carries `manual_completion`. Architecture §4.2's
  /// three-value provenance vocabulary is left intact.
  ///
  /// Null for an ordinary parsed transaction.
  final String? provenanceDetail;

  /// FK to `raw_message.id`, so the user can open a transaction and read the
  /// message it came from to verify the parse (AC-B1.2).
  final int? sourceMessageId;

  /// Which pack, version and rule produced this row. A rule change never
  /// rewrites history (ADR-007 "Provenance"); these three columns are what
  /// make it possible to tell later which parse produced which number.
  final String? rulePackId;
  final String? rulePackVersion;
  final String? ruleId;

  /// Set by ADR-017's D3 heuristic tier and by any other "we are not sure"
  /// signal. Surfaced in the Needs Review inbox (design.md S-18).
  final bool needsReview;

  /// A machine-readable reason, e.g. `possible_duplicate`. Never free text.
  final String? reviewReason;

  /// The transaction this one *might* duplicate.
  ///
  /// **Both rows stay in the list and in the totals until the user decides**
  /// (ADR-017 D3). The bias is deliberate and asymmetric: an inflated total
  /// is visible and correctable; a silently deleted real transaction is
  /// invisible and uncorrectable. Banking default — prefer the auditable,
  /// recoverable error.
  final int? possibleDuplicateOfId;

  /// Soft delete (US-B8) — hidden from normal lists/totals but retained and
  /// restorable. Only "erase everything" (ADR-011, P8) is a true hard
  /// delete.
  final bool isDeleted;

  /// When the soft delete happened. AC-B6.4 requires the change history to
  /// show a deletion "with timestamp and prior values" — the audit entry
  /// carries both, and this column makes the same fact readable from the row
  /// itself (e.g. for the Recently Deleted list's ordering, US-B8).
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TransactionRow({
    required this.id,
    this.merchantRawText,
    required this.amountAmount,
    required this.amountCurrency,
    required this.amountMinor,
    this.categoryId,
    this.convertedAmountAmount,
    this.convertedAmountCurrency,
    this.convertedAmountMinor,
    this.feeAmountAmount,
    this.feeAmountCurrency,
    this.feeAmountMinor,
    this.fxRate,
    this.occurredAt,
    this.timeSource,
    required this.direction,
    required this.transactionType,
    required this.affectsSpend,
    this.referenceNumber,
    this.instrumentKind,
    this.instrumentMaskedRef,
    this.instrumentId,
    this.counterpartyName,
    this.counterpartyBankName,
    this.remainingBalanceAmount,
    this.remainingBalanceCurrency,
    this.remainingBalanceMinor,
    required this.provenance,
    this.provenanceDetail,
    this.sourceMessageId,
    this.rulePackId,
    this.rulePackVersion,
    this.ruleId,
    required this.needsReview,
    this.reviewReason,
    this.possibleDuplicateOfId,
    required this.isDeleted,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || merchantRawText != null) {
      map['merchant_raw_text'] = Variable<String>(merchantRawText);
    }
    map['amount_amount'] = Variable<String>(amountAmount);
    map['amount_currency'] = Variable<String>(amountCurrency);
    map['amount_minor'] = Variable<int>(amountMinor);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || convertedAmountAmount != null) {
      map['converted_amount_amount'] = Variable<String>(convertedAmountAmount);
    }
    if (!nullToAbsent || convertedAmountCurrency != null) {
      map['converted_amount_currency'] = Variable<String>(
        convertedAmountCurrency,
      );
    }
    if (!nullToAbsent || convertedAmountMinor != null) {
      map['converted_amount_minor'] = Variable<int>(convertedAmountMinor);
    }
    if (!nullToAbsent || feeAmountAmount != null) {
      map['fee_amount_amount'] = Variable<String>(feeAmountAmount);
    }
    if (!nullToAbsent || feeAmountCurrency != null) {
      map['fee_amount_currency'] = Variable<String>(feeAmountCurrency);
    }
    if (!nullToAbsent || feeAmountMinor != null) {
      map['fee_amount_minor'] = Variable<int>(feeAmountMinor);
    }
    if (!nullToAbsent || fxRate != null) {
      map['fx_rate'] = Variable<String>(fxRate);
    }
    if (!nullToAbsent || occurredAt != null) {
      map['occurred_at'] = Variable<DateTime>(occurredAt);
    }
    if (!nullToAbsent || timeSource != null) {
      map['time_source'] = Variable<String>(timeSource);
    }
    map['direction'] = Variable<String>(direction);
    map['transaction_type'] = Variable<String>(transactionType);
    map['affects_spend'] = Variable<bool>(affectsSpend);
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    if (!nullToAbsent || instrumentKind != null) {
      map['instrument_kind'] = Variable<String>(instrumentKind);
    }
    if (!nullToAbsent || instrumentMaskedRef != null) {
      map['instrument_masked_ref'] = Variable<String>(instrumentMaskedRef);
    }
    if (!nullToAbsent || instrumentId != null) {
      map['instrument_id'] = Variable<int>(instrumentId);
    }
    if (!nullToAbsent || counterpartyName != null) {
      map['counterparty_name'] = Variable<String>(counterpartyName);
    }
    if (!nullToAbsent || counterpartyBankName != null) {
      map['counterparty_bank_name'] = Variable<String>(counterpartyBankName);
    }
    if (!nullToAbsent || remainingBalanceAmount != null) {
      map['remaining_balance_amount'] = Variable<String>(
        remainingBalanceAmount,
      );
    }
    if (!nullToAbsent || remainingBalanceCurrency != null) {
      map['remaining_balance_currency'] = Variable<String>(
        remainingBalanceCurrency,
      );
    }
    if (!nullToAbsent || remainingBalanceMinor != null) {
      map['remaining_balance_minor'] = Variable<int>(remainingBalanceMinor);
    }
    map['provenance'] = Variable<String>(provenance);
    if (!nullToAbsent || provenanceDetail != null) {
      map['provenance_detail'] = Variable<String>(provenanceDetail);
    }
    if (!nullToAbsent || sourceMessageId != null) {
      map['source_message_id'] = Variable<int>(sourceMessageId);
    }
    if (!nullToAbsent || rulePackId != null) {
      map['rule_pack_id'] = Variable<String>(rulePackId);
    }
    if (!nullToAbsent || rulePackVersion != null) {
      map['rule_pack_version'] = Variable<String>(rulePackVersion);
    }
    if (!nullToAbsent || ruleId != null) {
      map['rule_id'] = Variable<String>(ruleId);
    }
    map['needs_review'] = Variable<bool>(needsReview);
    if (!nullToAbsent || reviewReason != null) {
      map['review_reason'] = Variable<String>(reviewReason);
    }
    if (!nullToAbsent || possibleDuplicateOfId != null) {
      map['possible_duplicate_of_id'] = Variable<int>(possibleDuplicateOfId);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      merchantRawText: merchantRawText == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantRawText),
      amountAmount: Value(amountAmount),
      amountCurrency: Value(amountCurrency),
      amountMinor: Value(amountMinor),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      convertedAmountAmount: convertedAmountAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(convertedAmountAmount),
      convertedAmountCurrency: convertedAmountCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(convertedAmountCurrency),
      convertedAmountMinor: convertedAmountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(convertedAmountMinor),
      feeAmountAmount: feeAmountAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(feeAmountAmount),
      feeAmountCurrency: feeAmountCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(feeAmountCurrency),
      feeAmountMinor: feeAmountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(feeAmountMinor),
      fxRate: fxRate == null && nullToAbsent
          ? const Value.absent()
          : Value(fxRate),
      occurredAt: occurredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(occurredAt),
      timeSource: timeSource == null && nullToAbsent
          ? const Value.absent()
          : Value(timeSource),
      direction: Value(direction),
      transactionType: Value(transactionType),
      affectsSpend: Value(affectsSpend),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      instrumentKind: instrumentKind == null && nullToAbsent
          ? const Value.absent()
          : Value(instrumentKind),
      instrumentMaskedRef: instrumentMaskedRef == null && nullToAbsent
          ? const Value.absent()
          : Value(instrumentMaskedRef),
      instrumentId: instrumentId == null && nullToAbsent
          ? const Value.absent()
          : Value(instrumentId),
      counterpartyName: counterpartyName == null && nullToAbsent
          ? const Value.absent()
          : Value(counterpartyName),
      counterpartyBankName: counterpartyBankName == null && nullToAbsent
          ? const Value.absent()
          : Value(counterpartyBankName),
      remainingBalanceAmount: remainingBalanceAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(remainingBalanceAmount),
      remainingBalanceCurrency: remainingBalanceCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(remainingBalanceCurrency),
      remainingBalanceMinor: remainingBalanceMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(remainingBalanceMinor),
      provenance: Value(provenance),
      provenanceDetail: provenanceDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(provenanceDetail),
      sourceMessageId: sourceMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMessageId),
      rulePackId: rulePackId == null && nullToAbsent
          ? const Value.absent()
          : Value(rulePackId),
      rulePackVersion: rulePackVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(rulePackVersion),
      ruleId: ruleId == null && nullToAbsent
          ? const Value.absent()
          : Value(ruleId),
      needsReview: Value(needsReview),
      reviewReason: reviewReason == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewReason),
      possibleDuplicateOfId: possibleDuplicateOfId == null && nullToAbsent
          ? const Value.absent()
          : Value(possibleDuplicateOfId),
      isDeleted: Value(isDeleted),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionRow(
      id: serializer.fromJson<int>(json['id']),
      merchantRawText: serializer.fromJson<String?>(json['merchantRawText']),
      amountAmount: serializer.fromJson<String>(json['amountAmount']),
      amountCurrency: serializer.fromJson<String>(json['amountCurrency']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      convertedAmountAmount: serializer.fromJson<String?>(
        json['convertedAmountAmount'],
      ),
      convertedAmountCurrency: serializer.fromJson<String?>(
        json['convertedAmountCurrency'],
      ),
      convertedAmountMinor: serializer.fromJson<int?>(
        json['convertedAmountMinor'],
      ),
      feeAmountAmount: serializer.fromJson<String?>(json['feeAmountAmount']),
      feeAmountCurrency: serializer.fromJson<String?>(
        json['feeAmountCurrency'],
      ),
      feeAmountMinor: serializer.fromJson<int?>(json['feeAmountMinor']),
      fxRate: serializer.fromJson<String?>(json['fxRate']),
      occurredAt: serializer.fromJson<DateTime?>(json['occurredAt']),
      timeSource: serializer.fromJson<String?>(json['timeSource']),
      direction: serializer.fromJson<String>(json['direction']),
      transactionType: serializer.fromJson<String>(json['transactionType']),
      affectsSpend: serializer.fromJson<bool>(json['affectsSpend']),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      instrumentKind: serializer.fromJson<String?>(json['instrumentKind']),
      instrumentMaskedRef: serializer.fromJson<String?>(
        json['instrumentMaskedRef'],
      ),
      instrumentId: serializer.fromJson<int?>(json['instrumentId']),
      counterpartyName: serializer.fromJson<String?>(json['counterpartyName']),
      counterpartyBankName: serializer.fromJson<String?>(
        json['counterpartyBankName'],
      ),
      remainingBalanceAmount: serializer.fromJson<String?>(
        json['remainingBalanceAmount'],
      ),
      remainingBalanceCurrency: serializer.fromJson<String?>(
        json['remainingBalanceCurrency'],
      ),
      remainingBalanceMinor: serializer.fromJson<int?>(
        json['remainingBalanceMinor'],
      ),
      provenance: serializer.fromJson<String>(json['provenance']),
      provenanceDetail: serializer.fromJson<String?>(json['provenanceDetail']),
      sourceMessageId: serializer.fromJson<int?>(json['sourceMessageId']),
      rulePackId: serializer.fromJson<String?>(json['rulePackId']),
      rulePackVersion: serializer.fromJson<String?>(json['rulePackVersion']),
      ruleId: serializer.fromJson<String?>(json['ruleId']),
      needsReview: serializer.fromJson<bool>(json['needsReview']),
      reviewReason: serializer.fromJson<String?>(json['reviewReason']),
      possibleDuplicateOfId: serializer.fromJson<int?>(
        json['possibleDuplicateOfId'],
      ),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'merchantRawText': serializer.toJson<String?>(merchantRawText),
      'amountAmount': serializer.toJson<String>(amountAmount),
      'amountCurrency': serializer.toJson<String>(amountCurrency),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'categoryId': serializer.toJson<String?>(categoryId),
      'convertedAmountAmount': serializer.toJson<String?>(
        convertedAmountAmount,
      ),
      'convertedAmountCurrency': serializer.toJson<String?>(
        convertedAmountCurrency,
      ),
      'convertedAmountMinor': serializer.toJson<int?>(convertedAmountMinor),
      'feeAmountAmount': serializer.toJson<String?>(feeAmountAmount),
      'feeAmountCurrency': serializer.toJson<String?>(feeAmountCurrency),
      'feeAmountMinor': serializer.toJson<int?>(feeAmountMinor),
      'fxRate': serializer.toJson<String?>(fxRate),
      'occurredAt': serializer.toJson<DateTime?>(occurredAt),
      'timeSource': serializer.toJson<String?>(timeSource),
      'direction': serializer.toJson<String>(direction),
      'transactionType': serializer.toJson<String>(transactionType),
      'affectsSpend': serializer.toJson<bool>(affectsSpend),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'instrumentKind': serializer.toJson<String?>(instrumentKind),
      'instrumentMaskedRef': serializer.toJson<String?>(instrumentMaskedRef),
      'instrumentId': serializer.toJson<int?>(instrumentId),
      'counterpartyName': serializer.toJson<String?>(counterpartyName),
      'counterpartyBankName': serializer.toJson<String?>(counterpartyBankName),
      'remainingBalanceAmount': serializer.toJson<String?>(
        remainingBalanceAmount,
      ),
      'remainingBalanceCurrency': serializer.toJson<String?>(
        remainingBalanceCurrency,
      ),
      'remainingBalanceMinor': serializer.toJson<int?>(remainingBalanceMinor),
      'provenance': serializer.toJson<String>(provenance),
      'provenanceDetail': serializer.toJson<String?>(provenanceDetail),
      'sourceMessageId': serializer.toJson<int?>(sourceMessageId),
      'rulePackId': serializer.toJson<String?>(rulePackId),
      'rulePackVersion': serializer.toJson<String?>(rulePackVersion),
      'ruleId': serializer.toJson<String?>(ruleId),
      'needsReview': serializer.toJson<bool>(needsReview),
      'reviewReason': serializer.toJson<String?>(reviewReason),
      'possibleDuplicateOfId': serializer.toJson<int?>(possibleDuplicateOfId),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TransactionRow copyWith({
    int? id,
    Value<String?> merchantRawText = const Value.absent(),
    String? amountAmount,
    String? amountCurrency,
    int? amountMinor,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> convertedAmountAmount = const Value.absent(),
    Value<String?> convertedAmountCurrency = const Value.absent(),
    Value<int?> convertedAmountMinor = const Value.absent(),
    Value<String?> feeAmountAmount = const Value.absent(),
    Value<String?> feeAmountCurrency = const Value.absent(),
    Value<int?> feeAmountMinor = const Value.absent(),
    Value<String?> fxRate = const Value.absent(),
    Value<DateTime?> occurredAt = const Value.absent(),
    Value<String?> timeSource = const Value.absent(),
    String? direction,
    String? transactionType,
    bool? affectsSpend,
    Value<String?> referenceNumber = const Value.absent(),
    Value<String?> instrumentKind = const Value.absent(),
    Value<String?> instrumentMaskedRef = const Value.absent(),
    Value<int?> instrumentId = const Value.absent(),
    Value<String?> counterpartyName = const Value.absent(),
    Value<String?> counterpartyBankName = const Value.absent(),
    Value<String?> remainingBalanceAmount = const Value.absent(),
    Value<String?> remainingBalanceCurrency = const Value.absent(),
    Value<int?> remainingBalanceMinor = const Value.absent(),
    String? provenance,
    Value<String?> provenanceDetail = const Value.absent(),
    Value<int?> sourceMessageId = const Value.absent(),
    Value<String?> rulePackId = const Value.absent(),
    Value<String?> rulePackVersion = const Value.absent(),
    Value<String?> ruleId = const Value.absent(),
    bool? needsReview,
    Value<String?> reviewReason = const Value.absent(),
    Value<int?> possibleDuplicateOfId = const Value.absent(),
    bool? isDeleted,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TransactionRow(
    id: id ?? this.id,
    merchantRawText: merchantRawText.present
        ? merchantRawText.value
        : this.merchantRawText,
    amountAmount: amountAmount ?? this.amountAmount,
    amountCurrency: amountCurrency ?? this.amountCurrency,
    amountMinor: amountMinor ?? this.amountMinor,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    convertedAmountAmount: convertedAmountAmount.present
        ? convertedAmountAmount.value
        : this.convertedAmountAmount,
    convertedAmountCurrency: convertedAmountCurrency.present
        ? convertedAmountCurrency.value
        : this.convertedAmountCurrency,
    convertedAmountMinor: convertedAmountMinor.present
        ? convertedAmountMinor.value
        : this.convertedAmountMinor,
    feeAmountAmount: feeAmountAmount.present
        ? feeAmountAmount.value
        : this.feeAmountAmount,
    feeAmountCurrency: feeAmountCurrency.present
        ? feeAmountCurrency.value
        : this.feeAmountCurrency,
    feeAmountMinor: feeAmountMinor.present
        ? feeAmountMinor.value
        : this.feeAmountMinor,
    fxRate: fxRate.present ? fxRate.value : this.fxRate,
    occurredAt: occurredAt.present ? occurredAt.value : this.occurredAt,
    timeSource: timeSource.present ? timeSource.value : this.timeSource,
    direction: direction ?? this.direction,
    transactionType: transactionType ?? this.transactionType,
    affectsSpend: affectsSpend ?? this.affectsSpend,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    instrumentKind: instrumentKind.present
        ? instrumentKind.value
        : this.instrumentKind,
    instrumentMaskedRef: instrumentMaskedRef.present
        ? instrumentMaskedRef.value
        : this.instrumentMaskedRef,
    instrumentId: instrumentId.present ? instrumentId.value : this.instrumentId,
    counterpartyName: counterpartyName.present
        ? counterpartyName.value
        : this.counterpartyName,
    counterpartyBankName: counterpartyBankName.present
        ? counterpartyBankName.value
        : this.counterpartyBankName,
    remainingBalanceAmount: remainingBalanceAmount.present
        ? remainingBalanceAmount.value
        : this.remainingBalanceAmount,
    remainingBalanceCurrency: remainingBalanceCurrency.present
        ? remainingBalanceCurrency.value
        : this.remainingBalanceCurrency,
    remainingBalanceMinor: remainingBalanceMinor.present
        ? remainingBalanceMinor.value
        : this.remainingBalanceMinor,
    provenance: provenance ?? this.provenance,
    provenanceDetail: provenanceDetail.present
        ? provenanceDetail.value
        : this.provenanceDetail,
    sourceMessageId: sourceMessageId.present
        ? sourceMessageId.value
        : this.sourceMessageId,
    rulePackId: rulePackId.present ? rulePackId.value : this.rulePackId,
    rulePackVersion: rulePackVersion.present
        ? rulePackVersion.value
        : this.rulePackVersion,
    ruleId: ruleId.present ? ruleId.value : this.ruleId,
    needsReview: needsReview ?? this.needsReview,
    reviewReason: reviewReason.present ? reviewReason.value : this.reviewReason,
    possibleDuplicateOfId: possibleDuplicateOfId.present
        ? possibleDuplicateOfId.value
        : this.possibleDuplicateOfId,
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TransactionRow copyWithCompanion(TransactionsCompanion data) {
    return TransactionRow(
      id: data.id.present ? data.id.value : this.id,
      merchantRawText: data.merchantRawText.present
          ? data.merchantRawText.value
          : this.merchantRawText,
      amountAmount: data.amountAmount.present
          ? data.amountAmount.value
          : this.amountAmount,
      amountCurrency: data.amountCurrency.present
          ? data.amountCurrency.value
          : this.amountCurrency,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      convertedAmountAmount: data.convertedAmountAmount.present
          ? data.convertedAmountAmount.value
          : this.convertedAmountAmount,
      convertedAmountCurrency: data.convertedAmountCurrency.present
          ? data.convertedAmountCurrency.value
          : this.convertedAmountCurrency,
      convertedAmountMinor: data.convertedAmountMinor.present
          ? data.convertedAmountMinor.value
          : this.convertedAmountMinor,
      feeAmountAmount: data.feeAmountAmount.present
          ? data.feeAmountAmount.value
          : this.feeAmountAmount,
      feeAmountCurrency: data.feeAmountCurrency.present
          ? data.feeAmountCurrency.value
          : this.feeAmountCurrency,
      feeAmountMinor: data.feeAmountMinor.present
          ? data.feeAmountMinor.value
          : this.feeAmountMinor,
      fxRate: data.fxRate.present ? data.fxRate.value : this.fxRate,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      timeSource: data.timeSource.present
          ? data.timeSource.value
          : this.timeSource,
      direction: data.direction.present ? data.direction.value : this.direction,
      transactionType: data.transactionType.present
          ? data.transactionType.value
          : this.transactionType,
      affectsSpend: data.affectsSpend.present
          ? data.affectsSpend.value
          : this.affectsSpend,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      instrumentKind: data.instrumentKind.present
          ? data.instrumentKind.value
          : this.instrumentKind,
      instrumentMaskedRef: data.instrumentMaskedRef.present
          ? data.instrumentMaskedRef.value
          : this.instrumentMaskedRef,
      instrumentId: data.instrumentId.present
          ? data.instrumentId.value
          : this.instrumentId,
      counterpartyName: data.counterpartyName.present
          ? data.counterpartyName.value
          : this.counterpartyName,
      counterpartyBankName: data.counterpartyBankName.present
          ? data.counterpartyBankName.value
          : this.counterpartyBankName,
      remainingBalanceAmount: data.remainingBalanceAmount.present
          ? data.remainingBalanceAmount.value
          : this.remainingBalanceAmount,
      remainingBalanceCurrency: data.remainingBalanceCurrency.present
          ? data.remainingBalanceCurrency.value
          : this.remainingBalanceCurrency,
      remainingBalanceMinor: data.remainingBalanceMinor.present
          ? data.remainingBalanceMinor.value
          : this.remainingBalanceMinor,
      provenance: data.provenance.present
          ? data.provenance.value
          : this.provenance,
      provenanceDetail: data.provenanceDetail.present
          ? data.provenanceDetail.value
          : this.provenanceDetail,
      sourceMessageId: data.sourceMessageId.present
          ? data.sourceMessageId.value
          : this.sourceMessageId,
      rulePackId: data.rulePackId.present
          ? data.rulePackId.value
          : this.rulePackId,
      rulePackVersion: data.rulePackVersion.present
          ? data.rulePackVersion.value
          : this.rulePackVersion,
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      needsReview: data.needsReview.present
          ? data.needsReview.value
          : this.needsReview,
      reviewReason: data.reviewReason.present
          ? data.reviewReason.value
          : this.reviewReason,
      possibleDuplicateOfId: data.possibleDuplicateOfId.present
          ? data.possibleDuplicateOfId.value
          : this.possibleDuplicateOfId,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionRow(')
          ..write('id: $id, ')
          ..write('merchantRawText: $merchantRawText, ')
          ..write('amountAmount: $amountAmount, ')
          ..write('amountCurrency: $amountCurrency, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('categoryId: $categoryId, ')
          ..write('convertedAmountAmount: $convertedAmountAmount, ')
          ..write('convertedAmountCurrency: $convertedAmountCurrency, ')
          ..write('convertedAmountMinor: $convertedAmountMinor, ')
          ..write('feeAmountAmount: $feeAmountAmount, ')
          ..write('feeAmountCurrency: $feeAmountCurrency, ')
          ..write('feeAmountMinor: $feeAmountMinor, ')
          ..write('fxRate: $fxRate, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('timeSource: $timeSource, ')
          ..write('direction: $direction, ')
          ..write('transactionType: $transactionType, ')
          ..write('affectsSpend: $affectsSpend, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('instrumentKind: $instrumentKind, ')
          ..write('instrumentMaskedRef: $instrumentMaskedRef, ')
          ..write('instrumentId: $instrumentId, ')
          ..write('counterpartyName: $counterpartyName, ')
          ..write('counterpartyBankName: $counterpartyBankName, ')
          ..write('remainingBalanceAmount: $remainingBalanceAmount, ')
          ..write('remainingBalanceCurrency: $remainingBalanceCurrency, ')
          ..write('remainingBalanceMinor: $remainingBalanceMinor, ')
          ..write('provenance: $provenance, ')
          ..write('provenanceDetail: $provenanceDetail, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('rulePackId: $rulePackId, ')
          ..write('rulePackVersion: $rulePackVersion, ')
          ..write('ruleId: $ruleId, ')
          ..write('needsReview: $needsReview, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('possibleDuplicateOfId: $possibleDuplicateOfId, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    merchantRawText,
    amountAmount,
    amountCurrency,
    amountMinor,
    categoryId,
    convertedAmountAmount,
    convertedAmountCurrency,
    convertedAmountMinor,
    feeAmountAmount,
    feeAmountCurrency,
    feeAmountMinor,
    fxRate,
    occurredAt,
    timeSource,
    direction,
    transactionType,
    affectsSpend,
    referenceNumber,
    instrumentKind,
    instrumentMaskedRef,
    instrumentId,
    counterpartyName,
    counterpartyBankName,
    remainingBalanceAmount,
    remainingBalanceCurrency,
    remainingBalanceMinor,
    provenance,
    provenanceDetail,
    sourceMessageId,
    rulePackId,
    rulePackVersion,
    ruleId,
    needsReview,
    reviewReason,
    possibleDuplicateOfId,
    isDeleted,
    deletedAt,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionRow &&
          other.id == this.id &&
          other.merchantRawText == this.merchantRawText &&
          other.amountAmount == this.amountAmount &&
          other.amountCurrency == this.amountCurrency &&
          other.amountMinor == this.amountMinor &&
          other.categoryId == this.categoryId &&
          other.convertedAmountAmount == this.convertedAmountAmount &&
          other.convertedAmountCurrency == this.convertedAmountCurrency &&
          other.convertedAmountMinor == this.convertedAmountMinor &&
          other.feeAmountAmount == this.feeAmountAmount &&
          other.feeAmountCurrency == this.feeAmountCurrency &&
          other.feeAmountMinor == this.feeAmountMinor &&
          other.fxRate == this.fxRate &&
          other.occurredAt == this.occurredAt &&
          other.timeSource == this.timeSource &&
          other.direction == this.direction &&
          other.transactionType == this.transactionType &&
          other.affectsSpend == this.affectsSpend &&
          other.referenceNumber == this.referenceNumber &&
          other.instrumentKind == this.instrumentKind &&
          other.instrumentMaskedRef == this.instrumentMaskedRef &&
          other.instrumentId == this.instrumentId &&
          other.counterpartyName == this.counterpartyName &&
          other.counterpartyBankName == this.counterpartyBankName &&
          other.remainingBalanceAmount == this.remainingBalanceAmount &&
          other.remainingBalanceCurrency == this.remainingBalanceCurrency &&
          other.remainingBalanceMinor == this.remainingBalanceMinor &&
          other.provenance == this.provenance &&
          other.provenanceDetail == this.provenanceDetail &&
          other.sourceMessageId == this.sourceMessageId &&
          other.rulePackId == this.rulePackId &&
          other.rulePackVersion == this.rulePackVersion &&
          other.ruleId == this.ruleId &&
          other.needsReview == this.needsReview &&
          other.reviewReason == this.reviewReason &&
          other.possibleDuplicateOfId == this.possibleDuplicateOfId &&
          other.isDeleted == this.isDeleted &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TransactionsCompanion extends UpdateCompanion<TransactionRow> {
  final Value<int> id;
  final Value<String?> merchantRawText;
  final Value<String> amountAmount;
  final Value<String> amountCurrency;
  final Value<int> amountMinor;
  final Value<String?> categoryId;
  final Value<String?> convertedAmountAmount;
  final Value<String?> convertedAmountCurrency;
  final Value<int?> convertedAmountMinor;
  final Value<String?> feeAmountAmount;
  final Value<String?> feeAmountCurrency;
  final Value<int?> feeAmountMinor;
  final Value<String?> fxRate;
  final Value<DateTime?> occurredAt;
  final Value<String?> timeSource;
  final Value<String> direction;
  final Value<String> transactionType;
  final Value<bool> affectsSpend;
  final Value<String?> referenceNumber;
  final Value<String?> instrumentKind;
  final Value<String?> instrumentMaskedRef;
  final Value<int?> instrumentId;
  final Value<String?> counterpartyName;
  final Value<String?> counterpartyBankName;
  final Value<String?> remainingBalanceAmount;
  final Value<String?> remainingBalanceCurrency;
  final Value<int?> remainingBalanceMinor;
  final Value<String> provenance;
  final Value<String?> provenanceDetail;
  final Value<int?> sourceMessageId;
  final Value<String?> rulePackId;
  final Value<String?> rulePackVersion;
  final Value<String?> ruleId;
  final Value<bool> needsReview;
  final Value<String?> reviewReason;
  final Value<int?> possibleDuplicateOfId;
  final Value<bool> isDeleted;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.merchantRawText = const Value.absent(),
    this.amountAmount = const Value.absent(),
    this.amountCurrency = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.convertedAmountAmount = const Value.absent(),
    this.convertedAmountCurrency = const Value.absent(),
    this.convertedAmountMinor = const Value.absent(),
    this.feeAmountAmount = const Value.absent(),
    this.feeAmountCurrency = const Value.absent(),
    this.feeAmountMinor = const Value.absent(),
    this.fxRate = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.timeSource = const Value.absent(),
    this.direction = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.affectsSpend = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.instrumentKind = const Value.absent(),
    this.instrumentMaskedRef = const Value.absent(),
    this.instrumentId = const Value.absent(),
    this.counterpartyName = const Value.absent(),
    this.counterpartyBankName = const Value.absent(),
    this.remainingBalanceAmount = const Value.absent(),
    this.remainingBalanceCurrency = const Value.absent(),
    this.remainingBalanceMinor = const Value.absent(),
    this.provenance = const Value.absent(),
    this.provenanceDetail = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.rulePackId = const Value.absent(),
    this.rulePackVersion = const Value.absent(),
    this.ruleId = const Value.absent(),
    this.needsReview = const Value.absent(),
    this.reviewReason = const Value.absent(),
    this.possibleDuplicateOfId = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    this.merchantRawText = const Value.absent(),
    required String amountAmount,
    required String amountCurrency,
    required int amountMinor,
    this.categoryId = const Value.absent(),
    this.convertedAmountAmount = const Value.absent(),
    this.convertedAmountCurrency = const Value.absent(),
    this.convertedAmountMinor = const Value.absent(),
    this.feeAmountAmount = const Value.absent(),
    this.feeAmountCurrency = const Value.absent(),
    this.feeAmountMinor = const Value.absent(),
    this.fxRate = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.timeSource = const Value.absent(),
    this.direction = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.affectsSpend = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.instrumentKind = const Value.absent(),
    this.instrumentMaskedRef = const Value.absent(),
    this.instrumentId = const Value.absent(),
    this.counterpartyName = const Value.absent(),
    this.counterpartyBankName = const Value.absent(),
    this.remainingBalanceAmount = const Value.absent(),
    this.remainingBalanceCurrency = const Value.absent(),
    this.remainingBalanceMinor = const Value.absent(),
    this.provenance = const Value.absent(),
    this.provenanceDetail = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.rulePackId = const Value.absent(),
    this.rulePackVersion = const Value.absent(),
    this.ruleId = const Value.absent(),
    this.needsReview = const Value.absent(),
    this.reviewReason = const Value.absent(),
    this.possibleDuplicateOfId = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : amountAmount = Value(amountAmount),
       amountCurrency = Value(amountCurrency),
       amountMinor = Value(amountMinor);
  static Insertable<TransactionRow> custom({
    Expression<int>? id,
    Expression<String>? merchantRawText,
    Expression<String>? amountAmount,
    Expression<String>? amountCurrency,
    Expression<int>? amountMinor,
    Expression<String>? categoryId,
    Expression<String>? convertedAmountAmount,
    Expression<String>? convertedAmountCurrency,
    Expression<int>? convertedAmountMinor,
    Expression<String>? feeAmountAmount,
    Expression<String>? feeAmountCurrency,
    Expression<int>? feeAmountMinor,
    Expression<String>? fxRate,
    Expression<DateTime>? occurredAt,
    Expression<String>? timeSource,
    Expression<String>? direction,
    Expression<String>? transactionType,
    Expression<bool>? affectsSpend,
    Expression<String>? referenceNumber,
    Expression<String>? instrumentKind,
    Expression<String>? instrumentMaskedRef,
    Expression<int>? instrumentId,
    Expression<String>? counterpartyName,
    Expression<String>? counterpartyBankName,
    Expression<String>? remainingBalanceAmount,
    Expression<String>? remainingBalanceCurrency,
    Expression<int>? remainingBalanceMinor,
    Expression<String>? provenance,
    Expression<String>? provenanceDetail,
    Expression<int>? sourceMessageId,
    Expression<String>? rulePackId,
    Expression<String>? rulePackVersion,
    Expression<String>? ruleId,
    Expression<bool>? needsReview,
    Expression<String>? reviewReason,
    Expression<int>? possibleDuplicateOfId,
    Expression<bool>? isDeleted,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (merchantRawText != null) 'merchant_raw_text': merchantRawText,
      if (amountAmount != null) 'amount_amount': amountAmount,
      if (amountCurrency != null) 'amount_currency': amountCurrency,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (categoryId != null) 'category_id': categoryId,
      if (convertedAmountAmount != null)
        'converted_amount_amount': convertedAmountAmount,
      if (convertedAmountCurrency != null)
        'converted_amount_currency': convertedAmountCurrency,
      if (convertedAmountMinor != null)
        'converted_amount_minor': convertedAmountMinor,
      if (feeAmountAmount != null) 'fee_amount_amount': feeAmountAmount,
      if (feeAmountCurrency != null) 'fee_amount_currency': feeAmountCurrency,
      if (feeAmountMinor != null) 'fee_amount_minor': feeAmountMinor,
      if (fxRate != null) 'fx_rate': fxRate,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (timeSource != null) 'time_source': timeSource,
      if (direction != null) 'direction': direction,
      if (transactionType != null) 'transaction_type': transactionType,
      if (affectsSpend != null) 'affects_spend': affectsSpend,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (instrumentKind != null) 'instrument_kind': instrumentKind,
      if (instrumentMaskedRef != null)
        'instrument_masked_ref': instrumentMaskedRef,
      if (instrumentId != null) 'instrument_id': instrumentId,
      if (counterpartyName != null) 'counterparty_name': counterpartyName,
      if (counterpartyBankName != null)
        'counterparty_bank_name': counterpartyBankName,
      if (remainingBalanceAmount != null)
        'remaining_balance_amount': remainingBalanceAmount,
      if (remainingBalanceCurrency != null)
        'remaining_balance_currency': remainingBalanceCurrency,
      if (remainingBalanceMinor != null)
        'remaining_balance_minor': remainingBalanceMinor,
      if (provenance != null) 'provenance': provenance,
      if (provenanceDetail != null) 'provenance_detail': provenanceDetail,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (rulePackId != null) 'rule_pack_id': rulePackId,
      if (rulePackVersion != null) 'rule_pack_version': rulePackVersion,
      if (ruleId != null) 'rule_id': ruleId,
      if (needsReview != null) 'needs_review': needsReview,
      if (reviewReason != null) 'review_reason': reviewReason,
      if (possibleDuplicateOfId != null)
        'possible_duplicate_of_id': possibleDuplicateOfId,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TransactionsCompanion copyWith({
    Value<int>? id,
    Value<String?>? merchantRawText,
    Value<String>? amountAmount,
    Value<String>? amountCurrency,
    Value<int>? amountMinor,
    Value<String?>? categoryId,
    Value<String?>? convertedAmountAmount,
    Value<String?>? convertedAmountCurrency,
    Value<int?>? convertedAmountMinor,
    Value<String?>? feeAmountAmount,
    Value<String?>? feeAmountCurrency,
    Value<int?>? feeAmountMinor,
    Value<String?>? fxRate,
    Value<DateTime?>? occurredAt,
    Value<String?>? timeSource,
    Value<String>? direction,
    Value<String>? transactionType,
    Value<bool>? affectsSpend,
    Value<String?>? referenceNumber,
    Value<String?>? instrumentKind,
    Value<String?>? instrumentMaskedRef,
    Value<int?>? instrumentId,
    Value<String?>? counterpartyName,
    Value<String?>? counterpartyBankName,
    Value<String?>? remainingBalanceAmount,
    Value<String?>? remainingBalanceCurrency,
    Value<int?>? remainingBalanceMinor,
    Value<String>? provenance,
    Value<String?>? provenanceDetail,
    Value<int?>? sourceMessageId,
    Value<String?>? rulePackId,
    Value<String?>? rulePackVersion,
    Value<String?>? ruleId,
    Value<bool>? needsReview,
    Value<String?>? reviewReason,
    Value<int?>? possibleDuplicateOfId,
    Value<bool>? isDeleted,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      merchantRawText: merchantRawText ?? this.merchantRawText,
      amountAmount: amountAmount ?? this.amountAmount,
      amountCurrency: amountCurrency ?? this.amountCurrency,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryId: categoryId ?? this.categoryId,
      convertedAmountAmount:
          convertedAmountAmount ?? this.convertedAmountAmount,
      convertedAmountCurrency:
          convertedAmountCurrency ?? this.convertedAmountCurrency,
      convertedAmountMinor: convertedAmountMinor ?? this.convertedAmountMinor,
      feeAmountAmount: feeAmountAmount ?? this.feeAmountAmount,
      feeAmountCurrency: feeAmountCurrency ?? this.feeAmountCurrency,
      feeAmountMinor: feeAmountMinor ?? this.feeAmountMinor,
      fxRate: fxRate ?? this.fxRate,
      occurredAt: occurredAt ?? this.occurredAt,
      timeSource: timeSource ?? this.timeSource,
      direction: direction ?? this.direction,
      transactionType: transactionType ?? this.transactionType,
      affectsSpend: affectsSpend ?? this.affectsSpend,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      instrumentKind: instrumentKind ?? this.instrumentKind,
      instrumentMaskedRef: instrumentMaskedRef ?? this.instrumentMaskedRef,
      instrumentId: instrumentId ?? this.instrumentId,
      counterpartyName: counterpartyName ?? this.counterpartyName,
      counterpartyBankName: counterpartyBankName ?? this.counterpartyBankName,
      remainingBalanceAmount:
          remainingBalanceAmount ?? this.remainingBalanceAmount,
      remainingBalanceCurrency:
          remainingBalanceCurrency ?? this.remainingBalanceCurrency,
      remainingBalanceMinor:
          remainingBalanceMinor ?? this.remainingBalanceMinor,
      provenance: provenance ?? this.provenance,
      provenanceDetail: provenanceDetail ?? this.provenanceDetail,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      rulePackId: rulePackId ?? this.rulePackId,
      rulePackVersion: rulePackVersion ?? this.rulePackVersion,
      ruleId: ruleId ?? this.ruleId,
      needsReview: needsReview ?? this.needsReview,
      reviewReason: reviewReason ?? this.reviewReason,
      possibleDuplicateOfId:
          possibleDuplicateOfId ?? this.possibleDuplicateOfId,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (merchantRawText.present) {
      map['merchant_raw_text'] = Variable<String>(merchantRawText.value);
    }
    if (amountAmount.present) {
      map['amount_amount'] = Variable<String>(amountAmount.value);
    }
    if (amountCurrency.present) {
      map['amount_currency'] = Variable<String>(amountCurrency.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (convertedAmountAmount.present) {
      map['converted_amount_amount'] = Variable<String>(
        convertedAmountAmount.value,
      );
    }
    if (convertedAmountCurrency.present) {
      map['converted_amount_currency'] = Variable<String>(
        convertedAmountCurrency.value,
      );
    }
    if (convertedAmountMinor.present) {
      map['converted_amount_minor'] = Variable<int>(convertedAmountMinor.value);
    }
    if (feeAmountAmount.present) {
      map['fee_amount_amount'] = Variable<String>(feeAmountAmount.value);
    }
    if (feeAmountCurrency.present) {
      map['fee_amount_currency'] = Variable<String>(feeAmountCurrency.value);
    }
    if (feeAmountMinor.present) {
      map['fee_amount_minor'] = Variable<int>(feeAmountMinor.value);
    }
    if (fxRate.present) {
      map['fx_rate'] = Variable<String>(fxRate.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (timeSource.present) {
      map['time_source'] = Variable<String>(timeSource.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (transactionType.present) {
      map['transaction_type'] = Variable<String>(transactionType.value);
    }
    if (affectsSpend.present) {
      map['affects_spend'] = Variable<bool>(affectsSpend.value);
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (instrumentKind.present) {
      map['instrument_kind'] = Variable<String>(instrumentKind.value);
    }
    if (instrumentMaskedRef.present) {
      map['instrument_masked_ref'] = Variable<String>(
        instrumentMaskedRef.value,
      );
    }
    if (instrumentId.present) {
      map['instrument_id'] = Variable<int>(instrumentId.value);
    }
    if (counterpartyName.present) {
      map['counterparty_name'] = Variable<String>(counterpartyName.value);
    }
    if (counterpartyBankName.present) {
      map['counterparty_bank_name'] = Variable<String>(
        counterpartyBankName.value,
      );
    }
    if (remainingBalanceAmount.present) {
      map['remaining_balance_amount'] = Variable<String>(
        remainingBalanceAmount.value,
      );
    }
    if (remainingBalanceCurrency.present) {
      map['remaining_balance_currency'] = Variable<String>(
        remainingBalanceCurrency.value,
      );
    }
    if (remainingBalanceMinor.present) {
      map['remaining_balance_minor'] = Variable<int>(
        remainingBalanceMinor.value,
      );
    }
    if (provenance.present) {
      map['provenance'] = Variable<String>(provenance.value);
    }
    if (provenanceDetail.present) {
      map['provenance_detail'] = Variable<String>(provenanceDetail.value);
    }
    if (sourceMessageId.present) {
      map['source_message_id'] = Variable<int>(sourceMessageId.value);
    }
    if (rulePackId.present) {
      map['rule_pack_id'] = Variable<String>(rulePackId.value);
    }
    if (rulePackVersion.present) {
      map['rule_pack_version'] = Variable<String>(rulePackVersion.value);
    }
    if (ruleId.present) {
      map['rule_id'] = Variable<String>(ruleId.value);
    }
    if (needsReview.present) {
      map['needs_review'] = Variable<bool>(needsReview.value);
    }
    if (reviewReason.present) {
      map['review_reason'] = Variable<String>(reviewReason.value);
    }
    if (possibleDuplicateOfId.present) {
      map['possible_duplicate_of_id'] = Variable<int>(
        possibleDuplicateOfId.value,
      );
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('merchantRawText: $merchantRawText, ')
          ..write('amountAmount: $amountAmount, ')
          ..write('amountCurrency: $amountCurrency, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('categoryId: $categoryId, ')
          ..write('convertedAmountAmount: $convertedAmountAmount, ')
          ..write('convertedAmountCurrency: $convertedAmountCurrency, ')
          ..write('convertedAmountMinor: $convertedAmountMinor, ')
          ..write('feeAmountAmount: $feeAmountAmount, ')
          ..write('feeAmountCurrency: $feeAmountCurrency, ')
          ..write('feeAmountMinor: $feeAmountMinor, ')
          ..write('fxRate: $fxRate, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('timeSource: $timeSource, ')
          ..write('direction: $direction, ')
          ..write('transactionType: $transactionType, ')
          ..write('affectsSpend: $affectsSpend, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('instrumentKind: $instrumentKind, ')
          ..write('instrumentMaskedRef: $instrumentMaskedRef, ')
          ..write('instrumentId: $instrumentId, ')
          ..write('counterpartyName: $counterpartyName, ')
          ..write('counterpartyBankName: $counterpartyBankName, ')
          ..write('remainingBalanceAmount: $remainingBalanceAmount, ')
          ..write('remainingBalanceCurrency: $remainingBalanceCurrency, ')
          ..write('remainingBalanceMinor: $remainingBalanceMinor, ')
          ..write('provenance: $provenance, ')
          ..write('provenanceDetail: $provenanceDetail, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('rulePackId: $rulePackId, ')
          ..write('rulePackVersion: $rulePackVersion, ')
          ..write('ruleId: $ruleId, ')
          ..write('needsReview: $needsReview, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('possibleDuplicateOfId: $possibleDuplicateOfId, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTableTable extends AppSettingsTable
    with TableInfo<$AppSettingsTableTable, AppSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _baseCurrencyMeta = const VerificationMeta(
    'baseCurrency',
  );
  @override
  late final GeneratedColumn<String> baseCurrency = GeneratedColumn<String>(
    'base_currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('SAR'),
  );
  static const VerificationMeta _localeMeta = const VerificationMeta('locale');
  @override
  late final GeneratedColumn<String> locale = GeneratedColumn<String>(
    'locale',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ar'),
  );
  static const VerificationMeta _lockGraceSecondsMeta = const VerificationMeta(
    'lockGraceSeconds',
  );
  @override
  late final GeneratedColumn<int> lockGraceSeconds = GeneratedColumn<int>(
    'lock_grace_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _onboardingCompleteMeta =
      const VerificationMeta('onboardingComplete');
  @override
  late final GeneratedColumn<bool> onboardingComplete = GeneratedColumn<bool>(
    'onboarding_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("onboarding_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    baseCurrency,
    locale,
    lockGraceSeconds,
    onboardingComplete,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('base_currency')) {
      context.handle(
        _baseCurrencyMeta,
        baseCurrency.isAcceptableOrUnknown(
          data['base_currency']!,
          _baseCurrencyMeta,
        ),
      );
    }
    if (data.containsKey('locale')) {
      context.handle(
        _localeMeta,
        locale.isAcceptableOrUnknown(data['locale']!, _localeMeta),
      );
    }
    if (data.containsKey('lock_grace_seconds')) {
      context.handle(
        _lockGraceSecondsMeta,
        lockGraceSeconds.isAcceptableOrUnknown(
          data['lock_grace_seconds']!,
          _lockGraceSecondsMeta,
        ),
      );
    }
    if (data.containsKey('onboarding_complete')) {
      context.handle(
        _onboardingCompleteMeta,
        onboardingComplete.isAcceptableOrUnknown(
          data['onboarding_complete']!,
          _onboardingCompleteMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      baseCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_currency'],
      )!,
      locale: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locale'],
      )!,
      lockGraceSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lock_grace_seconds'],
      )!,
      onboardingComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}onboarding_complete'],
      )!,
    );
  }

  @override
  $AppSettingsTableTable createAlias(String alias) {
    return $AppSettingsTableTable(attachedDatabase, alias);
  }
}

class AppSettingsRow extends DataClass implements Insertable<AppSettingsRow> {
  final int id;
  final String baseCurrency;
  final String locale;

  /// Seconds of grace after backgrounding before the app re-locks
  /// (ADR-005's re-lock policy). Default `0` — lock immediately.
  final int lockGraceSeconds;
  final bool onboardingComplete;
  const AppSettingsRow({
    required this.id,
    required this.baseCurrency,
    required this.locale,
    required this.lockGraceSeconds,
    required this.onboardingComplete,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['base_currency'] = Variable<String>(baseCurrency);
    map['locale'] = Variable<String>(locale);
    map['lock_grace_seconds'] = Variable<int>(lockGraceSeconds);
    map['onboarding_complete'] = Variable<bool>(onboardingComplete);
    return map;
  }

  AppSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsTableCompanion(
      id: Value(id),
      baseCurrency: Value(baseCurrency),
      locale: Value(locale),
      lockGraceSeconds: Value(lockGraceSeconds),
      onboardingComplete: Value(onboardingComplete),
    );
  }

  factory AppSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      baseCurrency: serializer.fromJson<String>(json['baseCurrency']),
      locale: serializer.fromJson<String>(json['locale']),
      lockGraceSeconds: serializer.fromJson<int>(json['lockGraceSeconds']),
      onboardingComplete: serializer.fromJson<bool>(json['onboardingComplete']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'baseCurrency': serializer.toJson<String>(baseCurrency),
      'locale': serializer.toJson<String>(locale),
      'lockGraceSeconds': serializer.toJson<int>(lockGraceSeconds),
      'onboardingComplete': serializer.toJson<bool>(onboardingComplete),
    };
  }

  AppSettingsRow copyWith({
    int? id,
    String? baseCurrency,
    String? locale,
    int? lockGraceSeconds,
    bool? onboardingComplete,
  }) => AppSettingsRow(
    id: id ?? this.id,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    locale: locale ?? this.locale,
    lockGraceSeconds: lockGraceSeconds ?? this.lockGraceSeconds,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
  );
  AppSettingsRow copyWithCompanion(AppSettingsTableCompanion data) {
    return AppSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      baseCurrency: data.baseCurrency.present
          ? data.baseCurrency.value
          : this.baseCurrency,
      locale: data.locale.present ? data.locale.value : this.locale,
      lockGraceSeconds: data.lockGraceSeconds.present
          ? data.lockGraceSeconds.value
          : this.lockGraceSeconds,
      onboardingComplete: data.onboardingComplete.present
          ? data.onboardingComplete.value
          : this.onboardingComplete,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('locale: $locale, ')
          ..write('lockGraceSeconds: $lockGraceSeconds, ')
          ..write('onboardingComplete: $onboardingComplete')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    baseCurrency,
    locale,
    lockGraceSeconds,
    onboardingComplete,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.baseCurrency == this.baseCurrency &&
          other.locale == this.locale &&
          other.lockGraceSeconds == this.lockGraceSeconds &&
          other.onboardingComplete == this.onboardingComplete);
}

class AppSettingsTableCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<String> baseCurrency;
  final Value<String> locale;
  final Value<int> lockGraceSeconds;
  final Value<bool> onboardingComplete;
  const AppSettingsTableCompanion({
    this.id = const Value.absent(),
    this.baseCurrency = const Value.absent(),
    this.locale = const Value.absent(),
    this.lockGraceSeconds = const Value.absent(),
    this.onboardingComplete = const Value.absent(),
  });
  AppSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.baseCurrency = const Value.absent(),
    this.locale = const Value.absent(),
    this.lockGraceSeconds = const Value.absent(),
    this.onboardingComplete = const Value.absent(),
  });
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<String>? baseCurrency,
    Expression<String>? locale,
    Expression<int>? lockGraceSeconds,
    Expression<bool>? onboardingComplete,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baseCurrency != null) 'base_currency': baseCurrency,
      if (locale != null) 'locale': locale,
      if (lockGraceSeconds != null) 'lock_grace_seconds': lockGraceSeconds,
      if (onboardingComplete != null) 'onboarding_complete': onboardingComplete,
    });
  }

  AppSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? baseCurrency,
    Value<String>? locale,
    Value<int>? lockGraceSeconds,
    Value<bool>? onboardingComplete,
  }) {
    return AppSettingsTableCompanion(
      id: id ?? this.id,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      locale: locale ?? this.locale,
      lockGraceSeconds: lockGraceSeconds ?? this.lockGraceSeconds,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (baseCurrency.present) {
      map['base_currency'] = Variable<String>(baseCurrency.value);
    }
    if (locale.present) {
      map['locale'] = Variable<String>(locale.value);
    }
    if (lockGraceSeconds.present) {
      map['lock_grace_seconds'] = Variable<int>(lockGraceSeconds.value);
    }
    if (onboardingComplete.present) {
      map['onboarding_complete'] = Variable<bool>(onboardingComplete.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('baseCurrency: $baseCurrency, ')
          ..write('locale: $locale, ')
          ..write('lockGraceSeconds: $lockGraceSeconds, ')
          ..write('onboardingComplete: $onboardingComplete')
          ..write(')'))
        .toString();
  }
}

class $IngestWatermarksTable extends IngestWatermarks
    with TableInfo<$IngestWatermarksTable, IngestWatermarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IngestWatermarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(ingestWatermarkSingletonId),
  );
  static const VerificationMeta _lastProcessedSmsProviderIdMeta =
      const VerificationMeta('lastProcessedSmsProviderId');
  @override
  late final GeneratedColumn<int> lastProcessedSmsProviderId =
      GeneratedColumn<int>(
        'last_processed_sms_provider_id',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _lastProcessedSmsDateMeta =
      const VerificationMeta('lastProcessedSmsDate');
  @override
  late final GeneratedColumn<DateTime> lastProcessedSmsDate =
      GeneratedColumn<DateTime>(
        'last_processed_sms_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _importStateMeta = const VerificationMeta(
    'importState',
  );
  @override
  late final GeneratedColumn<String> importState = GeneratedColumn<String>(
    'import_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('idle'),
  );
  static const VerificationMeta _importCursorMeta = const VerificationMeta(
    'importCursor',
  );
  @override
  late final GeneratedColumn<int> importCursor = GeneratedColumn<int>(
    'import_cursor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importFromDateMeta = const VerificationMeta(
    'importFromDate',
  );
  @override
  late final GeneratedColumn<DateTime> importFromDate =
      GeneratedColumn<DateTime>(
        'import_from_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _importTotalCandidatesMeta =
      const VerificationMeta('importTotalCandidates');
  @override
  late final GeneratedColumn<int> importTotalCandidates = GeneratedColumn<int>(
    'import_total_candidates',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importProcessedCountMeta =
      const VerificationMeta('importProcessedCount');
  @override
  late final GeneratedColumn<int> importProcessedCount = GeneratedColumn<int>(
    'import_processed_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastProcessedSmsProviderId,
    lastProcessedSmsDate,
    importState,
    importCursor,
    importFromDate,
    importTotalCandidates,
    importProcessedCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingest_watermark';
  @override
  VerificationContext validateIntegrity(
    Insertable<IngestWatermarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_processed_sms_provider_id')) {
      context.handle(
        _lastProcessedSmsProviderIdMeta,
        lastProcessedSmsProviderId.isAcceptableOrUnknown(
          data['last_processed_sms_provider_id']!,
          _lastProcessedSmsProviderIdMeta,
        ),
      );
    }
    if (data.containsKey('last_processed_sms_date')) {
      context.handle(
        _lastProcessedSmsDateMeta,
        lastProcessedSmsDate.isAcceptableOrUnknown(
          data['last_processed_sms_date']!,
          _lastProcessedSmsDateMeta,
        ),
      );
    }
    if (data.containsKey('import_state')) {
      context.handle(
        _importStateMeta,
        importState.isAcceptableOrUnknown(
          data['import_state']!,
          _importStateMeta,
        ),
      );
    }
    if (data.containsKey('import_cursor')) {
      context.handle(
        _importCursorMeta,
        importCursor.isAcceptableOrUnknown(
          data['import_cursor']!,
          _importCursorMeta,
        ),
      );
    }
    if (data.containsKey('import_from_date')) {
      context.handle(
        _importFromDateMeta,
        importFromDate.isAcceptableOrUnknown(
          data['import_from_date']!,
          _importFromDateMeta,
        ),
      );
    }
    if (data.containsKey('import_total_candidates')) {
      context.handle(
        _importTotalCandidatesMeta,
        importTotalCandidates.isAcceptableOrUnknown(
          data['import_total_candidates']!,
          _importTotalCandidatesMeta,
        ),
      );
    }
    if (data.containsKey('import_processed_count')) {
      context.handle(
        _importProcessedCountMeta,
        importProcessedCount.isAcceptableOrUnknown(
          data['import_processed_count']!,
          _importProcessedCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IngestWatermarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IngestWatermarkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastProcessedSmsProviderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_processed_sms_provider_id'],
      )!,
      lastProcessedSmsDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_processed_sms_date'],
      ),
      importState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_state'],
      )!,
      importCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_cursor'],
      ),
      importFromDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}import_from_date'],
      ),
      importTotalCandidates: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_total_candidates'],
      ),
      importProcessedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_processed_count'],
      )!,
    );
  }

  @override
  $IngestWatermarksTable createAlias(String alias) {
    return $IngestWatermarksTable(attachedDatabase, alias);
  }
}

class IngestWatermarkRow extends DataClass
    implements Insertable<IngestWatermarkRow> {
  /// Fixed at [ingestWatermarkSingletonId] and enforced by the CHECK
  /// constraint in [customConstraints] — two watermark rows would mean two
  /// answers to "where did we get to", and whichever one a given code path
  /// read first would silently win.
  final int id;

  /// The `_id` of the newest SMS provider row processed. Used together with
  /// [lastProcessedSmsDate] because neither alone is sufficient: two messages
  /// can share a `date` to the millisecond (a multi-part SMS, or a carrier
  /// burst), and `_id` is monotonic but is reset when the user's SMS database
  /// is restored from a backup.
  final int lastProcessedSmsProviderId;

  /// The `date` of the newest processed message. Stored, like every instant
  /// in this schema, in UTC.
  final DateTime? lastProcessedSmsDate;

  /// `idle` | `running` | `paused` | `completed` — the historical import's
  /// state machine (architecture §4.2 `IngestWatermark`). The constants live
  /// in `IngestWatermarkDao`; the transition diagram is there too.
  ///
  /// `completed` is a **terminal** state and is deliberately not the same
  /// value as the initial `idle`. Reusing `idle` to mean "finished" made a
  /// completed import indistinguishable from one that had never started, so
  /// every app foreground re-ran the whole month's backfill. See
  /// `IngestWatermarkDao.completeImport`.
  ///
  /// Persisted rather than held in memory precisely because AC-A3.3 requires
  /// the import to survive the app being closed or the device restarting. An
  /// in-memory flag would report `idle` after a crash and silently restart
  /// the whole import from scratch.
  final String importState;

  /// How far the historical import has walked **backwards** through the
  /// inbox: the oldest provider `_id` it has already handled. Resuming means
  /// continuing from here rather than from the top.
  final int? importCursor;

  /// The lower bound of the historical import — **the start of the current
  /// calendar month in `Asia/Riyadh`** (AC-A3.1, OQ-11 resolved: not full
  /// history).
  ///
  /// Frozen at the moment the import starts rather than recomputed on each
  /// resume, so an import that spans midnight on the 1st does not silently
  /// change its own goalposts halfway through.
  final DateTime? importFromDate;

  /// Progress reporting for the S-05 onboarding screen (AC-A3.2). Counts, not
  /// content — nothing here is sensitive.
  final int? importTotalCandidates;
  final int importProcessedCount;
  const IngestWatermarkRow({
    required this.id,
    required this.lastProcessedSmsProviderId,
    this.lastProcessedSmsDate,
    required this.importState,
    this.importCursor,
    this.importFromDate,
    this.importTotalCandidates,
    required this.importProcessedCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['last_processed_sms_provider_id'] = Variable<int>(
      lastProcessedSmsProviderId,
    );
    if (!nullToAbsent || lastProcessedSmsDate != null) {
      map['last_processed_sms_date'] = Variable<DateTime>(lastProcessedSmsDate);
    }
    map['import_state'] = Variable<String>(importState);
    if (!nullToAbsent || importCursor != null) {
      map['import_cursor'] = Variable<int>(importCursor);
    }
    if (!nullToAbsent || importFromDate != null) {
      map['import_from_date'] = Variable<DateTime>(importFromDate);
    }
    if (!nullToAbsent || importTotalCandidates != null) {
      map['import_total_candidates'] = Variable<int>(importTotalCandidates);
    }
    map['import_processed_count'] = Variable<int>(importProcessedCount);
    return map;
  }

  IngestWatermarksCompanion toCompanion(bool nullToAbsent) {
    return IngestWatermarksCompanion(
      id: Value(id),
      lastProcessedSmsProviderId: Value(lastProcessedSmsProviderId),
      lastProcessedSmsDate: lastProcessedSmsDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastProcessedSmsDate),
      importState: Value(importState),
      importCursor: importCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(importCursor),
      importFromDate: importFromDate == null && nullToAbsent
          ? const Value.absent()
          : Value(importFromDate),
      importTotalCandidates: importTotalCandidates == null && nullToAbsent
          ? const Value.absent()
          : Value(importTotalCandidates),
      importProcessedCount: Value(importProcessedCount),
    );
  }

  factory IngestWatermarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IngestWatermarkRow(
      id: serializer.fromJson<int>(json['id']),
      lastProcessedSmsProviderId: serializer.fromJson<int>(
        json['lastProcessedSmsProviderId'],
      ),
      lastProcessedSmsDate: serializer.fromJson<DateTime?>(
        json['lastProcessedSmsDate'],
      ),
      importState: serializer.fromJson<String>(json['importState']),
      importCursor: serializer.fromJson<int?>(json['importCursor']),
      importFromDate: serializer.fromJson<DateTime?>(json['importFromDate']),
      importTotalCandidates: serializer.fromJson<int?>(
        json['importTotalCandidates'],
      ),
      importProcessedCount: serializer.fromJson<int>(
        json['importProcessedCount'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastProcessedSmsProviderId': serializer.toJson<int>(
        lastProcessedSmsProviderId,
      ),
      'lastProcessedSmsDate': serializer.toJson<DateTime?>(
        lastProcessedSmsDate,
      ),
      'importState': serializer.toJson<String>(importState),
      'importCursor': serializer.toJson<int?>(importCursor),
      'importFromDate': serializer.toJson<DateTime?>(importFromDate),
      'importTotalCandidates': serializer.toJson<int?>(importTotalCandidates),
      'importProcessedCount': serializer.toJson<int>(importProcessedCount),
    };
  }

  IngestWatermarkRow copyWith({
    int? id,
    int? lastProcessedSmsProviderId,
    Value<DateTime?> lastProcessedSmsDate = const Value.absent(),
    String? importState,
    Value<int?> importCursor = const Value.absent(),
    Value<DateTime?> importFromDate = const Value.absent(),
    Value<int?> importTotalCandidates = const Value.absent(),
    int? importProcessedCount,
  }) => IngestWatermarkRow(
    id: id ?? this.id,
    lastProcessedSmsProviderId:
        lastProcessedSmsProviderId ?? this.lastProcessedSmsProviderId,
    lastProcessedSmsDate: lastProcessedSmsDate.present
        ? lastProcessedSmsDate.value
        : this.lastProcessedSmsDate,
    importState: importState ?? this.importState,
    importCursor: importCursor.present ? importCursor.value : this.importCursor,
    importFromDate: importFromDate.present
        ? importFromDate.value
        : this.importFromDate,
    importTotalCandidates: importTotalCandidates.present
        ? importTotalCandidates.value
        : this.importTotalCandidates,
    importProcessedCount: importProcessedCount ?? this.importProcessedCount,
  );
  IngestWatermarkRow copyWithCompanion(IngestWatermarksCompanion data) {
    return IngestWatermarkRow(
      id: data.id.present ? data.id.value : this.id,
      lastProcessedSmsProviderId: data.lastProcessedSmsProviderId.present
          ? data.lastProcessedSmsProviderId.value
          : this.lastProcessedSmsProviderId,
      lastProcessedSmsDate: data.lastProcessedSmsDate.present
          ? data.lastProcessedSmsDate.value
          : this.lastProcessedSmsDate,
      importState: data.importState.present
          ? data.importState.value
          : this.importState,
      importCursor: data.importCursor.present
          ? data.importCursor.value
          : this.importCursor,
      importFromDate: data.importFromDate.present
          ? data.importFromDate.value
          : this.importFromDate,
      importTotalCandidates: data.importTotalCandidates.present
          ? data.importTotalCandidates.value
          : this.importTotalCandidates,
      importProcessedCount: data.importProcessedCount.present
          ? data.importProcessedCount.value
          : this.importProcessedCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IngestWatermarkRow(')
          ..write('id: $id, ')
          ..write('lastProcessedSmsProviderId: $lastProcessedSmsProviderId, ')
          ..write('lastProcessedSmsDate: $lastProcessedSmsDate, ')
          ..write('importState: $importState, ')
          ..write('importCursor: $importCursor, ')
          ..write('importFromDate: $importFromDate, ')
          ..write('importTotalCandidates: $importTotalCandidates, ')
          ..write('importProcessedCount: $importProcessedCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lastProcessedSmsProviderId,
    lastProcessedSmsDate,
    importState,
    importCursor,
    importFromDate,
    importTotalCandidates,
    importProcessedCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IngestWatermarkRow &&
          other.id == this.id &&
          other.lastProcessedSmsProviderId == this.lastProcessedSmsProviderId &&
          other.lastProcessedSmsDate == this.lastProcessedSmsDate &&
          other.importState == this.importState &&
          other.importCursor == this.importCursor &&
          other.importFromDate == this.importFromDate &&
          other.importTotalCandidates == this.importTotalCandidates &&
          other.importProcessedCount == this.importProcessedCount);
}

class IngestWatermarksCompanion extends UpdateCompanion<IngestWatermarkRow> {
  final Value<int> id;
  final Value<int> lastProcessedSmsProviderId;
  final Value<DateTime?> lastProcessedSmsDate;
  final Value<String> importState;
  final Value<int?> importCursor;
  final Value<DateTime?> importFromDate;
  final Value<int?> importTotalCandidates;
  final Value<int> importProcessedCount;
  const IngestWatermarksCompanion({
    this.id = const Value.absent(),
    this.lastProcessedSmsProviderId = const Value.absent(),
    this.lastProcessedSmsDate = const Value.absent(),
    this.importState = const Value.absent(),
    this.importCursor = const Value.absent(),
    this.importFromDate = const Value.absent(),
    this.importTotalCandidates = const Value.absent(),
    this.importProcessedCount = const Value.absent(),
  });
  IngestWatermarksCompanion.insert({
    this.id = const Value.absent(),
    this.lastProcessedSmsProviderId = const Value.absent(),
    this.lastProcessedSmsDate = const Value.absent(),
    this.importState = const Value.absent(),
    this.importCursor = const Value.absent(),
    this.importFromDate = const Value.absent(),
    this.importTotalCandidates = const Value.absent(),
    this.importProcessedCount = const Value.absent(),
  });
  static Insertable<IngestWatermarkRow> custom({
    Expression<int>? id,
    Expression<int>? lastProcessedSmsProviderId,
    Expression<DateTime>? lastProcessedSmsDate,
    Expression<String>? importState,
    Expression<int>? importCursor,
    Expression<DateTime>? importFromDate,
    Expression<int>? importTotalCandidates,
    Expression<int>? importProcessedCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastProcessedSmsProviderId != null)
        'last_processed_sms_provider_id': lastProcessedSmsProviderId,
      if (lastProcessedSmsDate != null)
        'last_processed_sms_date': lastProcessedSmsDate,
      if (importState != null) 'import_state': importState,
      if (importCursor != null) 'import_cursor': importCursor,
      if (importFromDate != null) 'import_from_date': importFromDate,
      if (importTotalCandidates != null)
        'import_total_candidates': importTotalCandidates,
      if (importProcessedCount != null)
        'import_processed_count': importProcessedCount,
    });
  }

  IngestWatermarksCompanion copyWith({
    Value<int>? id,
    Value<int>? lastProcessedSmsProviderId,
    Value<DateTime?>? lastProcessedSmsDate,
    Value<String>? importState,
    Value<int?>? importCursor,
    Value<DateTime?>? importFromDate,
    Value<int?>? importTotalCandidates,
    Value<int>? importProcessedCount,
  }) {
    return IngestWatermarksCompanion(
      id: id ?? this.id,
      lastProcessedSmsProviderId:
          lastProcessedSmsProviderId ?? this.lastProcessedSmsProviderId,
      lastProcessedSmsDate: lastProcessedSmsDate ?? this.lastProcessedSmsDate,
      importState: importState ?? this.importState,
      importCursor: importCursor ?? this.importCursor,
      importFromDate: importFromDate ?? this.importFromDate,
      importTotalCandidates:
          importTotalCandidates ?? this.importTotalCandidates,
      importProcessedCount: importProcessedCount ?? this.importProcessedCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastProcessedSmsProviderId.present) {
      map['last_processed_sms_provider_id'] = Variable<int>(
        lastProcessedSmsProviderId.value,
      );
    }
    if (lastProcessedSmsDate.present) {
      map['last_processed_sms_date'] = Variable<DateTime>(
        lastProcessedSmsDate.value,
      );
    }
    if (importState.present) {
      map['import_state'] = Variable<String>(importState.value);
    }
    if (importCursor.present) {
      map['import_cursor'] = Variable<int>(importCursor.value);
    }
    if (importFromDate.present) {
      map['import_from_date'] = Variable<DateTime>(importFromDate.value);
    }
    if (importTotalCandidates.present) {
      map['import_total_candidates'] = Variable<int>(
        importTotalCandidates.value,
      );
    }
    if (importProcessedCount.present) {
      map['import_processed_count'] = Variable<int>(importProcessedCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IngestWatermarksCompanion(')
          ..write('id: $id, ')
          ..write('lastProcessedSmsProviderId: $lastProcessedSmsProviderId, ')
          ..write('lastProcessedSmsDate: $lastProcessedSmsDate, ')
          ..write('importState: $importState, ')
          ..write('importCursor: $importCursor, ')
          ..write('importFromDate: $importFromDate, ')
          ..write('importTotalCandidates: $importTotalCandidates, ')
          ..write('importProcessedCount: $importProcessedCount')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AuditEntriesTable auditEntries = $AuditEntriesTable(this);
  late final $RawMessagesTable rawMessages = $RawMessagesTable(this);
  late final $BanksTable banks = $BanksTable(this);
  late final $InstrumentsTable instruments = $InstrumentsTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $AppSettingsTableTable appSettingsTable = $AppSettingsTableTable(
    this,
  );
  late final $IngestWatermarksTable ingestWatermarks = $IngestWatermarksTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    auditEntries,
    rawMessages,
    banks,
    instruments,
    transactions,
    appSettingsTable,
    ingestWatermarks,
  ];
}

typedef $$AuditEntriesTableCreateCompanionBuilder =
    AuditEntriesCompanion Function({
      Value<int> id,
      required String entityType,
      required String entityId,
      required String action,
      required String actor,
      Value<String?> actorDetail,
      required DateTime changedAt,
      required String fieldChangesJson,
      required String prevHash,
      required String entryHash,
    });
typedef $$AuditEntriesTableUpdateCompanionBuilder =
    AuditEntriesCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> action,
      Value<String> actor,
      Value<String?> actorDetail,
      Value<DateTime> changedAt,
      Value<String> fieldChangesJson,
      Value<String> prevHash,
      Value<String> entryHash,
    });

class $$AuditEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $AuditEntriesTable> {
  $$AuditEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actor => $composableBuilder(
    column: $table.actor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorDetail => $composableBuilder(
    column: $table.actorDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldChangesJson => $composableBuilder(
    column: $table.fieldChangesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prevHash => $composableBuilder(
    column: $table.prevHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryHash => $composableBuilder(
    column: $table.entryHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditEntriesTable> {
  $$AuditEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actor => $composableBuilder(
    column: $table.actor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorDetail => $composableBuilder(
    column: $table.actorDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldChangesJson => $composableBuilder(
    column: $table.fieldChangesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prevHash => $composableBuilder(
    column: $table.prevHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryHash => $composableBuilder(
    column: $table.entryHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditEntriesTable> {
  $$AuditEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get actor =>
      $composableBuilder(column: $table.actor, builder: (column) => column);

  GeneratedColumn<String> get actorDetail => $composableBuilder(
    column: $table.actorDetail,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  GeneratedColumn<String> get fieldChangesJson => $composableBuilder(
    column: $table.fieldChangesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prevHash =>
      $composableBuilder(column: $table.prevHash, builder: (column) => column);

  GeneratedColumn<String> get entryHash =>
      $composableBuilder(column: $table.entryHash, builder: (column) => column);
}

class $$AuditEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditEntriesTable,
          AuditEntryRow,
          $$AuditEntriesTableFilterComposer,
          $$AuditEntriesTableOrderingComposer,
          $$AuditEntriesTableAnnotationComposer,
          $$AuditEntriesTableCreateCompanionBuilder,
          $$AuditEntriesTableUpdateCompanionBuilder,
          (
            AuditEntryRow,
            BaseReferences<_$AppDatabase, $AuditEntriesTable, AuditEntryRow>,
          ),
          AuditEntryRow,
          PrefetchHooks Function()
        > {
  $$AuditEntriesTableTableManager(_$AppDatabase db, $AuditEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> actor = const Value.absent(),
                Value<String?> actorDetail = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<String> fieldChangesJson = const Value.absent(),
                Value<String> prevHash = const Value.absent(),
                Value<String> entryHash = const Value.absent(),
              }) => AuditEntriesCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                action: action,
                actor: actor,
                actorDetail: actorDetail,
                changedAt: changedAt,
                fieldChangesJson: fieldChangesJson,
                prevHash: prevHash,
                entryHash: entryHash,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String action,
                required String actor,
                Value<String?> actorDetail = const Value.absent(),
                required DateTime changedAt,
                required String fieldChangesJson,
                required String prevHash,
                required String entryHash,
              }) => AuditEntriesCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                action: action,
                actor: actor,
                actorDetail: actorDetail,
                changedAt: changedAt,
                fieldChangesJson: fieldChangesJson,
                prevHash: prevHash,
                entryHash: entryHash,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditEntriesTable,
      AuditEntryRow,
      $$AuditEntriesTableFilterComposer,
      $$AuditEntriesTableOrderingComposer,
      $$AuditEntriesTableAnnotationComposer,
      $$AuditEntriesTableCreateCompanionBuilder,
      $$AuditEntriesTableUpdateCompanionBuilder,
      (
        AuditEntryRow,
        BaseReferences<_$AppDatabase, $AuditEntriesTable, AuditEntryRow>,
      ),
      AuditEntryRow,
      PrefetchHooks Function()
    >;
typedef $$RawMessagesTableCreateCompanionBuilder =
    RawMessagesCompanion Function({
      Value<int> id,
      Value<String?> smsProviderId,
      required String sender,
      required DateTime receivedAt,
      Value<String?> sanitizedBody,
      required String contentHmac,
      Value<String?> bankId,
      required String classification,
      Value<bool> panRedacted,
      Value<bool> dismissedAsNotTransaction,
      Value<String?> unparsedReason,
      Value<String?> unparsedRuleId,
      Value<DateTime> createdAt,
    });
typedef $$RawMessagesTableUpdateCompanionBuilder =
    RawMessagesCompanion Function({
      Value<int> id,
      Value<String?> smsProviderId,
      Value<String> sender,
      Value<DateTime> receivedAt,
      Value<String?> sanitizedBody,
      Value<String> contentHmac,
      Value<String?> bankId,
      Value<String> classification,
      Value<bool> panRedacted,
      Value<bool> dismissedAsNotTransaction,
      Value<String?> unparsedReason,
      Value<String?> unparsedRuleId,
      Value<DateTime> createdAt,
    });

class $$RawMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smsProviderId => $composableBuilder(
    column: $table.smsProviderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sanitizedBody => $composableBuilder(
    column: $table.sanitizedBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHmac => $composableBuilder(
    column: $table.contentHmac,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get panRedacted => $composableBuilder(
    column: $table.panRedacted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dismissedAsNotTransaction => $composableBuilder(
    column: $table.dismissedAsNotTransaction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unparsedReason => $composableBuilder(
    column: $table.unparsedReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unparsedRuleId => $composableBuilder(
    column: $table.unparsedRuleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RawMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smsProviderId => $composableBuilder(
    column: $table.smsProviderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sanitizedBody => $composableBuilder(
    column: $table.sanitizedBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHmac => $composableBuilder(
    column: $table.contentHmac,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get panRedacted => $composableBuilder(
    column: $table.panRedacted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dismissedAsNotTransaction => $composableBuilder(
    column: $table.dismissedAsNotTransaction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unparsedReason => $composableBuilder(
    column: $table.unparsedReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unparsedRuleId => $composableBuilder(
    column: $table.unparsedRuleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RawMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RawMessagesTable> {
  $$RawMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get smsProviderId => $composableBuilder(
    column: $table.smsProviderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sanitizedBody => $composableBuilder(
    column: $table.sanitizedBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHmac => $composableBuilder(
    column: $table.contentHmac,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bankId =>
      $composableBuilder(column: $table.bankId, builder: (column) => column);

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get panRedacted => $composableBuilder(
    column: $table.panRedacted,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dismissedAsNotTransaction => $composableBuilder(
    column: $table.dismissedAsNotTransaction,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unparsedReason => $composableBuilder(
    column: $table.unparsedReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unparsedRuleId => $composableBuilder(
    column: $table.unparsedRuleId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$RawMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RawMessagesTable,
          RawMessageRow,
          $$RawMessagesTableFilterComposer,
          $$RawMessagesTableOrderingComposer,
          $$RawMessagesTableAnnotationComposer,
          $$RawMessagesTableCreateCompanionBuilder,
          $$RawMessagesTableUpdateCompanionBuilder,
          (
            RawMessageRow,
            BaseReferences<_$AppDatabase, $RawMessagesTable, RawMessageRow>,
          ),
          RawMessageRow,
          PrefetchHooks Function()
        > {
  $$RawMessagesTableTableManager(_$AppDatabase db, $RawMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RawMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RawMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RawMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> smsProviderId = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<String?> sanitizedBody = const Value.absent(),
                Value<String> contentHmac = const Value.absent(),
                Value<String?> bankId = const Value.absent(),
                Value<String> classification = const Value.absent(),
                Value<bool> panRedacted = const Value.absent(),
                Value<bool> dismissedAsNotTransaction = const Value.absent(),
                Value<String?> unparsedReason = const Value.absent(),
                Value<String?> unparsedRuleId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => RawMessagesCompanion(
                id: id,
                smsProviderId: smsProviderId,
                sender: sender,
                receivedAt: receivedAt,
                sanitizedBody: sanitizedBody,
                contentHmac: contentHmac,
                bankId: bankId,
                classification: classification,
                panRedacted: panRedacted,
                dismissedAsNotTransaction: dismissedAsNotTransaction,
                unparsedReason: unparsedReason,
                unparsedRuleId: unparsedRuleId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> smsProviderId = const Value.absent(),
                required String sender,
                required DateTime receivedAt,
                Value<String?> sanitizedBody = const Value.absent(),
                required String contentHmac,
                Value<String?> bankId = const Value.absent(),
                required String classification,
                Value<bool> panRedacted = const Value.absent(),
                Value<bool> dismissedAsNotTransaction = const Value.absent(),
                Value<String?> unparsedReason = const Value.absent(),
                Value<String?> unparsedRuleId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => RawMessagesCompanion.insert(
                id: id,
                smsProviderId: smsProviderId,
                sender: sender,
                receivedAt: receivedAt,
                sanitizedBody: sanitizedBody,
                contentHmac: contentHmac,
                bankId: bankId,
                classification: classification,
                panRedacted: panRedacted,
                dismissedAsNotTransaction: dismissedAsNotTransaction,
                unparsedReason: unparsedReason,
                unparsedRuleId: unparsedRuleId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RawMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RawMessagesTable,
      RawMessageRow,
      $$RawMessagesTableFilterComposer,
      $$RawMessagesTableOrderingComposer,
      $$RawMessagesTableAnnotationComposer,
      $$RawMessagesTableCreateCompanionBuilder,
      $$RawMessagesTableUpdateCompanionBuilder,
      (
        RawMessageRow,
        BaseReferences<_$AppDatabase, $RawMessagesTable, RawMessageRow>,
      ),
      RawMessageRow,
      PrefetchHooks Function()
    >;
typedef $$BanksTableCreateCompanionBuilder =
    BanksCompanion Function({
      Value<int> id,
      required String canonicalKey,
      required String displayNameAr,
      required String displayNameEn,
      Value<String> aliasesJson,
      Value<String> source,
      Value<int?> firstSeenMessageId,
      Value<DateTime> createdAt,
    });
typedef $$BanksTableUpdateCompanionBuilder =
    BanksCompanion Function({
      Value<int> id,
      Value<String> canonicalKey,
      Value<String> displayNameAr,
      Value<String> displayNameEn,
      Value<String> aliasesJson,
      Value<String> source,
      Value<int?> firstSeenMessageId,
      Value<DateTime> createdAt,
    });

class $$BanksTableFilterComposer extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayNameAr => $composableBuilder(
    column: $table.displayNameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayNameEn => $composableBuilder(
    column: $table.displayNameEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BanksTableOrderingComposer
    extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayNameAr => $composableBuilder(
    column: $table.displayNameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayNameEn => $composableBuilder(
    column: $table.displayNameEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BanksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayNameAr => $composableBuilder(
    column: $table.displayNameAr,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayNameEn => $composableBuilder(
    column: $table.displayNameEn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aliasesJson => $composableBuilder(
    column: $table.aliasesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BanksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BanksTable,
          BankRow,
          $$BanksTableFilterComposer,
          $$BanksTableOrderingComposer,
          $$BanksTableAnnotationComposer,
          $$BanksTableCreateCompanionBuilder,
          $$BanksTableUpdateCompanionBuilder,
          (BankRow, BaseReferences<_$AppDatabase, $BanksTable, BankRow>),
          BankRow,
          PrefetchHooks Function()
        > {
  $$BanksTableTableManager(_$AppDatabase db, $BanksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BanksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BanksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BanksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> canonicalKey = const Value.absent(),
                Value<String> displayNameAr = const Value.absent(),
                Value<String> displayNameEn = const Value.absent(),
                Value<String> aliasesJson = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int?> firstSeenMessageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => BanksCompanion(
                id: id,
                canonicalKey: canonicalKey,
                displayNameAr: displayNameAr,
                displayNameEn: displayNameEn,
                aliasesJson: aliasesJson,
                source: source,
                firstSeenMessageId: firstSeenMessageId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String canonicalKey,
                required String displayNameAr,
                required String displayNameEn,
                Value<String> aliasesJson = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int?> firstSeenMessageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => BanksCompanion.insert(
                id: id,
                canonicalKey: canonicalKey,
                displayNameAr: displayNameAr,
                displayNameEn: displayNameEn,
                aliasesJson: aliasesJson,
                source: source,
                firstSeenMessageId: firstSeenMessageId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BanksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BanksTable,
      BankRow,
      $$BanksTableFilterComposer,
      $$BanksTableOrderingComposer,
      $$BanksTableAnnotationComposer,
      $$BanksTableCreateCompanionBuilder,
      $$BanksTableUpdateCompanionBuilder,
      (BankRow, BaseReferences<_$AppDatabase, $BanksTable, BankRow>),
      BankRow,
      PrefetchHooks Function()
    >;
typedef $$InstrumentsTableCreateCompanionBuilder =
    InstrumentsCompanion Function({
      Value<int> id,
      required int bankId,
      required String kind,
      required String maskedIdentifier,
      required String refKey,
      Value<String?> network,
      Value<String?> cardType,
      Value<String?> friendlyName,
      Value<String?> currencyCode,
      Value<int?> settlementAccountId,
      Value<String?> linkSource,
      Value<DateTime?> linkObservedAt,
      Value<bool> isArchived,
      Value<int?> firstSeenMessageId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$InstrumentsTableUpdateCompanionBuilder =
    InstrumentsCompanion Function({
      Value<int> id,
      Value<int> bankId,
      Value<String> kind,
      Value<String> maskedIdentifier,
      Value<String> refKey,
      Value<String?> network,
      Value<String?> cardType,
      Value<String?> friendlyName,
      Value<String?> currencyCode,
      Value<int?> settlementAccountId,
      Value<String?> linkSource,
      Value<DateTime?> linkObservedAt,
      Value<bool> isArchived,
      Value<int?> firstSeenMessageId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$InstrumentsTableFilterComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get maskedIdentifier => $composableBuilder(
    column: $table.maskedIdentifier,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refKey => $composableBuilder(
    column: $table.refKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendlyName => $composableBuilder(
    column: $table.friendlyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get settlementAccountId => $composableBuilder(
    column: $table.settlementAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkSource => $composableBuilder(
    column: $table.linkSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get linkObservedAt => $composableBuilder(
    column: $table.linkObservedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstrumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get maskedIdentifier => $composableBuilder(
    column: $table.maskedIdentifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refKey => $composableBuilder(
    column: $table.refKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendlyName => $composableBuilder(
    column: $table.friendlyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get settlementAccountId => $composableBuilder(
    column: $table.settlementAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkSource => $composableBuilder(
    column: $table.linkSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get linkObservedAt => $composableBuilder(
    column: $table.linkObservedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstrumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstrumentsTable> {
  $$InstrumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get bankId =>
      $composableBuilder(column: $table.bankId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get maskedIdentifier => $composableBuilder(
    column: $table.maskedIdentifier,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refKey =>
      $composableBuilder(column: $table.refKey, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<String> get friendlyName => $composableBuilder(
    column: $table.friendlyName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get settlementAccountId => $composableBuilder(
    column: $table.settlementAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkSource => $composableBuilder(
    column: $table.linkSource,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get linkObservedAt => $composableBuilder(
    column: $table.linkObservedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSeenMessageId => $composableBuilder(
    column: $table.firstSeenMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$InstrumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstrumentsTable,
          InstrumentRow,
          $$InstrumentsTableFilterComposer,
          $$InstrumentsTableOrderingComposer,
          $$InstrumentsTableAnnotationComposer,
          $$InstrumentsTableCreateCompanionBuilder,
          $$InstrumentsTableUpdateCompanionBuilder,
          (
            InstrumentRow,
            BaseReferences<_$AppDatabase, $InstrumentsTable, InstrumentRow>,
          ),
          InstrumentRow,
          PrefetchHooks Function()
        > {
  $$InstrumentsTableTableManager(_$AppDatabase db, $InstrumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstrumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstrumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstrumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> bankId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> maskedIdentifier = const Value.absent(),
                Value<String> refKey = const Value.absent(),
                Value<String?> network = const Value.absent(),
                Value<String?> cardType = const Value.absent(),
                Value<String?> friendlyName = const Value.absent(),
                Value<String?> currencyCode = const Value.absent(),
                Value<int?> settlementAccountId = const Value.absent(),
                Value<String?> linkSource = const Value.absent(),
                Value<DateTime?> linkObservedAt = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int?> firstSeenMessageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => InstrumentsCompanion(
                id: id,
                bankId: bankId,
                kind: kind,
                maskedIdentifier: maskedIdentifier,
                refKey: refKey,
                network: network,
                cardType: cardType,
                friendlyName: friendlyName,
                currencyCode: currencyCode,
                settlementAccountId: settlementAccountId,
                linkSource: linkSource,
                linkObservedAt: linkObservedAt,
                isArchived: isArchived,
                firstSeenMessageId: firstSeenMessageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int bankId,
                required String kind,
                required String maskedIdentifier,
                required String refKey,
                Value<String?> network = const Value.absent(),
                Value<String?> cardType = const Value.absent(),
                Value<String?> friendlyName = const Value.absent(),
                Value<String?> currencyCode = const Value.absent(),
                Value<int?> settlementAccountId = const Value.absent(),
                Value<String?> linkSource = const Value.absent(),
                Value<DateTime?> linkObservedAt = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int?> firstSeenMessageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => InstrumentsCompanion.insert(
                id: id,
                bankId: bankId,
                kind: kind,
                maskedIdentifier: maskedIdentifier,
                refKey: refKey,
                network: network,
                cardType: cardType,
                friendlyName: friendlyName,
                currencyCode: currencyCode,
                settlementAccountId: settlementAccountId,
                linkSource: linkSource,
                linkObservedAt: linkObservedAt,
                isArchived: isArchived,
                firstSeenMessageId: firstSeenMessageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstrumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstrumentsTable,
      InstrumentRow,
      $$InstrumentsTableFilterComposer,
      $$InstrumentsTableOrderingComposer,
      $$InstrumentsTableAnnotationComposer,
      $$InstrumentsTableCreateCompanionBuilder,
      $$InstrumentsTableUpdateCompanionBuilder,
      (
        InstrumentRow,
        BaseReferences<_$AppDatabase, $InstrumentsTable, InstrumentRow>,
      ),
      InstrumentRow,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      Value<String?> merchantRawText,
      required String amountAmount,
      required String amountCurrency,
      required int amountMinor,
      Value<String?> categoryId,
      Value<String?> convertedAmountAmount,
      Value<String?> convertedAmountCurrency,
      Value<int?> convertedAmountMinor,
      Value<String?> feeAmountAmount,
      Value<String?> feeAmountCurrency,
      Value<int?> feeAmountMinor,
      Value<String?> fxRate,
      Value<DateTime?> occurredAt,
      Value<String?> timeSource,
      Value<String> direction,
      Value<String> transactionType,
      Value<bool> affectsSpend,
      Value<String?> referenceNumber,
      Value<String?> instrumentKind,
      Value<String?> instrumentMaskedRef,
      Value<int?> instrumentId,
      Value<String?> counterpartyName,
      Value<String?> counterpartyBankName,
      Value<String?> remainingBalanceAmount,
      Value<String?> remainingBalanceCurrency,
      Value<int?> remainingBalanceMinor,
      Value<String> provenance,
      Value<String?> provenanceDetail,
      Value<int?> sourceMessageId,
      Value<String?> rulePackId,
      Value<String?> rulePackVersion,
      Value<String?> ruleId,
      Value<bool> needsReview,
      Value<String?> reviewReason,
      Value<int?> possibleDuplicateOfId,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      Value<String?> merchantRawText,
      Value<String> amountAmount,
      Value<String> amountCurrency,
      Value<int> amountMinor,
      Value<String?> categoryId,
      Value<String?> convertedAmountAmount,
      Value<String?> convertedAmountCurrency,
      Value<int?> convertedAmountMinor,
      Value<String?> feeAmountAmount,
      Value<String?> feeAmountCurrency,
      Value<int?> feeAmountMinor,
      Value<String?> fxRate,
      Value<DateTime?> occurredAt,
      Value<String?> timeSource,
      Value<String> direction,
      Value<String> transactionType,
      Value<bool> affectsSpend,
      Value<String?> referenceNumber,
      Value<String?> instrumentKind,
      Value<String?> instrumentMaskedRef,
      Value<int?> instrumentId,
      Value<String?> counterpartyName,
      Value<String?> counterpartyBankName,
      Value<String?> remainingBalanceAmount,
      Value<String?> remainingBalanceCurrency,
      Value<int?> remainingBalanceMinor,
      Value<String> provenance,
      Value<String?> provenanceDetail,
      Value<int?> sourceMessageId,
      Value<String?> rulePackId,
      Value<String?> rulePackVersion,
      Value<String?> ruleId,
      Value<bool> needsReview,
      Value<String?> reviewReason,
      Value<int?> possibleDuplicateOfId,
      Value<bool> isDeleted,
      Value<DateTime?> deletedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get merchantRawText => $composableBuilder(
    column: $table.merchantRawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountAmount => $composableBuilder(
    column: $table.amountAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountCurrency => $composableBuilder(
    column: $table.amountCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get convertedAmountAmount => $composableBuilder(
    column: $table.convertedAmountAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get convertedAmountCurrency => $composableBuilder(
    column: $table.convertedAmountCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get convertedAmountMinor => $composableBuilder(
    column: $table.convertedAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feeAmountAmount => $composableBuilder(
    column: $table.feeAmountAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feeAmountCurrency => $composableBuilder(
    column: $table.feeAmountCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feeAmountMinor => $composableBuilder(
    column: $table.feeAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fxRate => $composableBuilder(
    column: $table.fxRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeSource => $composableBuilder(
    column: $table.timeSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get affectsSpend => $composableBuilder(
    column: $table.affectsSpend,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instrumentKind => $composableBuilder(
    column: $table.instrumentKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instrumentMaskedRef => $composableBuilder(
    column: $table.instrumentMaskedRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get instrumentId => $composableBuilder(
    column: $table.instrumentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get counterpartyName => $composableBuilder(
    column: $table.counterpartyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get counterpartyBankName => $composableBuilder(
    column: $table.counterpartyBankName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remainingBalanceAmount => $composableBuilder(
    column: $table.remainingBalanceAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remainingBalanceCurrency => $composableBuilder(
    column: $table.remainingBalanceCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remainingBalanceMinor => $composableBuilder(
    column: $table.remainingBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenanceDetail => $composableBuilder(
    column: $table.provenanceDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rulePackId => $composableBuilder(
    column: $table.rulePackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rulePackVersion => $composableBuilder(
    column: $table.rulePackVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get possibleDuplicateOfId => $composableBuilder(
    column: $table.possibleDuplicateOfId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get merchantRawText => $composableBuilder(
    column: $table.merchantRawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountAmount => $composableBuilder(
    column: $table.amountAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountCurrency => $composableBuilder(
    column: $table.amountCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get convertedAmountAmount => $composableBuilder(
    column: $table.convertedAmountAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get convertedAmountCurrency => $composableBuilder(
    column: $table.convertedAmountCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get convertedAmountMinor => $composableBuilder(
    column: $table.convertedAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feeAmountAmount => $composableBuilder(
    column: $table.feeAmountAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feeAmountCurrency => $composableBuilder(
    column: $table.feeAmountCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feeAmountMinor => $composableBuilder(
    column: $table.feeAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fxRate => $composableBuilder(
    column: $table.fxRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeSource => $composableBuilder(
    column: $table.timeSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get affectsSpend => $composableBuilder(
    column: $table.affectsSpend,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instrumentKind => $composableBuilder(
    column: $table.instrumentKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instrumentMaskedRef => $composableBuilder(
    column: $table.instrumentMaskedRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get instrumentId => $composableBuilder(
    column: $table.instrumentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get counterpartyName => $composableBuilder(
    column: $table.counterpartyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get counterpartyBankName => $composableBuilder(
    column: $table.counterpartyBankName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remainingBalanceAmount => $composableBuilder(
    column: $table.remainingBalanceAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remainingBalanceCurrency => $composableBuilder(
    column: $table.remainingBalanceCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remainingBalanceMinor => $composableBuilder(
    column: $table.remainingBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenanceDetail => $composableBuilder(
    column: $table.provenanceDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rulePackId => $composableBuilder(
    column: $table.rulePackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rulePackVersion => $composableBuilder(
    column: $table.rulePackVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get possibleDuplicateOfId => $composableBuilder(
    column: $table.possibleDuplicateOfId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get merchantRawText => $composableBuilder(
    column: $table.merchantRawText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amountAmount => $composableBuilder(
    column: $table.amountAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get amountCurrency => $composableBuilder(
    column: $table.amountCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get convertedAmountAmount => $composableBuilder(
    column: $table.convertedAmountAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get convertedAmountCurrency => $composableBuilder(
    column: $table.convertedAmountCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<int> get convertedAmountMinor => $composableBuilder(
    column: $table.convertedAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get feeAmountAmount => $composableBuilder(
    column: $table.feeAmountAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get feeAmountCurrency => $composableBuilder(
    column: $table.feeAmountCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<int> get feeAmountMinor => $composableBuilder(
    column: $table.feeAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fxRate =>
      $composableBuilder(column: $table.fxRate, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeSource => $composableBuilder(
    column: $table.timeSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get affectsSpend => $composableBuilder(
    column: $table.affectsSpend,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get instrumentKind => $composableBuilder(
    column: $table.instrumentKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get instrumentMaskedRef => $composableBuilder(
    column: $table.instrumentMaskedRef,
    builder: (column) => column,
  );

  GeneratedColumn<int> get instrumentId => $composableBuilder(
    column: $table.instrumentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get counterpartyName => $composableBuilder(
    column: $table.counterpartyName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get counterpartyBankName => $composableBuilder(
    column: $table.counterpartyBankName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remainingBalanceAmount => $composableBuilder(
    column: $table.remainingBalanceAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remainingBalanceCurrency => $composableBuilder(
    column: $table.remainingBalanceCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remainingBalanceMinor => $composableBuilder(
    column: $table.remainingBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provenanceDetail => $composableBuilder(
    column: $table.provenanceDetail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rulePackId => $composableBuilder(
    column: $table.rulePackId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rulePackVersion => $composableBuilder(
    column: $table.rulePackVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  GeneratedColumn<bool> get needsReview => $composableBuilder(
    column: $table.needsReview,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get possibleDuplicateOfId => $composableBuilder(
    column: $table.possibleDuplicateOfId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          TransactionRow,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            TransactionRow,
            BaseReferences<_$AppDatabase, $TransactionsTable, TransactionRow>,
          ),
          TransactionRow,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> merchantRawText = const Value.absent(),
                Value<String> amountAmount = const Value.absent(),
                Value<String> amountCurrency = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> convertedAmountAmount = const Value.absent(),
                Value<String?> convertedAmountCurrency = const Value.absent(),
                Value<int?> convertedAmountMinor = const Value.absent(),
                Value<String?> feeAmountAmount = const Value.absent(),
                Value<String?> feeAmountCurrency = const Value.absent(),
                Value<int?> feeAmountMinor = const Value.absent(),
                Value<String?> fxRate = const Value.absent(),
                Value<DateTime?> occurredAt = const Value.absent(),
                Value<String?> timeSource = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> transactionType = const Value.absent(),
                Value<bool> affectsSpend = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> instrumentKind = const Value.absent(),
                Value<String?> instrumentMaskedRef = const Value.absent(),
                Value<int?> instrumentId = const Value.absent(),
                Value<String?> counterpartyName = const Value.absent(),
                Value<String?> counterpartyBankName = const Value.absent(),
                Value<String?> remainingBalanceAmount = const Value.absent(),
                Value<String?> remainingBalanceCurrency = const Value.absent(),
                Value<int?> remainingBalanceMinor = const Value.absent(),
                Value<String> provenance = const Value.absent(),
                Value<String?> provenanceDetail = const Value.absent(),
                Value<int?> sourceMessageId = const Value.absent(),
                Value<String?> rulePackId = const Value.absent(),
                Value<String?> rulePackVersion = const Value.absent(),
                Value<String?> ruleId = const Value.absent(),
                Value<bool> needsReview = const Value.absent(),
                Value<String?> reviewReason = const Value.absent(),
                Value<int?> possibleDuplicateOfId = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                merchantRawText: merchantRawText,
                amountAmount: amountAmount,
                amountCurrency: amountCurrency,
                amountMinor: amountMinor,
                categoryId: categoryId,
                convertedAmountAmount: convertedAmountAmount,
                convertedAmountCurrency: convertedAmountCurrency,
                convertedAmountMinor: convertedAmountMinor,
                feeAmountAmount: feeAmountAmount,
                feeAmountCurrency: feeAmountCurrency,
                feeAmountMinor: feeAmountMinor,
                fxRate: fxRate,
                occurredAt: occurredAt,
                timeSource: timeSource,
                direction: direction,
                transactionType: transactionType,
                affectsSpend: affectsSpend,
                referenceNumber: referenceNumber,
                instrumentKind: instrumentKind,
                instrumentMaskedRef: instrumentMaskedRef,
                instrumentId: instrumentId,
                counterpartyName: counterpartyName,
                counterpartyBankName: counterpartyBankName,
                remainingBalanceAmount: remainingBalanceAmount,
                remainingBalanceCurrency: remainingBalanceCurrency,
                remainingBalanceMinor: remainingBalanceMinor,
                provenance: provenance,
                provenanceDetail: provenanceDetail,
                sourceMessageId: sourceMessageId,
                rulePackId: rulePackId,
                rulePackVersion: rulePackVersion,
                ruleId: ruleId,
                needsReview: needsReview,
                reviewReason: reviewReason,
                possibleDuplicateOfId: possibleDuplicateOfId,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> merchantRawText = const Value.absent(),
                required String amountAmount,
                required String amountCurrency,
                required int amountMinor,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> convertedAmountAmount = const Value.absent(),
                Value<String?> convertedAmountCurrency = const Value.absent(),
                Value<int?> convertedAmountMinor = const Value.absent(),
                Value<String?> feeAmountAmount = const Value.absent(),
                Value<String?> feeAmountCurrency = const Value.absent(),
                Value<int?> feeAmountMinor = const Value.absent(),
                Value<String?> fxRate = const Value.absent(),
                Value<DateTime?> occurredAt = const Value.absent(),
                Value<String?> timeSource = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> transactionType = const Value.absent(),
                Value<bool> affectsSpend = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> instrumentKind = const Value.absent(),
                Value<String?> instrumentMaskedRef = const Value.absent(),
                Value<int?> instrumentId = const Value.absent(),
                Value<String?> counterpartyName = const Value.absent(),
                Value<String?> counterpartyBankName = const Value.absent(),
                Value<String?> remainingBalanceAmount = const Value.absent(),
                Value<String?> remainingBalanceCurrency = const Value.absent(),
                Value<int?> remainingBalanceMinor = const Value.absent(),
                Value<String> provenance = const Value.absent(),
                Value<String?> provenanceDetail = const Value.absent(),
                Value<int?> sourceMessageId = const Value.absent(),
                Value<String?> rulePackId = const Value.absent(),
                Value<String?> rulePackVersion = const Value.absent(),
                Value<String?> ruleId = const Value.absent(),
                Value<bool> needsReview = const Value.absent(),
                Value<String?> reviewReason = const Value.absent(),
                Value<int?> possibleDuplicateOfId = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                merchantRawText: merchantRawText,
                amountAmount: amountAmount,
                amountCurrency: amountCurrency,
                amountMinor: amountMinor,
                categoryId: categoryId,
                convertedAmountAmount: convertedAmountAmount,
                convertedAmountCurrency: convertedAmountCurrency,
                convertedAmountMinor: convertedAmountMinor,
                feeAmountAmount: feeAmountAmount,
                feeAmountCurrency: feeAmountCurrency,
                feeAmountMinor: feeAmountMinor,
                fxRate: fxRate,
                occurredAt: occurredAt,
                timeSource: timeSource,
                direction: direction,
                transactionType: transactionType,
                affectsSpend: affectsSpend,
                referenceNumber: referenceNumber,
                instrumentKind: instrumentKind,
                instrumentMaskedRef: instrumentMaskedRef,
                instrumentId: instrumentId,
                counterpartyName: counterpartyName,
                counterpartyBankName: counterpartyBankName,
                remainingBalanceAmount: remainingBalanceAmount,
                remainingBalanceCurrency: remainingBalanceCurrency,
                remainingBalanceMinor: remainingBalanceMinor,
                provenance: provenance,
                provenanceDetail: provenanceDetail,
                sourceMessageId: sourceMessageId,
                rulePackId: rulePackId,
                rulePackVersion: rulePackVersion,
                ruleId: ruleId,
                needsReview: needsReview,
                reviewReason: reviewReason,
                possibleDuplicateOfId: possibleDuplicateOfId,
                isDeleted: isDeleted,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      TransactionRow,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        TransactionRow,
        BaseReferences<_$AppDatabase, $TransactionsTable, TransactionRow>,
      ),
      TransactionRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableTableCreateCompanionBuilder =
    AppSettingsTableCompanion Function({
      Value<int> id,
      Value<String> baseCurrency,
      Value<String> locale,
      Value<int> lockGraceSeconds,
      Value<bool> onboardingComplete,
    });
typedef $$AppSettingsTableTableUpdateCompanionBuilder =
    AppSettingsTableCompanion Function({
      Value<int> id,
      Value<String> baseCurrency,
      Value<String> locale,
      Value<int> lockGraceSeconds,
      Value<bool> onboardingComplete,
    });

class $$AppSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockGraceSeconds => $composableBuilder(
    column: $table.lockGraceSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockGraceSeconds => $composableBuilder(
    column: $table.lockGraceSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTableTable> {
  $$AppSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baseCurrency => $composableBuilder(
    column: $table.baseCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locale =>
      $composableBuilder(column: $table.locale, builder: (column) => column);

  GeneratedColumn<int> get lockGraceSeconds => $composableBuilder(
    column: $table.lockGraceSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTableTable,
          AppSettingsRow,
          $$AppSettingsTableTableFilterComposer,
          $$AppSettingsTableTableOrderingComposer,
          $$AppSettingsTableTableAnnotationComposer,
          $$AppSettingsTableTableCreateCompanionBuilder,
          $$AppSettingsTableTableUpdateCompanionBuilder,
          (
            AppSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $AppSettingsTableTable,
              AppSettingsRow
            >,
          ),
          AppSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableTableManager(
    _$AppDatabase db,
    $AppSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> baseCurrency = const Value.absent(),
                Value<String> locale = const Value.absent(),
                Value<int> lockGraceSeconds = const Value.absent(),
                Value<bool> onboardingComplete = const Value.absent(),
              }) => AppSettingsTableCompanion(
                id: id,
                baseCurrency: baseCurrency,
                locale: locale,
                lockGraceSeconds: lockGraceSeconds,
                onboardingComplete: onboardingComplete,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> baseCurrency = const Value.absent(),
                Value<String> locale = const Value.absent(),
                Value<int> lockGraceSeconds = const Value.absent(),
                Value<bool> onboardingComplete = const Value.absent(),
              }) => AppSettingsTableCompanion.insert(
                id: id,
                baseCurrency: baseCurrency,
                locale: locale,
                lockGraceSeconds: lockGraceSeconds,
                onboardingComplete: onboardingComplete,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTableTable,
      AppSettingsRow,
      $$AppSettingsTableTableFilterComposer,
      $$AppSettingsTableTableOrderingComposer,
      $$AppSettingsTableTableAnnotationComposer,
      $$AppSettingsTableTableCreateCompanionBuilder,
      $$AppSettingsTableTableUpdateCompanionBuilder,
      (
        AppSettingsRow,
        BaseReferences<_$AppDatabase, $AppSettingsTableTable, AppSettingsRow>,
      ),
      AppSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$IngestWatermarksTableCreateCompanionBuilder =
    IngestWatermarksCompanion Function({
      Value<int> id,
      Value<int> lastProcessedSmsProviderId,
      Value<DateTime?> lastProcessedSmsDate,
      Value<String> importState,
      Value<int?> importCursor,
      Value<DateTime?> importFromDate,
      Value<int?> importTotalCandidates,
      Value<int> importProcessedCount,
    });
typedef $$IngestWatermarksTableUpdateCompanionBuilder =
    IngestWatermarksCompanion Function({
      Value<int> id,
      Value<int> lastProcessedSmsProviderId,
      Value<DateTime?> lastProcessedSmsDate,
      Value<String> importState,
      Value<int?> importCursor,
      Value<DateTime?> importFromDate,
      Value<int?> importTotalCandidates,
      Value<int> importProcessedCount,
    });

class $$IngestWatermarksTableFilterComposer
    extends Composer<_$AppDatabase, $IngestWatermarksTable> {
  $$IngestWatermarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastProcessedSmsProviderId => $composableBuilder(
    column: $table.lastProcessedSmsProviderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastProcessedSmsDate => $composableBuilder(
    column: $table.lastProcessedSmsDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importState => $composableBuilder(
    column: $table.importState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importCursor => $composableBuilder(
    column: $table.importCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importFromDate => $composableBuilder(
    column: $table.importFromDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importTotalCandidates => $composableBuilder(
    column: $table.importTotalCandidates,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importProcessedCount => $composableBuilder(
    column: $table.importProcessedCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IngestWatermarksTableOrderingComposer
    extends Composer<_$AppDatabase, $IngestWatermarksTable> {
  $$IngestWatermarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastProcessedSmsProviderId => $composableBuilder(
    column: $table.lastProcessedSmsProviderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastProcessedSmsDate => $composableBuilder(
    column: $table.lastProcessedSmsDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importState => $composableBuilder(
    column: $table.importState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importCursor => $composableBuilder(
    column: $table.importCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importFromDate => $composableBuilder(
    column: $table.importFromDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importTotalCandidates => $composableBuilder(
    column: $table.importTotalCandidates,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importProcessedCount => $composableBuilder(
    column: $table.importProcessedCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IngestWatermarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $IngestWatermarksTable> {
  $$IngestWatermarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lastProcessedSmsProviderId => $composableBuilder(
    column: $table.lastProcessedSmsProviderId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastProcessedSmsDate => $composableBuilder(
    column: $table.lastProcessedSmsDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importState => $composableBuilder(
    column: $table.importState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importCursor => $composableBuilder(
    column: $table.importCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get importFromDate => $composableBuilder(
    column: $table.importFromDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importTotalCandidates => $composableBuilder(
    column: $table.importTotalCandidates,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importProcessedCount => $composableBuilder(
    column: $table.importProcessedCount,
    builder: (column) => column,
  );
}

class $$IngestWatermarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IngestWatermarksTable,
          IngestWatermarkRow,
          $$IngestWatermarksTableFilterComposer,
          $$IngestWatermarksTableOrderingComposer,
          $$IngestWatermarksTableAnnotationComposer,
          $$IngestWatermarksTableCreateCompanionBuilder,
          $$IngestWatermarksTableUpdateCompanionBuilder,
          (
            IngestWatermarkRow,
            BaseReferences<
              _$AppDatabase,
              $IngestWatermarksTable,
              IngestWatermarkRow
            >,
          ),
          IngestWatermarkRow,
          PrefetchHooks Function()
        > {
  $$IngestWatermarksTableTableManager(
    _$AppDatabase db,
    $IngestWatermarksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IngestWatermarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IngestWatermarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IngestWatermarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastProcessedSmsProviderId = const Value.absent(),
                Value<DateTime?> lastProcessedSmsDate = const Value.absent(),
                Value<String> importState = const Value.absent(),
                Value<int?> importCursor = const Value.absent(),
                Value<DateTime?> importFromDate = const Value.absent(),
                Value<int?> importTotalCandidates = const Value.absent(),
                Value<int> importProcessedCount = const Value.absent(),
              }) => IngestWatermarksCompanion(
                id: id,
                lastProcessedSmsProviderId: lastProcessedSmsProviderId,
                lastProcessedSmsDate: lastProcessedSmsDate,
                importState: importState,
                importCursor: importCursor,
                importFromDate: importFromDate,
                importTotalCandidates: importTotalCandidates,
                importProcessedCount: importProcessedCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> lastProcessedSmsProviderId = const Value.absent(),
                Value<DateTime?> lastProcessedSmsDate = const Value.absent(),
                Value<String> importState = const Value.absent(),
                Value<int?> importCursor = const Value.absent(),
                Value<DateTime?> importFromDate = const Value.absent(),
                Value<int?> importTotalCandidates = const Value.absent(),
                Value<int> importProcessedCount = const Value.absent(),
              }) => IngestWatermarksCompanion.insert(
                id: id,
                lastProcessedSmsProviderId: lastProcessedSmsProviderId,
                lastProcessedSmsDate: lastProcessedSmsDate,
                importState: importState,
                importCursor: importCursor,
                importFromDate: importFromDate,
                importTotalCandidates: importTotalCandidates,
                importProcessedCount: importProcessedCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IngestWatermarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IngestWatermarksTable,
      IngestWatermarkRow,
      $$IngestWatermarksTableFilterComposer,
      $$IngestWatermarksTableOrderingComposer,
      $$IngestWatermarksTableAnnotationComposer,
      $$IngestWatermarksTableCreateCompanionBuilder,
      $$IngestWatermarksTableUpdateCompanionBuilder,
      (
        IngestWatermarkRow,
        BaseReferences<
          _$AppDatabase,
          $IngestWatermarksTable,
          IngestWatermarkRow
        >,
      ),
      IngestWatermarkRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AuditEntriesTableTableManager get auditEntries =>
      $$AuditEntriesTableTableManager(_db, _db.auditEntries);
  $$RawMessagesTableTableManager get rawMessages =>
      $$RawMessagesTableTableManager(_db, _db.rawMessages);
  $$BanksTableTableManager get banks =>
      $$BanksTableTableManager(_db, _db.banks);
  $$InstrumentsTableTableManager get instruments =>
      $$InstrumentsTableTableManager(_db, _db.instruments);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$AppSettingsTableTableTableManager get appSettingsTable =>
      $$AppSettingsTableTableTableManager(_db, _db.appSettingsTable);
  $$IngestWatermarksTableTableManager get ingestWatermarks =>
      $$IngestWatermarksTableTableManager(_db, _db.ingestWatermarks);
}
