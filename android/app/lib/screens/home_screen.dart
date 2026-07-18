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
import '../util/datetime.dart';
import '../util/money.dart';
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
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(effectiveHomeMonthProvider);
    final currentDay = ref.watch(localDayTickProvider).value ?? DateTime.now();
    final canGoForward = month.year < currentDay.year ||
        (month.year == currentDay.year && month.month < currentDay.month);

    final range =
        rangeForPeriod(HistoryPeriod.month, DateTime(month.year, month.month));
    final txnsAsync =
        ref.watch(transactionsInRangeProvider((range.startMs, range.endMs)));
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final displayName = ref.watch(profileProvider).value?.displayName;
    final now = ref.watch(nowProvider)();
    final greeting = greetingFor(now);
    final isCurrentMonth =
        month.year == currentDay.year && month.month == currentDay.month;
    final recurringRules =
        ref.watch(activeRecurringProvider).value ?? const <RecurringRule>[];
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

                  // The ring's centre shows the money left this month:
                  // income − expenses − investments (matches the mockup,
                  // where ₹6,000 income − ₹1,180 spent → "₹4,820 left to
                  // spend"); the fill fraction is the same outflows measured
                  // against income, so a full ring = everything earned this
                  // month has been spent.
                  final outflowCents =
                      summary.expenseCents + summary.investmentCents;
                  final leftCents = summary.incomeCents - outflowCents;
                  final amountText = formatRupees(leftCents.abs());
                  final String descriptor;
                  if (leftCents < 0) {
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
                      Center(
                        child: GestureDetector(
                          // Swipe the ring itself to browse months — same
                          // effect as the header's prev/next arrows, just
                          // faster for flicking through several months of
                          // past transactions.
                          onHorizontalDragEnd: (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (velocity < 0) {
                              if (canGoForward) goToMonth(1);
                            } else if (velocity > 0) {
                              goToMonth(-1);
                            }
                          },
                          child: MonthRing(
                            progress: ringProgress(
                                outflowCents, summary.incomeCents),
                            amountText: amountText,
                            descriptor: descriptor,
                            footer: footer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SummaryChips(
                        incomeCents: summary.incomeCents,
                        expenseCents: summary.expenseCents,
                        // Net excludes investments, consistent with
                        // `PeriodSummary.netCents`/`netFlowCents`.
                        balanceCents: summary.netCents,
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
