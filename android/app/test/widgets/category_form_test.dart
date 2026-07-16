import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/widgets/category_form.dart';

void main() {
  testWidgets('tapping a suggested emoji persists exactly that emoji',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    String? savedId;
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        home: Scaffold(
          body: CategoryForm(onSaved: (id, kind) => savedId = id),
        ),
      ),
    ));
    await tester.pump();

    // Default preview is the first suggested shortcut.
    expect(find.text('💼'), findsWidgets);

    // Tap the second suggestion instead of the default.
    await tester.tap(find.text('💵'));
    await tester.pump();

    // TextField(0) is the emoji entry field; TextField(1) is Name.
    await tester.enterText(find.byType(TextField).at(1), 'Custom');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(savedId, isNotNull);
    final row = await db.categoriesDao.categoryById(savedId!);
    expect(row!.emoji, '💵');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'typing any emoji, not just a suggested one, persists exactly that',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    String? savedId;
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        home: Scaffold(
          body: CategoryForm(onSaved: (id, kind) => savedId = id),
        ),
      ),
    ));
    await tester.pump();

    // '🥷' is deliberately not in the suggested-shortcuts list — proves the
    // field accepts arbitrary emoji, not just the curated set.
    await tester.enterText(find.byType(TextField).first, '🥷');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Ninja stuff');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(savedId, isNotNull);
    final row = await db.categoriesDao.categoryById(savedId!);
    expect(row!.emoji, '🥷');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'editCategoryId prefills the existing category and updates it in place',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));

    String? savedId;
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        home: Scaffold(
          body: CategoryForm(
            editCategoryId: 'c1',
            onSaved: (id, kind) => savedId = id,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // async load

    // Prefilled from the existing row.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('🍔'), findsWidgets);
    // Editing shows "Update", not "Save".
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.enterText(find.byType(TextField).at(1), 'Groceries');
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(savedId, 'c1');
    final row = await db.categoriesDao.categoryById('c1');
    expect(row!.name, 'Groceries');
    expect(row.createdAt, 0); // untouched by the edit

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
