import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../providers/categories.dart';
import '../providers/transactions.dart';
import '../util/money.dart';
import '../widgets/category_chip.dart';

/// Today: net flow for the local day + a chip grid of the categories used
/// today (tap to quick-add another in the same category).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayTransactionsProvider);
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
      body: todayAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (txns) {
          final net = netFlowCents(txns);
          final categories = categoriesAsync.value ?? const <Category>[];
          final byId = {for (final c in categories) c.id: c};
          // Distinct categories used today, preserving newest-first order.
          final usedToday = <Category>[];
          final seen = <String>{};
          for (final t in txns) {
            if (seen.add(t.categoryId) && byId.containsKey(t.categoryId)) {
              usedToday.add(byId[t.categoryId]!);
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net flow today',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  formatCents(net),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: net < 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                ),
                const SizedBox(height: 24),
                if (usedToday.isEmpty)
                  const Text('No transactions yet today.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in usedToday)
                        CategoryChip(
                          category: c,
                          onTap: () =>
                              context.push('/add?categoryId=${c.id}'),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
