import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/categories.dart';
import 'database.dart';
import 'database_provider.dart';
import 'tables.dart';

// Hand-written (not @riverpod): touches drift row types across the
// CategoryWriter dependency. See DECISIONLOG 2026-06-23.

const _seededFlagKey = 'default_categories_seeded';

/// A default category to seed on first run. Not a drift row — [CategorySeeder]
/// writes each through [CategoryWriter] so the outbox contract holds.
class DefaultCategory {
  const DefaultCategory(this.name, this.emoji, this.kind);

  final String name;
  final String emoji;
  final TransactionKind kind;
}

/// Starter categories for a new install. Income and expense only — investment
/// categories are left for the user to define (no obvious universal set).
const kDefaultCategories = <DefaultCategory>[
  DefaultCategory('Salary', '💼', TransactionKind.income),
  DefaultCategory('RD Maturity', '💵', TransactionKind.income),
  DefaultCategory('FD Maturity', '🏦', TransactionKind.income),
  DefaultCategory('ESOPs', '📊', TransactionKind.income),
  DefaultCategory('Mutual Funds', '📈', TransactionKind.income),
  DefaultCategory('Interest', '🪙', TransactionKind.income),
  DefaultCategory('Food', '🍔', TransactionKind.expense),
  DefaultCategory('Tea', '☕', TransactionKind.expense),
  DefaultCategory('Groceries', '🛒', TransactionKind.expense),
  DefaultCategory('Rent', '🏠', TransactionKind.expense),
  DefaultCategory('Household', '🧹', TransactionKind.expense),
  DefaultCategory('Loan', '💳', TransactionKind.expense),
  DefaultCategory('Electronics', '🔌', TransactionKind.expense),
  DefaultCategory('Learning', '📚', TransactionKind.expense),
  DefaultCategory('Beauty', '💄', TransactionKind.expense),
  DefaultCategory('Health', '💊', TransactionKind.expense),
  DefaultCategory('Social', '🎉', TransactionKind.expense),
];

/// Idempotently seeds [kDefaultCategories] on first run, guarded by a
/// `sync_meta` flag (not a drift migration — `onCreate` never fires for
/// devices that already have a v1 database). Existing categories (including
/// the user's own) are matched by case-insensitive trimmed name and skipped.
class CategorySeeder {
  CategorySeeder(this._db, this._writer);

  final AppDatabase _db;
  final CategoryWriter _writer;

  Future<void> seedDefaults() async {
    final flag = await _db.syncMetaDao.getValue(_seededFlagKey);
    if (flag == 'true') return;

    final existingNames = (await _db.categoriesDao.allCategories())
        .map((c) => c.name.trim().toLowerCase())
        .toSet();

    for (final d in kDefaultCategories) {
      if (existingNames.contains(d.name.trim().toLowerCase())) continue;
      await _writer.add(name: d.name, emoji: d.emoji, kind: d.kind);
    }

    await _db.syncMetaDao.put(_seededFlagKey, 'true');
  }
}

final categorySeederProvider = Provider<CategorySeeder>((ref) {
  return CategorySeeder(
    ref.watch(appDatabaseProvider),
    ref.watch(categoryWriterProvider),
  );
});

/// Fire-and-forget seeding hook for app startup.
final seedDefaultCategoriesProvider = FutureProvider<void>((ref) {
  return ref.watch(categorySeederProvider).seedDefaults();
});
