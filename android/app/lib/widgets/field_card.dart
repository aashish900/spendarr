import 'package:flutter/material.dart';

import '../theme.dart';

/// Small caps section header, e.g. "AMOUNT" / "CATEGORY" / "SPEND BY
/// CATEGORY". Shared by every screen using the [FieldCard] bordered-card
/// language (Add/Edit-transaction, History).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: kTextSecondary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Bordered dark card used for every field/section row across the app's
/// black+gold screens (amount, category, date/time, note, recurring on
/// Add/Edit-transaction; the spend-by-category chart on History). Optionally
/// tappable.
class FieldCard extends StatelessWidget {
  const FieldCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCardBorder),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: content,
    );
  }
}
