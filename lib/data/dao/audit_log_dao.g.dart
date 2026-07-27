// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_log_dao.dart';

// ignore_for_file: type=lint
mixin _$AuditLogDaoMixin on DatabaseAccessor<AppDatabase> {
  $AuditEntriesTable get auditEntries => attachedDatabase.auditEntries;
  AuditLogDaoManager get managers => AuditLogDaoManager(this);
}

class AuditLogDaoManager {
  final _$AuditLogDaoMixin _db;
  AuditLogDaoManager(this._db);
  $$AuditEntriesTableTableManager get auditEntries =>
      $$AuditEntriesTableTableManager(_db.attachedDatabase, _db.auditEntries);
}
