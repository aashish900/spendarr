import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
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
            builder: (_, _) => const AddCategoryScreen()),
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

    // Name is the only TextField now (icon is picked from the icon grid).
    await tester.enterText(find.byType(TextField).first, 'Food');
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
}
