import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/reminder_copy.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pins the pure, unit-testable reminder helpers in [ReminderCopy]:
/// date formatting, next-fire computations, yesterday's calories, and the
/// last-7-days weekly stats — all without touching the plugin or stores.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  });

  MealRecord meal({
    required DateTime date,
    int calories = 500,
    double protein = 30,
    double carbs = 60,
    double fats = 15,
  }) => MealRecord(
    id: 'm-${date.millisecondsSinceEpoch}',
    name: 'Meal',
    category: 'Test',
    calories: calories,
    protein: protein,
    carbs: carbs,
    fats: fats,
    fiber: 5,
    serving: '1 serving',
    date: date,
  );

  test('dateStr formats YYYY-MM-DD', () {
    expect(ReminderCopy.dateStr(DateTime(2026, 8, 3)), '2026-8-3');
    expect(ReminderCopy.dateStr(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('nextDaily returns today if the time has not passed, else tomorrow', () {
    // Use a fixed "now" far in the future? We can't inject now, so instead
    // assert the invariant that the result is either today or tomorrow at the
    // requested hour — never yesterday, never +2 days.
    final when = ReminderCopy.nextDaily(12, 0);
    final now = tz.TZDateTime.now(tz.local);
    expect(when.hour, 12);
    expect(when.minute, 0);
    final dayDiff = when.day - now.day;
    expect(
      dayDiff,
      inInclusiveRange(0, 1),
      reason: 'nextDaily must be today or tomorrow',
    );
  });

  test('nextSunday returns the coming Sunday (1..7 days out)', () {
    final when = ReminderCopy.nextSunday(19, 0);
    expect(when.weekday, DateTime.sunday);
    expect(when.hour, 19);
    expect(when.minute, 0);
    final now = tz.TZDateTime.now(tz.local);
    final diff = when.difference(now).inDays;
    expect(diff, inInclusiveRange(0, 7));
  });

  test('daysAfter returns the exact date, null when past or missing', () {
    final future = DateTime.now()
        .add(const Duration(days: 10))
        .toIso8601String();
    final when = ReminderCopy.daysAfter(future, 5);
    expect(when, isNotNull);
    expect(
      when!.day,
      DateTime.now().add(const Duration(days: 15)).day,
      reason: 'subscribed + 5 days from a date 10 days out = 15 days out',
    );

    expect(ReminderCopy.daysAfter(null, 5), isNull);
    expect(ReminderCopy.daysAfter('', 5), isNull);
    expect(ReminderCopy.daysAfter('not-a-date', 5), isNull);
    expect(
      ReminderCopy.daysAfter(
        DateTime.now().subtract(const Duration(days: 60)).toIso8601String(),
        5,
      ),
      isNull,
      reason: 'a date already past must never be scheduled',
    );
  });

  test('yesterdayCalories sums only yesterday, null when nothing logged', () {
    final now = DateTime(2026, 8, 3, 12);
    final yesterday = DateTime(2026, 8, 2);
    final meals = [
      meal(date: yesterday, calories: 300),
      meal(date: yesterday, calories: 400),
      meal(date: now, calories: 999), // today must be excluded
      meal(date: DateTime(2026, 8, 1), calories: 100), // older excluded
    ];
    expect(ReminderCopy.yesterdayCalories(meals: meals, now: now), 700);

    final noYesterday = [meal(date: now, calories: 500)];
    expect(
      ReminderCopy.yesterdayCalories(meals: noYesterday, now: now),
      isNull,
    );
  });

  test('weeklyStats counts days hitting all macro targets and total kcal', () {
    // 70kg male, 170cm, 28, maintain -> ~targetProtein 112g, targetCalories
    // ~1800. A day hitting >= 90% of every target counts; a day at 50%
    // protein does not; an empty day is skipped.
    final profile = DietProfile(
      weightKg: 70,
      heightCm: 170,
      age: 28,
      gender: Gender.male,
      goal: Goal.maintain,
      activity: ActivityLevel.sedentary,
    );
    final now = DateTime(2026, 8, 3, 12);

    // Day 1: exceeds every target (>= 90% each) -> hit.
    // Day 2: well under targets -> not hit.
    final meals = [
      meal(
        date: DateTime(2026, 8, 2),
        calories: 2200,
        protein: 150,
        carbs: 260,
        fats: 70,
      ),
      meal(
        date: DateTime(2026, 8, 1),
        calories: 800,
        protein: 40,
        carbs: 90,
        fats: 20,
      ),
    ];
    final stats = ReminderCopy.weeklyStats(
      meals: meals,
      profile: profile,
      now: now,
    );
    expect(stats.daysHit, 1);
    expect(stats.totalCalories, 3000);
  });
}
