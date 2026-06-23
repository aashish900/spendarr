import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';

// Local-only aggregation. The online /summary path + network fallback is
// deferred to B7 (no server data until sync exists). See DECISIONLOG 2026-06-23.

/// History grouping.
enum HistoryPeriod { day, week, month }

/// UTC epoch-ms half-open range `[startMs, endMs)` for a period relative to the
/// local calendar of [now].
({int startMs, int endMs}) rangeForPeriod(HistoryPeriod period,
    [DateTime? now]) {
  final n = now ?? DateTime.now();
  final startOfDay = DateTime(n.year, n.month, n.day);

  int ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;

  switch (period) {
    case HistoryPeriod.day:
      return (startMs: ms(startOfDay), endMs: ms(startOfDay.add(const Duration(days: 1))));
    case HistoryPeriod.week:
      // Week starts Monday (weekday: Mon=1 … Sun=7).
      final monday = startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
      return (startMs: ms(monday), endMs: ms(monday.add(const Duration(days: 7))));
    case HistoryPeriod.month:
      final start = DateTime(n.year, n.month, 1);
      final end = n.month == 12
          ? DateTime(n.year + 1, 1, 1)
          : DateTime(n.year, n.month + 1, 1);
      return (startMs: ms(start), endMs: ms(end));
  }
}

/// Per-category expense total for the History bar chart.
class SpendByCategory {
  const SpendByCategory({
    required this.categoryId,
    required this.name,
    required this.emoji,
    required this.totalCents,
  });

  final String categoryId;
  final String name;
  final String emoji;
  final int totalCents;
}

/// Aggregate **expense** spend by category, joined with category metadata,
/// sorted by total descending. Income/investment are not "spend".
List<SpendByCategory> aggregateSpendByCategory(
  List<TransactionRow> txns,
  List<Category> categories,
) {
  final byId = {for (final c in categories) c.id: c};
  final totals = <String, int>{};
  for (final t in txns) {
    if (t.kind != TransactionKind.expense) continue;
    totals.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
  }

  final result = [
    for (final entry in totals.entries)
      SpendByCategory(
        categoryId: entry.key,
        name: byId[entry.key]?.name ?? 'Unknown',
        emoji: byId[entry.key]?.emoji ?? '❓',
        totalCents: entry.value,
      ),
  ];
  result.sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return result;
}

/// Non-deleted transactions in a `[startMs, endMs)` range. Keyed by the range
/// record (records have value equality, so identical ranges share state).
final transactionsInRangeProvider =
    StreamProvider.family<List<TransactionRow>, (int, int)>((ref, range) {
  return ref
      .watch(appDatabaseProvider)
      .transactionsDao
      .watchByOccurredRange(range.$1, range.$2);
});
