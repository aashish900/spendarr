import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/util/category_icon.dart';
import 'package:spendarr/widgets/category_icon_bubble.dart';

void main() {
  testWidgets('renders the mapped icon for a known emoji', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CategoryIconBubble('🍔')),
    ));

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(Icons.lunch_dining), findsOneWidget);
  });

  testWidgets('renders the fallback icon for an unknown emoji', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CategoryIconBubble('🦄')),
    ));

    expect(find.byIcon(kCategoryIconFallback), findsOneWidget);
  });
}
