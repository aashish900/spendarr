import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/category_icon.dart';
import 'gilded.dart';

/// Dark circle bubble with a gold themed icon for a category, replacing raw
/// colourful `Text(emoji)` rendering everywhere a category is shown (mockup:
/// every category row uses a monochrome gold line-icon in a dark bubble, not
/// a native emoji). The stored `emoji` string is only used to look up the
/// icon via [categoryIconFor] — display-only, see DECISIONLOG.
class CategoryIconBubble extends StatelessWidget {
  const CategoryIconBubble(this.emoji, {super.key, this.size = 40});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: kBackgroundBlack,
      child: Gilded(
        child: Icon(categoryIconFor(emoji), color: Colors.white, size: size * 0.55),
      ),
    );
  }
}
