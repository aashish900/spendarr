import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../theme.dart';
import '../widgets/category_icon_bubble.dart';
import '../widgets/gilded.dart';
import '../widgets/gold_fab.dart';

String kindLabel(TransactionKind kind) => switch (kind) {
      TransactionKind.income => 'Income',
      TransactionKind.expense => 'Expense',
      TransactionKind.investment => 'Investment',
    };

/// Categories: grid of non-archived categories (3 per row) with an archive
/// action, grouped and segregated by kind.
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
                  // A single-column ListTile per category wasted most of
                  // the row's width on a short name — 3 columns fit far
                  // more categories on screen without scrolling.
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: group.length,
                    itemBuilder: (context, i) {
                      final c = group[i];
                      return _CategoryTile(
                        category: c,
                        onTap: () => context
                            .push('/categories/add?editCategoryId=${c.id}'),
                        onArchive: () =>
                            ref.read(categoryWriterProvider).archive(c.id),
                      );
                    },
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onTap,
    required this.onArchive,
  });

  final Category category;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CategoryIconBubble(category.emoji, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Gilded(
                child: const Icon(Icons.archive_outlined,
                    size: 18, color: Colors.white),
              ),
              tooltip: 'Archive',
              onPressed: onArchive,
            ),
          ),
        ],
      ),
    );
  }
}
