// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instrument_dao.dart';

// ignore_for_file: type=lint
mixin _$InstrumentDaoMixin on DatabaseAccessor<AppDatabase> {
  $InstrumentsTable get instruments => attachedDatabase.instruments;
  InstrumentDaoManager get managers => InstrumentDaoManager(this);
}

class InstrumentDaoManager {
  final _$InstrumentDaoMixin _db;
  InstrumentDaoManager(this._db);
  $$InstrumentsTableTableManager get instruments =>
      $$InstrumentsTableTableManager(_db.attachedDatabase, _db.instruments);
}
