import 'dart:io';

import '../db/database.dart';
import '../util/money.dart';

/// Fixed CSV column order (see CONTEXT.md / CLAUDE.md).
const csvHeader = 'date,amount,kind,category,note,source,recurring_rule_id';

/// Builds and writes a CSV export of transactions from local drift. Pure CSV
/// generation ([buildCsv]) is separated from file IO ([exportToCsv]) so the
/// content is testable without `path_provider`.
class ExportService {
  ExportService(this._db);

  final AppDatabase _db;

  /// Build the CSV string for all non-deleted transactions, optionally
  /// filtered to `[fromMs, toMs)` (epoch ms, UTC). Categories (including
  /// archived) are joined for the `category` column.
  Future<String> buildCsv({int? fromMs, int? toMs}) async {
    final txns = (fromMs != null && toMs != null)
        ? await _db.transactionsDao.transactionsInRange(fromMs, toMs)
        : await _db.transactionsDao.activeTransactions();
    final names = {
      for (final c in await _db.categoriesDao.allCategories()) c.id: c.name,
    };

    final buffer = StringBuffer()..writeln(csvHeader);
    for (final t in txns) {
      buffer.writeln([
        _localDate(t.occurredAt),
        formatCents(t.amount),
        t.kind.name,
        names[t.categoryId] ?? '',
        t.note ?? '',
        t.source.name,
        t.recurringRuleId ?? '',
      ].map(_escape).join(','));
    }
    return buffer.toString();
  }

  /// Build the CSV and write it to `<cacheDir>/spendarr_export_<ts>.csv`.
  /// Returns the written file.
  Future<File> exportToCsv({
    required Directory cacheDir,
    int? fromMs,
    int? toMs,
  }) async {
    final csv = await buildCsv(fromMs: fromMs, toMs: toMs);
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final file = File('${cacheDir.path}/spendarr_export_$ts.csv');
    await file.writeAsString(csv);
    return file;
  }

  /// Local calendar date `YYYY-MM-DD` of a UTC epoch-ms instant.
  static String _localDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// RFC 4180: quote fields containing comma, quote, CR or LF; double any
  /// embedded quotes.
  static String _escape(String field) {
    if (field.contains(RegExp('[",\r\n]'))) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}
