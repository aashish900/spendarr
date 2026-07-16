import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_provider.dart';

// Hand-written (not @riverpod): touches drift row types via syncMetaDao.
// See DECISIONLOG 2026-06-23.

const _kDisplayNameKey = 'display_name';
const _kMonthlyBudgetCentsKey = 'monthly_budget_cents';

/// Local-only user profile: display name (for the Home greeting) and a
/// monthly budget (int cents) driving the Home month ring. Stored in
/// `sync_meta` — local-only settings, not synced to the server, so no
/// outbox entry is written (unlike Category/Transaction/Recurring writes).
class Profile {
  const Profile({this.displayName, this.monthlyBudgetCents});

  final String? displayName;
  final int? monthlyBudgetCents;

  Profile copyWith({String? displayName, int? monthlyBudgetCents}) => Profile(
        displayName: displayName ?? this.displayName,
        monthlyBudgetCents: monthlyBudgetCents ?? this.monthlyBudgetCents,
      );
}

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    final db = ref.watch(appDatabaseProvider);
    final displayName = await db.syncMetaDao.getValue(_kDisplayNameKey);
    final budgetRaw =
        await db.syncMetaDao.getValue(_kMonthlyBudgetCentsKey);
    return Profile(
      displayName: displayName,
      monthlyBudgetCents: budgetRaw == null ? null : int.parse(budgetRaw),
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
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);
