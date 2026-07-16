import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/services/export_service.dart';

void main() {
  late AppDatabase db;
  late ExportService service;

  int ms(int y, int m, int d) =>
      DateTime(y, m, d, 12).toUtc().millisecondsSinceEpoch;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = ExportService(db);

    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1', name: 'Food', emoji: '🍔',
      kind: TransactionKind.expense, createdAt: 0, updatedAt: 0,
    ));
    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c2', name: 'Travel', emoji: '✈️',
      kind: TransactionKind.expense, createdAt: 0, updatedAt: 0,
    ));
    await db.categoriesDao.archiveCategory('c2', deletedAt: 1); // archived but referenced

    Future<void> tx(String id, int amount, TransactionKind kind, String cat,
            int occurredAt, {String? note}) =>
        db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
          id: id, amount: amount, kind: kind, categoryId: cat,
          occurredAt: occurredAt, source: TransactionSource.manual,
          createdAt: 0, updatedAt: 0, note: Value(note),
        ));

    await tx('t1', 123456, TransactionKind.expense, 'c1', ms(2026, 6, 10),
        note: 'lunch');
    await tx('t2', 5000, TransactionKind.income, 'c2', ms(2026, 6, 20));
    await tx('t3', 999, TransactionKind.expense, 'c1', ms(2026, 6, 15));
    await db.transactionsDao.softDeleteTransaction('t3', deletedAt: 2);
    await tx('t4', 200, TransactionKind.expense, 'c1', ms(2026, 6, 12),
        note: 'a, b "x"');
  });

  tearDown(() => db.close());

  test('header is the fixed column order', () async {
    final csv = await service.buildCsv();
    expect(csv.split('\n').first, csvHeader);
    expect(csvHeader,
        'date,amount,kind,category,note,source,recurring_rule_id');
  });

  test('exports all non-deleted rows; soft-deleted excluded', () async {
    final csv = await service.buildCsv();
    final lines = csv.trim().split('\n');
    expect(lines, hasLength(1 + 3)); // header + t1, t4, t2
    expect(csv.contains('9.99'), isFalse); // t3 (soft-deleted) absent
  });

  test('amounts are decimal strings, not cents', () async {
    final csv = await service.buildCsv();
    expect(csv.contains('1234.56'), isTrue); // 123456 cents
    expect(csv.contains('123456'), isFalse);
  });

  test('category name resolved, including archived categories', () async {
    final csv = await service.buildCsv();
    expect(csv.contains('Food'), isTrue);
    expect(csv.contains('Travel'), isTrue); // c2 is archived
  });

  test('date column is local YYYY-MM-DD', () async {
    final csv = await service.buildCsv();
    expect(csv.contains('2026-06-10'), isTrue);
  });

  test('fields with commas/quotes are RFC-4180 escaped', () async {
    final csv = await service.buildCsv();
    expect(csv.contains('"a, b ""x"""'), isTrue);
  });

  test('rows ordered oldest first', () async {
    final csv = await service.buildCsv();
    final dataLines = csv.trim().split('\n').skip(1).toList();
    expect(dataLines[0].startsWith('2026-06-10'), isTrue); // t1
    expect(dataLines[1].startsWith('2026-06-12'), isTrue); // t4
    expect(dataLines[2].startsWith('2026-06-20'), isTrue); // t2
  });

  test('date-range filter selects only matching rows', () async {
    // 11 Jun .. 16 Jun → only t4 (12 Jun); t3 in range but soft-deleted.
    final csv = await service.buildCsv(
      fromMs: ms(2026, 6, 11),
      toMs: ms(2026, 6, 16),
    );
    final lines = csv.trim().split('\n');
    expect(lines, hasLength(2)); // header + t4
    expect(csv.contains('2.00'), isTrue); // t4 amount
    expect(csv.contains('1234.56'), isFalse); // t1 excluded
  });
}
