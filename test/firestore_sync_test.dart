import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/meal_sync_service.dart';
import 'package:macro_snap/services/sync_status_service.dart';

/// Behavioral tests for the Phase-3 Firestore migration of [MealSyncService].
///
/// In the test environment Firebase is never initialized, so
/// [MealSyncService]'s UID resolution returns null — the same state as a
/// guest user (or a fresh app before auth restores). The contract that must
/// hold: a guest is NOT a cloud failure, so every sync method returns its
/// "no cloud account" value WITHOUT raising the sync banner.
void main() {
  final meal = MealRecord(
    id: 'test-meal-1',
    date: DateTime(2026, 8, 4, 9, 30),
    name: 'Idli',
    category: 'Breakfast',
    calories: 200,
    protein: 5.0,
    carbs: 35.0,
    fats: 2.0,
    fiber: 3.0,
    serving: '2 pieces',
  );

  setUp(() {
    // Fresh singleton state per test.
    SyncStatusService.instance.dismiss();
  });

  test('guest (no Firebase) syncMeal is a silent no-op — no banner', () async {
    final ok = await MealSyncService.syncMeal(meal);
    expect(ok, false);
    expect(SyncStatusService.instance.backendUnreachable, false);
  });

  test(
    'guest (no Firebase) removeMeal is a silent no-op — no banner',
    () async {
      final ok = await MealSyncService.removeMeal('test-meal-1');
      expect(ok, false);
      expect(SyncStatusService.instance.backendUnreachable, false);
    },
  );

  test('guest fetchMeals returns empty list — no banner', () async {
    final meals = await MealSyncService.fetchMeals();
    expect(meals, isEmpty);
    expect(SyncStatusService.instance.backendUnreachable, false);
  });

  test('guest fetchHabits returns null — no banner', () async {
    final habits = await MealSyncService.fetchHabits();
    expect(habits, isNull);
    expect(SyncStatusService.instance.backendUnreachable, false);
  });

  test('guest syncHabits is a silent no-op — no banner', () async {
    final ok = await MealSyncService.syncHabits(
      habitsJson: const [],
      waterLog: const {},
      waterGoal: 8,
    );
    expect(ok, false);
    expect(SyncStatusService.instance.backendUnreachable, false);
  });

  test(
    'syncAllMeals and backupAll complete without throwing as guest',
    () async {
      await MealSyncService.syncAllMeals([meal]);
      final backedUp = await MealSyncService.backupAll(
        meals: [meal],
        habitsJson: const [],
        waterLog: const {},
        waterGoal: 8,
      );
      expect(backedUp, false);
      expect(SyncStatusService.instance.backendUnreachable, false);
    },
  );
}
