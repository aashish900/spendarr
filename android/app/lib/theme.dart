import 'package:flutter/material.dart';

/// Warm-metallic-gold AMOLED palette (Home redesign, 2026-07; refined to the
/// user's gradient spec — "90% matte black + 10% metallic gold", every gold
/// element a 3–5 stop gradient rather than a flat fill). See DECISIONLOG.

/// Primary gold base (champagne, not bright yellow).
const Color kGold = Color(0xFFC89B3C);
const Color kGoldMuted = Color(0xFF8A621E);

/// Cards sit just above pure black; borders are a thin 1px near-black.
const Color kSurfaceBlack = Color(0xFF111111);
const Color kBackgroundBlack = Color(0xFF000000);
const Color kCardBorder = Color(0xFF242424);
const Color kDivider = Color(0xFF1D1D1D);

/// Muted emerald / muted red — the only saturated colours in the UI.
const Color kIncomeGreen = Color(0xFF58C77A);
const Color kExpenseRed = Color(0xFFD46A6A);

const Color kTextSecondary = Color(0xFFA0A0A0);
const Color kTextMuted = Color(0xFF666666);

/// Primary gold gradient (top-left → bottom-right): general gold surfaces.
const LinearGradient kPrimaryGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFE9C46A),
    Color(0xFFD7B35A),
    Color(0xFFB8872B),
    Color(0xFF8F6320),
  ],
  stops: [0.0, 0.3, 0.7, 1.0],
);

/// Premium gold gradient (top → bottom): ring highlights, active tab,
/// important icons. Never reaches pure white.
const LinearGradient kPremiumGoldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFFFF1B8),
    Color(0xFFF2D27A),
    Color(0xFFD6AC4E),
    Color(0xFFB9862A),
    Color(0xFF8A621E),
  ],
  stops: [0.0, 0.2, 0.5, 0.8, 1.0],
);

/// FAB gradient (top → bottom) — one of the brightest pieces.
const LinearGradient kFabGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFF6D57F), Color(0xFFD9B054), Color(0xFFB8862D)],
);

/// Active tab / selected pill gradient (top → bottom).
const LinearGradient kActiveTabGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFE8C36A), Color(0xFFB98930)],
);

/// Gold icon gradient (top-left → bottom-right) — darker edge reads as
/// embossed metal. Apply via [ShaderMask] with [BlendMode.srcIn].
const LinearGradient kGoldIconGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF5D98D), Color(0xFFD6AA4C), Color(0xFF9B6B20)],
);

/// Month-ring progress arc stops — the brightest highlight sits at the arc's
/// leading edge (current progress), fading to dark bronze behind it.
const List<Color> kRingProgressColors = [
  Color(0xFFFFF2BF),
  Color(0xFFF8DB89),
  Color(0xFFE6BE63),
  Color(0xFFD4A548),
  Color(0xFFB87F24),
  Color(0xFF7E5517),
];
const List<double> kRingProgressStops = [0.0, 0.15, 0.35, 0.60, 0.85, 1.0];

/// Month-ring base track — very dark bronze, top → bottom.
const LinearGradient kRingTrackGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF3A3124), Color(0xFF19140E)],
);

/// Month-ring glow colour — barely-there on OLED (≈10% opacity, 16–20 blur).
const Color kRingGlow = Color(0xFFF2D27A);

/// The app's single (dark-only) theme. No light theme in v1 (see CONTEXT.md
/// "Out of scope").
ThemeData buildDarkTheme() {
  final colorScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: kGold,
    onPrimary: Colors.black,
    primaryContainer: kGoldMuted,
    onPrimaryContainer: Colors.white,
    secondary: kGoldMuted,
    onSecondary: Colors.white,
    surface: kSurfaceBlack,
    onSurface: Colors.white,
    error: kExpenseRed,
    onError: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kBackgroundBlack,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackgroundBlack,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurfaceBlack,
      modalBackgroundColor: kSurfaceBlack,
    ),
    dividerTheme: DividerThemeData(
      color: kDivider.withValues(alpha: 0.5),
      thickness: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kBackgroundBlack,
      // No filled pill behind the selected icon in the mockup — just a
      // colour change.
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? kGold
              : kTextSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? kGold
              : kTextSecondary,
          fontSize: 12,
        ),
      ),
    ),
    // Base colour only — GoldFab layers the metallic gradient on top (a
    // ThemeData can't express gradients).
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kGold,
      foregroundColor: Colors.black,
      shape: CircleBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? kGold
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : kTextSecondary,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: kGoldMuted),
        ),
        // The mockup's selected segment is a plain filled pill — no
        // checkmark icon overlay (Material 3's default).
        iconColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      selectedIcon: const SizedBox.shrink(),
    ),
    cardTheme: CardThemeData(
      color: kSurfaceBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kCardBorder),
      ),
    ),
  );
}
