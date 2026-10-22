import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/habit_store.dart';

/// Regression tests for corrupt-data handling.
///
/// Both stores used to parse a whole list inside one try/catch, so a single
/// bad row threw and the catch cleared everything — one truncated write cost
/// the user their entire habit list or meal history.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MealRecord.tryFromJson', () {
    test('keeps a valid record', () {
      final meal = MealRecord.tryFromJson({
        'id': 'm1',
        'date': '2026-10-17T08:30:00.000',
        'name': 'Poha',
        'category': 'breakfast',
        'calories': 250,
        'protein': 6,
        'carbs': 42,
        'fats': 7,
        'fiber': 3,
        'serving': '1 bowl',
      });
      expect(meal, isNotNull);
      expect(meal!.name, 'Poha');
      expect(meal.calories, 250);
    });

    test('returns null for a truncated record instead of throwing', () {
      expect(
        MealRecord.tryFromJson({'id': 'm2'}),
        isNull,
        reason: 'date/name/macros are required',
      );
    });

    test('returns null for an unparseable date', () {
      expect(
        MealRecord.tryFromJson({
          'id': 'm3',
          'date': 'not-a-date',
          'name': 'Dal',
          'calories': 120,
          'protein': 8,
          'carbs': 15,
          'fats': 2,
          'fiber': 5,
        }),
        isNull,
      );
    });
  });

  group('Habit.tryFromJson', () {
    test('keeps a valid habit', () {
      final habit = Habit.tryFromJson({
        'id': 'h1',
        'name': 'Walk',
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(habit, isNotNull);
      expect(habit!.name, 'Walk');
      expect(habit.createdAt.year, 2026);
    });

    test('returns null when required fields are missing or mistyped', () {
      expect(Habit.tryFromJson({'id': 'h2'}), isNull);
      expect(Habit.tryFromJson({'id': 123, 'name': 'Walk'}), isNull);
    });
  });

  group('HabitStore.load with mixed data', () {
    test('one corrupt habit does not wipe the others', () async {
      final good = Habit(
        id: 'good-1',
        name: 'Drink water',
        emoji: '💧',
        colorValue: 0xFF00CC52,
        frequency: 'Daily',
      );
      SharedPreferences.setMockInitialValues({
        'habits': jsonEncode([
          good.toJson(),
          {'id': 'broken'}, // missing name → used to throw for the whole list
        ]),
      });

      await HabitStore.instance.reload();

      expect(
        HabitStore.instance.habits,
        hasLength(1),
        reason: 'the valid habit must survive a corrupt neighbour',
      );
      expect(HabitStore.instance.habits.single.id, 'good-1');
    });
  });
}
