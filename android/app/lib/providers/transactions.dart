import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';

// DB-facing providers are hand-written (not @riverpod): riverpod_generator
// cannot resolve drift's generated row classes (TransactionRow) across
// builders. See DECISIONLOG 2026-06-23.

/// Net flow in cents for a set of transactions: income − expense.
/// Investments are excluded from net flow (CONTEXT.md: "income − expense").
int netFlowCents(List<TransactionRow> txns) {
  var net = 0;
  for (final t in txns) {
    switch (t.kind) {
      case TransactionKind.income:
        net += t.amount;
      case TransactionKind.expense:
        net -= t.amount;
      case TransactionKind.investment:
        break;
    }
  }
  return net;
}

/// The UTC epoch-ms half-open range `[startMs, endMs)` covering the local
/// calendar day of [now] (defaults to the current instant).
({int startMs, int endMs}) todayUtcBounds([DateTime? now]) {
  final local = (now ?? DateTime.now()).toLocal();
  final startLocal = DateTime(local.year, local.month, local.day);
  final endLocal = startLocal.add(const Duration(days: 1));
  return (
    startMs: startLocal.toUtc().millisecondsSinceEpoch,
    endMs: endLocal.toUtc().millisecondsSinceEpoch,
  );
}

/// Emits the current local calendar day (time truncated to midnight),
/// re-emitting whenever it changes. Watched by [todayTransactionsProvider] so
/// its window recomputes after midnight instead of staying pinned to the day
/// the provider was first created.
final localDayTickProvider = StreamProvider<DateTime>((ref) async* {
  DateTime localDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  yield localDay(DateTime.now());
  yield* Stream.periodic(const Duration(minutes: 1))
      .map((_) => localDay(DateTime.now()))
      .distinct();
});

/// Reactive stream of today's (local day) non-deleted transactions.
final todayTransactionsProvider =
    StreamProvider<List<TransactionRow>>((ref) {
  final day = ref.watch(localDayTickProvider).value ?? DateTime.now();
  final bounds = todayUtcBounds(day);
  return ref
      .watch(appDatabaseProvider)
      .transactionsDao
      .watchByOccurredRange(bounds.startMs, bounds.endMs);
});

/// Net flow (cents) for today, derived from [todayTransactionsProvider].
final todayNetFlowProvider = Provider<int>((ref) {
  final txns = ref.watch(todayTransactionsProvider).value ?? const [];
  return netFlowCents(txns);
});

final transactionWriterProvider = Provider<TransactionWriter>((ref) {
  return TransactionWriter(ref.watch(appDatabaseProvider));
});

/// Writes transactions through the local-first path: drift row + outbox entry
/// in a single DB transaction. This is the *only* correct write path — the
/// (deferred) sync engine drains the outbox; online and offline writes are
/// identical.
class TransactionWriter {
  TransactionWriter(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<String> add({
    required int amountCents,
    required TransactionKind kind,
    required String categoryId,
    required int occurredAtMs,
    String? note,
    String? recurringRuleId,
    String? id,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final txnId = id ?? _uuid.v4();

    await _db.transaction(() async {
      await _db.transactionsDao.upsertTransaction(
        TransactionsCompanion.insert(
          id: txnId,
          amount: amountCents,
          kind: kind,
          categoryId: categoryId,
          occurredAt: occurredAtMs,
          source: TransactionSource.manual,
          createdAt: now,
          updatedAt: now,
          note: Value(note),
          recurringRuleId: Value(recurringRuleId),
        ),
      );
      await _db.outboxDao.enqueue(
        OutboxEntriesCompanion.insert(
          id: _uuid.v4(),
          op: OutboxOp.upsert,
          targetTable: 'transactions',
          payloadJson: jsonEncode(<String, Object?>{
            'id': txnId,
            'amount': amountCents,
            'kind': kind.name,
            'category_id': categoryId,
            'occurred_at': occurredAtMs,
            'note': note,
            'source': TransactionSource.manual.name,
            'recurring_rule_id': recurringRuleId,
            'created_at': now,
            'updated_at': now,
            'deleted_at': null,
          }),
          queuedAt: now,
        ),
      );
    });

    return txnId;
  }

  /// Soft-deletes a transaction (sets `deletedAt`, row retained for sync)
  /// and enqueues an outbox `delete` in the same DB transaction.
  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await _db.transaction(() async {
      await _db.transactionsDao
          .softDeleteTransaction(id, deletedAt: now, updatedAt: now);
      await _db.outboxDao.enqueue(
        OutboxEntriesCompanion.insert(
          id: _uuid.v4(),
          op: OutboxOp.delete,
          targetTable: 'transactions',
          payloadJson: jsonEncode(<String, Object?>{
            'id': id,
            'deleted_at': now,
            'updated_at': now,
          }),
          queuedAt: now,
        ),
      );
    });
  }

  /// Edits an existing transaction. [recurringRuleId] is the desired final
  /// value (`null` unlinks it) — callers always pass the complete resolved
  /// state, there's no "leave unspecified" case at this layer.
  Future<void> update({
    required String id,
    required int amountCents,
    required TransactionKind kind,
    required String categoryId,
    required int occurredAtMs,
    String? note,
    String? recurringRuleId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await _db.transaction(() async {
      await _db.transactionsDao.updateTransaction(
        id,
        amount: amountCents,
        kind: kind,
        categoryId: categoryId,
        occurredAt: occurredAtMs,
        note: note,
        recurringRuleId: Value(recurringRuleId),
        updatedAt: now,
      );
      await _db.outboxDao.enqueue(
        OutboxEntriesCompanion.insert(
          id: _uuid.v4(),
          op: OutboxOp.upsert,
          targetTable: 'transactions',
          payloadJson: jsonEncode(<String, Object?>{
            'id': id,
            'amount': amountCents,
            'kind': kind.name,
            'category_id': categoryId,
            'occurred_at': occurredAtMs,
            'note': note,
            'recurring_rule_id': recurringRuleId,
            'updated_at': now,
          }),
          queuedAt: now,
        ),
      );
    });
  }
}
