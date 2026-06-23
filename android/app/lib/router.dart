import 'package:go_router/go_router.dart';

import 'screens/add_category_screen.dart';
import 'screens/add_recurring_screen.dart';
import 'screens/add_txn_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/export_screen.dart';
import 'screens/history_screen.dart';
import 'screens/recurring_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';

/// App routes. All primary screens are implemented (B2–B5).
final GoRouter appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
    GoRoute(
      path: '/add',
      builder: (_, state) => AddTxnScreen(
        initialCategoryId: state.uri.queryParameters['categoryId'],
      ),
    ),
    GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
    GoRoute(
        path: '/categories', builder: (_, _) => const CategoriesScreen()),
    GoRoute(
        path: '/categories/add',
        builder: (_, _) => const AddCategoryScreen()),
    GoRoute(path: '/recurring', builder: (_, _) => const RecurringScreen()),
    GoRoute(
        path: '/recurring/add',
        builder: (_, _) => const AddRecurringScreen()),
    GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
