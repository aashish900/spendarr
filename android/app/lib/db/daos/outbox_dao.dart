import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [OutboxEntries])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  /// Append a mutation to the queue.
  Future<void> enqueue(OutboxEntriesCompanion entry) {
    return into(outboxEntries).insert(entry);
  }

  /// Reactive stream of the queue in FIFO order.
  Stream<List<OutboxEntry>> watchQueue() {
    return (select(outboxEntries)
          ..orderBy([(o) => OrderingTerm.asc(o.queuedAt)]))
        .watch();
  }

  /// Snapshot of the queue in FIFO order.
  Future<List<OutboxEntry>> queue() {
    return (select(outboxEntries)
          ..orderBy([(o) => OrderingTerm.asc(o.queuedAt)]))
        .get();
  }

  /// Drop a drained entry. Named [remove] to avoid clashing with
  /// [DatabaseAccessor.delete].
  Future<void> remove(String id) {
    return (delete(outboxEntries)..where((o) => o.id.equals(id))).go();
  }
}
