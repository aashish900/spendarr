import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/router.dart';
import 'package:spendarr/widgets/category_form.dart';

void main() {
  testWidgets(
      'empty categories → "Create category" opens sheet → new category auto-selected → txn saves',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Tall virtual window so the redesigned Add screen's category card and
    // Save button aren't past ListView's sliver cacheExtent.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    expect(find.text('Add Transaction'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));

    // No categories yet: the category field card shows the placeholder.
    expect(find.text('Create or select category'), findsOneWidget);

    // Tap the category card → sheet opens with only "New category" (no
    // categories exist yet) → tap it → CategoryForm sheet opens on top.
    await tester.tap(find.text('Create or select category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.text('＋ New category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Sheet's CategoryForm fields are scoped to the sheet — the underlying
    // AddTxnScreen (with its own TextFields) is still in the tree behind the
    // modal. Name is CategoryForm's only TextField (icon is picked from the
    // icon grid, not typed).
    await tester.enterText(
      find.descendant(
        of: find.byType(CategoryForm),
        matching: find.byType(TextField),
      ).first,
      'Snacks',
    );
    await tester.tap(find.descendant(
      of: find.byType(CategoryForm),
      matching: find.widgetWithText(FilledButton, 'Save'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet pop transition
    await tester.pump(const Duration(milliseconds: 400)); // categories stream emits

    // Sheet closed; new category auto-selected on the category card.
    expect(find.text('Create or select category'), findsNothing);
    expect(find.text('Snacks'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '5.00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add Transaction'), findsNothing);

    final outbox = await db.outboxDao.queue();
    expect(outbox.map((o) => o.targetTable),
        containsAll(['categories', 'transactions']));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'existing categories → "New category" dropdown item opens sheet defaulting to the selected kind',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Tall virtual window so the redesigned Add screen's category card and
    // Save button aren't past ListView's sliver cacheExtent.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    // An existing Income category so the dropdown isn't empty after switching
    // kind below (the picker is filtered to the selected kind — see
    // add_txn_kind_filter_test.dart for the filtering behavior itself).
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Salary',
      emoji: '💼',
      kind: TransactionKind.income,
      createdAt: 0,
      updatedAt: 0,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // FAB → kind-picker sheet: pick Income directly (pre-selects the kind
    // on the Add screen, equivalent to switching there but unambiguous —
    // Home's own "Income" stat label is still mounted underneath the sheet).
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // Category card is pre-filled with the first Income category (Salary);
    // tap it to open the sheet, then tap "New category".
    await tester.tap(find.text('Salary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.text('＋ New category'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet close + sheet open

    // The sheet's kind segmented button should default to Income.
    final sheetKindButton = find.descendant(
      of: find.byType(CategoryForm),
      matching: find.byType(SegmentedButton<TransactionKind>),
    );
    expect(sheetKindButton, findsOneWidget);
    final selected = tester
        .widget<SegmentedButton<TransactionKind>>(sheetKindButton)
        .selected;
    expect(selected, {TransactionKind.income});

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
