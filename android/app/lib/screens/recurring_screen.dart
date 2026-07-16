import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/recurring.dart';
import '../theme.dart';
import '../util/cron.dart';
import '../util/money.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';
import '../widgets/gold_fab.dart';

String _formatDateMs(int? ms) {
  if (ms == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

/// Recurring rules: total-recurring summary, Active/Inactive sections (each
/// with its own empty state), pause/resume + delete per rule, filter by
/// kind, FAB to add. Matches the "Recurring expenses.png" mockup.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  TransactionKind? _kindFilter;

  Future<void> _pickFilter() async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: kSurfaceBlack,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All'),
              onTap: () => Navigator.of(sheetContext).pop(_allFilterValue),
            ),
            for (final k in TransactionKind.values)
              ListTile(
                title: Text(_kindLabel(k)),
                onTap: () => Navigator.of(sheetContext).pop(k),
              ),
          ],
        ),
      ),
    );
    if (picked == _allFilterValue) {
      setState(() => _kindFilter = null);
    } else if (picked is TransactionKind) {
      setState(() => _kindFilter = picked);
    }
  }

  String _kindLabel(TransactionKind k) => switch (k) {
        TransactionKind.expense => 'Expense',
        TransactionKind.income => 'Income',
        TransactionKind.investment => 'Investment',
      };

  Future<void> _confirmDelete(RecurringRule rule, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recurring rule?'),
        content: Text(
            'This stops "$label" from firing again. Past transactions it '
            'already created are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(recurringWriterProvider).delete(rule.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(activeRecurringProvider);
    final categories =
        ref.watch(activeCategoriesProvider).value ?? const <Category>[];
    final byId = {for (final c in categories) c.id: c};

    return Scaffold(
      appBar: AppBar(
        title: Text('Recurring',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(
            icon: Gilded(child: const Icon(Icons.filter_alt_outlined)),
            tooltip: 'Filter',
            onPressed: _pickFilter,
          ),
        ],
      ),
      floatingActionButton: GoldFab(
        heroTag: 'recurring-fab',
        onPressed: () => context.push('/recurring/add'),
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allRules) {
          final rules = _kindFilter == null
              ? allRules
              : allRules.where((r) => r.kind == _kindFilter).toList();
          final active = rules.where((r) => r.active).toList();
          final inactive = rules.where((r) => !r.active).toList();
          // The summary breakdown is always by-kind across *all* active
          // rules, regardless of the list's own kind filter — filtering to
          // one kind would otherwise leave the other two columns at ₹0.
          final allActive = allRules.where((r) => r.active).toList();
          int sumFor(TransactionKind k) => allActive
              .where((r) => r.kind == k)
              .fold<int>(0, (a, r) => a + r.amount);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(
                incomeCents: sumFor(TransactionKind.income),
                investmentCents: sumFor(TransactionKind.investment),
                expenseCents: sumFor(TransactionKind.expense),
                activeCount: allActive.length,
              ),
              const SizedBox(height: 24),
              SectionLabel('ACTIVE (${active.length})'),
              if (active.isEmpty)
                const _EmptyState(
                  icon: Icons.autorenew,
                  title: 'No active recurring transactions',
                  subtitle: 'Recurring transactions you create will appear here.',
                )
              else
                for (final r in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RuleCard(
                      rule: r,
                      category: byId[r.categoryId],
                      onToggle: (v) =>
                          ref.read(recurringWriterProvider).setActive(r.id, v),
                      onDelete: () => _confirmDelete(
                          r, byId[r.categoryId]?.name ?? 'this rule'),
                    ),
                  ),
              const SizedBox(height: 24),
              SectionLabel('INACTIVE (${inactive.length})'),
              if (inactive.isEmpty)
                const _EmptyState(
                  icon: Icons.event_busy,
                  title: 'No inactive recurring transactions',
                  subtitle: 'Inactive recurring transactions will appear here.',
                )
              else
                for (final r in inactive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RuleCard(
                      rule: r,
                      category: byId[r.categoryId],
                      onToggle: (v) =>
                          ref.read(recurringWriterProvider).setActive(r.id, v),
                      onDelete: () => _confirmDelete(
                          r, byId[r.categoryId]?.name ?? 'this rule'),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Sentinel returned by the filter sheet's "All" option — `null` itself is
/// also a valid pop value (sheet dismissed without a pick), so a distinct
/// sentinel is needed to tell the two apart.
const _allFilterValue = Object();

/// Recurring summary: instead of one combined total, breaks active rules
/// down by kind (Income/Investment/Expense) — a single "total recurring"
/// figure mixed money coming in with money going out into one meaningless
/// number.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.incomeCents,
    required this.investmentCents,
    required this.expenseCents,
    required this.activeCount,
  });

  final int incomeCents;
  final int investmentCents;
  final int expenseCents;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(child: Gilded(child: const Icon(Icons.autorenew, color: Colors.white))),
              const SizedBox(width: 12),
              Text('Recurring transactions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$activeCount active',
                  style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _KindStat(
                    label: 'Income', valueCents: incomeCents, color: kIncomeGreen),
              ),
              _divider(),
              Expanded(
                child: _KindStat(
                    label: 'Investment', valueCents: investmentCents, color: kGold),
              ),
              _divider(),
              Expanded(
                child: _KindStat(
                    label: 'Expense',
                    valueCents: expenseCents,
                    color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.white12,
      );
}

class _KindStat extends StatelessWidget {
  const _KindStat({
    required this.label,
    required this.valueCents,
    required this.color,
  });

  final String label;
  final int valueCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: kTextSecondary)),
        const SizedBox(height: 4),
        Text(formatRupees(valueCents),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.category,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringRule rule;
  final Category? category;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return FieldCard(
      child: Row(
        children: [
          _IconBox(
            child: Text(category?.emoji ?? '🔁', style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(category?.name ?? 'Unknown category',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                Text(formatRupees(rule.amount),
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: kGold),
                    ),
                    const SizedBox(width: 6),
                    Text(presetLabel(presetForCron(rule.cron)),
                        style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: kCardBorder,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Next due on',
                  style: TextStyle(color: kTextSecondary, fontSize: 12)),
              Text(_formatDateMs(rule.nextRunAt),
                  style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
            ],
          ),
          Switch(
            value: rule.active,
            activeThumbColor: kGold,
            onChanged: onToggle,
          ),
          PopupMenuButton<String>(
            icon: Gilded(child: const Icon(Icons.more_vert, color: Colors.white)),
            color: kSurfaceBlack,
            onSelected: (v) {
              if (v == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small rounded-square icon container shared by the summary card and each
/// rule card (mockup uses a square glyph box, not [CategoryIconBubble]'s
/// circle, for this screen).
class _IconBox extends StatelessWidget {
  const _IconBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kBackgroundBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCardBorder),
      ),
      child: Center(child: child),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: kBackgroundBlack),
            child: Center(child: Gilded(child: Icon(icon, size: 28, color: Colors.white))),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: kTextSecondary)),
        ],
      ),
    );
  }
}
