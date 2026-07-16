import 'package:flutter/material.dart';

import '../theme.dart';

/// Metallic-gradient FAB (ThemeData's FloatingActionButtonThemeData can only
/// express a flat colour): premium gold vertical gradient + soft black drop
/// shadow + a tiny outer gold glow, per the design spec.
class GoldFab extends StatelessWidget {
  const GoldFab({
    super.key,
    required this.heroTag,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final Object heroTag;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Full 5-stop premium gradient — the narrower kFabGradient stops are
        // too close in tone and render nearly flat at FAB size.
        gradient: kPremiumGoldGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFFDDB860).withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        child: Icon(icon, color: Colors.black),
      ),
    );
  }
}
