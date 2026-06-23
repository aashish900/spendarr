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
}
