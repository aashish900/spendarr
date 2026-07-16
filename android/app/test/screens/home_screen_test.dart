import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/clock.dart';
import 'package:spendarr/router.dart';
import 'package:spendarr/theme.dart';
import 'package:spendarr/widgets/home_timeline.dart';
import 'package:spendarr/widgets/kind_pill_selector.dart';
import 'package:spendarr/widgets/month_ring.dart';

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  DateTime Function()? now,
}) async {
  // The Home screen's ring/stats/chips now occupy most of the default
  // 600px test viewport, pushing ledger rows past ListView's cacheExtent
  // (a plain ListView is sliver-backed and only materializes children
  // near the viewport). Use a tall virtual window so ledger content
  // renders without needing a scroll gesture per test.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((ref) => db),
      if (now != null) nowProvider.overrideWithValue(now),
    ],
    child: MaterialApp.router(routerConfig: appRouter),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _seedTxn(
  AppDatabase db, {
  required String id,
  required int amount,
  required TransactionKind kind,
  required String categoryId,
  required int occurredAtMs,
}) {
  return db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
    id: id,
    amount: amount,
    kind: kind,
    categoryId: categoryId,
    occurredAt: occurredAtMs,
    source: TransactionSource.manual,
    createdAt: 0,
    updatedAt: 0,
    note: const Value.absent(),
  ));
}

/// Seeds an income transaction on the 1st of the current month (the reported
/// bug scenario) plus an expense today.
Future<void> _seedMonthIncomeAndTodayExpense(AppDatabase db) async {
  await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: 'c1',
    name: 'Salary',
    emoji: '💼',
    kind: TransactionKind.income,
    createdAt: 0,
    updatedAt: 0,
  ));
  await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
    id: 'c2',
    name: 'Food',
    emoji: '🍔',
    kind: TransactionKind.expense,
    createdAt: 0,
    updatedAt: 0,
  ));

  final now = DateTime.now();
  final firstOfMonthNoon =
      DateTime(now.year, now.month, 1, 12).toUtc().millisecondsSinceEpoch;
  final todayNoon =
      DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch;

  await _seedTxn(db,
      id: 'income-1st',
      amount: 500000,
      kind: TransactionKind.income,
      categoryId: 'c1',
      occurredAtMs: firstOfMonthNoon);
  await _seedTxn(db,
      id: 'expense-today',
      amount: 1234,
      kind: TransactionKind.expense,
      categoryId: 'c2',
      occurredAtMs: todayNoon);
}

