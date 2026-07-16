import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';

/// Settings: Export CSV only for now. Profile (display name/budget) and
/// Server (backend URL/token) are hidden until they're wired up to
/// something functional again — see DECISIONLOG.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('DATA'),
          FieldCard(
            onTap: () => context.push('/export'),
            child: Row(
              children: [
                Gilded(child: const Icon(Icons.ios_share, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Export CSV',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Download your transactions as a CSV file',
                          style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Gilded(child: const Icon(Icons.chevron_right, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
