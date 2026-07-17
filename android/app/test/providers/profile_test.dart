import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/providers/profile.dart';

void main() {
  test('loads nulls when nothing has been saved yet', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    final profile = await container.read(profileProvider.future);
    expect(profile.displayName, isNull);
    expect(profile.monthlyBudgetCents, isNull);
  });

  test('save persists display name and budget as int cents, round-trips',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(displayName: 'Aashish', monthlyBudgetCents: 5000000);

    final state = container.read(profileProvider).value!;
    expect(state.displayName, 'Aashish');
    expect(state.monthlyBudgetCents, 5000000);

    // Round-trips via the underlying sync_meta store.
    expect(await db.syncMetaDao.getValue('display_name'), 'Aashish');
    expect(await db.syncMetaDao.getValue('monthly_budget_cents'), '5000000');
  });

  test('saveBudget persists amount, mode, and the month it was set for',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    await container.read(profileProvider.future);
    await container.read(profileProvider.notifier).saveBudget(
          cents: 1500000,
          mode: BudgetMode.monthly,
          now: DateTime(2026, 7, 13),
        );

    final state = container.read(profileProvider).value!;
    expect(state.monthlyBudgetCents, 1500000);
    expect(state.budgetMode, BudgetMode.monthly);
    expect(state.budgetSetForMonth, '2026-07');

    expect(await db.syncMetaDao.getValue('monthly_budget_cents'), '1500000');
    expect(await db.syncMetaDao.getValue('budget_mode'), 'monthly');
    expect(await db.syncMetaDao.getValue('budget_set_for_month'), '2026-07');
  });

  test('saveBudget without a mode keeps the previously-chosen mode',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    await container.read(profileProvider.future);
    await container.read(profileProvider.notifier).saveBudget(
          cents: 1000000,
          mode: BudgetMode.monthly,
          now: DateTime(2026, 7, 1),
        );
    // Settings-style edit: re-entering the amount only, no mode argument.
    await container.read(profileProvider.notifier).saveBudget(
          cents: 2000000,
          now: DateTime(2026, 8, 1),
        );

    final state = container.read(profileProvider).value!;
    expect(state.monthlyBudgetCents, 2000000);
    expect(state.budgetMode, BudgetMode.monthly);
    expect(state.budgetSetForMonth, '2026-08');
  });

  group('needsBudgetPrompt', () {
    test('never configured → always prompts', () {
      const profile = Profile();
      expect(needsBudgetPrompt(profile, DateTime(2026, 7, 13)), isTrue);
    });

    test('constant mode never re-prompts, even in a stale month', () {
      const profile = Profile(
        monthlyBudgetCents: 1000000,
        budgetMode: BudgetMode.constant,
        budgetSetForMonth: '2020-01',
      );
      expect(needsBudgetPrompt(profile, DateTime(2026, 7, 13)), isFalse);
    });

    test('monthly mode prompts once the calendar month has moved on', () {
      const profile = Profile(
        monthlyBudgetCents: 1000000,
        budgetMode: BudgetMode.monthly,
        budgetSetForMonth: '2026-06',
      );
      expect(needsBudgetPrompt(profile, DateTime(2026, 7, 1)), isTrue);
    });

    test('monthly mode does not re-prompt within the same month', () {
      const profile = Profile(
        monthlyBudgetCents: 1000000,
        budgetMode: BudgetMode.monthly,
        budgetSetForMonth: '2026-07',
      );
      expect(needsBudgetPrompt(profile, DateTime(2026, 7, 30)), isFalse);
    });
  });

  test('save with only a budget leaves the name untouched', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);

    await container.read(profileProvider.future);
    await container
        .read(profileProvider.notifier)
        .save(displayName: 'Aashish', monthlyBudgetCents: null);
    await container
        .read(profileProvider.notifier)
        .save(displayName: null, monthlyBudgetCents: 1000000);

    final state = container.read(profileProvider).value!;
    expect(state.displayName, 'Aashish');
    expect(state.monthlyBudgetCents, 1000000);
  });
}
