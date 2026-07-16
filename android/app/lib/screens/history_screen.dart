import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/summary.dart';
import '../theme.dart';
import '../util/datetime.dart';
import '../util/money.dart';
import '../widgets/category_icon_bubble.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';
import '../widgets/pill_selector.dart';
import '../widgets/spend_bar_chart.dart';

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
        TransactionKind.income => kIncomeGreen,
        TransactionKind.investment => kGold,
      };

  String _signedAmount(TransactionRow t) => switch (t.kind) {
        TransactionKind.expense => formatRupees(-t.amount),
        TransactionKind.income => formatRupees(t.amount, signed: true),
        TransactionKind.investment => formatRupees(t.amount),
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
            icon: Gilded(child: const Icon(Icons.ios_share, color: Colors.white)),
            tooltip: 'Export CSV',
            onPressed: () => context.push('/export'),
          ),
          IconButton(
            icon: Gilded(child: const Icon(Icons.date_range, color: Colors.white)),
            tooltip: 'Pick range',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: PillSelector<HistoryPeriod>(
              items: HistoryPeriod.values,
              selected: _period,
              labelFor: periodLabel,
              onChanged: (p) => setState(() {
                _period = p;
                _customRange = null; // period toggle clears a custom range
              }),
            ),
          ),
          if (_customRange != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: kSurfaceBlack,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kCardBorder),
                ),
                child: Text(
                  '${_dateMs(range.startMs)} → ${_dateMs(range.endMs - 1)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: kTextSecondary),
                ),
              ),
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
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    if (spend.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('SPEND BY CATEGORY'),
                            FieldCard(child: SpendBarChart(data: spend)),
                          ],
                        ),
                      ),
                    const Divider(),
                    for (final t in txns)
                      ListTile(
                        onTap: () =>
                            context.push('/add?editTransactionId=${t.id}'),
                        leading: CategoryIconBubble(
                            byId[t.categoryId]?.emoji ?? '', size: 32),
                        title: Text(byId[t.categoryId]?.name ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_dateMs(t.occurredAt)} ${formatTimeOfDay(t.occurredAt)}',
                              style: const TextStyle(color: kTextSecondary),
                            ),
                            if (t.note != null && t.note!.isNotEmpty)
                              Text(t.note!,
                                  style: const TextStyle(color: kTextSecondary)),
                          ],
                        ),
                        trailing: Text(
                          _signedAmount(t),
                          style: TextStyle(
                            color: _amountColor(context, t.kind),
                            // Same size as the note/date subtitle line.
                            fontSize: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.fontSize,
                          ),
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
