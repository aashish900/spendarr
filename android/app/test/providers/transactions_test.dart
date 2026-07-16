import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/transactions.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    // Keep the stream subscribed so reads reflect live drift updates.
    container.listen(todayTransactionsProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  int todayNoonMs() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 12).toUtc().millisecondsSinceEpoch;
  }

  Future<void> waitForTxnCount(int n) async {
    for (var i = 0; i < 100; i++) {
      final v = container.read(todayTransactionsProvider).value;
      if (v != null && v.length == n) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('timed out waiting for $n active transactions');
  }

  test('todayUtcBounds brackets the local day', () {
    final noon = DateTime(2026, 6, 23, 12, 30);
    final b = todayUtcBounds(noon);
    final noonMs = noon.toUtc().millisecondsSinceEpoch;
    expect(b.startMs < b.endMs, isTrue);
    expect(noonMs >= b.startMs && noonMs < b.endMs, isTrue);
  });

  test('add writes drift row + outbox entry atomically', () async {
    final id = await container.read(transactionWriterProvider).add(
          amountCents: 1500,
          kind: TransactionKind.expense,
          categoryId: 'c1',
          occurredAtMs: todayNoonMs(),
          note: 'lunch',
        );

    final row = await db.transactionsDao.transactionById(id);
    expect(row, isNotNull);
    expect(row!.amount, 1500);
    expect(row.source, TransactionSource.manual);
    expect(row.note, 'lunch');

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1));
    expect(outbox.single.op, OutboxOp.upsert);
    expect(outbox.single.targetTable, 'transactions');
    expect(outbox.single.payloadJson, contains(id));
  });

  test('todayNetFlow = income − expense, investment excluded; reacts to delete',
      () async {
    final writer = container.read(transactionWriterProvider);

    await writer.add(
      amountCents: 10000,
      kind: TransactionKind.income,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
    );
    final expenseId = await writer.add(
      amountCents: 3000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
    );
    await waitForTxnCount(2);
    expect(container.read(todayNetFlowProvider), 7000);

    // Investment does not affect net flow.
    await writer.add(
      amountCents: 5000,
      kind: TransactionKind.investment,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
    );
    await waitForTxnCount(3);
    expect(container.read(todayNetFlowProvider), 7000);

    // Delete the expense → net flow rises to the income alone.
    await db.transactionsDao.softDeleteTransaction(
      expenseId,
      deletedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    await waitForTxnCount(2);
    expect(container.read(todayNetFlowProvider), 10000);
  });

  test('add accepts an optional recurringRuleId', () async {
    final id = await container.read(transactionWriterProvider).add(
          amountCents: 1500,
          kind: TransactionKind.expense,
          categoryId: 'c1',
          occurredAtMs: todayNoonMs(),
          recurringRuleId: 'r1',
        );

    final row = await db.transactionsDao.transactionById(id);
    expect(row!.recurringRuleId, 'r1');

    final outbox = await db.outboxDao.queue();
    expect(outbox.single.payloadJson, contains('r1'));
  });

  test('update edits fields, bumps updatedAt, preserves createdAt, enqueues outbox',
      () async {
    final writer = container.read(transactionWriterProvider);
    final id = await writer.add(
      amountCents: 1000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
      note: 'original',
    );
    final created = (await db.transactionsDao.transactionById(id))!.createdAt;

    await writer.update(
      id: id,
      amountCents: 2000,
      kind: TransactionKind.income,
      categoryId: 'c2',
      occurredAtMs: todayNoonMs(),
      note: 'edited',
      recurringRuleId: 'r1',
    );

    final row = await db.transactionsDao.transactionById(id);
    expect(row!.amount, 2000);
    expect(row.kind, TransactionKind.income);
    expect(row.categoryId, 'c2');
    expect(row.note, 'edited');
    expect(row.recurringRuleId, 'r1');
    expect(row.createdAt, created);
    expect(row.updatedAt, isNot(created));

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(2)); // add + update
    expect(outbox.last.op, OutboxOp.upsert);
    expect(outbox.last.targetTable, 'transactions');
  });

  test('update can clear recurringRuleId (unlink)', () async {
    final writer = container.read(transactionWriterProvider);
    final id = await writer.add(
      amountCents: 1000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
      recurringRuleId: 'r1',
    );

    await writer.update(
      id: id,
      amountCents: 1000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
      recurringRuleId: null,
    );

    final row = await db.transactionsDao.transactionById(id);
    expect(row!.recurringRuleId, isNull);
  });

  test('delete soft-deletes the row and enqueues an outbox delete', () async {
    final writer = container.read(transactionWriterProvider);
    final id = await writer.add(
      amountCents: 1000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAtMs: todayNoonMs(),
    );
    await waitForTxnCount(1);

    await writer.delete(id);
    await waitForTxnCount(0); // active-rows stream no longer includes it

    // Row is retained (soft delete), with deletedAt + updatedAt set.
    final row = await db.transactionsDao.transactionById(id);
    expect(row, isNotNull);
    expect(row!.deletedAt, isNotNull);
    expect(row.updatedAt, row.deletedAt);

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(2)); // add's upsert + the delete
    expect(outbox.last.op, OutboxOp.delete);
    expect(outbox.last.targetTable, 'transactions');
    expect(outbox.last.payloadJson, contains(id));
  });

  group('localDayTickProvider rollover', () {
    late StreamController<DateTime> dayController;
    late ProviderContainer dayContainer;
    late AppDatabase dayDb;

    int noonMs(DateTime day) =>
        DateTime(day.year, day.month, day.day, 12).toUtc().millisecondsSinceEpoch;

    setUp(() {
      dayDb = AppDatabase(NativeDatabase.memory());
      dayController = StreamController<DateTime>();
      dayContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) => dayDb),
          localDayTickProvider.overrideWith((ref) => dayController.stream),
        ],
      );
      dayContainer.listen(todayTransactionsProvider, (_, _) {});
    });

    tearDown(() async {
      dayContainer.dispose();
      await dayDb.close();
      await dayController.close();
    });

    test('window recomputes when the local day advances', () async {
      final dayA = DateTime(2026, 6, 23);
      final dayB = DateTime(2026, 6, 24);

      await dayDb.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: 't-a',
        amount: 100,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: noonMs(dayA),
        source: TransactionSource.manual,
        createdAt: 0,
        updatedAt: 0,
      ));
      await dayDb.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: 't-b',
        amount: 200,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: noonMs(dayB),
        source: TransactionSource.manual,
        createdAt: 0,
        updatedAt: 0,
      ));

      dayController.add(dayA);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      var rows = dayContainer.read(todayTransactionsProvider).value ?? [];
      expect(rows.map((r) => r.id), ['t-a']);

      dayController.add(dayB);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rows = dayContainer.read(todayTransactionsProvider).value ?? [];
      expect(rows.map((r) => r.id), ['t-b']);
    });
  });
}
