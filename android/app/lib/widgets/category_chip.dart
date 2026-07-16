import 'package:flutter/material.dart';

import '../db/database.dart';
import 'category_icon_bubble.dart';

/// Icon + name chip for a category. Tappable for quick-add on the Today grid.
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, this.onTap});

  final Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: CategoryIconBubble(category.emoji, size: 24),
      label: Text(category.name),
      onPressed: onTap,
    );
  }
}
