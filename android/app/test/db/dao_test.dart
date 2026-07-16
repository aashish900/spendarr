import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  group('CategoriesDao', () {
    test('insert → active stream emits the row', () async {
      await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
        id: 'c1',
        name: 'Food',
        emoji: '🍔',
        kind: TransactionKind.expense,
        createdAt: now(),
        updatedAt: now(),
      ));

      final rows = await db.categoriesDao.watchActiveCategories().first;
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Food');
      expect(rows.single.kind, TransactionKind.expense);
    });

    test('archive sets deletedAt and excludes from active stream', () async {
      await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
        id: 'c1',
        name: 'Food',
        emoji: '🍔',
        kind: TransactionKind.expense,
        createdAt: now(),
        updatedAt: now(),
      ));
      await db.categoriesDao.archiveCategory('c1', deletedAt: now());

      expect(await db.categoriesDao.watchActiveCategories().first, isEmpty);
      final row = await db.categoriesDao.categoryById('c1');
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull); // tombstone retained for sync
    });
  });

  group('TransactionsDao', () {
    TransactionsCompanion txn(String id) => TransactionsCompanion.insert(
          id: id,
          amount: 1234, // cents
          kind: TransactionKind.expense,
          categoryId: 'c1',
          occurredAt: now(),
          source: TransactionSource.manual,
          createdAt: now(),
          updatedAt: now(),
        );

    test('insert → active stream emits; amount stored as cents', () async {
      await db.transactionsDao.upsertTransaction(txn('t1'));

      final rows = await db.transactionsDao.watchActiveTransactions().first;
      expect(rows, hasLength(1));
      expect(rows.single.amount, 1234);
    });

    test('soft-delete sets deletedAt and filters out of active stream',
        () async {
      await db.transactionsDao.upsertTransaction(txn('t1'));
      await db.transactionsDao.softDeleteTransaction('t1', deletedAt: now());

      expect(await db.transactionsDao.watchActiveTransactions().first, isEmpty);
      final row = await db.transactionsDao.transactionById('t1');
      expect(row!.deletedAt, isNotNull);
    });

    test('updateTransaction changes fields, bumps updatedAt, preserves createdAt',
        () async {
      final created = now();
      await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: 't1',
        amount: 1000,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: created,
        source: TransactionSource.manual,
        createdAt: created,
        updatedAt: created,
      ));

      final updated = created + 5000;
      await db.transactionsDao.updateTransaction(
        't1',
        amount: 2000,
        kind: TransactionKind.income,
        categoryId: 'c2',
        occurredAt: created + 1000,
        note: 'edited',
        recurringRuleId: const Value('r1'),
        updatedAt: updated,
      );

      final row = await db.transactionsDao.transactionById('t1');
      expect(row!.amount, 2000);
      expect(row.kind, TransactionKind.income);
      expect(row.categoryId, 'c2');
      expect(row.occurredAt, created + 1000);
      expect(row.note, 'edited');
      expect(row.recurringRuleId, 'r1');
      expect(row.createdAt, created); // untouched
      expect(row.updatedAt, updated);
    });

    test('updateTransaction can clear note and unlink recurringRuleId',
        () async {
      await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: 't1',
        amount: 1000,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: now(),
        source: TransactionSource.manual,
        createdAt: now(),
        updatedAt: now(),
        note: const Value('original'),
        recurringRuleId: const Value('r1'),
      ));

      await db.transactionsDao.updateTransaction(
        't1',
        amount: 1000,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: now(),
        note: null,
        recurringRuleId: const Value(null),
        updatedAt: now(),
      );

      final row = await db.transactionsDao.transactionById('t1');
      expect(row!.note, isNull);
      expect(row.recurringRuleId, isNull);
    });
  });

  group('RecurringDao', () {
    RecurringRulesCompanion rule(String id) => RecurringRulesCompanion.insert(
          id: id,
          categoryId: 'c1',
          amount: 5000,
          kind: TransactionKind.expense,
          cron: '0 0 1 * *',
          createdAt: now(),
          updatedAt: now(),
        );

    test('insert → active stream emits; defaults active=true', () async {
      await db.recurringDao.upsertRule(rule('r1'));

      final rows = await db.recurringDao.watchActiveRules().first;
      expect(rows, hasLength(1));
      expect(rows.single.active, isTrue);
    });

    test('setActive(false) pauses the rule', () async {
      await db.recurringDao.upsertRule(rule('r1'));
      await db.recurringDao.setActive('r1', false, updatedAt: now());

      final row = await db.recurringDao.ruleById('r1');
      expect(row!.active, isFalse);
    });

    test('updateRule changes fields, bumps updatedAt, preserves createdAt + active',
        () async {
      final created = now();
      await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
        id: 'r1',
        categoryId: 'c1',
        amount: 5000,
        kind: TransactionKind.expense,
        cron: '0 0 1 * *',
        createdAt: created,
        updatedAt: created,
      ));
      await db.recurringDao.setActive('r1', false, updatedAt: now());

      final updated = created + 5000;
      await db.recurringDao.updateRule(
        'r1',
        categoryId: 'c2',
        amount: 7500,
        kind: TransactionKind.income,
        cron: '0 0 * * 1',
        note: 'edited',
        updatedAt: updated,
      );

      final row = await db.recurringDao.ruleById('r1');
      expect(row!.categoryId, 'c2');
      expect(row.amount, 7500);
      expect(row.kind, TransactionKind.income);
      expect(row.cron, '0 0 * * 1');
      expect(row.note, 'edited');
      expect(row.createdAt, created); // untouched
      expect(row.updatedAt, updated);
      expect(row.active, isFalse); // untouched by updateRule
    });
  });

  group('OutboxDao', () {
    test('enqueue → row visible in FIFO queue', () async {
      await db.outboxDao.enqueue(OutboxEntriesCompanion.insert(
        id: 'o1',
        op: OutboxOp.upsert,
        targetTable: 'transactions',
        payloadJson: '{"id":"t1"}',
        queuedAt: now(),
      ));

      final queue = await db.outboxDao.queue();
      expect(queue, hasLength(1));
      expect(queue.single.op, OutboxOp.upsert);
      expect(queue.single.targetTable, 'transactions');
    });

    test('remove drops a drained entry', () async {
      await db.outboxDao.enqueue(OutboxEntriesCompanion.insert(
        id: 'o1',
        op: OutboxOp.delete,
        targetTable: 'categories',
        payloadJson: '{"id":"c1"}',
        queuedAt: now(),
      ));
      await db.outboxDao.remove('o1');

      expect(await db.outboxDao.queue(), isEmpty);
    });
  });

  group('SyncMetaDao', () {
    test('put/get round-trip', () async {
      expect(await db.syncMetaDao.getValue('last_pull_at'), isNull);

      await db.syncMetaDao.put('last_pull_at', '1700000000000');
      expect(await db.syncMetaDao.getValue('last_pull_at'), '1700000000000');

      // upsert overwrites
      await db.syncMetaDao.put('last_pull_at', '1800000000000');
      expect(await db.syncMetaDao.getValue('last_pull_at'), '1800000000000');
    });
  });
}
