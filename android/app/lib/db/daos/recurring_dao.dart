import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'recurring_dao.g.dart';

@DriftAccessor(tables: [RecurringRules])
class RecurringDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.db);

  /// Reactive stream of non-deleted recurring rules.
  Stream<List<RecurringRule>> watchActiveRules() {
    return (select(recurringRules)..where((r) => r.deletedAt.isNull())).watch();
  }

  /// One-shot snapshot of non-deleted recurring rules (Future, not a stream).
  Future<List<RecurringRule>> activeRules() {
    return (select(recurringRules)..where((r) => r.deletedAt.isNull())).get();
  }

  Future<RecurringRule?> ruleById(String id) {
    return (select(recurringRules)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertRule(RecurringRulesCompanion entry) {
    return into(recurringRules).insertOnConflictUpdate(entry);
  }

  /// Pause/resume toggle; bumps `updatedAt` for LWW sync.
  Future<void> setActive(String id, bool active, {required int updatedAt}) {
    return (update(recurringRules)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(
        active: Value(active),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> softDeleteRule(String id, {required int deletedAt}) {
    return (update(recurringRules)..where((r) => r.id.equals(id)))
        .write(RecurringRulesCompanion(deletedAt: Value(deletedAt)));
  }
}
