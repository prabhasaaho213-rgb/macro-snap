import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/meal_record.dart';
import 'auth_http.dart';
import 'crash_reporting.dart';
import 'gemini_service.dart';
import 'meal_image_store.dart';
import 'sync_status_service.dart';
import 'subscription_service.dart';

/// Cloud backup of a meal's photo (Pro, opt-in).
///
/// MacroSnap keeps every meal's local photo only for the configurable
/// [MealImageStore.retention] window — and nothing at all across devices.
/// This service lifts exactly that: when the user turns on Settings →
/// Sync Meal Photos, every newly logged photo is uploaded through our
/// backend into the Firestore document `mealPhotos/{mealId}`, and a restore
/// here (a reinstall, a second device) downloads the ones the account still
/// has. Pro-only on both ends — the upload is gated by the SERVER (the
/// toggle alone would only ever be cosmetic) and the restore by the same
/// account flag.
///
/// Why the backend and not a direct Firestore write: the Pro gate must be
/// server-side, and `firestore.rules` denies clients the whole collection
/// on purpose. [MealSyncService] meals/habits go straight to Firestore;
/// photos go through `GeminiService.serverUrl` with [AuthHttp].
///
/// Everything here is fire-and-forget best effort: a failed upload costs
/// one cloud copy, never the meal, never the log.
class MealPhotoSyncService {
  MealPhotoSyncService._();

  /// Prefs key shared with the Settings tile (settings_screen.dart). "On"
  /// plus Pro is the one switch that decides uploads and restores alike.
  static const String prefKey = 'meal_photo_cloud_sync';

  static Uri _photoUri(String mealId) =>
      Uri.parse('${GeminiService.serverUrl}/meals/$mealId/photo');

  /// Whether photo backup is ON for the signed-in account right now.
  ///
  /// Reads the toggle and the subscription each time, so a Pro window that
  /// lapses mid-session stops uploads on the very next meal without any
  /// listener wiring.
  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool(prefKey) ?? false;
      if (!on) return false;
      return SubscriptionService.instance.isSubscribed;
    } catch (_) {
      return false;
    }
  }

  /// The toggle alone, without the Pro check. Deletion rides on the toggle
  /// only: removing a meal's cloud backup must work even after Pro lapses,
  /// and the backend allows deleting any photo the caller owns.
  static Future<bool> toggleOn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Uploads (or replaces) one meal's photo. No-op when the meal has no
  /// local live photo, when backup is off, or when the account is not Pro.
  static Future<void> uploadForMeal(MealRecord meal) async {
    final path = meal.imagePath;
    if (path == null || path.isEmpty) return;
    try {
      if (!await File(path).exists()) return;
      if (!await enabled()) return;
      final res = await AuthHttp.multipart(
        _photoUri(meal.id),
        fileField: 'image',
        filePath: path,
      );
      if (res.statusCode ~/ 100 == 2) {
        SyncStatusService.instance.reportSuccess();
      }
      // 403 (Pro expired mid-session), 413, 5xx: silently skipped — the
      // local photo is the primary copy and the meal already logged fine.
    } catch (e, st) {
      logError('MealPhotoSyncService.uploadForMeal', e, st);
    }
  }

  /// Deletes the meal's cloud copy after the meal itself was removed. Fires
  /// only when the toggle is on: with backup opted out, the collection may
  /// hold nothing of this account's anyway.
  static Future<void> removeForMeal(String mealId) async {
    try {
      if (!await toggleOn()) return;
      await AuthHttp.delete(_photoUri(mealId));
    } catch (e, st) {
      logError('MealPhotoSyncService.removeForMeal', e, st);
    }
  }

  /// Downloads the meal's cloud photo into local storage and returns the
  /// new path, or null when there is nothing to bring back. Only asked for
  /// meals whose local photo is gone or never existed; a photo restored
  /// here must still be inside the local retention window, or the launch
  /// sweep would erase it again minutes later.
  static Future<String?> downloadForMeal(MealRecord meal) async {
    try {
      if (!await enabled()) return null;
      if (DateTime.now().difference(meal.date) >= MealImageStore.retention) {
        return null;
      }
      final res = await AuthHttp.get(_photoUri(meal.id));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map ? body['data'] : null;
      if (data is! String || data.isEmpty) return null;
      // Awaited so a storage failure lands in the catch below (logged, then
      // null) instead of escaping the caller as an unhandled async error —
      // the whole point of this try block.
      return await MealImageStore.instance.saveBytes(
        mealId: meal.id,
        bytes: base64Decode(data),
        at: meal.date,
      );
    } catch (e, st) {
      logError('MealPhotoSyncService.downloadForMeal', e, st);
      return null;
    }
  }
}
