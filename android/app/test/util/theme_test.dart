import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/theme.dart';

void main() {
  group('buildDarkTheme', () {
    test('black+gold AMOLED palette', () {
      final theme = buildDarkTheme();
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.colorScheme.surface, const Color(0xFF111111));
      expect(theme.colorScheme.primary, kGold);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('exposes semantic colour constants (warm metallic gold spec)', () {
      expect(kGold, const Color(0xFFC89B3C)); // champagne base, not yellow
      expect(kGoldMuted, const Color(0xFF8A621E));
      expect(kIncomeGreen, const Color(0xFF58C77A)); // muted emerald
      expect(kExpenseRed, const Color(0xFFD46A6A)); // muted red
      expect(kTextSecondary, const Color(0xFFA0A0A0));
      expect(kCardBorder, const Color(0xFF242424));
      // Every gold element is a multi-stop gradient, not a flat fill.
      expect(kPremiumGoldGradient.colors, hasLength(5));
      expect(kRingProgressColors, hasLength(6));
      expect(kFabGradient.colors, hasLength(3));
    });

    test('FAB theme is a gold circle with a black icon', () {
      final theme = buildDarkTheme();
      expect(theme.floatingActionButtonTheme.backgroundColor, kGold);
      expect(theme.floatingActionButtonTheme.foregroundColor, Colors.black);
    });

    test('NavigationBar theme uses a black background', () {
      final theme = buildDarkTheme();
      expect(theme.navigationBarTheme.backgroundColor, const Color(0xFF000000));
    });
  });
}
