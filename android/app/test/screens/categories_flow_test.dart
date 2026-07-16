import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/screens/add_category_screen.dart';
import 'package:spendarr/screens/categories_screen.dart';

void main() {
  testWidgets('add a category → appears in list → archive → removed',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final router = GoRouter(
      initialLocation: '/categories',
      routes: [
        GoRoute(
            path: '/categories', builder: (_, _) => const CategoriesScreen()),
        GoRoute(
          path: '/categories/add',
          builder: (_, state) => AddCategoryScreen(
            editCategoryId: state.uri.queryParameters['editCategoryId'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No categories yet.'), findsOneWidget);

    // FAB → Add category.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add category'), findsOneWidget);

    // TextField(0) is the emoji entry field; TextField(1) is Name.
    await tester.enterText(find.byType(TextField).at(1), 'Food');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    // Back on the list with the new category.
    expect(find.text('Add category'), findsNothing);
    expect(find.text('Food'), findsOneWidget);

    // Archive it → list empties.
    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Food'), findsNothing);
    expect(find.text('No categories yet.'), findsOneWidget);

    // Two outbox rows: add (upsert) + archive (delete).
    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping a category row opens it for editing and updates it',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final router = GoRouter(
      initialLocation: '/categories',
      routes: [
        GoRoute(
            path: '/categories', builder: (_, _) => const CategoriesScreen()),
        GoRoute(
          path: '/categories/add',
          builder: (_, state) => AddCategoryScreen(
            editCategoryId: state.uri.queryParameters['editCategoryId'],
          ),
        ),
      ],
    );

    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap the row (not the trailing archive icon) → edit screen.
    await tester.tap(find.text('Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200)); // async load
    expect(find.text('Edit category'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'Groceries');
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump(); // _saving spinner
    await tester.pump(const Duration(milliseconds: 200)); // write completes
    await tester.pump(const Duration(milliseconds: 400)); // pop transition

    // Back on the list with the renamed category — same id, not a new row.
    expect(find.text('Edit category'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Food'), findsNothing);

    final row = await db.categoriesDao.categoryById('c1');
    expect(row!.name, 'Groceries');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
