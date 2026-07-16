import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/widgets/kind_pill_selector.dart';

void main() {
  testWidgets('renders all three labels and reports taps', (tester) async {
    TransactionKind? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KindPillSelector(
          selected: TransactionKind.expense,
          onChanged: (k) => tapped = k,
        ),
      ),
    ));

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Investment'), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pump();
    expect(tapped, TransactionKind.income);
  });

  testWidgets('selected segment renders its label in black', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KindPillSelector(
          selected: TransactionKind.investment,
          onChanged: (_) {},
        ),
      ),
    ));

    final selectedText =
        tester.widget<Text>(find.text('Investment'));
    expect(selectedText.style?.color, Colors.black);

    final unselectedText = tester.widget<Text>(find.text('Expense'));
    expect(unselectedText.style?.color, Colors.white);
  });
}
