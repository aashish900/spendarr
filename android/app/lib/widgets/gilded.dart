import 'package:flutter/material.dart';

import '../theme.dart';

/// Paints its child (icon or text) with the metallic gold gradient instead of
/// a flat colour — the design spec's "every gold element uses a 3–5 stop
/// metallic gradient". The child should be drawn in an opaque colour (white);
/// [BlendMode.srcIn] replaces those pixels with the gradient.
class Gilded extends StatelessWidget {
  const Gilded({super.key, required this.child, this.gradient = kGoldIconGradient});

  final Widget child;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: child,
    );
  }
}
