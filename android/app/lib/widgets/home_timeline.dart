import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../theme.dart';
import '../util/datetime.dart';
import '../util/money.dart';
import 'category_icon_bubble.dart';
import 'pill_selector.dart';

/// Home's journal-timeline zoom level.
enum TimelineZoom { day, week, month }

String timelineZoomLabel(TimelineZoom z) => switch (z) {
      TimelineZoom.day => 'Day',
      TimelineZoom.week => 'Week',
      TimelineZoom.month => 'Month',
    };

final timelineZoomProvider =
    StateProvider<TimelineZoom>((ref) => TimelineZoom.month);

/// Category id the timeline is filtered to, or `null` for all categories.
final timelineCategoryFilterProvider =
    StateProvider<String?>((ref) => null);

const _kWeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _localDateKey(int occurredAtMs) => _dateKey(
    DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true).toLocal());

String _signedRupees(TransactionRow t) => switch (t.kind) {
      TransactionKind.expense => formatRupees(-t.amount),
      TransactionKind.income => formatRupees(t.amount, signed: true),
      TransactionKind.investment => formatRupees(t.amount),
    };

Color? _amountColor(BuildContext context, TransactionKind kind) =>
    switch (kind) {
      TransactionKind.expense => Theme.of(context).colorScheme.error,
      TransactionKind.income => kIncomeGreen,
      TransactionKind.investment => kGold,
    };

/// Home's journal timeline: Day/Week/Month zoom over the already-loaded
/// month's transactions — no additional DB queries. Week/Day totals are
/// computed client-side from [monthTxns], so a week overlapping the
/// previous/next month only reflects the days that fall within the
/// currently displayed month (documented v1 limitation — see DECISIONLOG).
/// [allowZoom] is false for a past (non-current) month, where Day/Week
/// don't have a well-defined "today" — Month is always shown then.
class HomeTimeline extends ConsumerWidget {
  const HomeTimeline({
    super.key,
    required this.monthTxns,
    required this.categoriesById,
    required this.today,
    required this.allowZoom,
  });

  final List<TransactionRow> monthTxns;
  final Map<String, Category> categoriesById;
  final DateTime today;
  final bool allowZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = allowZoom ? ref.watch(timelineZoomProvider) : TimelineZoom.month;
    final filterId = ref.watch(timelineCategoryFilterProvider);

    // Categories actually present in this month's transactions, for the
    // filter menu (newest-first order preserved).
    final usedCategories = <Category>[];
    final seen = <String>{};
    for (final t in monthTxns) {
      final c = categoriesById[t.categoryId];
      if (c != null && seen.add(c.id)) usedCategories.add(c);
    }
    // A stale filter (e.g. from a month where that category was used) still
    // needs to be visible in the menu so it can be cleared.
    final activeFilter =
        filterId == null ? null : categoriesById[filterId];

    final txns = filterId == null
        ? monthTxns
        : monthTxns.where((t) => t.categoryId == filterId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (allowZoom) ...[
          Center(
            child: ZoomPillSelector(
              selected: zoom,
              onChanged: (z) =>
                  ref.read(timelineZoomProvider.notifier).state = z,
            ),
          ),
        ],
        if (monthTxns.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: _CategoryFilterButton(
              categories: usedCategories,
              selected: activeFilter,
              onChanged: (id) =>
                  ref.read(timelineCategoryFilterProvider.notifier).state = id,
            ),
          ),
        const SizedBox(height: 4),
        switch (zoom) {
          TimelineZoom.month =>
            _MonthView(txns: txns, categoriesById: categoriesById),
          TimelineZoom.day => _DayView(
              txns: txns, categoriesById: categoriesById, today: today),
          TimelineZoom.week => _WeekView(
              txns: txns, categoriesById: categoriesById, today: today),
        },
      ],
    );
  }
}

/// The "All ▾" category filter at the timeline's top right (mockup: a tune
/// icon + current selection). `null` selection = all categories.
class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<Category> categories;
  final Category? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      // Sentinel '' for "All" — PopupMenuItem's own value can't be null.
      onSelected: (v) => onChanged(v == '' ? null : v),
      color: kSurfaceBlack,
      itemBuilder: (context) => [
        const PopupMenuItem(value: '', child: Text('All')),
        for (final c in categories)
          PopupMenuItem(value: c.id, child: _CategoryMenuLabel(c)),
        if (selected != null && !categories.any((c) => c.id == selected!.id))
          PopupMenuItem(value: selected!.id, child: _CategoryMenuLabel(selected!)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 16, color: kTextSecondary),
            const SizedBox(width: 6),
            Text(
              selected?.name ?? 'All',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: kTextSecondary),
            ),
            const Icon(Icons.arrow_drop_down, color: kTextSecondary),
          ],
        ),
      ),
    );
  }
}

/// Category icon bubble + name, used for rows in the category filter menu.
class _CategoryMenuLabel extends StatelessWidget {
  const _CategoryMenuLabel(this.category);

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CategoryIconBubble(category.emoji, size: 24),
        const SizedBox(width: 8),
        Text(category.name),
      ],
    );
  }
}

/// Day/Week/Month zoom pill (matches the mockup). Thin wrapper around the
/// shared [PillSelector] so `find.byType(ZoomPillSelector)` keeps working
/// for existing callers/tests while the pill itself is generalized.
class ZoomPillSelector extends StatelessWidget {
  const ZoomPillSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TimelineZoom selected;
  final ValueChanged<TimelineZoom> onChanged;

