import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../providers/categories.dart';
import '../providers/recurring.dart';
import '../util/money.dart';

String _formatDateMs(int? ms) {
  if (ms == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Recurring rules: list with pause/resume; FAB to add.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(activeRecurringProvider);
    final categories = ref.watch(activeCategoriesProvider).value ?? const <Category>[];
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/recurring/add'),
        child: const Icon(Icons.add),
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rules) {
          if (rules.isEmpty) {
            return const Center(child: Text('No recurring rules yet.'));
          }
          return ListView(
            children: [
              for (final r in rules)
                ListTile(
                  leading: Text(byId[r.categoryId]?.emoji ?? '🔁',
                      style: const TextStyle(fontSize: 24)),
                  title: Text(byId[r.categoryId]?.name ?? 'Unknown category'),
                  subtitle: Text(
                      '${formatCents(r.amount)} · next ${_formatDateMs(r.nextRunAt)}'),
                  trailing: Switch(
                    value: r.active,
                    onChanged: (v) =>
                        ref.read(recurringWriterProvider).setActive(r.id, v),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
