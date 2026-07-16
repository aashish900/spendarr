import 'package:flutter/material.dart';

import '../db/tables.dart';
import '../theme.dart';
import 'gilded.dart';

IconData _iconFor(TransactionKind kind) => switch (kind) {
      TransactionKind.expense => Icons.arrow_circle_down_outlined,
      TransactionKind.income => Icons.arrow_circle_up_outlined,
      TransactionKind.investment => Icons.trending_up,
    };

String _labelFor(TransactionKind kind) => switch (kind) {
      TransactionKind.expense => 'Expense',
      TransactionKind.income => 'Income',
      TransactionKind.investment => 'Investment',
    };

/// Full-width Expense/Income/Investment pill selector (Add-transaction
/// redesign): outer bordered pill, selected segment filled with the premium
/// gold gradient + black icon/label, unselected segments show a gilded icon
/// on a transparent background. Same visual construction as
/// [ZoomPillSelector] in `home_timeline.dart`, generalized with per-segment
/// icons and equal-width [Expanded] segments.
class KindPillSelector extends StatelessWidget {
  const KindPillSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TransactionKind selected;
  final ValueChanged<TransactionKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          for (final k in TransactionKind.values)
            Expanded(child: _segment(context, k)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, TransactionKind kind) {
    final isSelected = kind == selected;
    final icon = Icon(_iconFor(kind), size: 18, color: Colors.white);
    return GestureDetector(
      onTap: () => onChanged(kind),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? kPremiumGoldGradient : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isSelected
                ? Icon(_iconFor(kind), size: 18, color: Colors.black)
                : Gilded(child: icon),
            const SizedBox(width: 6),
            Text(
              _labelFor(kind),
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
