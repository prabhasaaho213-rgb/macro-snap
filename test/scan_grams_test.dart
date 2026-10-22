import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/gemini_service.dart';

/// The analyzer now estimates the TOTAL weight of everything in the photo
/// (one egg ≈ 55 g, two ≈ 110 g). The app opens the serving at that weight,
/// while the +/- adjuster keeps rescaling macros from the per-100 g values.
Map<String, dynamic> _eggJson({Object? grams, Object? dishGrams}) => {
  'description': 'two boiled eggs',
  'confidence': 0.94,
  'grams': ?grams,
  'dishes': [
    {
      'name': 'Chicken egg',
      'portion_description': '2 boiled eggs',
      'calories_per_100g': 143,
      'protein_g_per_100g': 12.6,
      'carbs_g_per_100g': 0.6,
      'fats_g_per_100g': 9.6,
      'fiber_g_per_100g': 0,
      'sugar_g_per_100g': 0.2,
      'grams': ?dishGrams,
    },
  ],
};

void main() {
  test('the server total weight becomes the starting serving', () {
    final r = NutritionResult.fromJson(_eggJson(grams: 95));
    expect(r.grams, 95);
  });

  test('a missing weight falls back to the dishes\' own weights', () {
    // The server's total was lost but the per-dish weight survived: one egg
    // must open at one egg, never at the fixed 100 g baseline.
    final r = NutritionResult.fromJson(_eggJson(dishGrams: 55));
    expect(r.grams, 55);
  });

  test('a missing weight with no dish weights falls back to 100 g', () {
    final r = NutritionResult.fromJson(_eggJson());
    expect(r.grams, 100);
  });

  test('out-of-range weights are clamped to 5–3000 g', () {
    expect(NutritionResult.fromJson(_eggJson(grams: 99999)).grams, 3000);
    expect(NutritionResult.fromJson(_eggJson(grams: 1)).grams, 5);
    expect(NutritionResult.fromJson(_eggJson(grams: 0)).grams, 100);
  });

  test('the adjuster still rescales macros from the estimated weight', () {
    final r = NutritionResult.fromJson(_eggJson(grams: 100));
    expect(r.protein, closeTo(12.6, 0.01));
    expect(r.withGrams(50).protein, closeTo(6.3, 0.01));
    expect(r.withGrams(50).grams, 50);
  });

  test('per-dish cards use the estimated weight too', () {
    final r = NutritionResult.fromJson(_eggJson(grams: 100));
    final scaled = r.withGrams(50);
    expect(scaled.calories, 72, reason: '143 kcal/100 g at 50 g');
    expect(scaled.caloriesPer100g, 143);
  });
}
