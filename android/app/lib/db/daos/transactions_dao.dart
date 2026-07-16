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

  /// Reactive stream of non-deleted transactions whose [occurredAt] falls in
  /// `[fromMs, toMs)` (epoch ms, UTC). Newest first.
  Stream<List<TransactionRow>> watchByOccurredRange(int fromMs, int toMs) {
    return (select(transactions)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.occurredAt.isBiggerOrEqualValue(fromMs) &
              t.occurredAt.isSmallerThanValue(toMs))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch();
  }

  /// One-shot snapshot of all non-deleted transactions, oldest first
  /// (chronological — for CSV export).
  Future<List<TransactionRow>> activeTransactions() {
    return (select(transactions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
        .get();
  }

  /// One-shot snapshot of non-deleted transactions in `[fromMs, toMs)`,
  /// oldest first.
  Future<List<TransactionRow>> transactionsInRange(int fromMs, int toMs) {
    return (select(transactions)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.occurredAt.isBiggerOrEqualValue(fromMs) &
              t.occurredAt.isSmallerThanValue(toMs))
          ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
        .get();
  }

  Future<void> upsertTransaction(TransactionsCompanion entry) {
    return into(transactions).insertOnConflictUpdate(entry);
  }

  /// Edits an existing transaction's mutable fields. `createdAt` is left
  /// untouched (only `updatedAt` bumps, for LWW sync). [recurringRuleId]
  /// takes an explicit [Value] so callers can set, clear (`Value(null)`), or
  /// leave it unspecified (`Value.absent()`).
  Future<void> updateTransaction(
    String id, {
    required int amount,
    required TransactionKind kind,
    required String categoryId,
    required int occurredAt,
    String? note,
    Value<String?> recurringRuleId = const Value.absent(),
    required int updatedAt,
  }) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        amount: Value(amount),
        kind: Value(kind),
        categoryId: Value(categoryId),
        occurredAt: Value(occurredAt),
        note: Value(note),
        recurringRuleId: recurringRuleId,
        updatedAt: Value(updatedAt),
      ),
    );
  }

  /// Soft-delete: sets [deletedAt]; row is retained for sync. [updatedAt]
  /// bumps alongside it (when provided) so LWW ordering sees the deletion —
  /// same convention as `archiveCategory`.
  Future<void> softDeleteTransaction(
    String id, {
    required int deletedAt,
    int? updatedAt,
  }) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
      ),
    );
  }
}
