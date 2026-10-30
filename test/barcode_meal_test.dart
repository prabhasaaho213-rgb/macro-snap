import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/barcode_scan_screen.dart';
import 'package:macro_snap/services/barcode_db.dart';

/// Barcode labels quote per 100 g, so the logged meal must be scaled to what
/// was actually eaten. It used to log the raw per-100 g numbers with the
/// serving hardcoded to "100g", which over-counted every snack-sized portion.
void main() {
  const oats = BarcodeFood(
    barcode: '8901234567890',
    name: 'Masala Oats',
    brand: 'Saffola',
    caloriesPer100g: 380,
    proteinPer100g: 8.5,
    carbsPer100g: 61.0,
    fatsPer100g: 10.0,
    fiberPer100g: 4.0,
  );

  test('a 100 g portion is the label exactly', () {
    final meal = mealFromBarcode(oats, 100);
    expect(meal.calories, 380);
    expect(meal.protein, 8.5);
    expect(meal.carbs, 61.0);
    expect(meal.fats, 10.0);
    expect(meal.fiber, 4.0);
    expect(meal.serving, '100g');
  });

  test('a 30 g portion scales every macro and records the weight', () {
    final meal = mealFromBarcode(oats, 30);
    expect(meal.calories, 114); // 380 * 0.3 = 114
    expect(meal.protein, closeTo(2.55, 1e-9));
    expect(meal.carbs, closeTo(18.3, 1e-9));
    expect(meal.fats, closeTo(3.0, 1e-9));
    expect(meal.serving, '30g');
  });

  test('a portion larger than 100 g scales up', () {
    final meal = mealFromBarcode(oats, 250);
    expect(meal.calories, 950);
    expect(meal.serving, '250g');
  });

  test('the product name and brand land on the meal', () {
    final meal = mealFromBarcode(oats, 50);
    expect(meal.name, 'Masala Oats');
    expect(meal.category, 'Saffola');
    expect(meal.id, startsWith('barcode_'));
  });
}
