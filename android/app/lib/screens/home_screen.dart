import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/clock.dart';
import '../providers/insights.dart';
import '../providers/profile.dart';
import '../providers/recurring.dart';
import '../providers/summary.dart';
import '../providers/transactions.dart' show localDayTickProvider;
import '../theme.dart';
import '../util/cron.dart';
import '../util/datetime.dart';
import '../util/money.dart';
import '../widgets/budget_prompt_dialog.dart';
import '../widgets/gilded.dart';
import '../widgets/gold_fab.dart';
import '../widgets/home_header.dart';
import '../widgets/home_timeline.dart';
import '../widgets/insight_card.dart';
import '../widgets/month_ring.dart';
import '../widgets/summary_chips.dart';

String _kindLabel(TransactionKind k) => switch (k) {
      TransactionKind.income => 'Income',
      TransactionKind.expense => 'Expense',
      TransactionKind.investment => 'Investment',
    };

IconData _kindIcon(TransactionKind k) => switch (k) {
      TransactionKind.income => Icons.arrow_downward,
      TransactionKind.expense => Icons.arrow_upward,
      TransactionKind.investment => Icons.trending_up,
    };

Future<void> _showAddSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: kSurfaceBlack,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in TransactionKind.values)
            ListTile(
              leading: Gilded(
                child: Icon(_kindIcon(kind), color: Colors.white),
              ),
              title: Text(_kindLabel(kind)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/add?kind=${kind.name}');
              },
            ),
        ],
      ),
    ),
  );
}

