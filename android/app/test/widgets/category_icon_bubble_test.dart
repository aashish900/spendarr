import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/widgets/category_icon_bubble.dart';
import 'package:spendarr/widgets/gilded.dart';

void main() {
  testWidgets('renders the given emoji in its native colour, inside a dark circle',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CategoryIconBubble('🦄')),
    ));

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('🦄'), findsOneWidget);
    // Not gilded — an earlier attempt gilded the raw emoji, which discarded
    // its colour and left a solid gold silhouette (reported as a regression).
    expect(find.byType(Gilded), findsNothing);
  });

  testWidgets('renders any emoji, not just a curated set', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CategoryIconBubble('🥷')),
    ));

    expect(find.text('🥷'), findsOneWidget);
  });
}
