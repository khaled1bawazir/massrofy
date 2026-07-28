// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bank_dao.dart';

// ignore_for_file: type=lint
mixin _$BankDaoMixin on DatabaseAccessor<AppDatabase> {
  $BanksTable get banks => attachedDatabase.banks;
  BankDaoManager get managers => BankDaoManager(this);
}

class BankDaoManager {
  final _$BankDaoMixin _db;
  BankDaoManager(this._db);
  $$BanksTableTableManager get banks =>
      $$BanksTableTableManager(_db.attachedDatabase, _db.banks);
}
