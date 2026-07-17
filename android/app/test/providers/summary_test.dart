import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/summary.dart';
import 'package:spendarr/providers/transactions.dart' show localDayTickProvider;

void main() {
  group('rangeForPeriod', () {
    // Wed 17 Jun 2026, 15:00 local.
    final now = DateTime(2026, 6, 17, 15, 0);

    ({int startMs, int endMs}) r(HistoryPeriod p) => rangeForPeriod(p, now);

    DateTime localOf(int ms) =>
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

    test('day = the local calendar day', () {
      final range = r(HistoryPeriod.day);
      expect(localOf(range.startMs), DateTime(2026, 6, 17));
      expect(localOf(range.endMs), DateTime(2026, 6, 18));
    });

    test('week = Monday..next Monday', () {
      final range = r(HistoryPeriod.week);
      expect(localOf(range.startMs), DateTime(2026, 6, 15)); // Mon
      expect(localOf(range.startMs).weekday, DateTime.monday);
      expect(localOf(range.endMs), DateTime(2026, 6, 22));
    });

    test('month = 1st..1st of next month', () {
      final range = r(HistoryPeriod.month);
      expect(localOf(range.startMs), DateTime(2026, 6, 1));
      expect(localOf(range.endMs), DateTime(2026, 7, 1));
    });
  });

  group('aggregateSpendByCategory', () {
    Category cat(String id, String name, String emoji) => Category(
          id: id,
          name: name,
          emoji: emoji,
          kind: TransactionKind.expense,
          createdAt: 0,
          updatedAt: 0,
          deletedAt: null,
        );

    TransactionRow txn(String id, String catId, int amount, TransactionKind k) =>
        TransactionRow(
          id: id,
          amount: amount,
          kind: k,
          categoryId: catId,
          occurredAt: 0,
          source: TransactionSource.manual,
          createdAt: 0,
          updatedAt: 0,
          note: null,
          recurringRuleId: null,
          deletedAt: null,
        );

    test('sums expenses per category, excludes income/investment, sorts desc',
        () {
      final categories = [cat('c1', 'Food', '🍔'), cat('c2', 'Rent', '🏠')];
      final txns = [
        txn('t1', 'c1', 1000, TransactionKind.expense),
        txn('t2', 'c1', 500, TransactionKind.expense),
        txn('t3', 'c2', 5000, TransactionKind.expense),
        txn('t4', 'c1', 9999, TransactionKind.income), // ignored
        txn('t5', 'c2', 8888, TransactionKind.investment), // ignored
      ];

      final result = aggregateSpendByCategory(txns, categories);
      expect(result, hasLength(2));
      expect(result.first.categoryId, 'c2'); // 5000 > 1500
      expect(result.first.totalCents, 5000);
      expect(result[1].categoryId, 'c1');
      expect(result[1].totalCents, 1500);
      expect(result[1].emoji, '🍔');
    });

    test('unknown category falls back gracefully', () {
      final result = aggregateSpendByCategory(
        [txn('t1', 'ghost', 100, TransactionKind.expense)],
        const [],
      );
      expect(result.single.name, 'Unknown');
    });

    test('empty when no expenses', () {
      expect(aggregateSpendByCategory(const [], const []), isEmpty);
    });
  });

  group('summarizeTransactions', () {
    TransactionRow txn(String id, int amount, TransactionKind k) =>
        TransactionRow(
          id: id,
          amount: amount,
          kind: k,
          categoryId: 'c1',
          occurredAt: 0,
          source: TransactionSource.manual,
          createdAt: 0,
          updatedAt: 0,
          note: null,
          recurringRuleId: null,
          deletedAt: null,
        );

    test('sums income and expense, nets them, excludes investment', () {
      final summary = summarizeTransactions([
        txn('t1', 10000, TransactionKind.income),
        txn('t2', 3000, TransactionKind.expense),
        txn('t3', 5000, TransactionKind.investment),
      ]);

      expect(summary.incomeCents, 10000);
      expect(summary.expenseCents, 3000);
      expect(summary.investmentCents, 5000);
      expect(summary.netCents, 7000);
    });

    test('empty list → all zero', () {
      final summary = summarizeTransactions(const []);
      expect(summary.incomeCents, 0);
      expect(summary.expenseCents, 0);
      expect(summary.investmentCents, 0);
      expect(summary.netCents, 0);
    });
  });

  group('ringProgress (outflows vs income)', () {
    test('no outflows → 0 progress', () {
      expect(ringProgress(0, 10000), 0);
    });

    test('half the income spent → 0.5 progress', () {
      expect(ringProgress(5000, 10000), 0.5);
    });

    test('outflows beyond income clamp to 1', () {
      expect(ringProgress(15000, 10000), 1);
    });

    test('no income: any outflow is fully overspent, none is empty', () {
      expect(ringProgress(5000, 0), 1);
      expect(ringProgress(0, 0), 0);
    });
  });

  group('budgetRingProgress', () {
    test('no budget configured → 0 (blank ring)', () {
      expect(budgetRingProgress(0, 5000), 0);
      expect(budgetRingProgress(0, 0), 0);
    });

    test('zero spend against a budget → full (1)', () {
      expect(budgetRingProgress(10000, 0), 1);
    });

    test('half the budget spent → 0.5', () {
      expect(budgetRingProgress(10000, 5000), 0.5);
    });

    test('overspending drains past zero into negative (red) territory', () {
      expect(budgetRingProgress(10000, 12000), closeTo(-0.2, 0.0001));
    });

    test('overspend by the full budget clamps at -1', () {
      expect(budgetRingProgress(10000, 20000), -1);
      expect(budgetRingProgress(10000, 50000), -1); // clamped, not -4
    });
  });

  group('range query over seeded drift rows', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> seed(String id, int occurredAtMs, int amount) {
      return db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: id,
        amount: amount,
        kind: TransactionKind.expense,
        categoryId: 'c1',
        occurredAt: occurredAtMs,
        source: TransactionSource.manual,
        createdAt: 0,
        updatedAt: 0,
        note: const Value.absent(),
      ));
    }

    test('day/week/month windows select the right rows', () async {
      final now = DateTime(2026, 6, 17, 15, 0);
      int atLocalNoon(int y, int m, int d) =>
          DateTime(y, m, d, 12).toUtc().millisecondsSinceEpoch;

      await seed('today', atLocalNoon(2026, 6, 17), 100); // day, week, month
      await seed('mon', atLocalNoon(2026, 6, 15), 200); // week, month
      await seed('first', atLocalNoon(2026, 6, 1), 400); // month only
      await seed('may', atLocalNoon(2026, 5, 20), 800); // none

      Future<int> totalFor(HistoryPeriod p) async {
        final range = rangeForPeriod(p, now);
        final rows = await db.transactionsDao
            .watchByOccurredRange(range.startMs, range.endMs)
            .first;
        return aggregateSpendByCategory(rows, const [])
            .fold<int>(0, (sum, s) => sum + s.totalCents);
      }

      expect(await totalFor(HistoryPeriod.day), 100);
      expect(await totalFor(HistoryPeriod.week), 300); // today + mon
      expect(await totalFor(HistoryPeriod.month), 700); // today + mon + first
    });
  });

  group('effectiveHomeMonthProvider', () {
    late StreamController<DateTime> dayController;
    late ProviderContainer container;

    setUp(() {
      dayController = StreamController<DateTime>();
      container = ProviderContainer(overrides: [
        localDayTickProvider.overrideWith((ref) => dayController.stream),
      ]);
      container.listen(effectiveHomeMonthProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      await dayController.close();
    });

    test('falls back to the current tick month when the anchor is null',
        () async {
      dayController.add(DateTime(2026, 7, 14));
      await Future<void>.delayed(Duration.zero);

      final month = container.read(effectiveHomeMonthProvider);
      expect(month, (year: 2026, month: 7));
    });

    test('anchored past month overrides the current tick month', () async {
      dayController.add(DateTime(2026, 7, 14));
      await Future<void>.delayed(Duration.zero);

      container.read(homeMonthAnchorProvider.notifier).state =
          (year: 2026, month: 5);

      final month = container.read(effectiveHomeMonthProvider);
      expect(month, (year: 2026, month: 5));

      final range = rangeForPeriod(HistoryPeriod.month, DateTime(2026, 5, 1));
      expect(
        DateTime.fromMillisecondsSinceEpoch(range.startMs, isUtc: true)
            .toLocal(),
        DateTime(2026, 5, 1),
      );
    });
  });
}
