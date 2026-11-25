import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'crash_reporting.dart';
import '../models/habit.dart';
import '../services/account_partition.dart';
import '../services/badge_service.dart';
import '../services/meal_sync_service.dart';

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
  /// The stored key is scoped to the active account (see [_datesKey]) — it used
  /// to be a plain global key, so a second account on the same phone inherited
  /// the first one's streak and the backfill awarded its badges.
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

  /// The streak as of the last [load], for a first frame that already knows
  /// it. Null until the banked dates have been read, so a screen can tell
  /// "no streak yet" apart from "not loaded yet" instead of painting 0 and
  /// swapping to the real number.
  static int? get cachedCurrent => _loaded ? computeCurrentStreak() : null;

  /// Reads the banked dates once per process. Legacy counter + date are
  /// converted by replaying the old streak back from its last date, so an
  /// updating user keeps their number.
  static Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _loadOnce();
  }

  /// The preferences key for the ACTIVE account's banked days.
  static Future<String> _datesKey() async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = AccountPartition.suffix(
      AccountPartition.activeFromPrefs(prefs),
    );
    return AccountPartition.key(_keyDates, suffix);
  }

  /// Re-reads the banked days for the account that is active NOW.
  ///
  /// The service caches one set per process, which is right while the account
  /// never changes and wrong the moment it does: the previous account's streak
  /// (and the badges computed from it) stayed in memory after a sign-out.
  static Future<void> reload() async {
    _hitDates = [];
    _loaded = false;
    _loadFuture = null;
    await load();
  }

  static Future<void> _loadOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dates = <String>{};
      final scopedKey = await _datesKey();

      // Migration first: seed the date set from the legacy streak so the
      // user's banked days carry over across the model change.
      final legacyStreak = prefs.getInt(_keyLegacyStreak) ?? 0;
      final legacyDateRaw = prefs.getString(_keyLegacyDate) ?? '';
      final legacyDate = DateTime.tryParse(legacyDateRaw);
      if (legacyStreak > 0 && legacyDate != null) {
        for (var i = 0; i < legacyStreak; i++) {
          // Calendar arithmetic, not `subtract(Duration(days: i))`: across a
          // DST change a 24-hour step lands on 23:00 or 01:00 of the previous
          // day and the same date can be banked twice.
          dates.add(
            dateKey(
              DateTime(legacyDate.year, legacyDate.month, legacyDate.day - i),
            ),
          );
        }
      }

      // Defensive parse: a corrupt entry is dropped, corrupt storage resets
      // to the migration-seeded set — never crashes a screen that reads the
      // streak on every rebuild.
      // The scoped key first; the old global key seeds a pre-scoping install
      // once, then is removed below so it cannot leak to a second account.
      final raw =
          prefs.getString(scopedKey) ?? prefs.getString(_keyDates) ?? '';
      for (final entry in jsonList(raw)) {
        if (DateTime.tryParse(entry) != null) dates.add(entry);
      }

      _hitDates = dates.toList()..sort();

      if (prefs.containsKey(scopedKey) || dates.isNotEmpty) {
        // Persist the (possibly migration-seeded + cleaned) set once, and
        // drop the legacy keys so they can only seed a single time.
        await prefs.setString(scopedKey, _hitDates.join(','));
      }
      if (prefs.containsKey(_keyDates)) await prefs.remove(_keyDates);
      await prefs.remove(_keyLegacyStreak);
      await prefs.remove(_keyLegacyDate);
    } catch (e, st) {
      // A silent reset here reads as "you have no streak" — the same class of
      // invisible failure the per-account key was added to stop.
      logError('MealStreakService._loadOnce', e, st);
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
    _hitDates
      ..add(today)
      ..sort();
    final streak = computeCurrentStreak();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(await _datesKey(), _hitDates.join(','));
      // The banked days live in this account's `userPreferences` document too.
      // Without that, a reinstall started the streak at zero and the streak
      // badges "came back" only as a silent backfill with today's date.
      unawaited(
        MealSyncService.syncPreferences({'streakDates': _hitDates.join(',')}),
      );
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
      day = _previousDay(day);
    }
    var count = 0;
    while (hits.contains(dateKey(day))) {
      count++;
      day = _previousDay(day);
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
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return best;
  }

  /// The day before [day], as a calendar date.
  ///
  /// `subtract(const Duration(days: 1))` is 24 hours, not one day: on a DST
  /// fall-back day that lands back inside the same date and a day gets counted
  /// twice. India has no DST, so this only bites travellers — which is exactly
  /// why it survived this long.
  static DateTime _previousDay(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);

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

  /// The banked days, for callers that need the dates themselves (badge
  /// backfill wants the day a streak was reached, not "when we noticed").
  static Future<List<String>> bankedDates() async {
    await load();
    return List<String>.unmodifiable(_hitDates);
  }

  /// Unions the cloud's banked days into this device's set.
  ///
  /// A union, never a replace: the cloud copy can lag behind a day banked
  /// offline, and losing a met day is worse than carrying a stale one.
  static Future<void> mergeCloudDates(Iterable<String> cloudDates) async {
    await load();
    final merged = <String>{..._hitDates};
    for (final entry in cloudDates) {
      if (DateTime.tryParse(entry) != null) merged.add(entry.trim());
    }
    if (merged.length == _hitDates.length) return;
    _hitDates = merged.toList()..sort();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(await _datesKey(), _hitDates.join(','));
    } catch (e, st) {
      logError('MealStreakService.mergeCloudDates', e, st);
    }
  }

  /// Whether today's goal has already been banked — cheap, non-async check
  /// for rebuild paths (must be used after [load] has run, which any Home
  /// build that logs a meal has).
  static bool isGoalHitToday() => _loaded && _todayHit();

  /// Whether the current streak is the record. Kept for the share card.
  static bool isLongestStreak(int current, int best) {
    return current >= best && current > 0;
  }

  /// Forgets the streak entirely — memory and storage.
  ///
  /// The banked days are stored globally (not per account), so without this a
  /// deleted account's streak would be served to the next account on this
  /// device.
  static Future<void> clear() async {
    _hitDates = [];
    _loaded = true; // empty and loaded: nothing on disk is left to re-read
    _loadFuture = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(await _datesKey());
      await prefs.remove(_keyDates);
      await prefs.remove(_keyLegacyStreak);
      await prefs.remove(_keyLegacyDate);
    } catch (_) {
      // A storage failure must not block the wipe.
    }
  }

  /// Test hook: forget everything loaded so the next call re-reads prefs.
  @visibleForTesting
  static void resetForTest() {
    _hitDates = [];
    _loaded = false;
    _loadFuture = null;
  }
}
