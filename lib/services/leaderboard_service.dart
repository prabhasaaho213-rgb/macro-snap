import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';
import 'habit_store.dart';
import 'meal_store.dart';
import 'step_goal_service.dart';
import 'weight_store.dart';

/// The fitness points a user earns for using MacroSnap itself.
///
/// One place decides what an action is worth, how often it can pay, and what
/// the daily ceiling is — so a new activity can never award points through two
/// different code paths and no screen has to know the numbers.
///
/// Rules, in one sentence each:
///   * a meal pays once per meal id, capped at 3 meals a day
///   * a habit pays once per habit per day, capped at 3 habits a day
///   * water pays 1 point per logged glass (max 5) plus 5 for reaching the goal
///   * reaching the daily step goal pays 20, once
///   * a real weigh-in pays 5, once a day
///   * meeting the calorie tracking goal pays 10, once a day
///
/// Nothing pays twice for the same action: every award carries a key (the meal
/// id, `habit_<id>_<date>`, `steps_<date>`) and a key that has already paid is
/// rejected. That is what stops "delete and re-add the same meal" or
/// "uncheck and re-check a habit" from farming points.
///
/// Steps are the figure the app's own dashboard shows — including the steps
/// Health Connect reports, since that is the number the user sees and the one
/// they asked to be counted. They are typed in nowhere: the value is written by
/// [noteSteps] from the Health Connect read, so a hand-entered total cannot
/// exist.
class LeaderboardService extends ChangeNotifier {
  LeaderboardService._();
  static final LeaderboardService instance = LeaderboardService._();

  // ─── Scoring table ────────────────────────────────────────────────
  // Starting values from the product spec. Every one is a cap as well as a
  // value: the same action repeated past its cap earns nothing.
  static const int mealPoints = 10;
  static const int mealDailyCap = 30;

  static const int habitPoints = 5;
  static const int habitDailyCap = 15;

  static const int waterPoints = 1;
  static const int waterDailyCap = 5;

  static const int waterGoalBonus = 5;
  /// Entries (5) + goal bonus (5).
  static const int hydrationDailyCap = 10;

  static const int stepGoalPoints = 20;
  static const int stepGoalDailyCap = 20;

  static const int weighInPoints = 5;

  static const int calorieGoalPoints = 10;
  /// Meals (30) + the calorie-goal bonus (10).
  static const int nutritionDailyCap = 40;

  /// The most a user can bank in one day with today's table (90).
  static const int dailyMax =
      mealDailyCap + habitDailyCap + hydrationDailyCap + stepGoalDailyCap +
      weighInPoints + calorieGoalPoints;

  // ─── Preferences keys ─────────────────────────────────────────────
  static const String _daysKey = 'leaderboard_days_v1';
  static const String _stepsDayKey = 'leaderboard_steps_day';
  static const String _stepsValueKey = 'leaderboard_steps_value';

  /// How much history is kept. A season/quarter is plenty for "this week"
  /// plus a few weeks of context, and it keeps the stored JSON tiny.
  static const int keepDays = 35;

  final Map<String, DayPoints> _days = {};
  bool _loaded = false;
  bool _attached = false;

  /// Steps the health dashboard last read today, in the app's own words.
  int _stepsToday = 0;
  String? _stepsDay;

  bool get loaded => _loaded;

  /// Points banked today.
  int get todayPoints => _day(_dayKey(DateTime.now())).total;

