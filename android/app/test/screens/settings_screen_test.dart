import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spendarr/screens/settings_screen.dart';

void main() {
  testWidgets('Export CSV is the only option and navigates to /export',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
            path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
            path: '/export',
            builder: (_, _) => const Scaffold(body: Text('Export screen'))),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('Export CSV'), findsOneWidget);
    // Profile/Server fields are gone until they're functional again.
    expect(find.text('Display name'), findsNothing);
    expect(find.text('Backend URL'), findsNothing);

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Export screen'), findsOneWidget);
  });
}
