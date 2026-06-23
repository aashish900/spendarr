import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  /// Reactive stream of non-archived categories.
  Stream<List<Category>> watchActiveCategories() {
    return (select(categories)..where((c) => c.deletedAt.isNull())).watch();
  }

  Future<Category?> categoryById(String id) {
    return (select(categories)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  /// Insert or replace by primary key (used by both UI writes and sync pulls).
  Future<void> upsertCategory(CategoriesCompanion entry) {
    return into(categories).insertOnConflictUpdate(entry);
  }

  /// Soft-delete (archive): sets [deletedAt] and bumps `updatedAt` to the same
  /// instant (for LWW sync). Row is retained as a tombstone.
  Future<void> archiveCategory(String id, {required int deletedAt}) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }
}
