import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_provider.dart';
import '../services/export_service.dart';

// Hand-written providers (touch drift row types / platform plugins).

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref.watch(appDatabaseProvider));
});

/// App cache directory (`path_provider`). Overridden in tests with a temp dir.
final cacheDirProvider = FutureProvider<Directory>((ref) {
  return getApplicationCacheDirectory();
});

/// Opens the OS share sheet for a file. Behind an interface so tests can inject
/// a fake (no platform channel).
abstract interface class FileSharer {
  Future<void> shareCsv(String path);
}

class PlatformFileSharer implements FileSharer {
  @override
  Future<void> shareCsv(String path) {
    return SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: 'text/csv')]),
    );
  }
}

final fileSharerProvider = Provider<FileSharer>((ref) => PlatformFileSharer());

/// Reactive count of non-deleted transactions matching the optional range.
/// Key `(null, null)` = all time.
final exportRowCountProvider =
    StreamProvider.family<int, (int?, int?)>((ref, range) {
  final dao = ref.watch(appDatabaseProvider).transactionsDao;
  final stream = (range.$1 == null || range.$2 == null)
      ? dao.watchActiveTransactions()
      : dao.watchByOccurredRange(range.$1!, range.$2!);
  return stream.map((rows) => rows.length);
});
