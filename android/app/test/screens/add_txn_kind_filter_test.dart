import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/router.dart';
import 'package:spendarr/widgets/kind_pill_selector.dart';

Future<void> _seedCategory(
  AppDatabase db, {
  required String id,
  required String name,
  required String emoji,
  required TransactionKind kind,
}) {
  return db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: id,
    name: name,
    emoji: emoji,
    kind: kind,
    createdAt: 0,
    updatedAt: 0,
  ));
}

Future<void> _seedNoBudgetPrompt(AppDatabase db) async {
  // Home would otherwise show its blocking first-run budget-setup dialog,
  // which isn't what this file tests.
  final n = DateTime.now();
  await db.syncMetaDao.put('budget_mode', 'constant');
  await db.syncMetaDao
      .put('budget_set_for_month', '${n.year}-${n.month.toString().padLeft(2, '0')}');
}

void main() {
  // appRouter is a shared top-level singleton; reset its location after each
  // test so a test that navigates to /add (and never pops back) doesn't leak
  // that route into the next test's fresh widget tree.
  tearDown(() => appRouter.go('/home'));

  testWidgets(
      'category dropdown only shows categories matching the selected kind',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedNoBudgetPrompt(db);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _seedCategory(db,
        id: 'c1', name: 'Food', emoji: '🍔', kind: TransactionKind.expense);
    await _seedCategory(db,
        id: 'c2', name: 'Salary', emoji: '💼', kind: TransactionKind.income);
    await _seedCategory(db,
        id: 'c3',
        name: 'Mutual Funds',
        emoji: '📈',
        kind: TransactionKind.investment);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // Default kind is Expense: only Food is selectable, auto-selected.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    expect(find.text('Mutual Funds'), findsNothing);

    // Switch to Income: only Salary is selectable now, auto-selected.
    await tester.tap(find.text('Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
    expect(find.text('Mutual Funds'), findsNothing);

    // Switch to Investment: only Mutual Funds is selectable now.
    await tester.tap(find.text('Investment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Mutual Funds'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
    expect(find.text('Salary'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'no categories for the selected kind → shows Create category button, not an empty dropdown',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedNoBudgetPrompt(db);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _seedCategory(db,
        id: 'c1', name: 'Food', emoji: '🍔', kind: TransactionKind.expense);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // No Income categories exist yet — pick Income directly from the sheet.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // No Income categories: the category card shows the empty placeholder,
    // and its sheet offers only "New category".
    expect(find.text('Create or select category'), findsOneWidget);
    await tester.tap(find.text('Create or select category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    expect(find.text('＋ New category'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'quick-add chip for an income category pre-selects Income kind',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedNoBudgetPrompt(db);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _seedCategory(db,
        id: 'c1', name: 'Salary', emoji: '💼', kind: TransactionKind.income);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(
        routerConfig: appRouter,
        // AddTxnScreen reads initialCategoryId from the query param on
        // `/add?categoryId=...`, which the router already wires up.
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Simulate the Home quick-add chip route directly. The context must be a
    // descendant of the Router (MaterialApp's own element is above it).
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).push('/add?categoryId=c1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    final pill =
        tester.widget<KindPillSelector>(find.byType(KindPillSelector));
    expect(pill.selected, TransactionKind.income);
    expect(find.text('Salary'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'category sheet lists only the current kind\'s categories; tapping one selects it',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedNoBudgetPrompt(db);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _seedCategory(db,
        id: 'c1', name: 'Food', emoji: '🍔', kind: TransactionKind.expense);
    await _seedCategory(db,
        id: 'c2', name: 'Snacks', emoji: '🍿', kind: TransactionKind.expense);
    await _seedCategory(db,
        id: 'c3', name: 'Salary', emoji: '💼', kind: TransactionKind.income);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // Auto-selected to the first expense category (Food).
    expect(find.text('Food'), findsOneWidget);

    // Open the category sheet: only the two Expense categories are listed
    // (Salary, an Income category, is excluded).
    await tester.tap(find.text('Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Snacks'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Salary'), findsNothing);

    // Tapping Snacks selects it and closes the sheet.
    await tester.tap(find.widgetWithText(ListTile, 'Snacks'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet close
    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Food'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'category sheet scrolls with a long list, and "New category" is still reachable',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedNoBudgetPrompt(db);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Enough expense categories that the sheet's list can't fit on screen
    // without scrolling — regression test for the sheet being a
    // non-scrollable Column that clipped "New category" off-screen.
    for (var i = 0; i < 30; i++) {
      await _seedCategory(db,
          id: 'c$i',
          name: 'Category $i',
          emoji: '🍔',
          kind: TransactionKind.expense);
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Category 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open

    // "New category" isn't visible yet (30 rows don't fit on screen), but
    // scrolling the sheet's ListView down reaches it.
    expect(find.text('＋ New category'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tester.pump();
    expect(find.text('＋ New category'), findsOneWidget);

    await tester.tap(find.text('＋ New category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet transition
    expect(find.byType(TextField), findsWidgets); // CategoryForm sheet opened

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
