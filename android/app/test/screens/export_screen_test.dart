import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/export.dart';
import 'package:spendarr/screens/export_screen.dart';

class _FakeSharer implements FileSharer {
  String? sharedPath;

  @override
  Future<void> shareCsv(String path) async {
    sharedPath = path;
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late _FakeSharer sharer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('spendarr_export_test');
    sharer = _FakeSharer();

    await db.categoriesDao.upsertCategory(CategoriesCompanion.insert(
      id: 'c1', name: 'Food', emoji: '🍔',
      kind: TransactionKind.expense, createdAt: 0, updatedAt: 0,
    ));
    for (final id in ['t1', 't2']) {
      await db.transactionsDao.upsertTransaction(TransactionsCompanion.insert(
        id: id, amount: 100, kind: TransactionKind.expense, categoryId: 'c1',
        occurredAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        source: TransactionSource.manual, createdAt: 0, updatedAt: 0,
        note: const Value.absent(),
      ));
    }
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        cacheDirProvider.overrideWith((ref) => tempDir),
        fileSharerProvider.overrideWithValue(sharer),
      ],
      child: const MaterialApp(home: ExportScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('shows reactive row count preview', (tester) async {
    await pump(tester);
    expect(find.text('2 transaction(s) will be exported'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Export writes a CSV file and shares it', (tester) async {
    await pump(tester);

    // runAsync: the export does real filesystem IO (File.writeAsString) which
    // the fake test clock won't advance.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(); // reflect snackbar + _exporting = false

    expect(sharer.sharedPath, isNotNull);
    expect(sharer.sharedPath, endsWith('.csv'));
    expect(File(sharer.sharedPath!).existsSync(), isTrue);
    expect(find.text('Exported CSV'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
