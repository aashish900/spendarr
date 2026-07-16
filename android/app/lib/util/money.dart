// Money helpers. Amounts are integer cents end-to-end — never `double`.

/// Parse a user-entered amount string into integer cents.
///
/// Accepts a non-negative decimal with up to two fraction digits
/// (e.g. `"12"`, `"12.3"`, `"12.34"`). Returns null on anything malformed.
int? parseAmountToCents(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;

  final parts = s.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return whole * 100 + int.parse(fraction);
}

/// Format integer cents as a fixed two-decimal string (e.g. `1234` → `"12.34"`,
/// `-50` → `"-0.50"`). No locale/currency symbol — that's a display concern.
String formatCents(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

/// Groups a non-negative digit string using the Indian numbering system:
/// the last 3 digits form one group, then pairs of digits to the left
/// (e.g. `1234567` → `12,34,567`).
String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Format integer cents as a display rupee string with Indian digit
/// grouping (e.g. `482000` → `"₹4,820"`, `12345678` → `"₹1,23,456.78"`).
/// Paise are dropped when zero. Display-only — never round-trip this
/// through [parseAmountToCents]; use [formatCents] for that.
///
/// When [signed] is true, positive amounts get a `+` prefix. Negative
/// amounts always use the true minus sign (U+2212), not a hyphen.
String formatRupees(int cents, {bool signed = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final groupedWhole = _groupIndian(whole.toString());
  final amount = fraction == 0
      ? groupedWhole
      : '$groupedWhole.${fraction.toString().padLeft(2, '0')}';
  final sign = negative ? '−' : (signed ? '+' : '');
  return '$sign₹$amount';
}
