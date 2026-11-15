import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/services/barcode_lookup.dart';

/// Two rules that were wrong in opposite directions: the calorie floor could
/// hand a "Maintain" user a surplus, and a barcode with macros but no energy
/// figure was logged as 0 kcal.
void main() {
  group('calorie targets', () {
    test('a small sedentary maintain profile is not pushed above maintenance',
        () {
      final profile = DietProfile(
        weightKg: 42,
        heightCm: 148,
        age: 60,
        gender: Gender.female,
        goal: Goal.maintain,
        activity: ActivityLevel.sedentary,
      );
      // The floor (max(BMR, 1200)) is above this TDEE, so the old code raised a
      // maintain target into a surplus.
      expect(profile.tdee, lessThan(1500));
      expect(profile.targetCalories, profile.tdee.round());
      expect(profile.targetCalories, lessThan(DietProfile.safeMinimumCaloriesFemale));
    });

    test('a deficit is still floored at the safe minimum', () {
      final profile = DietProfile(
        weightKg: 45,
        heightCm: 150,
        age: 25,
        gender: Gender.female,
        goal: Goal.loseWeight,
        activity: ActivityLevel.sedentary,
      );
      expect(
        profile.targetCalories,
        greaterThanOrEqualTo(DietProfile.safeMinimumCaloriesFemale),
      );
    });

    test('gain muscle keeps its own surplus, floor or not', () {
      final profile = DietProfile(
        weightKg: 50,
        heightCm: 155,
        age: 40,
        gender: Gender.female,
        goal: Goal.gainMuscle,
        activity: ActivityLevel.sedentary,
      );
      expect(profile.targetCalories, profile.tdee.round() + 300);
    });
  });

  group('barcode parsing', () {
    Map<String, dynamic> product(Map<String, dynamic> nutriments) => {
      'status': 1,
      'product': {'product_name': 'Test bar', 'nutriments': nutriments},
    };

    test('macros without an energy figure become an Atwater estimate', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        product({
          'proteins_100g': 10,
          'carbohydrates_100g': 20,
          'fat_100g': 5,
        }),
        '8901234567890',
      );
      expect(food, isNotNull);
      // 10*4 + 20*4 + 5*9 = 165
      expect(food!.caloriesPer100g, 165);
    });

    test('a stated energy figure still wins', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        product({'energy-kcal_100g': 250, 'proteins_100g': 10}),
        '8901234567890',
      );
      expect(food!.caloriesPer100g, 250);
    });

    test('an impossible macro is dropped, not logged', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        product({'energy-kcal_100g': 120, 'proteins_100g': 500}),
        '8901234567890',
      );
      expect(food!.proteinPer100g, 0);
    });

    test('impossible energy is treated as missing', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        product({'energy-kcal_100g': 4000, 'proteins_100g': 10}),
        '8901234567890',
      );
      // Falls back to 4/4/9 from the one macro present (10 g protein = 40).
      expect(food!.caloriesPer100g, 40);
    });

    test('a product with nothing usable is a miss', () {
      expect(
        BarcodeService.foodFromOpenFoodFacts(product({}), '8901234567890'),
        isNull,
      );
    });
  });
}
