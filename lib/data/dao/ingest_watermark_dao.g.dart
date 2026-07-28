// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingest_watermark_dao.dart';

// ignore_for_file: type=lint
mixin _$IngestWatermarkDaoMixin on DatabaseAccessor<AppDatabase> {
  $IngestWatermarksTable get ingestWatermarks =>
      attachedDatabase.ingestWatermarks;
  IngestWatermarkDaoManager get managers => IngestWatermarkDaoManager(this);
}

class IngestWatermarkDaoManager {
  final _$IngestWatermarkDaoMixin _db;
  IngestWatermarkDaoManager(this._db);
  $$IngestWatermarksTableTableManager get ingestWatermarks =>
      $$IngestWatermarksTableTableManager(
        _db.attachedDatabase,
        _db.ingestWatermarks,
      );
}
