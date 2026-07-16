import 'package:flutter/material.dart';

import '../theme.dart';
import 'gilded.dart';

/// Dark circle bubble with the category's own emoji, gilded gold via
/// [Gilded]'s `BlendMode.srcIn` — the shader replaces the emoji glyph's
/// native colour with the app's metallic gold gradient, keeping only its
/// alpha silhouette. This lets a user pick *any* emoji (not just a curated
/// set) and still see it rendered on-theme everywhere in the app — see
/// DECISIONLOG for the switch away from the earlier fixed emoji→icon map.
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
        child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}
