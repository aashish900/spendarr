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
    expect(find.text('No recurring rules yet.'), findsOneWidget);

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
}
