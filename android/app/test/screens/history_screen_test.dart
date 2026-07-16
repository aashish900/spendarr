import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/summary.dart';
import 'package:spendarr/screens/add_txn_screen.dart';
import 'package:spendarr/screens/history_screen.dart';
import 'package:spendarr/widgets/pill_selector.dart';
import 'package:spendarr/widgets/spend_bar_chart.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: const MaterialApp(home: HistoryScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _seedExpenseToday(AppDatabase db) async {
  await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: 'c1',
    name: 'Food',
    emoji: '🍔',
    kind: TransactionKind.expense,
    createdAt: 0,
    updatedAt: 0,
  ));
  final now = DateTime.now();
  final noonToday =
      DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch;
  await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
    id: 't1',
    amount: 1234,
    kind: TransactionKind.expense,
    categoryId: 'c1',
    occurredAt: noonToday,
    source: TransactionSource.manual,
    createdAt: 0,
    updatedAt: 0,
    note: const Value.absent(),
  ));
}

void main() {
  testWidgets('empty state when no transactions in range', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    expect(find.text('No transactions in this range.'), findsOneWidget);
    expect(find.byType(SpendBarChart), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('renders chart + list and re-renders on period toggle',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedExpenseToday(db);

    await _pump(tester, db);

    // Default (Month) shows the chart and the category.
    expect(find.byType(SpendBarChart), findsOneWidget);
    expect(find.byType(PillSelector<HistoryPeriod>), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('−₹12.34'), findsOneWidget); // expense shown negative

    // Toggle to Day → re-renders; today's expense is still in range.
    await tester.tap(find.text('Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(SpendBarChart), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('transaction list row shows the recorded time alongside the date',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedExpenseToday(db); // seeded at local noon (12:00)

    await _pump(tester, db);

    final now = DateTime.now();
    final dateLabel =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(find.textContaining('$dateLabel 12:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping a transaction row opens it for editing', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedExpenseToday(db);

    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
        GoRoute(
          path: '/add',
          builder: (_, state) => AddTxnScreen(
            editTransactionId: state.uri.queryParameters['editTransactionId'],
          ),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.widgetWithText(ListTile, 'Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
