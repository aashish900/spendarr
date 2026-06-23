import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/categories_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/recurring_dao.dart';
import 'daos/sync_meta_dao.dart';
import 'daos/transactions_dao.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    Transactions,
    RecurringRules,
    OutboxEntries,
    SyncMetaEntries,
  ],
  daos: [
    CategoriesDao,
    TransactionsDao,
    RecurringDao,
    OutboxDao,
    SyncMetaDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device SQLite file. Pass an explicit [executor]
  /// (e.g. `NativeDatabase.memory()`) in tests.
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'spendarr'));

  @override
  int get schemaVersion => 1;
}
