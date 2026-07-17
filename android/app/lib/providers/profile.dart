import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_provider.dart';

// Hand-written (not @riverpod): touches drift row types via syncMetaDao.
// See DECISIONLOG 2026-06-23.

const _kDisplayNameKey = 'display_name';
const _kMonthlyBudgetCentsKey = 'monthly_budget_cents';
const _kBudgetModeKey = 'budget_mode';
const _kBudgetSetForMonthKey = 'budget_set_for_month';

/// Whether the user re-enters a budget every month, or sets it once and
/// keeps it. `null` on [Profile] means the budget has never been configured
/// (first run).
enum BudgetMode { constant, monthly }

/// `"yyyy-MM"` for [d]'s local calendar month — used to detect whether a
/// monthly-mode budget is stale (a new month has started since it was set).
String yyyymm(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Local-only user profile: display name (for the Home greeting) and a
/// monthly budget (int cents) driving the Home month ring. Stored in
/// `sync_meta` — local-only settings, not synced to the server, so no
/// outbox entry is written (unlike Category/Transaction/Recurring writes).
class Profile {
  const Profile({
    this.displayName,
    this.monthlyBudgetCents,
    this.budgetMode,
    this.budgetSetForMonth,
  });

  final String? displayName;
  final int? monthlyBudgetCents;
  final BudgetMode? budgetMode;
  final String? budgetSetForMonth;

  Profile copyWith({
    String? displayName,
    int? monthlyBudgetCents,
    BudgetMode? budgetMode,
    String? budgetSetForMonth,
  }) =>
      Profile(
        displayName: displayName ?? this.displayName,
        monthlyBudgetCents: monthlyBudgetCents ?? this.monthlyBudgetCents,
        budgetMode: budgetMode ?? this.budgetMode,
        budgetSetForMonth: budgetSetForMonth ?? this.budgetSetForMonth,
      );
}

/// Whether Home should block on a budget-setup/re-entry dialog: never
/// configured, or `monthly` mode with a budget that wasn't set for [now]'s
/// calendar month yet. `constant` mode is only ever prompted once (at
/// first run) — it never goes stale.
bool needsBudgetPrompt(Profile profile, DateTime now) {
  if (profile.budgetMode == null) return true;
  if (profile.budgetMode == BudgetMode.monthly) {
    return profile.budgetSetForMonth != yyyymm(now);
  }
  return false;
}

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    final db = ref.watch(appDatabaseProvider);
    final displayName = await db.syncMetaDao.getValue(_kDisplayNameKey);
    final budgetRaw = await db.syncMetaDao.getValue(_kMonthlyBudgetCentsKey);
    final modeRaw = await db.syncMetaDao.getValue(_kBudgetModeKey);
    final budgetSetForMonth =
        await db.syncMetaDao.getValue(_kBudgetSetForMonthKey);
    return Profile(
      displayName: displayName,
      monthlyBudgetCents: budgetRaw == null ? null : int.parse(budgetRaw),
      budgetMode: modeRaw == null
          ? null
          : BudgetMode.values.byName(modeRaw),
      budgetSetForMonth: budgetSetForMonth,
    );
  }

  /// Persist a partial update (a null argument leaves that field unchanged)
  /// and update state optimistically.
  Future<void> save({String? displayName, int? monthlyBudgetCents}) async {
    final db = ref.read(appDatabaseProvider);
    final current = state.value ?? const Profile();
    final next = current.copyWith(
      displayName: displayName,
      monthlyBudgetCents: monthlyBudgetCents,
    );

    if (displayName != null) {
      await db.syncMetaDao.put(_kDisplayNameKey, displayName);
    }
    if (monthlyBudgetCents != null) {
      await db.syncMetaDao
          .put(_kMonthlyBudgetCentsKey, monthlyBudgetCents.toString());
    }
    state = AsyncData(next);
  }

  /// The single write path for setting up or re-entering a budget — used by
  /// the first-run dialog, the monthly re-prompt, and Settings edits alike.
  /// Always stamps `budgetSetForMonth` to [now]'s month, so saving from any
  /// of those three places counts as "set for this month".
  Future<void> saveBudget({
    required int cents,
    BudgetMode? mode,
    DateTime? now,
  }) async {
    final db = ref.read(appDatabaseProvider);
    final current = state.value ?? const Profile();
    final resolvedMode = mode ?? current.budgetMode ?? BudgetMode.constant;
    final setForMonth = yyyymm(now ?? DateTime.now());
    final next = current.copyWith(
      monthlyBudgetCents: cents,
      budgetMode: resolvedMode,
      budgetSetForMonth: setForMonth,
    );

    await db.syncMetaDao.put(_kMonthlyBudgetCentsKey, cents.toString());
    await db.syncMetaDao.put(_kBudgetModeKey, resolvedMode.name);
    await db.syncMetaDao.put(_kBudgetSetForMonthKey, setForMonth);
    state = AsyncData(next);
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);
