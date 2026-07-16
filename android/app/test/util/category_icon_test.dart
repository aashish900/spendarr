import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/util/category_icon.dart';

void main() {
  group('categoryIconFor', () {
    test('resolves a representative subset of the curated emoji', () {
      expect(categoryIconFor('🍔'), Icons.lunch_dining);
      expect(categoryIconFor('💼'), Icons.work_outline);
      expect(categoryIconFor('☕'), Icons.local_cafe_outlined);
      expect(categoryIconFor('🏠'), Icons.home_outlined);
      expect(categoryIconFor('📈'), Icons.trending_up);
    });

    test('falls back for an unmapped emoji', () {
      expect(categoryIconFor('🦄'), kCategoryIconFallback);
    });

    test('falls back for an empty string', () {
      expect(categoryIconFor(''), kCategoryIconFallback);
    });
  });
}
