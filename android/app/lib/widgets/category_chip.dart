import 'package:flutter/material.dart';

import '../db/database.dart';

/// Emoji + name chip for a category. Tappable for quick-add on the Today grid.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, this.onTap});

  final Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Text(category.emoji, style: const TextStyle(fontSize: 18)),
      label: Text(category.name),
      onPressed: onTap,
    );
  }
}
