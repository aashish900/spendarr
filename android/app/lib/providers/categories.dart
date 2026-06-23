import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

// Hand-written (not @riverpod): riverpod_generator cannot resolve drift's
// generated row classes (Category) across builders. See DECISIONLOG 2026-06-23.

/// Reactive stream of non-archived categories from local drift.
final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).categoriesDao.watchActiveCategories();
});
