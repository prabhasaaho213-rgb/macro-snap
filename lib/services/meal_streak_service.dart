import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/badge_service.dart';
import '../services/meal_store.dart';
import '../models/diet_profile.dart';

/// What happened when the meal streak was checked/updated.
enum StreakCheck { none, continued, zenkaiBoost }

/// Outcome of [MealStreakService.checkAndUpdate]. [brokenStreak] carries the
/// length of the streak that was lost — only meaningful for
/// [StreakCheck.zenkaiBoost].
class StreakUpdateResult {
  final StreakCheck status;
  final int brokenStreak;

  const StreakUpdateResult(this.status, {this.brokenStreak = 0});

  static const none = StreakUpdateResult(StreakCheck.none);
  static const continued = StreakUpdateResult(StreakCheck.continued);
}

/// Tracks the user's meal-logging streak — consecutive days where ALL
/// macro targets are hit (>= 90% of protein, carbs, and fats).
///
/// This is **separate from Habit.currentStreak** which tracks individual
/// habit completion streaks. MealStreakService = "macro target streak",
/// while Habit.currentStreak = "habit completion streak".
class MealStreakService {
  static const _keyStreak = 'current_streak';
  static const _keyBest = 'best_streak';
  static const _keyDate = 'last_streak_date';

  /// A streak at least this long is "long" enough to be a Zenkai Boost
  /// when it's broken and the user comes back.
  static const zenkaiThreshold = 3;

  static String _dateStr(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Pure streak math (unit-tested). Given the last logged date, the current
  /// streak and today, decides the new streak — and whether today is a
  /// **Zenkai Boost**: the user broke a [zenkaiThreshold]+ day streak and is
  /// starting a fresh one (coming back stronger).
  static ({int newStreak, int brokenStreak, bool zenkai}) computeStreakUpdate({
    required String lastDate,
    required int current,
    required DateTime today,
  }) {
    final todayStr = _dateStr(today);
    final yesterdayStr = _dateStr(
      DateTime(today.year, today.month, today.day - 1),
    );
    if (lastDate == todayStr) {
      return (newStreak: current, brokenStreak: 0, zenkai: false);
    }
    if (lastDate == yesterdayStr) {
      return (newStreak: current + 1, brokenStreak: 0, zenkai: false);
    }
    // A gap of a day or more: the previous streak (if 3+ days) counts as
    // "broken", and coming back today is the Zenkai Boost moment.
    final broken = current >= zenkaiThreshold ? current : 0;
    return (
      newStreak: 1,
      brokenStreak: broken,
      zenkai: broken >= zenkaiThreshold,
    );
  }

  static Future<int> getCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyStreak) ?? 0;
  }

  static Future<int> getBest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBest) ?? 0;
  }

  static Future<StreakUpdateResult> checkAndUpdate() async {
    // Streak = consecutive days where ALL macro targets are hit (>= 90% each)
    if (!checkAllTargetsHit()) return StreakUpdateResult.none;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = _dateStr(today);
    final lastDate = prefs.getString(_keyDate) ?? '';
    final current = prefs.getInt(_keyStreak) ?? 0;

    if (lastDate == todayStr) return StreakUpdateResult.none;

    final update = computeStreakUpdate(
      lastDate: lastDate,
      current: current,
      today: today,
    );

    await prefs.setInt(_keyStreak, update.newStreak);
    await prefs.setString(_keyDate, todayStr);

    final best = prefs.getInt(_keyBest) ?? 0;
    if (update.newStreak > best) {
      await prefs.setInt(_keyBest, update.newStreak);
    }

    // Streak badges reward persistence, not the body: 7 and 14 days of
    // hitting targets earn Week Warrior / Fortnight Flame.
    unawaited(BadgeService.instance.noteStreak(update.newStreak));

    // Fires exactly once per break: the date was just written to today, so
    // any later call the same day returns early above.
    if (update.zenkai) {
      return StreakUpdateResult(
        StreakCheck.zenkaiBoost,
        brokenStreak: update.brokenStreak,
      );
    }
    return StreakUpdateResult.continued;
  }

  static bool isLongestStreak(int current, int best) {
    return current >= best && current > 0;
  }

  /// Check if ALL macro targets are hit today (>= 90% of each target)
  static bool checkAllTargetsHit() {
    final profile = DietPlanService.instance.profile;
    final p = MealStore.instance.todayProtein;
    final c = MealStore.instance.todayCarbs;
    final f = MealStore.instance.todayFats;
    final targetP = profile?.targetProtein ?? 150;
    final targetC = profile?.targetCarbs ?? 300;
    final targetF = profile?.targetFats ?? 67;
    return p >= targetP * 0.9 && c >= targetC * 0.9 && f >= targetF * 0.9;
  }
}
