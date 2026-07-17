import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/profile.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/budget_prompt_dialog.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';

String _budgetModeSubtitle(BudgetMode? mode) => switch (mode) {
      null => 'Not set up yet',
      BudgetMode.constant => 'Same every month',
      BudgetMode.monthly => 'Set every month',
    };

/// Settings: Export CSV + Budget. Profile display name / Server (backend
/// URL/token) are hidden until they're wired up to something functional
/// again — see DECISIONLOG.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value ?? const Profile();

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
          const SizedBox(height: 20),
          const SectionLabel('BUDGET'),
          FieldCard(
            onTap: () => showBudgetPromptDialog(
              context,
              canCancel: true,
              showModeChoice: true,
              title: 'Edit budget',
              initialCents: profile.monthlyBudgetCents,
              initialMode: profile.budgetMode,
            ),
            child: Row(
              children: [
                Gilded(child: const Icon(Icons.savings_outlined, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Monthly budget',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                          '${formatRupees(profile.monthlyBudgetCents ?? 0)} · ${_budgetModeSubtitle(profile.budgetMode)}',
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
