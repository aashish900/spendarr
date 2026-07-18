import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/router.dart';
import 'package:spendarr/util/datetime.dart';
import 'package:spendarr/widgets/kind_pill_selector.dart';

void main() {
  testWidgets('add a transaction → Today net flow updates reactively',
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

    // A tall virtual window so Home's ring/stats/chips + ledger all fit
    // within ListView's cacheExtent without needing a scroll gesture.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    // Explicit pumps (not pumpAndSettle): the loading/saving
    // CircularProgressIndicators animate forever and would hang pumpAndSettle.
    await tester.pump(); // first frame
    await tester.pump(const Duration(milliseconds: 200)); // drift stream emits

    // Home starts at ₹0 everywhere (current month, no txns): ring amount,
    // Income/Expenses/Balance chips.
    expect(find.text('₹0'), findsNWidgets(4));

    // FAB → kind-picker sheet → Add screen.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.widgetWithText(ListTile, 'Expense'));
    await tester.pump(); // start route push
    await tester.pump(const Duration(milliseconds: 400)); // transition done
    expect(find.text('Add Transaction'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100)); // categories load → default

    // Enter amount; kind defaults to expense; category defaults to first (Food).
    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump(); // _saving spinner
    await tester.pump(const Duration(milliseconds: 200)); // write completes
    await tester.pump(const Duration(milliseconds: 400)); // pop transition + stream update

    // Popped back to Home; the new expense shows up on the ring amount
    // (no budget set), the Expenses chip, and the ledger row.
    expect(find.text('Add Transaction'), findsNothing);
    expect(find.text('₹12.34'), findsNWidgets(2)); // ring + Expenses chip
    // ledger row + that date's own day-summary header (same single txn) +
    // the Balance chip (income 0 − expense 12.34, signed the same way).
    expect(find.text('−₹12.34'), findsNWidgets(3));

    // Outbox got the mutation.
    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(1));
    expect(outbox.single.targetTable, 'transactions');

    // Unmount to cancel drift stream subscriptions, then flush drift's
    // zero-duration coalescing timers and the SnackBar timer so the test ends
    // without "Timer still pending".
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Add transaction shows a time picker button defaulting to now',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

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

    expect(find.byIcon(Icons.access_time), findsOneWidget);
    // Label matches 12-hour h:mm AM/PM, close to "now" (not asserting the
    // exact instant to avoid flakiness around a minute boundary).
    final now = TimeOfDay.now();
    final expectedLabel = formatTime12h(now.hour, now.minute);
    expect(find.text(expectedLabel), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('/add?kind=income pre-selects the Income kind', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).push('/add?kind=income');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    final pill =
        tester.widget<KindPillSelector>(find.byType(KindPillSelector));
    expect(pill.selected, TransactionKind.income);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
