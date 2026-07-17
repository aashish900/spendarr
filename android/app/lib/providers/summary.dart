import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';
import 'transactions.dart' show localDayTickProvider;

// Local-only aggregation. The online /summary path + network fallback is
// deferred to B7 (no server data until sync exists). See DECISIONLOG 2026-06-23.

/// History grouping.
enum HistoryPeriod { day, week, month }

String periodLabel(HistoryPeriod p) => switch (p) {
      HistoryPeriod.day => 'Day',
      HistoryPeriod.week => 'Week',
      HistoryPeriod.month => 'Month',
    };

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

/// Income / expense / investment totals for a period. Net excludes
/// investment, consistent with [netFlowCents] in providers/transactions.dart.
class PeriodSummary {
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    this.investmentCents = 0,
  });

  final int incomeCents;
  final int expenseCents;
  final int investmentCents;
  int get netCents => incomeCents - expenseCents;
}

/// Sums income, expense and investment (net excludes investment).
PeriodSummary summarizeTransactions(List<TransactionRow> txns) {
  var income = 0;
  var expense = 0;
  var investment = 0;
  for (final t in txns) {
    switch (t.kind) {
      case TransactionKind.income:
        income += t.amount;
      case TransactionKind.expense:
        expense += t.amount;
      case TransactionKind.investment:
        investment += t.amount;
    }
  }
  return PeriodSummary(
    incomeCents: income,
    expenseCents: expense,
    investmentCents: investment,
  );
}

/// Month-ring fill fraction: outflows (expenses + investments) as a fraction
/// of the month's income, clamped to `[0, 1]` — consistent with the ring's
/// centre figure (income − outflows): a full ring means everything earned
/// this month has been spent. With no income recorded, any outflow at all
/// means fully overspent (`1`); no income and no outflows is `0`.
double ringProgress(int outflowCents, int incomeCents) {
  if (incomeCents <= 0) return outflowCents > 0 ? 1 : 0;
  return (outflowCents / incomeCents).clamp(0, 1).toDouble();
}

/// Budget-based month-ring fill: `1` (full, gold) at zero spend, draining
/// toward `0` as [outflowCents] approaches [budgetCents], then negative
/// (red, opposite direction) once overspent — clamped at `-1` once the
/// overspend itself reaches the budget amount. `0` (blank ring) when no
/// budget is configured.
double budgetRingProgress(int budgetCents, int outflowCents) {
  if (budgetCents <= 0) return 0;
  return ((budgetCents - outflowCents) / budgetCents).clamp(-1.0, 1.0);
}

/// User-selected Home month, or `null` to follow the current calendar month.
/// Set by the month-switcher chevrons; capped at the current month (no
/// browsing into the future).
final homeMonthAnchorProvider =
    StateProvider<({int year, int month})?>((ref) => null);

/// The month Home actually displays: the anchor if set, otherwise the
/// current month from [localDayTickProvider] (so an unset anchor still rolls
/// over automatically at the month boundary).
final effectiveHomeMonthProvider = Provider<({int year, int month})>((ref) {
  final anchor = ref.watch(homeMonthAnchorProvider);
  if (anchor != null) return anchor;
  final day = ref.watch(localDayTickProvider).value ?? DateTime.now();
  return (year: day.year, month: day.month);
});

/// Non-deleted transactions in a `[startMs, endMs)` range. Keyed by the range
/// record (records have value equality, so identical ranges share state).
final transactionsInRangeProvider =
    StreamProvider.family<List<TransactionRow>, (int, int)>((ref, range) {
  return ref
      .watch(appDatabaseProvider)
      .transactionsDao
      .watchByOccurredRange(range.$1, range.$2);
});
