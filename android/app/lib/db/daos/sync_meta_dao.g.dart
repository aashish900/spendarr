// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_meta_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncMetaDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncMetaEntriesTable get syncMetaEntries => attachedDatabase.syncMetaEntries;
  SyncMetaDaoManager get managers => SyncMetaDaoManager(this);
}

class SyncMetaDaoManager {
  final _$SyncMetaDaoMixin _db;
  SyncMetaDaoManager(this._db);
  $$SyncMetaEntriesTableTableManager get syncMetaEntries =>
      $$SyncMetaEntriesTableTableManager(
        _db.attachedDatabase,
        _db.syncMetaEntries,
      );
}
