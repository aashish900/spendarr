import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';

// Hand-written providers (drift row types). See DECISIONLOG 2026-06-23.

/// Reactive stream of non-deleted recurring rules from local drift.
final activeRecurringProvider = StreamProvider<List<RecurringRule>>((ref) {
  return ref.watch(appDatabaseProvider).recurringDao.watchActiveRules();
});

final recurringWriterProvider = Provider<RecurringWriter>((ref) {
  return RecurringWriter(ref.watch(appDatabaseProvider));
});

/// Local-first writes for recurring rules: drift row + outbox entry in one
/// transaction. Create/pause/resume are all `upsert` (see DECISIONLOG).
class RecurringWriter {
  RecurringWriter(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<String> add({
    required String categoryId,
    required int amountCents,
    required TransactionKind kind,
    required String cron,
    String? note,
    int? nextRunAtMs,
    String? id,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ruleId = id ?? _uuid.v4();

    await _db.transaction(() async {
      await _db.recurringDao.upsertRule(
        RecurringRulesCompanion.insert(
          id: ruleId,
          categoryId: categoryId,
          amount: amountCents,
          kind: kind,
          cron: cron,
          createdAt: now,
          updatedAt: now,
          note: Value(note),
          nextRunAt: Value(nextRunAtMs),
        ),
      );
      await _db.outboxDao.enqueue(_outbox(ruleId, {
        'id': ruleId,
        'category_id': categoryId,
        'amount': amountCents,
        'kind': kind.name,
        'cron': cron,
        'note': note,
        'active': true,
        'next_run_at': nextRunAtMs,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      }, now));
    });

    return ruleId;
  }

  /// Edits an existing rule (category/amount/kind/cron/note). Leaves
  /// `active`/`createdAt` untouched; bumps `updatedAt` + outbox upsert.
  Future<void> update({
    required String id,
    required String categoryId,
    required int amountCents,
    required TransactionKind kind,
    required String cron,
    String? note,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.recurringDao.updateRule(
        id,
        categoryId: categoryId,
        amount: amountCents,
        kind: kind,
        cron: cron,
        note: note,
        updatedAt: now,
      );
      await _db.outboxDao.enqueue(_outbox(id, {
        'id': id,
        'category_id': categoryId,
        'amount': amountCents,
        'kind': kind.name,
        'cron': cron,
        'note': note,
        'updated_at': now,
      }, now));
    });
  }

  /// Pause/resume; writes `active` + outbox upsert.
  Future<void> setActive(String id, bool active) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.recurringDao.setActive(id, active, updatedAt: now);
      await _db.outboxDao.enqueue(_outbox(id, {
        'id': id,
        'active': active,
        'updated_at': now,
      }, now));
    });
  }

  /// Soft-deletes a rule; existing transactions already linked to it are
  /// untouched (only the rule itself stops firing/appearing).
  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.recurringDao.softDeleteRule(id, deletedAt: now);
      await _db.outboxDao.enqueue(
        OutboxEntriesCompanion.insert(
          id: _uuid.v4(),
          op: OutboxOp.delete,
          targetTable: 'recurring_rules',
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

  OutboxEntriesCompanion _outbox(
    String id,
    Map<String, Object?> payload,
    int now,
  ) {
    return OutboxEntriesCompanion.insert(
      id: _uuid.v4(),
      op: OutboxOp.upsert,
      targetTable: 'recurring_rules',
      payloadJson: jsonEncode(payload),
      queuedAt: now,
    );
  }
}
