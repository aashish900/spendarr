import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'gilded.dart';

/// Bottom-nav shell for the five primary sections (Home/History/Categories/
/// Recurring/Settings), driven by go_router's `StatefulShellRoute`. Replaces
/// the temporary Drawer from B4 — see DECISIONLOG.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  // Selected icons get the metallic gradient (Gilded); unselected stay the
  // theme's muted grey.
  static NavigationDestination _destination(IconData icon, String label) =>
      NavigationDestination(
        icon: Icon(icon),
        selectedIcon: Gilded(child: Icon(icon, color: Colors.white)),
        label: label,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          _destination(Icons.home_outlined, 'Home'),
          _destination(Icons.history, 'History'),
          _destination(Icons.category_outlined, 'Categories'),
          _destination(Icons.repeat, 'Recurring'),
          _destination(Icons.settings, 'Settings'),
        ],
      ),
    );
  }
}
