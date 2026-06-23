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
