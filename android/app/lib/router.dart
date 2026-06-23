import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/settings_screen.dart';

/// App routes. Screens are placeholders at B1 — real implementations land in
/// B2+ (Settings), B3 (Today/Add), B4 (Categories/Recurring), B5 (History).
final GoRouter appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    GoRoute(path: '/today', builder: (_, _) => const _Placeholder('Today')),
    GoRoute(path: '/add', builder: (_, _) => const _Placeholder('Add')),
    GoRoute(
        path: '/history', builder: (_, _) => const _Placeholder('History')),
    GoRoute(
        path: '/categories',
        builder: (_, _) => const _Placeholder('Categories')),
    GoRoute(
        path: '/recurring',
        builder: (_, _) => const _Placeholder('Recurring')),
    GoRoute(
        path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);

/// Temporary stand-in until each screen is built in its milestone.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(child: Text('$label screen — coming soon')),
    );
  }
}
