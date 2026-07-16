import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'db/tables.dart';
import 'screens/add_category_screen.dart';
import 'screens/add_recurring_screen.dart';
import 'screens/add_txn_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/export_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/recurring_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>();

TransactionKind? _parseKind(String? name) {
  for (final k in TransactionKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// App routes. Five primary sections live behind a bottom-nav
/// `StatefulShellRoute` (`AppShell`); "add"/"export" screens push on the root
/// navigator so they cover the nav bar.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/categories',
              builder: (_, _) => const CategoriesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/recurring', builder: (_, _) => const RecurringScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ]),
      ],
    ),
    GoRoute(
      path: '/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => AddTxnScreen(
        initialCategoryId: state.uri.queryParameters['categoryId'],
        editTransactionId: state.uri.queryParameters['editTransactionId'],
        initialKind: _parseKind(state.uri.queryParameters['kind']),
      ),
    ),
    GoRoute(
      path: '/categories/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => AddCategoryScreen(
        editCategoryId: state.uri.queryParameters['editCategoryId'],
      ),
    ),
    GoRoute(
      path: '/recurring/add',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, _) => const AddRecurringScreen(),
    ),
    GoRoute(
      path: '/export',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, _) => const ExportScreen(),
    ),
  ],
);
