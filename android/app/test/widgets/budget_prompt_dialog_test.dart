import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/providers/profile.dart';
import 'package:spendarr/widgets/budget_prompt_dialog.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget dialog) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showDialog(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('mode toggle switches between constant and monthly',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(
        tester,
        db,
        const BudgetPromptDialog(
          canCancel: true,
          showModeChoice: true,
          title: 'Set up your budget',
        ));

    expect(find.text('Every month is the same'), findsOneWidget);
    expect(find.text('Ask me each month'), findsOneWidget);

    await tester.tap(find.text('Ask me each month'));
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ElevatedButton)));
    final profile = container.read(profileProvider).value!;
    expect(profile.budgetMode, BudgetMode.monthly);
    expect(profile.monthlyBudgetCents, 0); // 0 is a valid budget
  });

  testWidgets('canCancel: false blocks barrier-tap dismissal', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(
        tester,
        db,
        const BudgetPromptDialog(
          canCancel: false,
          showModeChoice: true,
          title: 'Set up your budget',
        ));

    expect(find.text('Cancel'), findsNothing);
    await tester.tapAt(const Offset(5, 5)); // barrier, outside the dialog
    await tester.pump();
    expect(find.text('Set up your budget'), findsOneWidget);
  });

  testWidgets('showModeChoice: false hides the mode toggle', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(
        tester,
        db,
        const BudgetPromptDialog(
          canCancel: false,
          showModeChoice: false,
          title: "Set this month's budget",
          initialCents: 500000,
        ));

    expect(find.text('Every month is the same'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '5000'); // prefilled from initialCents
  });
}
