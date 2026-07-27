// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'raw_message_dao.dart';

// ignore_for_file: type=lint
mixin _$RawMessageDaoMixin on DatabaseAccessor<AppDatabase> {
  $RawMessagesTable get rawMessages => attachedDatabase.rawMessages;
  RawMessageDaoManager get managers => RawMessageDaoManager(this);
}

class RawMessageDaoManager {
  final _$RawMessageDaoMixin _db;
  RawMessageDaoManager(this._db);
  $$RawMessagesTableTableManager get rawMessages =>
      $$RawMessagesTableTableManager(_db.attachedDatabase, _db.rawMessages);
}
