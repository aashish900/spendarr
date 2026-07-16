import 'package:flutter/material.dart';

/// Fallback icon for any emoji outside the curated map below — keeps every
/// category row visually consistent (a themed gold icon, never a raw
/// colourful emoji) even for a user-typed custom emoji.
const IconData kCategoryIconFallback = Icons.label_outline;

const Map<String, IconData> _categoryIcons = {
  // Seeded income categories (lib/db/seed_categories.dart).
  '💼': Icons.work_outline,
  '💵': Icons.payments_outlined,
  '🏦': Icons.account_balance_outlined,
  '📊': Icons.bar_chart_outlined,
  '📈': Icons.trending_up,
  '🪙': Icons.monetization_on_outlined,
  // Seeded expense categories.
  '🍔': Icons.lunch_dining,
  '☕': Icons.local_cafe_outlined,
  '🛒': Icons.shopping_cart_outlined,
  '🏠': Icons.home_outlined,
  '🧹': Icons.cleaning_services_outlined,
  '💳': Icons.credit_card,
  '🔌': Icons.bolt_outlined,
  '📚': Icons.menu_book_outlined,
  '💄': Icons.face_retouching_natural_outlined,
  '💊': Icons.medication_outlined,
  '🎉': Icons.celebration_outlined,
  // Extra CategoryForm quickEmojis without a seeded category.
  '🚗': Icons.directions_car_outlined,
  '💡': Icons.lightbulb_outline,
  '🎬': Icons.movie_outlined,
  '🎁': Icons.card_giftcard_outlined,
  '✈️': Icons.flight_outlined,
  '📱': Icons.smartphone_outlined,
  '💰': Icons.savings_outlined,
  '👕': Icons.checkroom_outlined,
  '🐶': Icons.pets_outlined,
  '🏥': Icons.local_hospital_outlined,
};

/// Maps a category's stored emoji to a themed Material icon for display.
/// The `emoji` field itself is untouched — this is a display-only lookup
/// (see DECISIONLOG) — so anything outside the curated set above (including
/// a genuinely custom emoji the user typed in) falls back to
/// [kCategoryIconFallback] rather than rendering the raw emoji.
IconData categoryIconFor(String emoji) =>
    _categoryIcons[emoji] ?? kCategoryIconFallback;

/// Every emoji with a curated icon mapping, in a stable display order — the
/// choices offered by [CategoryForm]'s icon picker. Picking from this list
/// guarantees what the user selects is exactly what renders everywhere else
/// (no silent fallback-icon remapping), since every entry has a real mapping
/// above.
final List<String> categoryIconChoices = _categoryIcons.keys.toList();
