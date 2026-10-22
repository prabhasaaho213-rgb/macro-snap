import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/share_service.dart';

/// The numbers on the weekly share card: average calories per *logged* day,
/// protein goal hits by the same 90% rule the streak uses, and the window
/// edge (today and the six days before it).
void main() {
  MealRecord meal(DateTime day, {int calories = 0, double protein = 0}) =>
      MealRecord(
        id: '${day.millisecondsSinceEpoch}-$calories',
        date: day,
        name: 'Test meal',
        category: 'lunch',
        calories: calories,
        protein: protein,
        carbs: 0,
        fats: 0,
        fiber: 0,
        serving: '1 serving',
      );

  final now = DateTime(2026, 10, 21, 14); // fixed "today" for determinism

  test('no meals in the window → hasData is false (nothing to share)', () {
    final s = ShareService.computeWeekly(
      meals: [],
      streakDays: 0,
      proteinTarget: 150,
      now: now,
    );
    expect(s.hasData, isFalse);
    expect(s.daysLogged, 0);
    expect(s.avgCalories, 0);
    expect(s.proteinHitDays, 0);
  });

  test('average is per logged day, not per calendar day', () {
    final meals = [
      // Day 1: two meals, 600 total. Day 2: one meal, 400. Nothing else.
      meal(now.subtract(const Duration(days: 3)), calories: 400),
      meal(now.subtract(const Duration(days: 3)), calories: 200),
      meal(now.subtract(const Duration(days: 2)), calories: 400),
    ];
    final s = ShareService.computeWeekly(
      meals: meals,
      streakDays: 2,
      proteinTarget: 100,
      now: now,
    );
    expect(s.daysLogged, 2);
    // 1000 kcal over 2 logged days = 500 — not 1000/7 ≈ 143.
    expect(s.avgCalories, closeTo(500, 0.001));
    expect(s.hasData, isTrue);
  });

  test('meals older than the 7-day window are excluded', () {
    final meals = [
      meal(now.subtract(const Duration(days: 8)), calories: 900),
      meal(now.subtract(const Duration(days: 6)), calories: 500),
    ];
    final s = ShareService.computeWeekly(
      meals: meals,
      streakDays: 0,
      proteinTarget: 100,
      now: now,
    );
    expect(s.daysLogged, 1);
    expect(s.avgCalories, closeTo(500, 0.001));
  });

  test('tomorrow (a clock skew meal) never counts toward this week', () {
    final meals = [meal(now.add(const Duration(days: 1)), calories: 700)];
    final s = ShareService.computeWeekly(
      meals: meals,
      streakDays: 0,
      proteinTarget: 100,
      now: now,
    );
    expect(s.hasData, isFalse);
  });

  test('protein hit uses the streak\'s own 90% rule', () {
    final meals = [
      // 95 g of a 100 g target → hit.
      meal(now.subtract(const Duration(days: 1)), protein: 95),
      // 89 g → below 90%, not a hit.
      meal(now, protein: 89),
      // Two meals summing to 92 g on one day → hit (per day, not per meal).
      meal(now.subtract(const Duration(days: 2)), protein: 40),
      meal(now.subtract(const Duration(days: 2)), protein: 52),
    ];
    final s = ShareService.computeWeekly(
      meals: meals,
      streakDays: 0,
      proteinTarget: 100,
      now: now,
    );
    expect(s.proteinHitDays, 2);
  });

  test('date range spans the window, one month', () {
    final s = ShareService.computeWeekly(
      meals: [meal(now)],
      streakDays: 1,
      proteinTarget: 100,
      now: now,
    );
    expect(s.dateRange(now), '15–21 Oct');
  });

  test('date range crosses a month boundary', () {
    final marchNow = DateTime(2026, 3, 2);
    final s = ShareService.computeWeekly(
      meals: [meal(marchNow)],
      streakDays: 1,
      proteinTarget: 100,
      now: marchNow,
    );
    expect(s.dateRange(marchNow), '24 Feb–2 Mar');
  });

  test('share text names the streak and the protein hits', () {
    final s = ShareService.computeWeekly(
      meals: [meal(now, calories: 2000, protein: 140)],
      streakDays: 5,
      proteinTarget: 150,
      now: now,
    );
    final text = ShareService.weekSummaryText(s);
    expect(text, contains('1/7 days logged'));
    expect(text, contains('Streak: 5 days'));
    expect(text, contains('2000 kcal/day'));
    expect(text, contains('Protein goal hit: 1/7 days'));
    expect(text, contains('play.google.com'));
  });
}
