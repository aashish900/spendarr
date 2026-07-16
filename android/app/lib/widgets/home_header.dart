import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/datetime.dart';
import 'gilded.dart';

/// Home's greeting + month switcher header, replacing the plain AppBar.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.greeting,
    this.displayName,
    required this.month,
    required this.canGoForward,
    required this.onPrev,
    required this.onNext,
  });

  final String greeting;
  final String? displayName;
  final ({int year, int month}) month;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final name = displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name == null || name.isEmpty ? greeting : '$greeting, $name',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: kTextSecondary,
                onPressed: onPrev,
              ),
              Gilded(
                child: Text(
                  monthLabel(month.year, month.month),
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: kTextSecondary,
                onPressed: canGoForward ? onNext : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
