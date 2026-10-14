import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/meal_record.dart';
import 'firebase_identity.dart';
import 'sync_status_service.dart';

/// Cloud backup/sync of ALL user data to **Cloud Firestore (Firebase)**.
///
/// Phase 3 of the Firestore migration: this replaces the old HTTP sync to the
/// Railway/Postgres backend. Every meal, habit and water write lands directly
/// in Firestore, keyed by the Firebase Auth UID, so a reinstall or a new
/// device restores everything from Firebase — no backend required.
///
/// Collection layout (matches docs/firestore-migration.md):
///   meals/{mealId}      — one doc per meal, uid field for security rules
///   habitData/{uid}     — one doc per user: habits[], waterLog{}, waterGoal
///
/// Guests (no Firebase Auth account) have no cloud storage and are skipped
/// silently — exactly like the old flow skipped `guest_*` identifiers. A
/// guest skip is NOT a failure, so it never raises the sync banner.
class MealSyncService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Resolves the current Firebase Auth UID (see [FirebaseIdentity.currentUid]).
  static Future<String?> _uid() => FirebaseIdentity.currentUid();

  static bool _isGuestUid(String? uid) => uid == null || uid.isEmpty;

  // ═══════════════════════════════════════════════════════════════
  // MEALS
  // ═══════════════════════════════════════════════════════════════

  /// Sync a single meal to Firestore (upsert by meal id).
  static Future<bool> syncMeal(MealRecord meal) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('meals').doc(meal.id).set(
            {...meal.toJson(), 'uid': uid},
            SetOptions(merge: true),
          );
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncMeal failed: $e');
      SyncStatusService.instance.reportFailure('Meal sync failed');
      return false;
    }
  }

  /// Remove a meal from Firestore.
  static Future<bool> removeMeal(String mealId) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('meals').doc(mealId).delete();
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.removeMeal failed: $e');
      SyncStatusService.instance.reportFailure('Meal remove failed');
      return false;
    }
  }

  /// Fetch all meals for the signed-in user from Firestore.
  ///
  /// Normalizes both app-written docs (ISO-string `date`, explicit `id`) and
  /// backend/backfill-written docs (Timestamp `date`, no `id` field) so old
  /// cloud data reads cleanly after the migration.
  static Future<List<MealRecord>> fetchMeals() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return [];
    try {
      final snap = await _db
          .collection('meals')
          .where('uid', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 15));
      final meals = snap.docs.map(_mealFromDoc).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      SyncStatusService.instance.reportSuccess();
      return meals;
    } catch (e) {
      debugPrint('MealSyncService.fetchMeals failed: $e');
      SyncStatusService.instance.reportFailure('Meal restore failed');
      return [];
    }
  }

  static MealRecord _mealFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return mealFromMap(Map<String, dynamic>.from(doc.data()), doc.id);
  }

  /// Converts a Firestore meal doc map into a [MealRecord], normalizing both
  /// app-written docs (ISO-string `date`, explicit `id` field) and
  /// backend/backfill-written docs (Firestore [Timestamp] `date`, no `id`
  /// field, possible null optional strings) so old cloud data reads cleanly
  /// after the migration. Exposed for testing; prefer [_mealFromDoc] when a
  /// snapshot is available.
  @visibleForTesting
  static MealRecord mealFromMap(Map<String, dynamic> data, String docId) {
    final normalized = Map<String, dynamic>.from(data);
    normalized['id'] = normalized['id'] ?? docId;
    final date = normalized['date'];
    if (date is Timestamp) {
      normalized['date'] = date.toDate().toIso8601String();
    } else if (date is DateTime) {
      normalized['date'] = date.toIso8601String();
    }
    return MealRecord.fromJson(normalized);
  }

  /// Bulk sync all local meals to Firestore (SYNC ALL DATA button).
  ///
  /// Batch-replace semantics, matching the old backend `/meals/sync` (which
  /// deleted all then re-inserted): cloud meals that no longer exist locally
  /// are deleted too, so a meal deleted on this device never resurrects on
  /// reinstall.
  static Future<void> syncAllMeals(List<MealRecord> meals) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return;
    try {
      final db = _db;
      final col = db.collection('meals');
      final existing = await col.where('uid', isEqualTo: uid).get();
      final localIds = meals.map((m) => m.id).toSet();
      final batch = db.batch();
      var ops = 0;
      for (final doc in existing.docs) {
        if (!localIds.contains(doc.id)) {
          batch.delete(doc.reference);
          ops++;
        }
      }
      for (final meal in meals) {
        batch.set(
          col.doc(meal.id),
          {...meal.toJson(), 'uid': uid},
          SetOptions(merge: true),
        );
        ops++;
      }
      if (ops > 0) await batch.commit();
      SyncStatusService.instance.reportSuccess();
    } catch (e) {
      debugPrint('MealSyncService.syncAllMeals failed: $e');
      SyncStatusService.instance.reportFailure('Bulk meal sync failed');
    }
  }

  /// Total meal count stored in Firestore for the current user.
  static Future<int> mealCount() async {
    final meals = await fetchMeals();
    return meals.length;
  }

  // ═══════════════════════════════════════════════════════════════
  // HABITS & WATER
  // ═══════════════════════════════════════════════════════════════

  /// Sync all habits + water log to Firestore (one habitData doc per user).
  static Future<bool> syncHabits({
    required List<Map<String, dynamic>> habitsJson,
    required Map<String, int> waterLog,
    required int waterGoal,
  }) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('habitData').doc(uid).set({
        'habits': habitsJson,
        'waterLog': waterLog,
        'waterGoal': waterGoal,
        'updatedAt': DateTime.now(),
      });
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncHabits failed: $e');
      SyncStatusService.instance.reportFailure('Habit sync failed');
      return false;
    }
  }

  /// Fetch habits + water log from Firestore.
  /// Returns a map with 'habits', 'waterLog', 'waterGoal' keys, or null when
  /// the user has never backed up (or on failure).
  static Future<Map<String, dynamic>?> fetchHabits() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return null;
    try {
      final doc = await _db
          .collection('habitData')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      final data = doc.data() ?? const <String, dynamic>{};
      SyncStatusService.instance.reportSuccess();
      return {
        'habits':
            (data['habits'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'waterLog': Map<String, int>.from(data['waterLog'] as Map? ?? {}),
        'waterGoal': (data['waterGoal'] as num?)?.toInt() ?? 8,
      };
    } catch (e) {
      debugPrint('MealSyncService.fetchHabits failed: $e');
      SyncStatusService.instance.reportFailure('Habit restore failed');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DIET PROFILE
  // ═══════════════════════════════════════════════════════════════

  /// Sync diet profile to Firestore.
  static Future<bool> syncDietProfile(Map<String, dynamic> profileJson) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('dietProfiles').doc(uid).set({
        ...profileJson,
        'uid': uid,
        'updatedAt': DateTime.now(),
      });
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncDietProfile failed: $e');
      SyncStatusService.instance.reportFailure('Diet profile sync failed');
      return false;
    }
  }

  /// Fetch diet profile from Firestore.
  static Future<Map<String, dynamic>?> fetchDietProfile() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return null;
    try {
      final doc = await _db
          .collection('dietProfiles')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      SyncStatusService.instance.reportSuccess();
      return doc.data();
    } catch (e) {
      debugPrint('MealSyncService.fetchDietProfile failed: $e');
      SyncStatusService.instance.reportFailure('Diet profile restore failed');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RECENT FOODS
  // ═══════════════════════════════════════════════════════════════

  /// Sync recent foods list to Firestore.
  static Future<bool> syncRecentFoods(List<Map<String, dynamic>> foodsJson) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('recentFoods').doc(uid).set({
        'foods': foodsJson,
        'updatedAt': DateTime.now(),
      });
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncRecentFoods failed: $e');
      SyncStatusService.instance.reportFailure('Recent foods sync failed');
      return false;
    }
  }

  /// Fetch recent foods from Firestore.
  static Future<List<Map<String, dynamic>>?> fetchRecentFoods() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return null;
    try {
      final doc = await _db
          .collection('recentFoods')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      final data = doc.data();
      SyncStatusService.instance.reportSuccess();
      return (data?['foods'] as List?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('MealSyncService.fetchRecentFoods failed: $e');
      SyncStatusService.instance.reportFailure('Recent foods restore failed');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RECIPES
  // ═══════════════════════════════════════════════════════════════

  /// Sync the user's custom recipes to Firestore (one recipes doc per user).
  static Future<bool> syncRecipes(List<Map<String, dynamic>> recipesJson) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('recipes').doc(uid).set({
        'recipes': recipesJson,
        'updatedAt': DateTime.now(),
      });
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncRecipes failed: $e');
      SyncStatusService.instance.reportFailure('Recipe sync failed');
      return false;
    }
  }

  /// Fetch custom recipes from Firestore.
  /// Returns null when the user has never backed up (or on failure).
  static Future<List<Map<String, dynamic>>?> fetchRecipes() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return null;
    try {
      final doc = await _db
          .collection('recipes')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      SyncStatusService.instance.reportSuccess();
      return (doc.data()?['recipes'] as List?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('MealSyncService.fetchRecipes failed: $e');
      SyncStatusService.instance.reportFailure('Recipe restore failed');
      return null;
    }
  }

  // USER PREFERENCES (theme, name, etc.)
  // ═══════════════════════════════════════════════════════════════

  /// Sync user preferences (theme, name, etc.) to Firestore.
  static Future<bool> syncPreferences(Map<String, dynamic> prefs) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    try {
      await _db.collection('userPreferences').doc(uid).set({
        ...prefs,
        'uid': uid,
        'updatedAt': DateTime.now(),
      });
      SyncStatusService.instance.reportSuccess();
      return true;
    } catch (e) {
      debugPrint('MealSyncService.syncPreferences failed: $e');
      SyncStatusService.instance.reportFailure('Preferences sync failed');
      return false;
    }
  }

  /// Fetch user preferences from Firestore.
  static Future<Map<String, dynamic>?> fetchPreferences() async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return null;
    try {
      final doc = await _db
          .collection('userPreferences')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      SyncStatusService.instance.reportSuccess();
      return doc.data();
    } catch (e) {
      debugPrint('MealSyncService.fetchPreferences failed: $e');
      SyncStatusService.instance.reportFailure('Preferences restore failed');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FULL BACKUP / RESTORE
  // ═══════════════════════════════════════════════════════════════

  /// Backup ALL data (meals + habits + water + diet profile + recent foods +
  /// user preferences) to Firestore. Returns true if ALL syncs succeeded.
  static Future<bool> backupAll({
    required List<MealRecord> meals,
    required List<Map<String, dynamic>> habitsJson,
    required Map<String, int> waterLog,
    required int waterGoal,
    List<Map<String, dynamic>>? recentFoodsJson,
    Map<String, dynamic>? preferences,
  }) async {
    bool allOk = true;

    for (final meal in meals) {
      if (!await syncMeal(meal)) allOk = false;
    }

    if (!await syncHabits(
      habitsJson: habitsJson,
      waterLog: waterLog,
      waterGoal: waterGoal,
    )) {
      allOk = false;
    }

    if (recentFoodsJson != null) {
      if (!await syncRecentFoods(recentFoodsJson)) allOk = false;
    }

    if (preferences != null) {
      if (!await syncPreferences(preferences)) allOk = false;
    }

    return allOk;
  }
}
