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
