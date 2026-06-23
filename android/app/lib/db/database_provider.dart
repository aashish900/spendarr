import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';

part 'database_provider.g.dart';

/// The single app-wide drift database. Opened once; closed when the provider
/// is disposed. Tests override this with `AppDatabase(NativeDatabase.memory())`.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
