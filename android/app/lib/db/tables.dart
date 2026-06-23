import 'package:drift/drift.dart';

/// Kind of money movement. Stored as the enum name (TEXT) via [textEnum].
enum TransactionKind { income, expense, investment }

/// How a transaction came to exist.
enum TransactionSource { manual, recurring }

/// Outbox operation type — what the sync engine will replay to the server.
enum OutboxOp { upsert, delete }

/// User-defined spend/income categories (emoji + name + kind).
///
/// Synced table: carries the standard id/createdAt/updatedAt/deletedAt set.
/// "Archive" is a soft delete (deletedAt set); rows are never hard-deleted.
@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()(); // UUID string — same PK as server.
  TextColumn get name => text()();
  TextColumn get emoji => text()();
  TextColumn get kind => textEnum<TransactionKind>()();
  IntColumn get createdAt => integer()(); // epoch ms, UTC
  IntColumn get updatedAt => integer()(); // epoch ms, UTC
  IntColumn get deletedAt => integer().nullable()(); // epoch ms, UTC; null = active

  @override
  Set<Column> get primaryKey => {id};
}

/// Income / expense / investment entries. [amount] is INTEGER cents — never a
/// float (SQLite has no DECIMAL; cents avoids IEEE-754 drift).
@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get amount => integer()(); // cents, e.g. 1234 = 12.34
  TextColumn get kind => textEnum<TransactionKind>()();
  TextColumn get categoryId => text()(); // no FK constraint — server is source of truth on sync
  IntColumn get occurredAt => integer()(); // epoch ms, UTC — drives retention
  TextColumn get note => text().nullable()();
  TextColumn get source => textEnum<TransactionSource>()();
  TextColumn get recurringRuleId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recurring transaction templates. [active] is the pause/resume flag.
@DataClassName('RecurringRule')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  IntColumn get amount => integer()(); // cents
  TextColumn get kind => textEnum<TransactionKind>()();
  TextColumn get note => text().nullable()();
  TextColumn get cron => text()(); // cron-ish schedule string
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get nextRunAt => integer().nullable()(); // epoch ms, UTC
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-only mutation queue. The sync engine (deferred, B7) drains this FIFO.
/// Not a synced table itself — no soft-delete columns.
@DataClassName('OutboxEntry')
class OutboxEntries extends Table {
  @override
  String get tableName => 'outbox';

  TextColumn get id => text()();
  TextColumn get op => textEnum<OutboxOp>()();
  TextColumn get targetTable => text()(); // which synced table the payload belongs to
  TextColumn get payloadJson => text()();
  IntColumn get queuedAt => integer()(); // epoch ms, UTC — FIFO order
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-only key/value store: `last_pull_at`, `pre_rotation_*` flags, etc.
@DataClassName('SyncMetaEntry')
class SyncMetaEntries extends Table {
  @override
  String get tableName => 'sync_meta';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
