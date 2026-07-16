import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../widgets/category_icon_bubble.dart';
import '../widgets/gilded.dart';
import '../widgets/gold_fab.dart';

String kindLabel(TransactionKind kind) => switch (kind) {
      TransactionKind.income => 'Income',
      TransactionKind.expense => 'Expense',
      TransactionKind.investment => 'Investment',
    };

/// Categories: list of non-archived categories with an archive action.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: GoldFab(
        heroTag: 'categories-fab',
        onPressed: () => context.push('/categories/add'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No categories yet.'));
          }
          // Grouped and segregated by kind — a category's kind is intrinsic
          // to what it means (Salary is always income), so the list makes
          // that grouping visible rather than mixing all three together.
          final byKind = <TransactionKind, List<Category>>{};
          for (final c in categories) {
            byKind.putIfAbsent(c.kind, () => []).add(c);
          }

          return ListView(
            children: [
              for (final kind in TransactionKind.values)
                if (byKind[kind] case final group? when group.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Gilded(
                      child: Text(
                        kindLabel(kind),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  for (final c in group)
                    ListTile(
                      leading: CategoryIconBubble(c.emoji, size: 36),
                      title: Text(c.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Archive',
                        onPressed: () =>
                            ref.read(categoryWriterProvider).archive(c.id),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}
