import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/router.dart';

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

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    // Explicit pumps (not pumpAndSettle): the loading/saving
    // CircularProgressIndicators animate forever and would hang pumpAndSettle.
    await tester.pump(); // first frame
    await tester.pump(const Duration(milliseconds: 200)); // drift stream emits

    // Today starts at net flow 0.00.
    expect(find.text('Net flow today'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);

    // FAB → Add screen.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); // start route push
    await tester.pump(const Duration(milliseconds: 400)); // transition done
    expect(find.text('Add transaction'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100)); // categories load → default

    // Enter amount; kind defaults to expense; category defaults to first (Food).
    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump(); // _saving spinner
    await tester.pump(const Duration(milliseconds: 200)); // write completes
    await tester.pump(const Duration(milliseconds: 400)); // pop transition + stream update

    // Popped back to Today; expense lowers net flow to -12.34.
    expect(find.text('Add transaction'), findsNothing);
    expect(find.text('-12.34'), findsOneWidget);

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
}
