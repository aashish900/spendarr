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

  /// All categories including archived — for resolving names of transactions
  /// whose category was later archived (e.g. CSV export).
  Future<List<Category>> allCategories() => select(categories).get();

  /// Insert or replace by primary key (used by both UI writes and sync pulls).
  Future<void> upsertCategory(CategoriesCompanion entry) {
    return into(categories).insertOnConflictUpdate(entry);
  }

  /// Partial update for editing an existing category — leaves [Category.createdAt]
  /// untouched (unlike [upsertCategory], which would reset it), bumping only
  /// the edited fields + `updatedAt`. Mirrors `TransactionsDao.updateTransaction`.
  Future<void> updateCategory(
    String id, {
    required String name,
    required String emoji,
    required TransactionKind kind,
    required int updatedAt,
  }) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        emoji: Value(emoji),
        kind: Value(kind),
        updatedAt: Value(updatedAt),
      ),
    );
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
