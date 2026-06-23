import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';

// Hand-written (not @riverpod): riverpod_generator cannot resolve drift's
// generated row classes (Category) across builders. See DECISIONLOG 2026-06-23.

/// Reactive stream of non-archived categories from local drift.
final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).categoriesDao.watchActiveCategories();
});

final categoryWriterProvider = Provider<CategoryWriter>((ref) {
  return CategoryWriter(ref.watch(appDatabaseProvider));
});

/// Local-first writes for categories: drift row + outbox entry in one
/// transaction. Outbox op convention: `upsert` for create/edit, `delete` for
/// archive (soft-delete). See DECISIONLOG 2026-06-23.
class CategoryWriter {
  CategoryWriter(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<String> add({
    required String name,
    required String emoji,
    required TransactionKind kind,
    String? id,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final categoryId = id ?? _uuid.v4();

    await _db.transaction(() async {
      await _db.categoriesDao.upsertCategory(
        CategoriesCompanion.insert(
          id: categoryId,
          name: name,
          emoji: emoji,
          kind: kind,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _db.outboxDao.enqueue(_outbox(
        op: OutboxOp.upsert,
        now: now,
        payload: {
          'id': categoryId,
          'name': name,
          'emoji': emoji,
          'kind': kind.name,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        },
      ));
    });

    return categoryId;
  }

  Future<void> archive(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.categoriesDao.archiveCategory(id, deletedAt: now);
      await _db.outboxDao.enqueue(_outbox(
        op: OutboxOp.delete,
        now: now,
        payload: {'id': id, 'updated_at': now, 'deleted_at': now},
      ));
    });
  }

  OutboxEntriesCompanion _outbox({
    required OutboxOp op,
    required int now,
    required Map<String, Object?> payload,
  }) {
    return OutboxEntriesCompanion.insert(
      id: _uuid.v4(),
      op: op,
      targetTable: 'categories',
      payloadJson: jsonEncode(payload),
      queuedAt: now,
    );
  }
}