/// Home: greeting + month switcher header, a budget-progress ring +
/// income/expense/summary chips for the selected month, and a journal
/// timeline (Day/Week/Month zoom) of that month's transactions. Defaults to
/// the current calendar month and rolls over automatically at the boundary
/// (see `effectiveHomeMonthProvider`); the switcher lets the user browse
/// earlier months but not past the current one. Day/Week zoom only applies
/// to the current month — a past month always shows Month view.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Tracks whether the budget prompt has already been scheduled this widget
  // lifetime, so it doesn't re-fire on every rebuild while `profileProvider`
  // settles or the user browses months.
  bool _promptScheduled = false;

  void _maybeSchedulePrompt(Profile profile, DateTime now) {
    if (_promptScheduled || !needsBudgetPrompt(profile, now)) return;
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (profile.budgetMode == null) {
        showBudgetPromptDialog(
          context,
          canCancel: false,
          showModeChoice: true,
          title: 'Set up your budget',
        );
      } else {
        showBudgetPromptDialog(
          context,
          canCancel: false,
          showModeChoice: false,
          title: "Set this month's budget",
          initialCents: profile.monthlyBudgetCents,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(effectiveHomeMonthProvider);
    final currentDay = ref.watch(localDayTickProvider).value ?? DateTime.now();
    final canGoForward = month.year < currentDay.year ||
        (month.year == currentDay.year && month.month < currentDay.month);

    final range =
        rangeForPeriod(HistoryPeriod.month, DateTime(month.year, month.month));
    final txnsAsync =
        ref.watch(transactionsInRangeProvider((range.startMs, range.endMs)));
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value ?? const Profile();
    final displayName = profile.displayName;
    final now = ref.watch(nowProvider)();
    if (profileAsync.hasValue) _maybeSchedulePrompt(profile, currentDay);
    final greeting = greetingFor(now);
    final isCurrentMonth =
        month.year == currentDay.year && month.month == currentDay.month;
    final recurringRules =
        ref.watch(activeRecurringProvider).value ?? const <RecurringRule>[];
    // Home's Recurring figure is upcoming outflows only (expense +
    // investment) — an income rule (e.g. salary) shouldn't inflate it.
    final recurringProjectedCents = [
      for (final r in recurringRules)
        if (r.kind != TransactionKind.income)
          occurrencesInMonth(r.cron, month.year, month.month) * r.amount,
    ].fold<int>(0, (a, b) => a + b);
    final categories = categoriesAsync.value ?? const <Category>[];
    final categoriesById = {for (final c in categories) c.id: c};
    final renewalFact = upcomingRenewal(recurringRules, categoriesById, now);

    void goToMonth(int deltaMonths) {
      final total = month.year * 12 + (month.month - 1) + deltaMonths;
      ref.read(homeMonthAnchorProvider.notifier).state =
          (year: total ~/ 12, month: total % 12 + 1);
    }

    return Scaffold(
      floatingActionButton: GoldFab(
        heroTag: 'home-fab',
        onPressed: () => _showAddSheet(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              greeting: greeting,
              displayName: displayName,
              month: month,
              canGoForward: canGoForward,
              onPrev: () => goToMonth(-1),
              onNext: canGoForward ? () => goToMonth(1) : null,
            ),
            Expanded(
              child: txnsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (txns) {
                  final summary = summarizeTransactions(txns);

                  // The ring's centre shows the money left against the
                  // user's budget this month: budget − expenses −
                  // investments. Full ring (gold) at zero spend, draining
                  // toward zero as budget is used up, then filling red in
                  // the opposite direction once overspent (see
                  // `budgetRingProgress`). With no budget configured the
                  // ring is blank and the centre just shows total spend.
                  final outflowCents =
                      summary.expenseCents + summary.investmentCents;
                  final budgetCents = profile.monthlyBudgetCents ?? 0;
                  final remainingCents = budgetCents - outflowCents;
                  final progress =
                      budgetRingProgress(budgetCents, outflowCents);
                  final amountText = formatRupees(
                      (budgetCents <= 0 ? outflowCents : remainingCents)
                          .abs());
                  final String descriptor;
                  if (budgetCents <= 0) {
                    descriptor = 'spent';
                  } else if (remainingCents < 0) {
                    descriptor = 'overspent';
                  } else {
                    descriptor = isCurrentMonth ? 'left to spend' : 'left over';
                  }
                  final daysInMonth =
                      DateTime(month.year, month.month + 1, 0).day;
                  final footer = isCurrentMonth
                      ? 'Day ${currentDay.day}/$daysInMonth'
                      : null;

                  return ListView(
                    // Extra bottom padding so the last ledger row can scroll
                    // clear of the FAB instead of sitting underneath it.
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _Stat(
                                label: 'Income',
                                valueCents: summary.incomeCents,
                                alignEnd: false),
                          ),
                          GestureDetector(
                            // Swipe the ring itself to browse months — same
                            // effect as the header's prev/next arrows, just
                            // faster for flicking through several months of
                            // past transactions.
                            onHorizontalDragEnd: (details) {
                              final velocity =
                                  details.primaryVelocity ?? 0;
                              if (velocity < 0) {
                                if (canGoForward) goToMonth(1);
                              } else if (velocity > 0) {
                                goToMonth(-1);
                              }
                            },
                            child: MonthRing(
                              progress: progress,
                              amountText: amountText,
                              descriptor: descriptor,
                              footer: footer,
                            ),
                          ),
                          Expanded(
                            child: _Stat(
                                // Total outflow (expenses + investments), not
                                // expenses alone — matches what the ring's
                                // fill fraction is measured against.
                                label: 'Expense',
                                valueCents: outflowCents,
                                alignEnd: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SummaryChips(
                        expenseCents: summary.expenseCents,
                        investmentCents: summary.investmentCents,
                        recurringProjectedCents: recurringProjectedCents,
                      ),
                      const SizedBox(height: 24),
                      HomeTimeline(
                        monthTxns: txns,
                        categoriesById: categoriesById,
                        today: DateTime(currentDay.year, currentDay.month,
                            currentDay.day),
                        allowZoom: isCurrentMonth,
                      ),
                      if (renewalFact != null) ...[
                        const SizedBox(height: 24),
                        InsightCard(fact: renewalFact, now: now),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.valueCents,
    required this.alignEnd,
  });

  final String label;
  final int valueCents;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        // Shrinks to fit rather than wrapping to a second line when the
        // amount is wide (large totals, e.g. once investments are folded
        // into the Expense figure).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(formatRupees(valueCents),
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}
