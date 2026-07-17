import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/screens/settings_screen.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
          path: '/export',
          builder: (_, _) => const Scaffold(body: Text('Export screen'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('Export CSV navigates to /export', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);

    expect(find.text('Export CSV'), findsOneWidget);
    // Profile display-name field is gone until it's functional again.
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Backend URL'), findsNothing);

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Export screen'), findsOneWidget);
  });

  testWidgets(
      'Budget row shows the current budget, and tapping opens the edit dialog prefilled',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncMetaDao.put('monthly_budget_cents', '1500000'); // ₹15,000
    await db.syncMetaDao.put('budget_mode', 'constant');
    await _pump(tester, db);

    expect(find.textContaining('₹15,000'), findsOneWidget);
    expect(find.textContaining('Same every month'), findsOneWidget);

    await tester.tap(find.text('Monthly budget'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Edit budget'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '15000');
    // Editing from Settings is dismissible, unlike the Home prompts.
    expect(find.text('Cancel'), findsOneWidget);
  });
}
