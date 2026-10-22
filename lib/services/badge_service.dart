import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_badge.dart';
import 'account_partition.dart';
import 'crash_reporting.dart';

/// Awards and stores achievements.
///
/// The rules live here (not in the widgets) and are all triggered by a *user
/// action that already happened* — a meal was added, a weigh-in was saved, a
/// streak day was banked. Nothing in this file reads the scale's value or the
/// user's weight: the weigh-in badge fires the first time they record one,
/// whatever the number is.
///
/// Storage is per account (`badges_<suffix>`), so two accounts on one phone do
/// not share a trophy case. Guests keep the legacy unprefixed key, like every
/// other local store.
class BadgeService extends ChangeNotifier {
  static final BadgeService _instance = BadgeService._();
  static BadgeService get instance => _instance;
  BadgeService._();

  static const _prefsKey = 'badges';

  /// The streak length that earns [AppBadge.weekWarrior] / the fortnight one.
  static const int weekStreak = 7;
  static const int fortnightStreak = 14;

  /// How many meals earn [AppBadge.tenPlates].
  static const int tenPlatesCount = 10;

  /// id → ISO date it was earned. A map (not a set) so the board can say
  /// "earned on 21 Oct" without a second store.
  final Map<String, String> _earnedAt = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Fires once per newly earned badge, so the shell can celebrate it. A
  /// ValueNotifier rather than a stream: the celebration is a one-shot UI
  /// event, and the last value is all anyone needs.
  final ValueNotifier<AppBadge?> justEarned = ValueNotifier(null);

  bool isEarned(String id) => _earnedAt.containsKey(id);

  /// When [id] was earned, or null.
  DateTime? earnedOn(String id) => DateTime.tryParse(_earnedAt[id] ?? '');

  /// Earned badges in [AppBadge.all] order.
  List<AppBadge> get earned =>
      AppBadge.all.where((b) => isEarned(b.id)).toList();

  /// Not-yet-earned badges, same order.
  List<AppBadge> get locked =>
      AppBadge.all.where((b) => !isEarned(b.id)).toList();

  int get earnedCount => earned.length;

  static Future<String> _suffix() async {
    final prefs = await SharedPreferences.getInstance();
    return AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs));
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        AccountPartition.key(_prefsKey, await _suffix()),
      );
      _earnedAt.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            // Skip ids this build no longer ships, and anything malformed:
            // a stale trophy must never break the board.
            if (AppBadge.byId(key.toString()) != null && value is String) {
              _earnedAt[key.toString()] = value;
            }
          });
        }
      }
    } catch (e, st) {
      // Corrupt storage resets the board instead of crashing a screen that
      // opens on every visit to Profile.
      _earnedAt.clear();
      logError('BadgeService.load', e, st);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Re-reads for a newly active account (login / logout).
  Future<void> reload() async {
    _loaded = false;
    _earnedAt.clear();
    justEarned.value = null;
    await load();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AccountPartition.key(_prefsKey, await _suffix()),
        jsonEncode(_earnedAt),
      );
    } catch (e, st) {
      logError('BadgeService._save', e, st);
    }
  }

  /// Records [badge] if it is new. Returns true when it was just earned.
  Future<bool> _award(AppBadge badge) async {
    if (isEarned(badge.id)) return false;
    _earnedAt[badge.id] = DateTime.now().toIso8601String();
    await _save();
    notifyListeners();
    justEarned.value = badge;
    return true;
  }

  /// Called after a meal is stored. [totalMeals] is the new total, so the
  /// caller (MealStore) does not have to be imported here.
  Future<void> noteMealLogged(int totalMeals) async {
    await load();
    if (totalMeals <= 0) return;
    await _award(AppBadge.firstBite);
    if (totalMeals >= tenPlatesCount) await _award(AppBadge.tenPlates);
  }

  /// Called after a weigh-in is saved. The value is never inspected — one
  /// recorded weight earns the badge, and no weight ever loses it.
  Future<void> noteWeighIn() async {
    await load();
    await _award(AppBadge.firstWeighIn);
  }

  /// Called when the macro-target streak advances.
  Future<void> noteStreak(int days) async {
    await load();
    if (days >= weekStreak) await _award(AppBadge.weekWarrior);
    if (days >= fortnightStreak) await _award(AppBadge.fortnightFlame);
  }

  /// Test hook: forget everything loaded so the next [load] re-reads prefs.
  @visibleForTesting
  void resetForTest() {
    _earnedAt.clear();
    _loaded = false;
    justEarned.value = null;
  }
}
