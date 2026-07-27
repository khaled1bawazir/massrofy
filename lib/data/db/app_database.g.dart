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
  final bool dismissedAsNotTransaction;
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
          ..write('createdAt: $createdAt')
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
    isDeleted,
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
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
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
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
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

  /// Soft delete (US-B8) — hidden from normal lists/totals but retained and
  /// restorable. Only "erase everything" (ADR-011, P8) is a true hard
  /// delete.
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TransactionRow({
    required this.id,
    this.merchantRawText,
    required this.amountAmount,
    required this.amountCurrency,
    required this.amountMinor,
    this.categoryId,
    required this.isDeleted,
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
    map['is_deleted'] = Variable<bool>(isDeleted);
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
      isDeleted: Value(isDeleted),
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
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
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
      'isDeleted': serializer.toJson<bool>(isDeleted),
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
    bool? isDeleted,
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
    isDeleted: isDeleted ?? this.isDeleted,
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
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
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
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    merchantRawText,
    amountAmount,
    amountCurrency,
    amountMinor,
    categoryId,
    isDeleted,
    createdAt,
    updatedAt,
  );
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
          other.isDeleted == this.isDeleted &&
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
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.merchantRawText = const Value.absent(),
    this.amountAmount = const Value.absent(),
    this.amountCurrency = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.isDeleted = const Value.absent(),
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
    this.isDeleted = const Value.absent(),
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
    Expression<bool>? isDeleted,
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
      if (isDeleted != null) 'is_deleted': isDeleted,
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
    Value<bool>? isDeleted,
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
      isDeleted: isDeleted ?? this.isDeleted,
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
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
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
          ..write('isDeleted: $isDeleted, ')
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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AuditEntriesTable auditEntries = $AuditEntriesTable(this);
  late final $RawMessagesTable rawMessages = $RawMessagesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $AppSettingsTableTable appSettingsTable = $AppSettingsTableTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    auditEntries,
    rawMessages,
    transactions,
    appSettingsTable,
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
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      Value<String?> merchantRawText,
      required String amountAmount,
      required String amountCurrency,
      required int amountMinor,
      Value<String?> categoryId,
      Value<bool> isDeleted,
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
      Value<bool> isDeleted,
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

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
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

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
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

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

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
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                merchantRawText: merchantRawText,
                amountAmount: amountAmount,
                amountCurrency: amountCurrency,
                amountMinor: amountMinor,
                categoryId: categoryId,
                isDeleted: isDeleted,
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
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                merchantRawText: merchantRawText,
                amountAmount: amountAmount,
                amountCurrency: amountCurrency,
                amountMinor: amountMinor,
                categoryId: categoryId,
                isDeleted: isDeleted,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AuditEntriesTableTableManager get auditEntries =>
      $$AuditEntriesTableTableManager(_db, _db.auditEntries);
  $$RawMessagesTableTableManager get rawMessages =>
      $$RawMessagesTableTableManager(_db, _db.rawMessages);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$AppSettingsTableTableTableManager get appSettingsTable =>
      $$AppSettingsTableTableTableManager(_db, _db.appSettingsTable);
}
