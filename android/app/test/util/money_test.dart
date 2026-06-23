import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/util/money.dart';

void main() {
  group('parseAmountToCents', () {
    test('whole and decimal inputs', () {
      expect(parseAmountToCents('12'), 1200);
      expect(parseAmountToCents('12.3'), 1230);
      expect(parseAmountToCents('12.34'), 1234);
      expect(parseAmountToCents('0.05'), 5);
      expect(parseAmountToCents('  7.50 '), 750);
    });

    test('rejects malformed input', () {
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('12.345'), isNull); // >2 fraction digits
      expect(parseAmountToCents('-5'), isNull); // negatives not entered
      expect(parseAmountToCents('1,234'), isNull);
      expect(parseAmountToCents('.5'), isNull);
    });
  });

  group('formatCents', () {
    test('formats with two decimals', () {
      expect(formatCents(1234), '12.34');
      expect(formatCents(5), '0.05');
      expect(formatCents(0), '0.00');
      expect(formatCents(-1234), '-12.34');
      expect(formatCents(-50), '-0.50');
    });
  });
}
