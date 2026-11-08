import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/habit.dart';
import '../services/badge_service.dart';

/// Tracks the user's calorie-goal streak — consecutive days where the daily
/// calorie goal was met.
///
/// It works exactly like a habit's daily streak ([Habit.currentStreak]):
/// every day the goal is hit banks that day as a date marker, and the streak
/// is the run of consecutive banked days ending today (or yesterday, on a
/// morning before today's goal has been met yet). One met day can never be
/// "un-banked" by a later edit or delete, just like a habit completion.
class MealStreakService {
  /// Every dateKey (yyyy-MM-dd) the calorie goal was met, sorted ascending.
  static const _keyDates = 'calorie_goal_hit_dates';

  /// Legacy keys from the previous streak model (a counter + one date,
  /// fed by an all-macros rule that no mentor ever updated). Read once for
  /// backward-compatible seeding so a user's existing streak survives the
  /// model change, then removed.
  static const _keyLegacyStreak = 'current_streak';
  static const _keyLegacyDate = 'last_streak_date';

  static List<String> _hitDates = [];
  static bool _loaded = false;
  static Future<void>? _loadFuture;

  static bool get isLoaded => _loaded;

  /// Reads the banked dates once per process. Legacy counter + date are
  /// converted by replaying the old streak back from its last date, so an
  /// updating user keeps their number.
  static Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _loadOnce();
  }

  static Future<void> _loadOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dates = <String>{};

      // Migration first: seed the date set from the legacy streak so the
      // user's banked days carry over across the model change.
      final legacyStreak = prefs.getInt(_keyLegacyStreak) ?? 0;
      final legacyDateRaw = prefs.getString(_keyLegacyDate) ?? '';
      final legacyDate = DateTime.tryParse(legacyDateRaw);
      if (legacyStreak > 0 && legacyDate != null) {
        for (var i = 0; i < legacyStreak; i++) {
          dates.add(dateKey(legacyDate.subtract(Duration(days: i))));
        }
      }

      // Defensive parse: a corrupt entry is dropped, corrupt storage resets
      // to the migration-seeded set — never crashes a screen that reads the
      // streak on every rebuild.
      final raw = prefs.getString(_keyDates) ?? '';
      for (final entry in jsonList(raw)) {
        if (DateTime.tryParse(entry) != null) dates.add(entry);
      }

      _hitDates = dates.toList()..sort();

      if (prefs.containsKey(_keyDates) || dates.isNotEmpty) {
        // Persist the (possibly migration-seeded + cleaned) set once, and
        // drop the legacy keys so they can only seed a single time.
        await prefs.setString(_keyDates, _hitDates.join(','));
      }
      await prefs.remove(_keyLegacyStreak);
      await prefs.remove(_keyLegacyDate);
    } catch (_) {
      _hitDates = [];
    }
    _loaded = true;
  }

  /// Parses the stored comma list — parsed manually so a malformed entry is
  /// dropped instead of throwing out of the whole read.
  static List<String> jsonList(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// Caches the in-memory set so [noteGoalHitToday] called from every Home
  /// rebuild after a goal is met is a membership check, not an I/O round-trip.
  static bool _todayHit({DateTime? now}) {
    return _hitDates.contains(dateKey(now ?? DateTime.now()));
  }

  /// Banks today when the calorie goal is met. Idempotent per day — a later
  /// rebuild, re-open or a second "Log This Meal" never double-counts.
  ///
  /// The caller decides whether the goal is actually met today; this only
  /// owns the storage and the side effects (best streak, badges).
  static Future<int> noteGoalHitToday() async {
    await load();
    final today = dateKey(DateTime.now());
    if (_hitDates.contains(today)) return computeCurrentStreak();
    _hitDates..add(today)..sort();
    final streak = computeCurrentStreak();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDates, _hitDates.join(','));
      // Streak badges reward persistence: 7 and 14 banked days earn
      // Week Warrior / Fortnight Flame.
      await BadgeService.instance.noteStreak(streak);
    } catch (_) {
      // Storage failure must not stop the streak from being appended.
    }
    return streak;
  }

  /// The current streak: consecutive banked days ending today when today is
  /// already banked, otherwise ending yesterday (the goal is still pending
  /// today, like a habit due-but-not-completed).
  static int computeCurrentStreak([DateTime? now]) => computeCurrentStreakFor(
    hitDates: _hitDates,
    today: now ?? DateTime.now(),
  );

  /// Pure — pinned by tests.
  static int computeCurrentStreakFor({
    required List<String> hitDates,
    required DateTime today,
  }) {
    final hits = hitDates.toSet();
    var day = DateTime(today.year, today.month, today.day);
    if (!hits.contains(dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (hits.contains(dateKey(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// Pure — pinned by tests. The longest run of consecutive banked days.
  static int computeBestStreakFor({required List<String> hitDates}) {
    final hits = hitDates.toSet();
    final days = hits.map(DateTime.tryParse).whereType<DateTime>().toList();
    if (days.isEmpty) return 0;
    days.sort();

    var run = 0;
    var best = 0;
    var cursor = DateTime(days.first.year, days.first.month, days.first.day);
    final end = DateTime(days.last.year, days.last.month, days.last.day);
    while (!cursor.isAfter(end)) {
      if (hits.contains(dateKey(cursor))) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return best;
  }

  /// Current streak, async for callers that may race the one-time load.
  static Future<int> getCurrent() async {
    await load();
    return computeCurrentStreak();
  }

  /// Longest streak on record, recomputed from the banked days (self-healing:
  /// no persisted best to go stale).
  static Future<int> getBest() async {
    await load();
    return computeBestStreakFor(hitDates: _hitDates);
  }

  /// Whether today's goal has already been banked — cheap, non-async check
  /// for rebuild paths (must be used after [load] has run, which any Home
  /// build that logs a meal has).
  static bool isGoalHitToday() => _loaded && _todayHit();

  /// Whether the current streak is the record. Kept for the share card.
  static bool isLongestStreak(int current, int best) {
    return current >= best && current > 0;
  }

  /// Test hook: forget everything loaded so the next call re-reads prefs.
  @visibleForTesting
  static void resetForTest() {
    _hitDates = [];
    _loaded = false;
    _loadFuture = null;
  }
}
