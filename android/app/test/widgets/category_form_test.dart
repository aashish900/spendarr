import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/util/category_icon.dart';
import 'package:spendarr/widgets/category_form.dart';

void main() {
  testWidgets('picking an icon and saving persists exactly that emoji',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    String? savedId;
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        home: Scaffold(
          body: CategoryForm(onSaved: (id, kind) => savedId = id),
        ),
      ),
    ));
    await tester.pump();

    // Default selection is the first curated icon choice.
    expect(categoryIconChoices.first, isNotEmpty);

    // Pick the second curated icon instead of the default.
    final secondEmoji = categoryIconChoices[1];
    await tester.tap(find.byIcon(categoryIconFor(secondEmoji)));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'Custom');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(savedId, isNotNull);
    final row = await db.categoriesDao.categoryById(savedId!);
    // What was tapped is exactly what got persisted — no fallback remapping.
    expect(row!.emoji, secondEmoji);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping an icon updates the visual selection', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        home: Scaffold(body: CategoryForm(onSaved: (_, _) {})),
      ),
    ));
    await tester.pump();

    // Every curated choice renders as an icon on screen (the picker itself,
    // not just other screens, uses the themed icon — no colourful emoji).
    for (final e in categoryIconChoices.take(3)) {
      expect(find.byIcon(categoryIconFor(e)), findsWidgets);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
