import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/screens/add_txn_screen.dart';

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  String? editTransactionId,
}) async {
  // A tall virtual window so the redesigned screen's cards/switch/Save
  // button all fit within ListView's cacheExtent (avoids the sliver
  // virtualization gotcha where off-screen children aren't built/findable).
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Two routes so AddTxnScreen's context.pop() on save has somewhere to
  // return to, matching how it's always pushed on top of another screen.
  final router = GoRouter(
    initialLocation: '/base',
    routes: [
      GoRoute(path: '/base', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/add',
        builder: (_, _) => AddTxnScreen(editTransactionId: editTransactionId),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  router.push('/add');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<String> _seedCategory(
  AppDatabase db, {
  required String id,
  required String name,
  required TransactionKind kind,
}) async {
  await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: id,
    name: name,
    emoji: '🔹',
    kind: kind,
    createdAt: 0,
    updatedAt: 0,
  ));
  return id;
}

void main() {
  testWidgets(
      'editing an existing transaction pre-fills fields and updates on save',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Food', kind: TransactionKind.expense);
    await _seedCategory(db, id: 'c2', name: 'Salary', kind: TransactionKind.income);

    final occurredAt =
        DateTime(2026, 6, 17, 14, 30).toUtc().millisecondsSinceEpoch;
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 1234,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAt: occurredAt,
      source: TransactionSource.manual,
      createdAt: 100,
      updatedAt: 100,
      note: const Value('lunch'),
    ));

    await _pump(tester, db, editTransactionId: 't1');

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget); // amount prefilled
    expect(find.text('Food'), findsOneWidget); // category prefilled
    expect(find.text('17 Jun 2026'), findsOneWidget); // date prefilled
    expect(find.text('Wednesday'), findsOneWidget); // weekday prefilled
    expect(find.text('2:30 PM'), findsOneWidget); // time prefilled
    expect(find.text('lunch'), findsOneWidget); // note prefilled

    // Edit the amount and save.
    await tester.enterText(find.byType(TextField).first, '55.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    final row = await db.transactionsDao.transactionById('t1');
    expect(row!.amount, 5500);
    expect(row.createdAt, 100); // untouched
    expect(row.updatedAt, isNot(100));

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1)); // just the update (no separate add)
    expect(outbox.single.targetTable, 'transactions');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'make-recurring toggle creates a linked RecurringRule when adding a transaction',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Rent', kind: TransactionKind.expense);

    await _pump(tester, db);

    await tester.enterText(find.byType(TextField).first, '900.00');
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    final rules = await db.recurringDao.activeRules();
    expect(rules, hasLength(1));
    expect(rules.single.amount, 90000);
    expect(rules.single.categoryId, 'c1');

    final txns = await db.transactionsDao.activeTransactions();
    expect(txns, hasLength(1));
    expect(txns.single.recurringRuleId, rules.single.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'editing a linked transaction with recurring toggled off unlinks without deleting the rule',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Rent', kind: TransactionKind.expense);
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 90000,
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 90000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAt: 0,
      source: TransactionSource.manual,
      createdAt: 0,
      updatedAt: 0,
      recurringRuleId: const Value('r1'),
    ));

    await _pump(tester, db, editTransactionId: 't1');

    expect(find.byType(Switch), findsOneWidget);
    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue); // prefilled from the linked rule

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    final row = await db.transactionsDao.transactionById('t1');
    expect(row!.recurringRuleId, isNull);

    final rule = await db.recurringDao.ruleById('r1');
    expect(rule, isNotNull); // rule itself untouched, not deleted

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'editing a linked transaction with recurring still on keeps the rule in sync (same id)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Rent', kind: TransactionKind.expense);
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 90000,
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 90000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAt: 0,
      source: TransactionSource.manual,
      createdAt: 0,
      updatedAt: 0,
      recurringRuleId: const Value('r1'),
    ));

    await _pump(tester, db, editTransactionId: 't1');

    await tester.enterText(find.byType(TextField).first, '1000.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    final row = await db.transactionsDao.transactionById('t1');
    expect(row!.recurringRuleId, 'r1'); // same rule, not a new one

    final rules = await db.recurringDao.activeRules();
    expect(rules, hasLength(1)); // no duplicate rule created
    expect(rules.single.amount, 100000); // kept in sync

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('delete action confirms, soft-deletes, and pops', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Food', kind: TransactionKind.expense);
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 1234,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      source: TransactionSource.manual,
      createdAt: 100,
      updatedAt: 100,
      note: const Value.absent(),
    ));

    await _pump(tester, db, editTransactionId: 't1');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Cancel first — nothing happens.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    var row = await db.transactionsDao.transactionById('t1');
    expect(row!.deletedAt, isNull);

    // Delete for real.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400)); // pop transition

    expect(find.text('Edit Transaction'), findsNothing); // popped

    row = await db.transactionsDao.transactionById('t1');
    expect(row!.deletedAt, isNotNull); // soft-deleted, row retained

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1));
    expect(outbox.single.op, OutboxOp.delete);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no delete action when creating a new transaction',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Food', kind: TransactionKind.expense);

    await _pump(tester, db);

    expect(find.text('Add Transaction'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'recurring frequency card only appears once the toggle is on',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Rent', kind: TransactionKind.expense);

    await _pump(tester, db);

    // Toggle off by default: no frequency card, no preset label.
    expect(find.text('Monthly'), findsNothing);
    expect(find.byIcon(Icons.autorenew), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Toggle on: frequency card appears, defaulting to Monthly.
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Every Month'), findsOneWidget);
    expect(find.byIcon(Icons.autorenew), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Toggled back off: frequency card is gone again.
    expect(find.text('Monthly'), findsNothing);
    expect(find.byIcon(Icons.autorenew), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('note field enforces a 120-character limit', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedCategory(db, id: 'c1', name: 'Food', kind: TransactionKind.expense);

    await _pump(tester, db);

    final noteField = find.byType(TextField).at(1); // amount is .first
    final tooLong = 'x' * 150;
    await tester.enterText(noteField, tooLong);
    await tester.pump();

    final entered = tester.widget<TextField>(noteField).controller!.text;
    expect(entered.length, 120); // truncated by maxLength

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
