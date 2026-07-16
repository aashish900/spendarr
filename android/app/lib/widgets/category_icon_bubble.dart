import 'package:flutter/material.dart';

import '../theme.dart';

/// Dark circle bubble with the category's own emoji in its native colour.
/// Letting a user pick *any* emoji (not just a curated set) means the glyph
/// is a multi-colour bitmap, not a single-colour line icon — gilding it via
/// `ShaderMask`'s `BlendMode.srcIn` (an earlier attempt) discarded that
/// colour entirely and left a solid gold silhouette/blob, losing all detail.
/// Reported as a regression, so the emoji itself renders as-is; only the
/// surrounding bubble stays on-theme. See DECISIONLOG.
class CategoryIconBubble extends StatelessWidget {
  const CategoryIconBubble(this.emoji, {super.key, this.size = 40});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: kBackgroundBlack,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}
