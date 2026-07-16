import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/categories.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('add → appears in active categories stream + outbox upsert', () async {
    final id = await container.read(categoryWriterProvider).add(
          name: 'Food',
          emoji: '🍔',
          kind: TransactionKind.expense,
        );

    final cats = await db.categoriesDao.watchActiveCategories().first;
    expect(cats.where((c) => c.id == id), isNotEmpty);
    expect(cats.firstWhere((c) => c.id == id).name, 'Food');

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1));
    expect(outbox.single.op, OutboxOp.upsert);
    expect(outbox.single.targetTable, 'categories');
    expect(outbox.single.payloadJson, contains(id));
  });

  test('archive → deletedAt set, removed from active, outbox delete', () async {
    final id = await container.read(categoryWriterProvider).add(
          name: 'Food',
          emoji: '🍔',
          kind: TransactionKind.expense,
        );
    await container.read(categoryWriterProvider).archive(id);

    final row = await db.categoriesDao.categoryById(id);
    expect(row, isNotNull);
    expect(row!.deletedAt, isNotNull);
    expect(row.updatedAt, row.deletedAt); // bumped together

    final active = await db.categoriesDao.watchActiveCategories().first;
    expect(active, isEmpty);

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(2)); // add + archive
    expect(outbox.last.op, OutboxOp.delete);
    expect(outbox.last.targetTable, 'categories');
  });
}
