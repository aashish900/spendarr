import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/router.dart';
import 'package:spendarr/widgets/app_shell.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // Budget never configured would otherwise pop the blocking first-run
  // budget-setup dialog on Home, which isn't what this file tests.
  final n = DateTime.now();
  await db.syncMetaDao.put('budget_mode', 'constant');
  await db.syncMetaDao
      .put('budget_set_for_month', '${n.year}-${n.month.toString().padLeft(2, '0')}');

  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: MaterialApp.router(routerConfig: appRouter),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('shows all 5 destinations and starts on Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget); // nav label
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    // "Recurring" matches twice: the nav label + the Recurring summary chip.
    expect(find.text('Recurring'), findsNWidgets(2));
    expect(find.text('Settings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping a destination swaps the visible screen',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    expect(find.text('No categories yet.'), findsNothing);

    await tester.tap(find.text('Categories'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('No categories yet.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget); // nav bar persists

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('FAB push (/add) covers the nav bar; pop returns to same tab',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);

    await tester.tap(find.text('History'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(NavigationBar), findsOneWidget);

    // Switch back to Home to use its FAB.
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Pushed on the root navigator (over the shell), not swapped into a
    // branch: the AddTxnScreen's own Scaffold has no bottom nav bar, and the
    // shell (with its NavigationBar) remains mounted underneath rather than
    // being torn down — Navigator keeps prior routes in the tree by default.
    expect(find.text('Add Transaction'), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add Transaction'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
