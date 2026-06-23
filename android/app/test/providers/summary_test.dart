import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/summary.dart';

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
}
