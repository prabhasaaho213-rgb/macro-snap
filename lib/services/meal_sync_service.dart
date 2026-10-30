import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/meal_record.dart';
import 'firebase_identity.dart';
import 'sync_status_service.dart';

/// Cloud backup/sync of ALL user data to **Cloud Firestore (Firebase)**.
///
/// Firestore is the storage layer: every meal, habit and water write lands
/// directly in Firestore, keyed by the Firebase Auth UID, so a reinstall or a
/// new device restores everything without any request to our own backend.
/// The HTTP backend is only used for things Firebase cannot decide alone
/// (payments, scan limits via the Admin SDK).
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

  /// The most writes one batch is allowed to carry.
  ///
  /// Firestore's hard limit is 500 operations per batch; 400 leaves headroom
  /// and keeps each commit well under the 10 MiB request size.
  static const int maxBatchOperations = 400;

  // ─── Payload ceiling, mirrored from firestore.rules ─────────────────────
  //
  // `validMeal()` in firestore.rules REJECTS a meal whose name is over 80
  // bytes, calories are outside 0..10000, or a macro is outside 0..1000. A
  // rejected write fails on its own; inside a bulk batch it takes every other
  // operation in that batch down with it. Names come from the AI scan, so an
  // unusually long dish name was enough to break sync for the whole account.
  // The rules and these limits must stay in step.
  static const int _maxNameBytes = 80;
  static const int _maxServingBytes = 200;
  static const int _maxCategoryBytes = 40;
  static const int _maxCalories = 10000;
  static const double _maxMacro = 1000;

  /// Trims [text] and cuts it to at most [maxBytes] UTF-8 bytes.
  ///
  /// Rules measure string size in BYTES, so two emoji take 8, not 4 — a
  /// character count would still let a name of emoji through. The cut never
  /// lands in the middle of a multi-byte character, so the result is always
  /// valid UTF-8 and can be re-read by every restore path.
  @visibleForTesting
  static String clampText(String text, int maxBytes, {String fallback = ''}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return fallback;
    if (utf8.encode(trimmed).length <= maxBytes) return trimmed;
    final buffer = <int>[];
    for (final rune in trimmed.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (buffer.length + bytes.length > maxBytes) break;
      buffer.addAll(bytes);
    }
    final cut = utf8.decode(buffer).trim();
    return cut.isEmpty ? fallback : cut;
  }

  static double _clampMacro(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    return value.clamp(0, _maxMacro).toDouble();
  }

  /// The document body written for [meal] — [MealRecord.toJson] with every
  /// value pulled back inside the limits firestore.rules enforces.
  ///
  /// Only the UPLOAD is clamped: the local record keeps the original numbers,
  /// so a restore on a new device brings back the clamped copy. That is a
  /// deliberate trade — one clamped meal is better than an account that
  /// cannot back up at all — and the clamp only bites on values no real food
  /// produces (a name over 80 bytes, 10,000+ kcal, a macro over 1 kg).
  @visibleForTesting
  static Map<String, dynamic> mealDoc(MealRecord meal, String uid) {
    final json = meal.toJson();
    // Rules require an int: clamp() returns num, so convert back explicitly.
    final calories = meal.calories.clamp(0, _maxCalories).toInt();
    final doc = <String, dynamic>{
      ...json,
      'name': clampText(meal.name, _maxNameBytes, fallback: 'Meal'),
      'category': clampText(meal.category, _maxCategoryBytes),
      'serving': clampText(meal.serving, _maxServingBytes),
      'calories': calories,
      'protein': _clampMacro(meal.protein),
      'carbs': _clampMacro(meal.carbs),
      'fats': _clampMacro(meal.fats),
      'fiber': _clampMacro(meal.fiber),
      'uid': uid,
    };
    // `date` is an ISO-8601 string, well under the rule's 40-byte cap; trim it
    // defensively in case a malformed record ever reaches a write.
    doc['date'] = clampText(meal.date.toIso8601String(), 40, fallback: '');
    if ((doc['date'] as String).isEmpty) {
      doc['date'] = DateTime.now().toIso8601String();
    }
    return doc;
  }

  // ═══════════════════════════════════════════════════════════════
  // MEALS
  // ═══════════════════════════════════════════════════════════════

  /// Sync a single meal to Firestore (upsert by meal id).
  static Future<bool> syncMeal(MealRecord meal) async {
    final uid = await _uid();
    if (_isGuestUid(uid)) return false;
    final owner = uid!; // promoted: _isGuestUid only rejects null/empty
    try {
      await _db
          .collection('meals')
          .doc(meal.id)
          .set(mealDoc(meal, owner), SetOptions(merge: true));
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
      // Parse each doc on its own: one malformed cloud document used to throw
      // out of the whole map, fail the fetch, and report "Meal restore
      // failed" — silently dropping every other meal as well. Now the bad doc
      // is logged and skipped.
      final meals = <MealRecord>[];
      for (final doc in snap.docs) {
        try {
          meals.add(_mealFromDoc(doc));
        } catch (e) {
          debugPrint('Skipping malformed meal doc ${doc.id}: $e');
        }
      }
      meals.sort((a, b) => b.date.compareTo(a.date));
      SyncStatusService.instance.reportSuccess();
      return meals;
    } catch (e) {
      debugPrint('MealSyncService.fetchMeals failed: $e');
      SyncStatusService.instance.reportFailure('Meal restore failed');
      return [];
    }
  }

  static MealRecord _mealFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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
      final owner = uid!; // promoted: _isGuestUid only rejects null/empty
      final existing = await col.where('uid', isEqualTo: owner).get();
      final localIds = meals.map((m) => m.id).toSet();

      // Collect the operations first, then commit them in fixed-size chunks.
      // One batch could previously carry every delete and every set at once —
      // a long history hit Firestore's 500-operation limit and the release
      // build failed the ENTIRE backup with "Bulk meal sync failed".
      final writes = <void Function(WriteBatch batch)>[];
      for (final doc in existing.docs) {
        if (!localIds.contains(doc.id)) {
          writes.add((batch) => batch.delete(doc.reference));
        }
      }
      for (final meal in meals) {
        final data = mealDoc(meal, owner);
        final ref = col.doc(meal.id);
        writes.add((batch) => batch.set(ref, data, SetOptions(merge: true)));
      }

      for (var start = 0; start < writes.length; start += maxBatchOperations) {
        final end = (start + maxBatchOperations).clamp(0, writes.length);
        final batch = db.batch();
        for (var i = start; i < end; i++) {
          writes[i](batch);
        }
        await batch.commit();
      }
      SyncStatusService.instance.reportSuccess();
    } catch (e) {
      debugPrint('MealSyncService.syncAllMeals failed: $e');
      SyncStatusService.instance.reportFailure('Bulk meal sync failed');
    }
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
        'habits': (data['habits'] as List?)?.cast<Map<String, dynamic>>() ?? [],
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
  static Future<bool> syncRecentFoods(
    List<Map<String, dynamic>> foodsJson,
  ) async {
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