void main() {
  // appRouter is a shared top-level singleton across tests in this isolate.
  tearDown(() => appRouter.go('/home'));

  testWidgets(
      'Month zoom shows the whole month immediately (fixes the reported bug)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedMonthIncomeAndTodayExpense(db);

    await _pump(tester, db);

    // Income from the 1st is visible immediately, without switching views.
    // Summary stats show unsigned rupee amounts; ledger rows show a signed
    // amount (income +, expense −), so the two don't share text.
    expect(find.text('₹5,000'), findsOneWidget); // Income stat
    // "+₹5,000" matches 2x: the ledger row (income) + that date's own
    // day-summary header (income total for the day, same single txn).
    expect(find.text('+₹5,000'), findsNWidgets(2));
    // ₹12.34 matches 2x: Expense stat + Expenses chip.
    expect(find.text('₹12.34'), findsNWidgets(2));
    // "−₹12.34" matches 2x: the ledger row (expense) + that date's own
    // day-summary header (expense total for the day, same single txn).
    expect(find.text('−₹12.34'), findsNWidgets(2));
    // Ring amount = income − expenses − investments.
    expect(find.text('₹4,987.66'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'ring and income figures stay month-scoped regardless of timeline zoom',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedMonthIncomeAndTodayExpense(db);

    await _pump(tester, db);

    // Default Month zoom shows both transactions.
    expect(find.text('₹5,000'), findsOneWidget); // Income stat
    // ledger row (income) + that date's day-summary header.
    expect(find.text('+₹5,000'), findsNWidgets(2));

    // Switch to Day zoom: the Income stat (month-scoped) is unchanged, but
    // the timeline narrows to just today — the 1st's income drops out of
    // the ledger view even though its total still counts toward the stat.
    await tester.tap(find.text('Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('₹5,000'), findsOneWidget); // Income stat still shown
    expect(find.text('+₹5,000'), findsNothing); // income row gone (not today)
    expect(find.text('−₹12.34'), findsOneWidget); // today's expense remains

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('transactions are grouped by date in a chronological ledger',
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

    final now = DateTime.now();
    final firstNoon =
        DateTime(now.year, now.month, 1, 12).toUtc().millisecondsSinceEpoch;
    final secondNoon =
        DateTime(now.year, now.month, 2, 12).toUtc().millisecondsSinceEpoch;
    await _seedTxn(db,
        id: 't1',
        amount: 100,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: firstNoon);
    await _seedTxn(db,
        id: 't2',
        amount: 200,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: secondNoon);

    await _pump(tester, db);

    final firstLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final secondLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}-02';
    expect(find.text(firstLabel), findsOneWidget);
    expect(find.text(secondLabel), findsOneWidget);

    // Newest date group is on top.
    final firstY = tester.getTopLeft(find.text(firstLabel)).dy;
    final secondY = tester.getTopLeft(find.text(secondLabel)).dy;
    expect(secondY, lessThan(firstY));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'every date group header is left-aligned and shows that day\'s income (green) / '
      'expense-incl-investment (red) totals — not just the latest day',
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
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Mutual Funds',
      emoji: '📈',
      kind: TransactionKind.investment,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c3',
      name: 'Salary',
      emoji: '💼',
      kind: TransactionKind.income,
      createdAt: 0,
      updatedAt: 0,
    ));

    final now = DateTime.now();
    final firstNoon =
        DateTime(now.year, now.month, 1, 12).toUtc().millisecondsSinceEpoch;
    final secondNoon =
        DateTime(now.year, now.month, 2, 12).toUtc().millisecondsSinceEpoch;
    // Day 1: two income + two expense rows, none individually matching the
    // day total — proves the header shows the day's *sum*, not a row echo.
    await _seedTxn(db,
        id: 't1', amount: 300000, kind: TransactionKind.income,
        categoryId: 'c3', occurredAtMs: firstNoon); // ₹3,000
    await _seedTxn(db,
        id: 't2', amount: 200000, kind: TransactionKind.income,
        categoryId: 'c3', occurredAtMs: firstNoon); // ₹2,000 (day total ₹5,000)
    await _seedTxn(db,
        id: 't3', amount: 10000, kind: TransactionKind.expense,
        categoryId: 'c1', occurredAtMs: firstNoon); // ₹100
    await _seedTxn(db,
        id: 't4', amount: 20000, kind: TransactionKind.expense,
        categoryId: 'c1', occurredAtMs: firstNoon); // ₹200 (day total ₹300)
    // Day 2: investment + expense, no income — outflow folds both in.
    await _seedTxn(db,
        id: 't5', amount: 200000, kind: TransactionKind.investment,
        categoryId: 'c2', occurredAtMs: secondNoon); // ₹2,000
    await _seedTxn(db,
        id: 't6', amount: 10000, kind: TransactionKind.expense,
        categoryId: 'c1', occurredAtMs: secondNoon); // ₹100 (day total outflow ₹2,100)

    await _pump(tester, db);

    final firstLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final secondLabel = '${now.year}-${now.month.toString().padLeft(2, '0')}-02';

    // Day 1: income ₹5,000 (green) and expense ₹300 (red) — both shown.
    expect(find.text('+₹5,000'), findsOneWidget);
    expect(find.text('−₹300'), findsOneWidget);
    // Day 2 (not the latest day, and not "today"): outflow ₹2,100 shown too,
    // proving the summary isn't limited to the most recent date group.
    expect(find.text('−₹2,100'), findsOneWidget);

    // Both dates are left-aligned in their row, not centered — left edge
    // sits at the row's own left edge (no extra horizontal inset).
    for (final label in [firstLabel, secondLabel]) {
      final dateLeft = tester.getTopLeft(find.text(label)).dx;
      expect(dateLeft, lessThan(20));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ledger rows show the recorded time-of-day', (tester) async {
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

    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 8, 30)
        .toUtc()
        .millisecondsSinceEpoch;
    final evening = DateTime(now.year, now.month, now.day, 19, 45)
        .toUtc()
        .millisecondsSinceEpoch;
    await _seedTxn(db,
        id: 't1',
        amount: 100,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: morning);
    await _seedTxn(db,
        id: 't2',
        amount: 200,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: evening);

    await _pump(tester, db);

    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('19:45'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'FAB opens a kind-picker sheet (Income/Expense/Investment, no Transfer) → Add screen',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Home's own "Income"/"Expense" stat labels are still mounted behind the
    // sheet, so scope to the sheet's ListTiles.
    expect(find.widgetWithText(ListTile, 'Income'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Expense'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Investment'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Transfer'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add Transaction'), findsOneWidget);
    final pill =
        tester.widget<KindPillSelector>(find.byType(KindPillSelector));
    expect(pill.selected, TransactionKind.income);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping a ledger row opens it for editing', (tester) async {
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
    await _seedTxn(db,
        id: 't1',
        amount: 1234,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs:
            DateTime.now().toUtc().millisecondsSinceEpoch);

    await _pump(tester, db);

    // "Food" also appears on the quick-add chip; only the ledger row is a
    // ListTile.
    await tester.tap(find.widgetWithText(ListTile, 'Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('greeting reflects the injected clock and profile name',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncMetaDao.put('display_name', 'Aashish');

    await _pump(tester, db, now: () => DateTime(2026, 7, 14, 9, 0));

    expect(find.text('Good Morning, Aashish'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('greeting falls back to no name when none is set',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db, now: () => DateTime(2026, 7, 14, 20, 0));

    expect(find.text('Good Evening'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'month switcher: previous chevron swaps to last month\'s transactions',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'ThisMonthCat',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'LastMonthCat',
      emoji: '📦',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));

    final now = DateTime.now();
    final thisMonthNoon =
        DateTime(now.year, now.month, 15, 12).toUtc().millisecondsSinceEpoch;
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final lastMonthNoon = DateTime(lastMonth.year, lastMonth.month, 15, 12)
        .toUtc()
        .millisecondsSinceEpoch;

    await _seedTxn(db,
        id: 't1',
        amount: 100,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: thisMonthNoon);
    await _seedTxn(db,
        id: 't2',
        amount: 200,
        kind: TransactionKind.expense,
        categoryId: 'c2',
        occurredAtMs: lastMonthNoon);

    await _pump(tester, db);

    expect(find.text('ThisMonthCat'), findsWidgets);
    expect(find.text('LastMonthCat'), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('LastMonthCat'), findsWidgets);
    expect(find.text('ThisMonthCat'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('month switcher: cannot advance past the current month',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);

    final nextButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(nextButton.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'swiping the month ring browses months, and cannot advance past the current month',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'ThisMonthCat',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'LastMonthCat',
      emoji: '📦',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));

    final now = DateTime.now();
    final thisMonthNoon =
        DateTime(now.year, now.month, 15, 12).toUtc().millisecondsSinceEpoch;
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final lastMonthNoon = DateTime(lastMonth.year, lastMonth.month, 15, 12)
        .toUtc()
        .millisecondsSinceEpoch;

    await _seedTxn(db,
        id: 't1',
        amount: 100,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: thisMonthNoon);
    await _seedTxn(db,
        id: 't2',
        amount: 200,
        kind: TransactionKind.expense,
        categoryId: 'c2',
        occurredAtMs: lastMonthNoon);

    await _pump(tester, db);

    expect(find.text('ThisMonthCat'), findsWidgets);
    expect(find.text('LastMonthCat'), findsNothing);

    // Swipe right-to-left over the ring → next month. Already on the
    // current month, so this is a no-op (mirrors the disabled next arrow).
    await tester.fling(find.byType(MonthRing), const Offset(-300, 0), 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ThisMonthCat'), findsWidgets);
    expect(find.text('LastMonthCat'), findsNothing);

    // Swipe left-to-right over the ring → previous month.
    await tester.fling(find.byType(MonthRing), const Offset(300, 0), 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('LastMonthCat'), findsWidgets);
    expect(find.text('ThisMonthCat'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'month ring: centre shows income − expenses − investments "left to spend"',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncMetaDao.put('monthly_budget_cents', '1000000'); // ₹10,000
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Salary',
      emoji: '💼',
      kind: TransactionKind.income,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c3',
      name: 'Mutual Funds',
      emoji: '📈',
      kind: TransactionKind.investment,
      createdAt: 0,
      updatedAt: 0,
    ));
    final now = DateTime.now();
    final todayNoon =
        DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch;
    await _seedTxn(db,
        id: 't1',
        amount: 482000, // ₹4,820 expense
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: todayNoon);
    await _seedTxn(db,
        id: 't2',
        amount: 600000, // ₹6,000 income
        kind: TransactionKind.income,
        categoryId: 'c2',
        occurredAtMs: todayNoon);
    await _seedTxn(db,
        id: 't3',
        amount: 100000, // ₹1,000 investment
        kind: TransactionKind.investment,
        categoryId: 'c3',
        occurredAtMs: todayNoon);

    await _pump(tester, db);

    // 6,000 − 4,820 − 1,000 = ₹180 left.
    expect(find.text('₹180'), findsOneWidget); // ring amount (bold)
    expect(find.text('left to spend'), findsOneWidget); // descriptor
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    expect(find.text('Day ${now.day}/$daysInMonth'), findsOneWidget);

    // Fill = outflows / income: (4,820 + 1,000) / 6,000 = 0.97.
    final ring = tester.widget<MonthRing>(find.byType(MonthRing));
    expect(ring.progress, closeTo(0.97, 0.0001));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('month ring: outflows beyond income show "overspent"',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncMetaDao.put('monthly_budget_cents', '100000'); // ₹1,000
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await _seedTxn(db,
        id: 't1',
        amount: 150000, // ₹1,500 expense, no income this month
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: DateTime.now().toUtc().millisecondsSinceEpoch);

    await _pump(tester, db);

    // ₹1,500 matches 3x: ring amount + Expense stat + Expenses chip.
    expect(find.text('₹1,500'), findsNWidgets(3));
    expect(find.text('overspent'), findsOneWidget); // descriptor
    final ring = tester.widget<MonthRing>(find.byType(MonthRing));
    expect(ring.progress, 1.0); // outflows with no income → ring full

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('month ring: empty month → ₹0 left, empty ring, no hint',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);

    expect(find.text('left to spend'), findsOneWidget); // descriptor
    // The budget-driven "Set a budget" hint is gone — the ring fills from
    // outflows vs income now, no setup required.
    expect(find.text('Set a budget'), findsNothing);
    final ring = tester.widget<MonthRing>(find.byType(MonthRing));
    expect(ring.progress, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'month ring: past month shows "left over" (not "left to spend") and no Day line',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.syncMetaDao.put('monthly_budget_cents', '1000000');
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Food',
      emoji: '🍔',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Salary',
      emoji: '💼',
      kind: TransactionKind.income,
      createdAt: 0,
      updatedAt: 0,
    ));
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final lastMonthNoon = DateTime(lastMonth.year, lastMonth.month, 15, 12)
        .toUtc()
        .millisecondsSinceEpoch;
    await _seedTxn(db,
        id: 't1',
        amount: 100000, // ₹1,000 expense
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs: lastMonthNoon);
    await _seedTxn(db,
        id: 't2',
        amount: 300000, // ₹3,000 income
        kind: TransactionKind.income,
        categoryId: 'c2',
        occurredAtMs: lastMonthNoon);

    await _pump(tester, db);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 3,000 − 1,000 = ₹2,000 left over.
    expect(find.text('₹2,000'), findsOneWidget); // ring amount (bold)
    expect(find.text('left over'), findsOneWidget); // past-month descriptor
    expect(find.text('left to spend'), findsNothing);
    expect(find.textContaining('Day '), findsNothing);
    // Day/Week zoom only makes sense for the current month.
    expect(find.byType(ZoomPillSelector), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Day zoom shows only today\'s transactions with no header',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedMonthIncomeAndTodayExpense(db);

    await _pump(tester, db);
    await tester.tap(find.text('Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Food'), findsOneWidget); // today's expense
    expect(find.text('Salary'), findsNothing); // 1st's income excluded
    final now = DateTime.now();
    expect(
        find.text(
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'),
        findsNothing); // no date-group header in Day zoom

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Day zoom empty state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.text('Day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('No transactions today.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'Week zoom shows one row per weekday with a spend total; tap expands it',
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
    final now = DateTime.now();
    await _seedTxn(db,
        id: 't1',
        amount: 50000,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs:
            DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch);

    await _pump(tester, db);
    await tester.tap(find.text('Week'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // One row per weekday of the current week.
    for (final name in weekdayNames) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Spent ₹500'), findsOneWidget); // today's total
    expect(find.text('Food'), findsNothing); // collapsed by default

    await tester.tap(find.text('Spent ₹500'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Food'), findsOneWidget); // expanded reveals the txn

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'summary chips: expenses/investments actuals + recurring projection',
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
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2',
      name: 'Mutual Funds',
      emoji: '📈',
      kind: TransactionKind.investment,
      createdAt: 0,
      updatedAt: 0,
    ));
    final now = DateTime.now();
    await _seedTxn(db,
        id: 't1',
        amount: 30000,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAtMs:
            DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch);
    await _seedTxn(db,
        id: 't2',
        amount: 200000,
        kind: TransactionKind.investment,
        categoryId: 'c2',
        occurredAtMs:
            DateTime(now.year, now.month, now.day, 12).toUtc().millisecondsSinceEpoch);
    // Active monthly recurring rule (fires once this month) → ₹649 projected.
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 64900,
      kind: TransactionKind.expense,
      cron: '0 0 1 * *',
      createdAt: 0,
      updatedAt: 0,
    ));

    await _pump(tester, db);

    // ₹300 matches once: the Expenses chip only — the Expense stat now shows
    // total outflow (expense + investment), not the expense-only figure.
    expect(find.text('₹300'), findsOneWidget);
    // ₹2,300 matches twice: ring amount + Expense stat (expense + investment
    // = income − expenses − investments = −₹2,300 → "₹2,300 overspent").
    expect(find.text('₹2,300'), findsNWidgets(2));
    // ₹2,000 matches twice: the ledger row (unsigned, investment) + the
    // Investments summary chip.
    expect(find.text('₹2,000'), findsNWidgets(2));
    expect(find.text('₹649'), findsOneWidget); // Recurring chip (projected)

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('insight card renders for an active rule firing tomorrow',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Entertainment',
      emoji: '🎬',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.recurringDao.upsertRule(RecurringRulesCompanion.insert(
      id: 'r1',
      categoryId: 'c1',
      amount: 64900,
      kind: TransactionKind.expense,
      cron: '0 0 * * *', // daily → fires tomorrow relative to `now`
      note: const Value('Netflix'),
      createdAt: 0,
      updatedAt: 0,
    ));

    await _pump(tester, db, now: () => DateTime(2026, 7, 14, 9, 0));

    expect(find.text('Netflix renews tomorrow'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('insight card absent when no rule fires within 7 days',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db, now: () => DateTime(2026, 7, 14, 9, 0));

    expect(find.byIcon(Icons.autorenew), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('timeline category filter narrows the ledger to one category',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedMonthIncomeAndTodayExpense(db); // Salary income + Food expense

    await _pump(tester, db);

    // Both categories' rows visible; filter shows "All".
    expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Salary'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    // Open the filter and pick Food.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // menu open
    await tester.tap(find.widgetWithText(PopupMenuItem<String?>, 'Food'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // menu close
    await tester.pump(const Duration(milliseconds: 300)); // route removal

    expect(find.widgetWithText(ListTile, 'Food'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Salary'), findsNothing);
    // Button label reflects the selection ('Food' = row title + button label).
    expect(find.text('Food'), findsNWidgets(2));

    // Back to All restores everything.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(ListTile, 'Salary'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ledger rows show the recorded time on the left and note below',
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
    final now = DateTime.now();
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 18000,
      kind: TransactionKind.expense,
      categoryId: 'c1',
      occurredAt: DateTime(now.year, now.month, now.day, 9, 30)
          .toUtc()
          .millisecondsSinceEpoch,
      source: TransactionSource.manual,
      createdAt: 0,
      updatedAt: 0,
      note: const Value('Cafe Coffee Day'),
    ));

    await _pump(tester, db);

    final row = find.widgetWithText(ListTile, 'Food');
    expect(row, findsOneWidget);
    // Time renders inside the row's leading (left side), note as subtitle.
    expect(find.descendant(of: row, matching: find.text('09:30')),
        findsOneWidget);
    expect(
        find.descendant(of: row, matching: find.text('Cafe Coffee Day')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'investment amounts render gold; amount font matches the note subtitle',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1',
      name: 'Mutual Funds',
      emoji: '📈',
      kind: TransactionKind.investment,
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
      id: 't1',
      amount: 100000,
      kind: TransactionKind.investment,
      categoryId: 'c1',
      occurredAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      source: TransactionSource.manual,
      createdAt: 0,
      updatedAt: 0,
      note: const Value('SIP'),
    ));

    await _pump(tester, db);

    final row = find.widgetWithText(ListTile, 'Mutual Funds');
    final amountText = tester.widget<Text>(
        find.descendant(of: row, matching: find.text('₹1,000')));
    expect(amountText.style?.color, kGold);

    // The note (ListTile's subtitle) has no explicit style of its own —
    // it inherits bodyMedium from the ListTile's subtitle theme. The
    // amount's explicit fontSize should match that same value.
    final context = tester.element(find.text('SIP'));
    final bodyMediumSize = Theme.of(context).textTheme.bodyMedium?.fontSize;
    expect(amountText.style?.fontSize, bodyMediumSize);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
