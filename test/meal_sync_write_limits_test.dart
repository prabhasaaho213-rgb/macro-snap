import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/meal_sync_service.dart';

/// Guards the two write-side limits that used to break cloud backup:
///
///   1. `syncAllMeals` put every delete and every set into ONE batch, and
///      Firestore caps a batch at 500 operations — a long history failed the
///      whole backup with "Bulk meal sync failed".
///   2. `firestore.rules` rejects a meal whose name is over 80 BYTES, whose
///      calories are outside 0..10000, or whose macros are outside 0..1000.
///      One bad meal (the name comes from the AI scan) failed on its own, and
///      inside a bulk batch took every other operation down with it.
///
/// These tests pin the clamping against the same numbers the rules use, so a
/// change to either side without the other shows up here.
void main() {
  MealRecord meal({
    String name = 'Idli',
    int calories = 200,
    double protein = 5,
    double carbs = 35,
    double fats = 2,
    double fiber = 3,
    String serving = '2 pieces',
    String category = 'Breakfast',
  }) => MealRecord(
    id: 'meal-1',
    date: DateTime(2026, 10, 30, 9, 30),
    name: name,
    category: category,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fats: fats,
    fiber: fiber,
    serving: serving,
  );

  group('batch size', () {
    test('stays under the 500-operation Firestore limit', () {
      expect(MealSyncService.maxBatchOperations, lessThan(500));
      expect(MealSyncService.maxBatchOperations, greaterThan(0));
    });
  });

  group('clampText', () {
    test('keeps short text untouched', () {
      expect(MealSyncService.clampText('Idli', 80), 'Idli');
    });

    test('cuts at the byte limit, not the character limit', () {
      // Four-byte characters: 20 emoji = 80 bytes, 21 would be 84.
      final name = '🍕' * 21;
      final clamped = MealSyncService.clampText(name, 80);
      expect(utf8.encode(clamped).length, lessThanOrEqualTo(80));
      expect(utf8.encode(clamped).length, 80);
      // A cut mid-character would either throw or produce a replacement char.
      expect(clamped.contains('\uFFFD'), isFalse);
    });

    test('never returns an empty string when a fallback is given', () {
      expect(MealSyncService.clampText('   ', 80, fallback: 'Meal'), 'Meal');
      expect(MealSyncService.clampText('', 80, fallback: 'Meal'), 'Meal');
    });
  });

  group('mealDoc', () {
    test('clamps a long AI dish name to the rule limit', () {
      final doc = MealSyncService.mealDoc(
        meal(name: 'P' * 400),
        'user-123',
      );
      final name = doc['name'] as String;
      expect(name.length, lessThanOrEqualTo(80));
      expect(utf8.encode(name).length, lessThanOrEqualTo(80));
    });

    test('clamps calories and macros into the allowed ranges', () {
      final doc = MealSyncService.mealDoc(
        meal(calories: 99999, protein: 5000, carbs: -4, fats: 2200, fiber: 1e9),
        'user-123',
      );
      expect(doc['calories'], 10000);
      expect(doc['protein'], 1000);
      expect(doc['carbs'], 0);
      expect(doc['fats'], 1000);
      expect(doc['fiber'], 1000);
    });

    test('always carries the owner uid and an int calorie count', () {
      final doc = MealSyncService.mealDoc(meal(), 'user-123');
      expect(doc['uid'], 'user-123');
      expect(doc['calories'], isA<int>());
      expect(doc['protein'], isA<num>());
    });

    test('stays within the 20-field document cap', () {
      final doc = MealSyncService.mealDoc(meal(), 'user-123');
      expect(doc.length, lessThanOrEqualTo(20));
    });

    test('trims the serving and category to the rule limits', () {
      final doc = MealSyncService.mealDoc(
        meal(serving: 's' * 500, category: 'c' * 100),
        'user-123',
      );
      expect(utf8.encode(doc['serving'] as String).length, lessThanOrEqualTo(200));
      expect(
        utf8.encode(doc['category'] as String).length,
        lessThanOrEqualTo(40),
      );
    });
  });
}
