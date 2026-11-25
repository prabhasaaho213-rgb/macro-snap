import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';
import 'habit_store.dart';
import 'meal_store.dart';
import 'step_counter_service.dart';
import 'step_goal_service.dart';
import 'step_limit.dart';
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
///   * movement pays 10 for every complete 5,000 steps, capped at 100
///   * a real weigh-in pays 5, once a day
///   * meeting the calorie tracking goal pays 10, once a day
///
/// Nothing pays twice for the same action: every award carries a key (the meal
/// id, `habit_<id>_<date>`, `steps_<date>`) and a key that has already paid is
/// rejected. That is what stops "delete and re-add the same meal" or
/// "uncheck and re-check a habit" from farming points.
///
/// Steps are the figure the app's own dashboard shows, from the phone's own
/// step sensor first and Health Connect second (see StepCounterService). They
/// are typed in nowhere: [noteSteps] is the only writer. Each day's total is
/// also kept in [_stepDays] so the whole week can be sent to the server on
/// sync — that is what makes yesterday's movement points survive a reinstall,
/// which the old "today only" value could not.
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

  /// Movement is paid per distance walked, not for crossing one target:
  /// every complete 5,000 steps is 10 points. 50,000 steps (the cap) is 100.
  static const int stepsPerAward = 5000;
  static const int stepAward = 10;
  static const int movementDailyCap = 100;

  static const int weighInPoints = 5;

  static const int calorieGoalPoints = 10;
  /// Meals (30) + the calorie-goal bonus (10).
  static const int nutritionDailyCap = 40;

  /// Movement points for a day's step total: 10 for every complete 5,000
  /// steps, capped at [movementDailyCap]. The single definition of the rule —
  /// [sync] awards with it and the server's `leaderboard.js` mirrors it.
  static int movementPointsFor(int steps) {
    if (steps <= 0) return 0;
    final points = (steps ~/ stepsPerAward) * stepAward;
    return points > movementDailyCap ? movementDailyCap : points;
  }

  /// The most a user can bank in one day with today's table (170).
  static const int dailyMax =
      mealDailyCap + habitDailyCap + hydrationDailyCap + movementDailyCap +
      weighInPoints + calorieGoalPoints;

  // ─── Preferences keys ─────────────────────────────────────────────
  static const String _daysKey = 'leaderboard_days_v1';
  static const String _stepsDayKey = 'leaderboard_steps_day';
  static const String _stepsValueKey = 'leaderboard_steps_value';
  static const String _stepsDaysKey = 'leaderboard_steps_days_v1';
  static const String _optInKey = 'leaderboard_opt_in';
  static const String _statePrefKey = 'leaderboard_state_key';
  static const String _districtPrefKey = 'leaderboard_district';

  /// How much history is kept. A season/quarter is plenty for "this week"
  /// plus a few weeks of context, and it keeps the stored JSON tiny.
  static const int keepDays = 35;

  final Map<String, DayPoints> _days = {};
  bool _loaded = false;
  bool _attached = false;

  /// Steps the health dashboard last read today, in the app's own words.
  int _stepsToday = 0;
  String? _stepsDay;

  /// Day key -> step total, for the whole week. This is the history the server
  /// needs to score every day of the week, not just the day the app is open.
  final Map<String, int> _stepDays = {};

  /// Server-scored points for the current week, when a sync has answered. They
  /// are displayed INSTEAD of the local estimate: the board shows the server's
  /// number, so the page and the ranking cannot disagree, and a reinstall gets
  /// yesterday's points back from the server rather than starting at today.
  final Map<String, DayPoints> _serverDays = {};
  String? _serverWeek;

  /// Public leaderboard identity. Off by default: joining puts the user's
  /// name and weekly score on a board other accounts can read, so it is the
  /// user's decision, not a side effect of logging a meal.
  bool _optIn = false;
  String? _stateKey;
  String? _district;

  bool get optIn => _optIn;
  String? get stateKey => _stateKey;
  String? get district => _district;

  /// True when there is enough profile to place the user on a board.
  bool get hasLocation =>
      (_stateKey?.isNotEmpty ?? false) && (_district?.isNotEmpty ?? false);

  bool get loaded => _loaded;

  /// Points banked today.
  int get todayPoints => _visible(_dayKey(DateTime.now())).total;

  /// Points banked this week, Monday to Sunday.
  int get weekPoints {
    final start = _weekStart(DateTime.now());
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += _visible(_dayKey(start.add(Duration(days: i)))).total;
    }
    return sum;
  }

  /// Consecutive days (ending today or yesterday) with any points at all.
  int get activeStreak {
    var streak = 0;
    var cursor = DateTime.now();
    if (_visible(_dayKey(cursor)).total == 0) {
      // Today may simply not have started yet; the streak is still alive if
      // yesterday banked something.
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (_visible(_dayKey(cursor)).total > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The points for one day, for the week strip.
  DayPoints dayPoints(DateTime day) => _visible(_dayKey(day));

  /// A day's step total from the stored history (0 when unknown).
  int stepsForDay(String dayKey) => _stepDays[dayKey] ?? 0;

  /// The stored step history, oldest day first. Sent to the server on sync so
  /// it can score every day of the week, including days this install never
  /// saw (after a reinstall) and days the app was not opened on.
  Map<String, int> get stepDays => Map.unmodifiable(_stepDays);

  /// Monday..Sunday of the current week, oldest first.
  List<({DateTime date, DayPoints points})> get currentWeek {
    final start = _weekStart(DateTime.now());
    return [
      for (var i = 0; i < 7; i++)
        (
          date: start.add(Duration(days: i)),
          points: _visible(_dayKey(start.add(Duration(days: i)))),
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
      final stepsDaysRaw = prefs.getString(_stepsDaysKey);
      if (stepsDaysRaw != null && stepsDaysRaw.isNotEmpty) {
        final data = jsonDecode(stepsDaysRaw);
        if (data is Map) {
          data.forEach((key, value) {
            final steps = value is num ? value.toInt() : null;
            if (key is String && steps != null && steps >= 0) {
              _stepDays[key] = steps;
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
      } else if (_stepsDay != null) {
        // Carry the single-day value the previous build stored into the new
        // history map, so upgrading mid-day does not zero today's movement.
        final previous = _stepDays[_stepsDay!] ?? 0;
        if (_stepsToday > previous) _stepDays[_stepsDay!] = _stepsToday;
      }
      _optIn = prefs.getBool(_optInKey) ?? false;
      _stateKey = prefs.getString(_statePrefKey);
      _district = prefs.getString(_districtPrefKey);
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
    // The phone's own step sensor is the PRIMARY step source; the Health tab is
    // only one place it is read. Listening here means a day's steps are banked
    // even when that tab is never opened — Health Connect is an optional
    // second source, not a requirement.
    StepCounterService.instance.addListener(_onSensorSteps);
    await sync();
    _onSensorSteps();
  }

  void _onStoreChanged() {
    unawaited(sync());
  }

  /// Last step total already fed into the stores, and when.
  int _lastSensorSteps = -1;
  DateTime? _lastSensorPush;

  /// Feeds a sensor reading into the streak and the points.
  ///
  /// The hardware counter can emit several times a second while walking, and
  /// every push writes prefs and rescans today's meals/habits. Both are
  /// idempotent, but doing that per step is pure I/O, so a reading is only
  /// acted on when it moved by 25 steps or 20 seconds have passed. The number
  /// on screen is updated by the dashboard itself, so nothing looks laggy.
  void _onSensorSteps() {
    final steps = StepCounterService.instance.todaySteps;
    if (steps == null) return;
    final now = DateTime.now();
    final grew = steps - _lastSensorSteps;
    final due =
        _lastSensorPush == null ||
        now.difference(_lastSensorPush!) >= const Duration(seconds: 20);
    if (_lastSensorSteps >= 0 && !due && grew < 25) return;
    _lastSensorSteps = steps;
    _lastSensorPush = now;
    unawaited(StepGoalService.instance.recordToday(steps));
    unawaited(noteSteps(steps));
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
    final cutoff = _dayKey(
      DateTime.now().subtract(const Duration(days: keepDays)),
    );
    _days.removeWhere((key, _) => key.compareTo(cutoff) < 0);
    _stepDays.removeWhere((key, _) => key.compareTo(cutoff) < 0);
  }

  // ─── Scoring ──────────────────────────────────────────────────────

  /// Re-reads the stores and awards anything not yet paid: today's meals,
  /// habits, water and weigh-in, plus every stored step day of the week.
  ///
  /// Safe to call as often as wanted: every award is keyed and idempotent, and
  /// a run that changes nothing writes nothing. These points are the offline
  /// estimate the page shows before a server sync answers; the server's scored
  /// days replace them on screen once it does.
  Future<void> sync() async {
    await load();
    // The streak lives in the goal store, and loading it here means a launch
    // that never opened the Health tab still has the current target.
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

    // Movement — 10 points for each complete 5,000 steps, awarded per unit so
    // the total grows while the user walks. The stored day total is used (not
    // only today's), so a launch after a day the app was closed still credits
    // that day's walking.
    for (final entry in _stepDays.entries) {
      // Capped again here: a step day restored from the server can hold the raw
      // total, and an offline week must not pay for more than the plan allows.
      final units = StepLimit.cap(entry.value) ~/ stepsPerAward;
      for (var i = 1; i <= units; i++) {
        changed |= _award(
          entry.key,
          'steps_${i}_${entry.key}',
          PointsBucket.movement,
          stepAward,
          movementDailyCap,
        );
      }
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

  /// Records today's step total as the phone's sensor (or Health Connect)
  /// reported it. Called on every sensor batch, and again from the Health tab
  /// with the health platform's figure when that is higher.
  ///
  /// Deliberately not user-enterable: no screen takes a step number from a
  /// text field, so a typed total cannot exist.
  Future<void> noteSteps(int rawSteps) async {
    await load();
    // The free plan's daily ceiling, applied where a reading becomes history.
    // The raw total stays with the sensor, so an upgrade reveals the steps
    // already walked instead of rewriting the day backwards.
    final steps = StepLimit.cap(rawSteps);
    final today = _dayKey(DateTime.now());
    final previous = _stepDays[today] ?? 0;
    if (_stepsDay == today && _stepsToday == steps && steps <= previous) return;
    _stepsDay = today;
    _stepsToday = steps;
    // The sensor only counts up; a lower reading (a reboot, a fresh install)
    // must never walk the day — or its points — backwards.
    if (steps > previous) _stepDays[today] = steps;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stepsDayKey, today);
      await prefs.setInt(_stepsValueKey, steps);
      await prefs.setString(_stepsDaysKey, jsonEncode(_stepDays));
    } catch (e, st) {
      logError('LeaderboardService.noteSteps', e, st);
    }
    await sync();
  }

  /// Merges step totals restored from the server (a fresh install has none).
  Future<void> applyServerStepDays(Map<String, int> days) async {
    if (days.isEmpty) return;
    await load();
    var changed = false;
    days.forEach((key, steps) {
      if (steps <= (_stepDays[key] ?? 0)) return;
      _stepDays[key] = steps;
      changed = true;
    });
    if (!changed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stepsDaysKey, jsonEncode(_stepDays));
    } catch (e, st) {
      logError('LeaderboardService.applyServerStepDays', e, st);
    }
    notifyListeners();
  }

  /// Replaces this week's displayed points with the server's scored days.
  ///
  /// The server is the authority on the board, so showing anything else here
  /// lets the page and the ranking disagree — and a local-only week is exactly
  /// what lost yesterday's points when the app was reinstalled.
  void applyServerWeek(
    String week,
    Iterable<({String dateKey, int points, Map<String, int> buckets})> days,
  ) {
    var changed = false;
    if (_serverWeek != week) {
      _serverWeek = week;
      _serverDays.clear();
      changed = true;
    }
    for (final day in days) {
      final points = DayPoints()
        ..movement = day.buckets['movement'] ?? 0
        ..nutrition = day.buckets['nutrition'] ?? 0
        ..habits = day.buckets['habits'] ?? 0
        ..hydration = day.buckets['hydration'] ?? 0
        ..body = day.buckets['body'] ?? 0;
      final previous = _serverDays[day.dateKey];
      // Only notify on a real change. Without this every sync (which is
      // scheduled by this very notification) re-notified and pushed again,
      // forever — an 8-second loop of identical requests.
      if (previous != null &&
          previous.total == points.total &&
          previous.movement == points.movement &&
          previous.nutrition == points.nutrition &&
          previous.habits == points.habits &&
          previous.hydration == points.hydration &&
          previous.body == points.body) {
        continue;
      }
      _serverDays[day.dateKey] = points;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Saves the public leaderboard profile.
  ///
  /// Kept on the device rather than in `users/{uid}` on purpose: that document
  /// is read-only for clients (it holds entitlements), so a leaderboard
  /// location belongs with the score it places.
  Future<void> setProfile({
    required bool optIn,
    String? stateKey,
    String? district,
  }) async {
    await load();
    _optIn = optIn;
    _stateKey = stateKey ?? _stateKey;
    _district = district ?? _district;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_optInKey, _optIn);
      if (_stateKey == null) {
        await prefs.remove(_statePrefKey);
      } else {
        await prefs.setString(_statePrefKey, _stateKey!);
      }
      if (_district == null) {
        await prefs.remove(_districtPrefKey);
      } else {
        await prefs.setString(_districtPrefKey, _district!);
      }
    } catch (e, st) {
      logError('LeaderboardService.setProfile', e, st);
    }
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

  /// What the UI shows for one day: the server's scored points when this week
  /// has been synced, otherwise the local estimate (offline, before the first
  /// sync of the week). Never inserts, so reading the week cannot grow the
  /// stored map.
  DayPoints _visible(String key) =>
      _serverDays[key] ?? _days[key] ?? DayPoints();

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
