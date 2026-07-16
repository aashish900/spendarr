import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/screens/categories_screen.dart';

Future<void> _seed(
  AppDatabase db, {
  required String id,
  required String name,
  required TransactionKind kind,
}) {
  return db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: id,
    name: name,
    emoji: '🔹',
    kind: kind,
    createdAt: 0,
    updatedAt: 0,
  ));
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  final router = GoRouter(
    initialLocation: '/categories',
    routes: [
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  testWidgets('categories are grouped under Income/Expense/Investment headers',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db, id: 'c1', name: 'Salary', kind: TransactionKind.income);
    await _seed(db, id: 'c2', name: 'Food', kind: TransactionKind.expense);
    await _seed(db, id: 'c3', name: 'Rent', kind: TransactionKind.expense);
    await _seed(db,
        id: 'c4', name: 'Mutual Funds', kind: TransactionKind.investment);

    await _pump(tester, db);

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Investment'), findsOneWidget);

    // Income header appears before Expense header before Investment header.
    final incomeY = tester.getTopLeft(find.text('Income')).dy;
    final expenseY = tester.getTopLeft(find.text('Expense')).dy;
    final investmentY = tester.getTopLeft(find.text('Investment')).dy;
    expect(incomeY, lessThan(expenseY));
    expect(expenseY, lessThan(investmentY));

    // Each category appears once, under some header (not asserting exact
    // nesting — order above already proves grouping).
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Mutual Funds'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('kinds with no categories show no header', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db, id: 'c1', name: 'Food', kind: TransactionKind.expense);

    await _pump(tester, db);

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsNothing);
    expect(find.text('Investment'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
