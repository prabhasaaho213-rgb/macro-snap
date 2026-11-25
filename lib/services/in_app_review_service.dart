import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';

/// Asks for a rating through Play's OWN in-app review sheet.
///
/// This replaces the old launch-counter dialog that said "Rate 5 Stars ⭐". An
/// app telling the user what to rate, before they have a reason to have an
/// opinion, is the pattern Play's policy treats as solicitation — and it is how
/// listings collect ratings that say nothing. Here the ask waits until the
/// third saved meal, so it follows real use of the feature being rated, and the
/// question itself is Play's sheet: it decides whether to appear at all, and
/// the user can rate any score or none.
///
/// Nothing here blocks a save. By the time it runs the meal is persisted and on
/// screen; the call is fire-and-forget, and every failure is swallowed.
class InAppReviewService {
  /// Set once Play's sheet has been requested.
  ///
  /// Device-level on purpose: the review belongs to the phone's Play account,
  /// not to a MacroSnap account, so a second sign-in on the same phone is not a
  /// reason to ask again.
  static const String promptedKey = 'in_app_review_prompted';

  /// Meals that must be saved before the ask: enough use to have an opinion.
  static const int minMealsBeforePrompt = 3;

  /// Test seams. Both default to the real plugin.
  @visibleForTesting
  static Future<bool> Function()? availabilityOverride;
  @visibleForTesting
  static Future<void> Function()? requestOverride;

  @visibleForTesting
  static void resetForTest() {
    availabilityOverride = null;
    requestOverride = null;
  }

  /// Raises Play's review card now, because the user asked for it.
  ///
  /// Used by the Settings "Rate Us" row: a deliberate tap deserves the sheet
  /// in-app instead of a jump to the listing. Returns `false` when Play cannot
  /// show the card here (a sideloaded build, no Play account, quota used for
  /// this version), which is the caller's cue to fall back to the store page.
  ///
  /// The prompted flag is set here too, so a manual ask counts as the one ask
  /// and the automatic prompt does not follow it.
  static Future<bool> requestNow() async {
    try {
      // The app is Android-only, and a Play review sheet means nothing on any
      // other platform (including `flutter test`, for which the host platform
      // is not Android).
      if (defaultTargetPlatform != TargetPlatform.android) return false;

      final available = availabilityOverride != null
          ? await availabilityOverride!()
          : await InAppReview.instance.isAvailable();
      if (!available) {
        // A sideloaded build, or an install Play will not review. Leave the
        // flag alone: burned here, the ask would never happen for a real
        // install.
        return false;
      }

      // Marked BEFORE the request. Play shows the sheet at its own discretion
      // and reports nothing back, so waiting for a result would mean asking
      // again later — the nagging this exists to avoid.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(promptedKey, true);

      final request = requestOverride ?? InAppReview.instance.requestReview;
      await request();
      return true;
    } catch (e, st) {
      logError('InAppReviewService.requestNow', e, st);
      return false;
    }
  }

  /// Called after a meal is saved, with the number saved so far.
  ///
  /// Safe to call on every save: it returns immediately until the threshold,
  /// and after the first ask. It never throws — a store that cannot show a
  /// review sheet must never touch the save path.
  static Future<void> maybeAfterMealSave(int totalMeals) async {
    try {
      if (totalMeals < minMealsBeforePrompt) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(promptedKey) ?? false) return;
      await requestNow();
    } catch (e, st) {
      logError('InAppReviewService.maybeAfterMealSave', e, st);
    }
  }
}
