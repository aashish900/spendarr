import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'transactions_dao.g.dart';

@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  /// Reactive stream of non-deleted transactions, newest first.
  Stream<List<TransactionRow>> watchActiveTransactions() {
    return (select(transactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch();
  }

  Future<TransactionRow?> transactionById(String id) {
    return (select(transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertTransaction(TransactionsCompanion entry) {
    return into(transactions).insertOnConflictUpdate(entry);
  }

  /// Soft-delete: sets [deletedAt]; row is retained for sync.
  Future<void> softDeleteTransaction(String id, {required int deletedAt}) {
    return (update(transactions)..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(deletedAt: Value(deletedAt)));
  }
}
