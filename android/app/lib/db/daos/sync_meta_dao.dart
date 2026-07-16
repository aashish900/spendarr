import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMetaEntries])
class SyncMetaDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  /// Upsert a key/value pair.
  Future<void> put(String key, String value) {
    return into(syncMetaEntries).insertOnConflictUpdate(
      SyncMetaEntriesCompanion(key: Value(key), value: Value(value)),
    );
  }

  /// Read a value, or null if the key is absent.
  Future<String?> getValue(String key) async {
    final row = await (select(syncMetaEntries)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }
}
