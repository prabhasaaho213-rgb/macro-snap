import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';

/// The user's daily step target, plus the streak of days that target was hit.
///
/// Both live here rather than in the dashboard's State because the dashboard
/// is rebuilt (and re-created) every time the shell comes back, and a streak
/// that resets whenever the tab is rebuilt is not a streak.
///
/// The target moves in 5,000-step steps — a phone cannot measure a 2,500-step
/// difference in daily behaviour any better than a 5,000-step one, and four
/// taps that all mean something (5k / 10k / 15k / 20k) are easier to pick from
/// than a free-text box.
class StepGoalService extends ChangeNotifier {
  StepGoalService._();
  static final StepGoalService instance = StepGoalService._();

  /// Prefs keys. The goal is per device (not per account): it is a body
  /// target, like the step count it is compared against.
  static const String goalKey = 'health_step_goal';
  static const String _streakDayKey = 'health_step_streak_day';
  static const String _streakCountKey = 'health_step_streak_count';
  static const String _streakBestKey = 'health_step_streak_best';

  /// 10,000 is the target the dashboard shipped with, so an existing install
  /// keeps the ring it already understands.
  static const int defaultGoal = 10000;

  /// The granularity the target is offered in.
  static const int goalStep = 5000;

  static const int minGoal = 5000;
  static const int maxGoal = 50000;

  int _goal = defaultGoal;
  int _streak = 0;
  int _best = 0;
  String? _lastGoalDay;
  bool _loaded = false;

  /// The daily target in steps.
  int get goal => _goal;

  /// Consecutive days the target was reached, counting today once it is hit.
  /// Zero once a whole day has been missed — a streak that survives a skipped
  /// day is not a streak.
  int get streak => _streak;

  /// The longest streak this device has recorded.
  int get bestStreak => _best;

  bool get loaded => _loaded;

  /// Today's target has been reached (only meaningful once [recordToday] has
  /// seen a reading).
  bool get reachedToday => _lastGoalDay == _dayKey(DateTime.now());

  /// The targets offered in the goal picker: 5k, 10k … 30k.
  static List<int> get goalOptions => [
    for (var g = goalStep; g <= 30000; g += goalStep) g,
  ];

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(goalKey);
      if (stored != null && stored >= minGoal && stored <= maxGoal) {
        _goal = stored;
      }
      _streak = prefs.getInt(_streakCountKey) ?? 0;
      _best = prefs.getInt(_streakBestKey) ?? 0;
      _lastGoalDay = prefs.getString(_streakDayKey);
    } catch (e, st) {
      logError('StepGoalService.load', e, st);
    }
    _loaded = true;
    _dropExpiredStreak();
    notifyListeners();
  }

  /// Persists a new daily target.
  ///
  /// The target is snapped to the 5,000-step grid and clamped, so a value from
  /// an older build (or a hand-edited pref) can never leave the ring asking
  /// for 7,483 steps. The streak is deliberately kept: changing tomorrow's
  /// target says nothing about the days already walked.
  Future<void> setGoal(int goal) async {
    final snapped = ((goal / goalStep).round() * goalStep).clamp(
      minGoal,
      maxGoal,
    );
    if (snapped == _goal) return;
    _goal = snapped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(goalKey, snapped);
    } catch (e, st) {
      logError('StepGoalService.setGoal', e, st);
    }
  }

  /// Feeds today's step count in, advancing (or breaking) the streak.
  ///
  /// Called from every dashboard read, including the 5-second poll, so the
  /// streak advances the moment the target is crossed rather than at the next
  /// launch. Returns true when the target was reached on this call for the
  /// first time today, which is what the dashboard uses to celebrate.
  Future<bool> recordToday(int steps) async {
    final today = _dayKey(DateTime.now());
    var newlyReached = false;
    var changed = false;

    if (steps >= _goal) {
      if (_lastGoalDay != today) {
        final yesterday = _dayKey(
          DateTime.now().subtract(const Duration(days: 1)),
        );
        // Consecutive day → extend. A gap of a day or more → start again at 1.
        _streak = _lastGoalDay == yesterday ? _streak + 1 : 1;
        _lastGoalDay = today;
        if (_streak > _best) _best = _streak;
        newlyReached = true;
        changed = true;
      }
    } else if (_lastGoalDay == today) {
      // The target was met earlier today and the read now comes back below it
      // (a record was deleted in Health Connect). Take the day back instead of
      // leaving a streak for a day that no longer qualifies.
      _lastGoalDay = null;
      _streak = _streak > 0 ? _streak - 1 : 0;
      changed = true;
    }

    if (!changed) {
      final before = _streak;
      _dropExpiredStreak();
      changed = _streak != before;
    }
    if (!changed) return false;

    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_streakCountKey, _streak);
      await prefs.setInt(_streakBestKey, _best);
      if (_lastGoalDay == null) {
        await prefs.remove(_streakDayKey);
      } else {
        await prefs.setString(_streakDayKey, _lastGoalDay!);
      }
    } catch (e, st) {
      logError('StepGoalService.recordToday', e, st);
    }
    return newlyReached;
  }

  /// Resets a streak whose last qualifying day is older than yesterday.
  ///
  /// The stored count stays in prefs until the next write so a clock change or
  /// a late-night read cannot wipe history; only the displayed streak is
  /// zeroed, because the run really is over.
  void _dropExpiredStreak() {
    final last = _lastGoalDay;
    if (last == null) {
      _streak = 0;
      return;
    }
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final today = _dayKey(DateTime.now());
    if (last != today && last != yesterday) _streak = 0;
  }
}
