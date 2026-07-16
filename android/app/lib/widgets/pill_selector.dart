import 'package:flutter/material.dart';

import '../theme.dart';

/// A single continuous rounded-pill selector: one outer border, a solid
/// gold-gradient fill sliding behind whichever segment is selected — unlike
/// Material's [SegmentedButton], which draws a border/divider around every
/// segment. Generic over any enum-shaped [items] list with a [labelFor]
/// function, so every Day/Week/Month-style toggle in the app shares one
/// widget instead of re-implementing the same pill per screen.
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.items,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  final List<T> items;
  final T selected;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items) _segment(context, item),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, T item) {
    final isSelected = item == selected;
    return GestureDetector(
      onTap: () => onChanged(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          // Full 5-stop premium gradient — narrower gradients render nearly
          // flat at pill size (see kFabGradient's doc comment in theme.dart).
          gradient: isSelected ? kPremiumGoldGradient : null,
          borderRadius: BorderRadius.circular(999),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Text(
          labelFor(item),
          style: TextStyle(
            color: isSelected ? Colors.black : kTextSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
