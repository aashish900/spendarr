import 'package:flutter/material.dart';

import '../providers/insights.dart';
import '../theme.dart';
import 'gilded.dart';

/// Deterministic upcoming-renewal fact card, e.g. "Netflix renews
/// tomorrow". No spending-pattern analysis — see providers/insights.dart.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.fact, required this.now});

  final RenewalFact fact;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        children: [
          const Gilded(child: Icon(Icons.autorenew, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${fact.label} renews ${renewalPhrase(fact.fireMs, now)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