  /// Points banked this week, Monday to Sunday.
  int get weekPoints {
    final start = _weekStart(DateTime.now());
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += _day(_dayKey(start.add(Duration(days: i)))).total;
    }
    return sum;
  }

  /// Consecutive days (ending today or yesterday) with any points at all.
  int get activeStreak {
    var streak = 0;
    var cursor = DateTime.now();
    if (_day(_dayKey(cursor)).total == 0) {
      // Today may simply not have started yet; the streak is still alive if
      // yesterday banked something.
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (_day(_dayKey(cursor)).total > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The points for one day, for the week strip.
  DayPoints dayPoints(DateTime day) => _day(_dayKey(day));

  /// Monday..Sunday of the current week, oldest first.
  List<({DateTime date, DayPoints points})> get currentWeek {
    final start = _weekStart(DateTime.now());
    return [
      for (var i = 0; i < 7; i++)
        (
          date: start.add(Duration(days: i)),
          points: _day(_dayKey(start.add(Duration(days: i)))),
        ),
    ];
  }

  int get stepsToday => _stepsToday;

  // ─── Loading and persistence ──────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_daysKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map && data['days'] is Map) {
          (data['days'] as Map).forEach((key, value) {
            if (value is Map) {
              _days[key as String] = DayPoints.fromJson(
                Map<String, dynamic>.from(value),
              );
            }
          });
        }
      }
      _stepsDay = prefs.getString(_stepsDayKey);
      _stepsToday = prefs.getInt(_stepsValueKey) ?? 0;
      if (_stepsDay != _dayKey(DateTime.now())) {
        // Yesterday's step total must not count toward today's goal.
        _stepsToday = 0;
        _stepsDay = null;
      }
      _prune();
    } catch (e, st) {
      logError('LeaderboardService.load', e, st);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Registers the store listeners once, so a meal logged anywhere (scan,
  /// barcode, manual, recent foods) scores without every call site knowing the
  /// leaderboard exists.
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    await load();
    MealStore.instance.changeNotifier.addListener(_onStoreChanged);
    HabitStore.instance.addListener(_onStoreChanged);
    WeightStore.instance.addListener(_onStoreChanged);
    await sync();
  }

  void _onStoreChanged() {
    unawaited(sync());
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _daysKey,
        jsonEncode({
          'days': {
            for (final entry in _days.entries) entry.key: entry.value.toJson(),
          },
        }),
      );
    } catch (e, st) {
      logError('LeaderboardService._save', e, st);
    }
  }

  void _prune() {
    if (_days.length <= keepDays) return;
    final cutoff = _dayKey(
      DateTime.now().subtract(const Duration(days: keepDays)),
    );
    _days.removeWhere((key, _) => key.compareTo(cutoff) < 0);
  }

  // ─── Scoring ──────────────────────────────────────────────────────

  /// Re-reads today from the stores and awards anything not yet paid.
  ///
  /// Safe to call as often as wanted: every award is keyed and idempotent, and
  /// a run that changes nothing writes nothing.
  Future<void> sync() async {
    await load();
    // The step target lives in its own store; without this a launch that never
    // opened the Health tab would score against the 10,000 default instead of
    // the target the user actually chose.
    await StepGoalService.instance.load();
    final today = _dayKey(DateTime.now());
    var changed = false;

    // Meals — every logged meal id pays once, capped at three a day.
    for (final meal in MealStore.instance.todayMeals) {
      changed |= _award(
        today,
        'meal_${meal.id}',
        PointsBucket.nutrition,
        mealPoints,
        mealDailyCap,
      );
    }

    // Habits — one completion per habit per day, capped at three.
    for (final habit in HabitStore.instance.todayHabits) {
      if (!habit.isCompleted(DateTime.now())) continue;
      changed |= _award(
        today,
        'habit_${habit.id}_$today',
        PointsBucket.habits,
        habitPoints,
        habitDailyCap,
      );
    }

    // Water — one point per glass up to five, plus the goal bonus.
    final glasses = HabitStore.instance.waterToday;
    final goal = HabitStore.instance.waterGoal;
    for (var i = 1; i <= glasses && i <= waterDailyCap; i++) {
      changed |= _award(
        today,
        'water_${i}_$today',
        PointsBucket.hydration,
        waterPoints,
        waterDailyCap,
      );
    }
    if (goal > 0 && glasses >= goal) {
      changed |= _award(
        today,
        'waterGoal_$today',
        PointsBucket.hydration,
        waterGoalBonus,
        hydrationDailyCap,
      );
    }

    // Steps — the goal pays once, and only for a count the health dashboard
    // actually read (see [noteSteps]).
    final stepGoal = StepGoalService.instance.goal;
    if (_stepsDay == today && _stepsToday >= stepGoal) {
      changed |= _award(
        today,
        'steps_$today',
        PointsBucket.movement,
        stepGoalPoints,
        stepGoalDailyCap,
      );
    }

    // Weigh-in — a real reading (not a value seeded from the profile) pays
    // once a day. Losing weight pays nothing extra.
    final weighedToday = WeightStore.instance.entries.any(
      (e) => !e.seeded && _sameDay(e.date, DateTime.now()),
    );
    if (weighedToday) {
      changed |= _award(
        today,
        'weighIn_$today',
        PointsBucket.body,
        weighInPoints,
        weighInPoints,
      );
    }

    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Records today's step total as the health dashboard read it.
  ///
  /// Deliberately not user-enterable: the only caller is the Health Connect
  /// read, which is the figure the dashboard shows.
  Future<void> noteSteps(int steps) async {
    await load();
    final today = _dayKey(DateTime.now());
    if (_stepsDay == today && _stepsToday == steps) return;
    _stepsDay = today;
    _stepsToday = steps;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stepsDayKey, today);
      await prefs.setInt(_stepsValueKey, steps);
    } catch (e, st) {
      logError('LeaderboardService.noteSteps', e, st);
    }
    await sync();
  }

  /// Called when the daily calorie tracking goal is met (Home already detects
  /// this for the calorie-goal streak, so this rides on that one event rather
  /// than re-deriving it).
  Future<void> noteCalorieGoalMet() async {
    await load();
    final today = _dayKey(DateTime.now());
    final changed = _award(
      today,
      'calorieGoal_$today',
      PointsBucket.nutrition,
      calorieGoalPoints,
      nutritionDailyCap,
    );
    if (changed) {
      await _save();
      notifyListeners();
    }
  }

  /// Awards [points] under [key] unless the key already paid or the bucket is
  /// at its cap. Returns whether anything changed.
  bool _award(
    String day,
    String key,
    PointsBucket bucket,
    int points,
    int cap,
  ) {
    final score = _day(day);
    if (score.earnedKeys.contains(key)) return false;
    final current = score.bucket(bucket);
    if (current + points > cap) return false;
    score.add(bucket, points);
    score.earnedKeys.add(key);
    return true;
  }

  DayPoints _day(String key) => _days.putIfAbsent(key, DayPoints.new);

  // ─── Date helpers ─────────────────────────────────────────────────

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _weekStart(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - 1));
  }
}

