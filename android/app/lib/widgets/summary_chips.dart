import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/money.dart';

/// The Income / Expenses / Balance strip below the month ring, drawn as one
/// bordered card with an icon bubble per section (matches the mockup)
/// rather than three separate chips. Reuses the existing icon assets rather
/// than sourcing new ones: `investment.png` for Income, `expenses.png` for
/// Expenses (unchanged), `recurring.png` for Balance.
class SummaryChips extends StatelessWidget {
  const SummaryChips({
    super.key,
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceCents,
  });

  final int incomeCents;
  final int expenseCents;
  final int balanceCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Item(
              iconAsset: 'assets/icons/investment.png',
              label: 'Income',
              valueCents: incomeCents,
            ),
          ),
          _divider(),
          Expanded(
            child: _Item(
              iconAsset: 'assets/icons/expenses.png',
              label: 'Expenses',
              valueCents: expenseCents,
            ),
          ),
          _divider(),
          Expanded(
            child: _Item(
              iconAsset: 'assets/icons/recurring.png',
              label: 'Balance',
              valueCents: balanceCents,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Colors.white12,
      );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.iconAsset,
    required this.label,
    required this.valueCents,
  });

  final String iconAsset;
  final String label;
  final int valueCents;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: kBackgroundBlack,
          child: ClipOval(
            child: Image.asset(iconAsset, width: 32, height: 32, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: kTextSecondary)),
              const SizedBox(height: 2),
              Text(formatRupees(valueCents),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}
