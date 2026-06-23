import 'package:flutter/material.dart';

/// Seed colour for the Material 3 scheme. Deep violet — deliberately distinct
/// from heerr's green so the two apps are visually unmistakable. See
/// DECISIONLOG 2026-06-23.
const Color kSeedColor = Color(0xFF7C4DFF);

/// The app's single (dark-only) theme. No light theme in v1 (see CONTEXT.md
/// "Out of scope").
ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: Brightness.dark,
    ),
  );
}