/// The five kinds of activity a day's points are split into.
enum PointsBucket { movement, nutrition, habits, hydration, body }

/// One day of points, split by bucket, plus the award keys already paid.
///
/// The keys are what make scoring idempotent across restarts: a meal that was
/// scored yesterday morning still cannot be scored again this evening.
class DayPoints {
  int movement = 0;
  int nutrition = 0;
  int habits = 0;
  int hydration = 0;
  int body = 0;
  final Set<String> earnedKeys = {};

  int get total => movement + nutrition + habits + hydration + body;

  bool get isEmpty => total == 0;

  int bucket(PointsBucket bucket) => switch (bucket) {
    PointsBucket.movement => movement,
    PointsBucket.nutrition => nutrition,
    PointsBucket.habits => habits,
    PointsBucket.hydration => hydration,
    PointsBucket.body => body,
  };

  void add(PointsBucket bucket, int points) {
    switch (bucket) {
      case PointsBucket.movement:
        movement += points;
      case PointsBucket.nutrition:
        nutrition += points;
      case PointsBucket.habits:
        habits += points;
      case PointsBucket.hydration:
        hydration += points;
      case PointsBucket.body:
        body += points;
    }
  }

  Map<String, dynamic> toJson() => {
    if (movement > 0) 'm': movement,
    if (nutrition > 0) 'n': nutrition,
    if (habits > 0) 'h': habits,
    if (hydration > 0) 'w': hydration,
    if (body > 0) 'b': body,
    if (earnedKeys.isNotEmpty) 'k': earnedKeys.toList(),
  };

  static DayPoints fromJson(Map<String, dynamic> json) {
    final day = DayPoints();
    day.movement = (json['m'] as num?)?.toInt() ?? 0;
    day.nutrition = (json['n'] as num?)?.toInt() ?? 0;
    day.habits = (json['h'] as num?)?.toInt() ?? 0;
    day.hydration = (json['w'] as num?)?.toInt() ?? 0;
    day.body = (json['b'] as num?)?.toInt() ?? 0;
    final keys = json['k'];
    if (keys is List) {
      day.earnedKeys.addAll(keys.whereType<String>());
    }
    return day;
  }
}
