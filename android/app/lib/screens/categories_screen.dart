import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/tables.dart';
import '../providers/categories.dart';

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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/categories/add'),
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No categories yet.'));
          }
          return ListView(
            children: [
              for (final c in categories)
                ListTile(
                  leading: Text(c.emoji,
                      style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  subtitle: Text(kindLabel(c.kind)),
                  trailing: IconButton(
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'Archive',
                    onPressed: () =>
                        ref.read(categoryWriterProvider).archive(c.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
