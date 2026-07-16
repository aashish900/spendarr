import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/recurring.dart';

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

  test('add → appears in active recurring stream + outbox upsert', () async {
    final id = await container.read(recurringWriterProvider).add(
          categoryId: 'c1',
          amountCents: 5000,
          kind: TransactionKind.expense,
          cron: '0 0 1 * *',
          nextRunAtMs: 123456789,
        );

    final rules = await db.recurringDao.watchActiveRules().first;
    final rule = rules.firstWhere((r) => r.id == id);
    expect(rule.active, isTrue);
    expect(rule.amount, 5000);
    expect(rule.cron, '0 0 1 * *');

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1));
    expect(outbox.single.op, OutboxOp.upsert);
    expect(outbox.single.targetTable, 'recurring_rules');
  });

  test('setActive(false) pauses + outbox upsert', () async {
    final id = await container.read(recurringWriterProvider).add(
          categoryId: 'c1',
          amountCents: 5000,
          kind: TransactionKind.expense,
          cron: '0 0 1 * *',
        );
    await container.read(recurringWriterProvider).setActive(id, false);

    final row = await db.recurringDao.ruleById(id);
    expect(row!.active, isFalse);

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(2)); // add + pause
    expect(outbox.last.op, OutboxOp.upsert);
    expect(outbox.last.targetTable, 'recurring_rules');
  });

  test('update edits fields, bumps updatedAt, preserves createdAt + active, outbox upsert',
      () async {
    final writer = container.read(recurringWriterProvider);
    final id = await writer.add(
      categoryId: 'c1',
      amountCents: 5000,
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
    );
    await writer.setActive(id, false);
    final created = (await db.recurringDao.ruleById(id))!.createdAt;

    await writer.update(
      id: id,
      categoryId: 'c2',
      amountCents: 7500,
      kind: TransactionKind.income,
      cron: '0 0 * * 1',
      note: 'edited',
    );

    final row = await db.recurringDao.ruleById(id);
    expect(row!.categoryId, 'c2');
    expect(row.amount, 7500);
    expect(row.kind, TransactionKind.income);
    expect(row.cron, '0 0 * * 1');
    expect(row.note, 'edited');
    expect(row.createdAt, created);
    expect(row.active, isFalse); // untouched

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(3)); // add + pause + update
    expect(outbox.last.op, OutboxOp.upsert);
    expect(outbox.last.targetTable, 'recurring_rules');
  });
}