  @override
  Widget build(BuildContext context) {
    return PillSelector<TimelineZoom>(
      items: TimelineZoom.values,
      selected: selected,
      labelFor: timelineZoomLabel,
      onChanged: onChanged,
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.t, required this.category});

  final TransactionRow t;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final note = t.note;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/add?editTransactionId=${t.id}'),
      // Mockup layout: recorded time on the far left, then the category icon.
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              formatTimeOfDay(t.occurredAt),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: kTextSecondary),
            ),
          ),
          CategoryIconBubble(category?.emoji ?? '', size: 32),
        ],
      ),
      title: Text(category?.name ?? 'Unknown'),
      subtitle: note == null || note.isEmpty ? null : Text(note),
      trailing: Text(
        _signedRupees(t),
        // Same size as the note (ListTile's subtitle uses bodyMedium).
        style: TextStyle(
          color: _amountColor(context, t.kind),
          fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize,
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({required this.txns, required this.categoriesById});

  final List<TransactionRow> txns;
  final Map<String, Category> categoriesById;

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) return const SizedBox.shrink();
    // txns is already newest-first; group runs of the same local date
    // together without re-sorting.
    final dateGroups = <String, List<TransactionRow>>{};
    for (final t in txns) {
      dateGroups.putIfAbsent(_localDateKey(t.occurredAt), () => []).add(t);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A divider before every date group (not just the first) so each
        // day's block reads as clearly separated from the one before it.
        for (final entry in dateGroups.entries) ...[
          const Divider(color: kDivider),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: _DayHeader(dateLabel: entry.key, dayTxns: entry.value),
          ),
          for (final t in entry.value)
            _TxnRow(t: t, category: categoriesById[t.categoryId]),
        ],
      ],
    );
  }
}

int _sumByKind(List<TransactionRow> txns, TransactionKind kind) =>
    txns.where((t) => t.kind == kind).fold<int>(0, (a, t) => a + t.amount);

/// Date group header for [_MonthView]: the date, left-aligned, with that
/// day's money-in/money-out totals alongside it as a quick day's summary —
/// income (credit) in green, expense (debit, which folds in investments —
/// both are money leaving the income pool) in red. Rendered for every date
/// group in the month, not just the most recent one.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.dateLabel, required this.dayTxns});

  final String dateLabel;
  final List<TransactionRow> dayTxns;

  @override
  Widget build(BuildContext context) {
    final income = _sumByKind(dayTxns, TransactionKind.income);
    final outflow = _sumByKind(dayTxns, TransactionKind.expense) +
        _sumByKind(dayTxns, TransactionKind.investment);
    // Same size as the date label so the day's summary doesn't read as a
    // lesser-importance afterthought next to it.
    final summaryStyle = Theme.of(context).textTheme.labelLarge;
    return Row(
      children: [
        Text(dateLabel, style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        if (income > 0) ...[
          Text(formatRupees(income, signed: true),
              style: summaryStyle?.copyWith(color: kIncomeGreen)),
          if (outflow > 0) const SizedBox(width: 8),
        ],
        if (outflow > 0)
          Text(formatRupees(-outflow),
              style: summaryStyle?.copyWith(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.txns,
    required this.categoriesById,
    required this.today,
  });

  final List<TransactionRow> txns;
  final Map<String, Category> categoriesById;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final todayKey = _dateKey(today);
    final todayTxns =
        txns.where((t) => _localDateKey(t.occurredAt) == todayKey).toList();
    if (todayTxns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No transactions today.'),
      );
    }
    return Column(
      children: [
        const Divider(),
        for (final t in todayTxns)
          _TxnRow(t: t, category: categoriesById[t.categoryId]),
      ],
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.txns,
    required this.categoriesById,
    required this.today,
  });

  final List<TransactionRow> txns;
  final Map<String, Category> categoriesById;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    final byDate = <String, List<TransactionRow>>{};
    for (final t in txns) {
      byDate.putIfAbsent(_localDateKey(t.occurredAt), () => []).add(t);
    }

    int spendFor(DateTime d) => (byDate[_dateKey(d)] ?? const [])
        .where((t) => t.kind == TransactionKind.expense)
        .fold<int>(0, (a, t) => a + t.amount);

    final spends = {for (final d in days) d: spendFor(d)};
    final maxSpend =
        spends.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        const Divider(),
        for (final d in days)
          _WeekDayTile(
            date: d,
            spentCents: spends[d]!,
            maxSpentCents: maxSpend,
            dayTxns: byDate[_dateKey(d)] ?? const [],
            categoriesById: categoriesById,
          ),
      ],
    );
  }
}

class _WeekDayTile extends StatelessWidget {
  const _WeekDayTile({
    required this.date,
    required this.spentCents,
    required this.maxSpentCents,
    required this.dayTxns,
    required this.categoriesById,
  });

  final DateTime date;
  final int spentCents;
  final int maxSpentCents;
  final List<TransactionRow> dayTxns;
  final Map<String, Category> categoriesById;

  @override
  Widget build(BuildContext context) {
    final barFraction = maxSpentCents > 0 ? spentCents / maxSpentCents : 0.0;
    return ExpansionTile(
      key: PageStorageKey(_dateKey(date)),
      enabled: dayTxns.isNotEmpty,
      title: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(_kWeekdayNames[date.weekday - 1],
                style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 6,
                  color: kDivider,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: barFraction.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: kActiveTabGradient,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text('Spent ${formatRupees(spentCents)}',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: kTextSecondary)),
        ],
      ),
      children: [
        for (final t in dayTxns)
          _TxnRow(t: t, category: categoriesById[t.categoryId]),
      ],
    );
  }
}
