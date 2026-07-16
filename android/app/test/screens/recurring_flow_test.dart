import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/screens/add_recurring_screen.dart';
import 'package:spendarr/screens/recurring_screen.dart';

void main() {
  testWidgets('add a recurring rule → appears in list → pause toggles active',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Tall virtual window so the redesigned Add recurring screen's Save
    // button isn't past ListView's sliver cacheExtent.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Rent',
      emoji: '🏠',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));

    final router = GoRouter(
      initialLocation: '/recurring',
      routes: [
        GoRoute(
            path: '/recurring', builder: (_, _) => const RecurringScreen()),
        GoRoute(
            path: '/recurring/add',
            builder: (_, _) => const AddRecurringScreen()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ACTIVE (0)'), findsOneWidget);
    expect(find.text('INACTIVE (0)'), findsOneWidget);
    expect(find.text('No active recurring transactions'), findsOneWidget);
    expect(find.text('No inactive recurring transactions'), findsOneWidget);

    // FAB → Add recurring.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add recurring'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100)); // category defaults

    // Amount is the first TextField; preset defaults monthly, category 'Rent'.
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    // Back on the list with the rule (category name shown).
    expect(find.text('Add recurring'), findsNothing);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // The rule starts active. (Future query, not a stream — a watch().first
    // would hang under the widget-test fake clock.)
    final added = await db.recurringDao.activeRules();
    expect(added.single.active, isTrue);

    // Toggle the switch → paused.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final ruleId = added.single.id;
    final paused = await db.recurringDao.ruleById(ruleId);
    expect(paused!.active, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'paused rule moves to Inactive; kebab menu → Delete soft-deletes it',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Rent',
      emoji: '🏠',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 3200000,
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));

    final router = GoRouter(
      initialLocation: '/recurring',
      routes: [
        GoRoute(
            path: '/recurring', builder: (_, _) => const RecurringScreen()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ACTIVE (1)'), findsOneWidget);
    expect(find.text('INACTIVE (0)'), findsOneWidget);
    expect(find.text('₹32,000'), findsNWidgets(2)); // summary total + rule row

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ACTIVE (0)'), findsOneWidget);
    expect(find.text('INACTIVE (1)'), findsOneWidget);

    // Kebab menu → Delete → confirm.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final remaining = await db.recurringDao.activeRules();
    expect(remaining, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'summary breaks active rules down by kind (Income/Investment/Expense), not one combined total',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Rent',
      emoji: '🏠',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Salary',
      emoji: '💼',
      kind: TransactionKind.income,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c3',
      name: 'SIP',
      emoji: '📈',
      kind: TransactionKind.investment,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 1000000, // ₹10,000
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r2',
      categoryId: 'c2',
      amount: 5000000, // ₹50,000
      kind: TransactionKind.income,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r3',
      categoryId: 'c3',
      amount: 2000000, // ₹20,000
      kind: TransactionKind.investment,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));

    final router = GoRouter(
      initialLocation: '/recurring',
      routes: [
        GoRoute(
            path: '/recurring', builder: (_, _) => const RecurringScreen()),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Investment'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    // Summary column figure + that rule's own row amount, one each.
    expect(find.text('₹50,000'), findsNWidgets(2));
    expect(find.text('₹20,000'), findsNWidgets(2));
    expect(find.text('₹10,000'), findsNWidgets(2));
    // No single combined total is shown anywhere.
    expect(find.text('₹80,000'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
