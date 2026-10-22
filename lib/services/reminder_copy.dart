import 'package:timezone/timezone.dart' as tz;
import '../models/diet_profile.dart';
import '../models/meal_record.dart';
import 'meal_streak_service.dart';

/// Pure, unit-testable helpers for reminder scheduling and copy. Everything
/// here is free of plugin/singleton state so it can be tested in isolation;
/// the registry wires these to the real stores.
class ReminderCopy {
  ReminderCopy._();

  static String dateStr(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// The next occurrence of [hour]:[minute] today (or tomorrow if past).
  static tz.TZDateTime nextDaily(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  /// The next Sunday at [hour]:[minute] (or the following week if past).
  static tz.TZDateTime nextSunday(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    final daysUntilSunday = 7 - now.weekday;
    var sunday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysUntilSunday,
      hour,
      minute,
    );
    if (sunday.isBefore(now)) sunday = sunday.add(const Duration(days: 7));
    return sunday;
  }

  /// `subscribedDate + days` as a tz instant; null if the date is already
  /// past or the subscription date is missing/invalid.
  static tz.TZDateTime? daysAfter(String? subscribedDate, int days) {
    if (subscribedDate == null || subscribedDate.isEmpty) return null;
    try {
      final start = DateTime.parse(subscribedDate);
      final when = start.add(Duration(days: days));
      if (when.isBefore(DateTime.now())) return null;
      return tz.TZDateTime.from(when, tz.local);
    } catch (_) {
      return null;
    }
  }

  /// Total calories logged on the calendar day before [now], from [meals],
  /// or null when nothing was logged that day. Pure — no store access.
  static int? yesterdayCalories({
    required List<MealRecord> meals,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    var total = 0;
    for (final m in meals) {
      if (m.date.year == yesterday.year &&
          m.date.month == yesterday.month &&
          m.date.day == yesterday.day) {
        total += m.calories;
      }
    }
    return total > 0 ? total : null;
  }

  /// Current meal streak, or 0 when unknown. Never throws.
  static Future<int> currentStreak() async {
    try {
      return await MealStreakService.getCurrent();
    } catch (_) {
      return 0;
    }
  }

  /// Pure last-7-days stats from [meals] against [profile]: how many of the
  /// last 7 days hit every macro target (>= 90% each) and total calories.
  static ({int daysHit, int totalCalories}) weeklyStats({
    required List<MealRecord> meals,
    required DietProfile profile,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    var daysHit = 0;
    var totalCalories = 0;
    for (var i = 0; i < 7; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      final dayMeals = meals
          .where(
            (m) =>
                m.date.year == day.year &&
                m.date.month == day.month &&
                m.date.day == day.day,
          )
          .toList();
      if (dayMeals.isEmpty) continue;
      final protein = dayMeals.fold(0.0, (s, m) => s + m.protein);
      final carbs = dayMeals.fold(0.0, (s, m) => s + m.carbs);
      final fats = dayMeals.fold(0.0, (s, m) => s + m.fats);
      final calories = dayMeals.fold(0, (s, m) => s + m.calories);
      totalCalories += calories;
      if (protein >= profile.targetProtein * 0.9 &&
          carbs >= profile.targetCarbs * 0.9 &&
          fats >= profile.targetFats * 0.9) {
        daysHit++;
      }
    }
    return (daysHit: daysHit, totalCalories: totalCalories);
  }
}
