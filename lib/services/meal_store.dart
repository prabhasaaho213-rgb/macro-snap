import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models/meal_record.dart';
import 'account_partition.dart';
import 'badge_service.dart';
import 'meal_sync_service.dart';
import 'crash_reporting.dart';

class MealStore {
  static final MealStore _instance = MealStore._();
  static MealStore get instance => _instance;
  MealStore._();

  final ValueNotifier<int> changeNotifier = ValueNotifier(0);

  /// Fires only when a meal is actually ADDED (not on generic refresh bumps
  /// like subscription activation). Notification suppression listens to this
  /// so a "scan counts changed" bump can never accidentally silence
  /// reminders.
  final ValueNotifier<int> mealAddedNotifier = ValueNotifier(0);

  List<MealRecord> _meals = [];
  bool _loaded = false;

  /// The account whose local partition is loaded. Null until [load] runs
  /// (guests and unknown states use the legacy `meals.json` file).
  String? _activeAccount;
  String get _suffix => AccountPartition.suffix(_activeAccount ?? '');

  /// Local file for the active account's partition: `meals.json` for guests,
  /// `meals_{suffix}.json` for signed-in accounts — one device holds many
  /// accounts without any data leaking between them.
  String get _fileName => '${AccountPartition.key('meals', _suffix)}.json';

  List<MealRecord> get todayMeals =>
      _meals.where((m) => m.isToday).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  List<MealRecord> get allMeals => List.unmodifiable(_meals);

  int get todayCalories => todayMeals.fold(0, (sum, m) => sum + m.calories);
  double get todayProtein => todayMeals.fold(0.0, (sum, m) => sum + m.protein);
  double get todayCarbs => todayMeals.fold(0.0, (sum, m) => sum + m.carbs);
  double get todayFats => todayMeals.fold(0.0, (sum, m) => sum + m.fats);

  Future<void> load() async {
    if (_loaded) return;
    _activeAccount = AccountPartition.activeFromPrefs(
      await SharedPreferences.getInstance(),
    );
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists() && _suffix.isNotEmpty) {
        // One-shot migration: attribute the legacy pre-partitioning file to
        // this account (a signed-in user updating the app keeps their meals;
        // the move deletes the legacy file so a later different account can
        // never inherit it).
        final legacy = File('${dir.path}/meals.json');
        if (await legacy.exists()) {
          await legacy.rename(file.path);
        }
      }
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          _meals = [];
        } else {
          final data = jsonDecode(raw);
          if (data is List) {
            // Parse per record: a single corrupt entry is skipped instead of
            // aborting the loop (which used to reset the whole history).
            _meals = data
                .whereType<Map>()
                .map(
                  (e) => MealRecord.tryFromJson(Map<String, dynamic>.from(e)),
                )
                .whereType<MealRecord>()
                .toList();
          }
        }
      }
    } catch (_) {
      // Corrupted or unreadable local data — reset rather than crash.
      _meals = [];
    }
    _loaded = true;
    // Announce completion: anything that started listening before the load
    // finished (Home builds as soon as the startup gate opens) must repaint
    // with the real history. Without this a load that finished late — e.g.
    // after the startup splash hit its safety timeout — never reached the UI,
    // which then showed zeros for the rest of the session.
    changeNotifier.value++;
    // Cloud restore merges missing meals in the background so a slow or
    // sleeping backend never blocks the app from opening.
    unawaited(_syncFromCloud());
  }

  /// Force a full reload from local + cloud. Awaits any in-flight cloud
  /// merge from the previous account first so its late completion can never
  /// pollute the freshly loaded state.
  Future<void> reload() async {
    await _syncFuture;
    _loaded = false;
    _meals = [];
    await load();
    changeNotifier.value++;
  }

  /// The in-flight cloud merge, so [reload] can await it before clearing for
  /// a newly active account (mirrors HabitStore's restore guard).
  Future<void>? _syncFuture;

  /// Completes when the background restore triggered by [load] has settled.
  ///
  /// For work that has to run on the restored history rather than on whatever
  /// was on the device — achievements backfill is the case that needs it: a
  /// new phone has no local meals, so a backfill run before the merge sees
  /// zero and awards nothing.
  Future<void> get cloudSynced => _syncFuture ?? Future<void>.value();

  /// Sync meals from cloud backup. Reentrant-safe: returns the in-flight
  /// future if a merge is already running.
  Future<void> _syncFromCloud() {
    if (_syncFuture != null) return _syncFuture!;
    final f = _doSyncFromCloud().whenComplete(() => _syncFuture = null);
    _syncFuture = f;
    return f;
  }

  Future<void> _doSyncFromCloud() async {
    try {
      final cloudMeals = await MealSyncService.fetchMeals();
      if (cloudMeals.isEmpty) return;
      final localIds = _meals.map((m) => m.id).toSet();
      bool added = false;
      for (final meal in cloudMeals) {
        if (!localIds.contains(meal.id)) {
          _meals.add(meal);
          added = true;
        }
      }
      if (added) {
        await _save();
      }
    } catch (e, st) {
      logError('MealStore._doSyncFromCloud', e, st);
    } // Silently fail — local data is primary
  }

  Future<void> add(MealRecord meal) async {
    _meals.add(meal);
    // Announce before persisting: the list is the source of truth for the UI,
    // and a slow (or wedged) disk write must not delay the calorie ring, the
    // "first meal" moment or the meal card appearing.
    changeNotifier.value++;
    mealAddedNotifier.value++;
    await _save();
    // Achievements are a side effect of logging, never a gate on it: the meal
    // is already stored and on screen by the time this runs.
    unawaited(BadgeService.instance.noteMealLogged(_meals.length));
    // Async sync to cloud (fire-and-forget)
    MealSyncService.syncMeal(meal);
  }

  Future<void> remove(String id) async {
    _meals.removeWhere((m) => m.id == id);
    // Same rule as add(): the row leaves the screen now, the write follows.
    changeNotifier.value++;
    await _save();
    // Async remove from cloud (fire-and-forget)
    MealSyncService.removeMeal(id);
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(
        jsonEncode(_meals.map((m) => m.toJson()).toList()),
      );
    } catch (e, st) {
      logError('MealStore._save', e, st);
    }
  }
}
