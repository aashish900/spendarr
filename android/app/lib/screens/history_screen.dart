import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/summary.dart';
import '../util/money.dart';
import '../widgets/spend_bar_chart.dart';

String _periodLabel(HistoryPeriod p) => switch (p) {
      HistoryPeriod.day => 'Day',
      HistoryPeriod.week => 'Week',
      HistoryPeriod.month => 'Month',
    };

String _dateMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// History: spend-by-category bar chart + transaction list for a period or a
/// custom date range. Local drift aggregation only (online /summary → B7).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryPeriod _period = HistoryPeriod.month;
  ({int startMs, int endMs})? _customRange;

  ({int startMs, int endMs}) get _range =>
      _customRange ?? rangeForPeriod(_period);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
      final endExclusive =
          DateTime(picked.end.year, picked.end.month, picked.end.day)
              .add(const Duration(days: 1));
      setState(() => _customRange = (
            startMs: start.toUtc().millisecondsSinceEpoch,
            endMs: endExclusive.toUtc().millisecondsSinceEpoch,
          ));
    }
  }

  Color? _amountColor(BuildContext context, TransactionKind kind) =>
      switch (kind) {
        TransactionKind.expense => Theme.of(context).colorScheme.error,
        TransactionKind.income => Colors.green,
        TransactionKind.investment => null,
      };

  String _signedAmount(TransactionRow t) => switch (t.kind) {
        TransactionKind.expense => '-${formatCents(t.amount)}',
        TransactionKind.income => '+${formatCents(t.amount)}',
        TransactionKind.investment => formatCents(t.amount),
      };

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final txnsAsync = ref.watch(transactionsInRangeProvider((range.startMs, range.endMs)));
    final categories =
        ref.watch(activeCategoriesProvider).value ?? const <Category>[];
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Pick range',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<HistoryPeriod>(
              segments: [
                for (final p in HistoryPeriod.values)
                  ButtonSegment(value: p, label: Text(_periodLabel(p))),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() {
                _period = s.first;
                _customRange = null; // period toggle clears a custom range
              }),
            ),
          ),
          if (_customRange != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  '${_dateMs(range.startMs)} → ${_dateMs(range.endMs - 1)}'),
            ),
          Expanded(
            child: txnsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (txns) {
                if (txns.isEmpty) {
                  return const Center(
                      child: Text('No transactions in this range.'));
                }
                final spend = aggregateSpendByCategory(txns, categories);
                return ListView(
                  children: [
                    if (spend.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SpendBarChart(data: spend),
                      ),
                    const Divider(),
                    for (final t in txns)
                      ListTile(
                        leading: Text(byId[t.categoryId]?.emoji ?? '❓',
                            style: const TextStyle(fontSize: 22)),
                        title: Text(byId[t.categoryId]?.name ?? 'Unknown'),
                        subtitle: Text(
                          [
                            _dateMs(t.occurredAt),
                            if (t.note != null && t.note!.isNotEmpty) t.note!,
                          ].join(' · '),
                        ),
                        trailing: Text(
                          _signedAmount(t),
                          style: TextStyle(color: _amountColor(context, t.kind)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
