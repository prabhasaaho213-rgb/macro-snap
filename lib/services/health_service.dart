import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// One day's activity, as read from the health platform.
///
/// [steps] is null when no step data exists yet today; [caloriesBurned] is the
/// best available burn figure (total when the platform records it, otherwise
/// active energy — which is what almost every phone and watch actually writes);
/// [activeCalories] is always the active-energy figure on its own, so the
/// dashboard can label the number honestly.
class HealthToday {
  final int? steps;
  final double? caloriesBurned;
  final double? activeCalories;

  /// True when at least one of the reads worked. False means the platform
  /// refused or errored, which the dashboard reports instead of showing a
  /// silent "—".
  final bool ok;

  const HealthToday({
    this.steps,
    this.caloriesBurned,
    this.activeCalories,
    this.ok = true,
  });

  const HealthToday.unavailable()
    : steps = null,
      caloriesBurned = null,
      activeCalories = null,
      ok = false;
}

/// Thin wrapper around the `health` package (Health Connect on Android,
/// HealthKit on iOS) so the rest of the app never touches HealthDataType
/// constants directly.
///
/// MacroSnap needs three things from health data:
///   * read today's step count
///   * read today's calories burned (total, falling back to active energy)
///   * write a nutrition meal log (food intake)
///
/// Everything is best-effort: if Health Connect is unavailable, denied, or
/// the device is too old, the service returns sensible nulls / false and the
/// dashboard shows an empty state instead of throwing.
class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  final Health _health = Health();

  /// Whether the platform this app is running on is supported by the
  /// `health` plugin at all. Web/desktop always false.
  bool get isPlatformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Quick check whether Health Connect (Android) or HealthKit (iOS) is
  /// reachable on this device. Returns true only when the SDK is present and
  /// the app can actually talk to it.
  ///
  /// On Android 13 and lower this also implies the separate Health Connect
  /// app from Play Store is installed (or the OS has it built in).
  Future<bool> get isHealthAvailable async {
    if (!isPlatformSupported) return false;
    try {
      return await _health.isHealthConnectAvailable();
    } catch (e, st) {
      debugHealthError('isHealthAvailable', e, st);
      return false;
    }
  }

  /// The kinds of health data MacroSnap reads.
  ///
  /// TOTAL_CALORIES_BURNED is what we *want* (it includes basal burn), but most
  /// phones and watches only ever write ACTIVE_ENERGY_BURNED — reading just the
  /// total is why the dashboard showed an em dash for calories on most devices
  /// while the phone's own Health Connect app showed a number.
  static const _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// The types we WRITE (a nutrition meal log).
  static const _writeTypes = [HealthDataType.NUTRITION];

  /// Whether the user has already granted MacroSnap read access to steps and
  /// calories burned.
  ///
  /// Best-effort: returns false if the platform is unreachable, the SDK is
  /// missing, or permission was never granted / was revoked.
  Future<bool> get hasReadPermission async {
    if (!isPlatformSupported) return false;
    try {
      final result = await _health.hasPermissions(_readTypes);
      return result ?? false;
    } catch (e, st) {
      debugHealthError('hasReadPermission', e, st);
      return false;
    }
  }

  /// Ask the user to grant read access to steps + calories burned.
  ///
  /// Returns true when the user accepted at least the read permissions.
  /// Returns false when they declined, the SDK is unavailable, or the platform
  /// does not support health data.
  ///
  /// On Android this triggers the Health Connect permission dialog; on iOS it
  /// triggers the HealthKit "allow MacroSnap to read..." dialog.
  Future<bool> requestReadPermissions() async {
    if (!isPlatformSupported) return false;
    try {
      // Explicit access per type: `permissions` defaults differ between
      // platforms, and a write-only nutrition grant must not come back as
      // "connected" while steps and energy stay unreadable.
      return await _health.requestAuthorization(
        [ ..._readTypes, ..._writeTypes ],
        permissions: [
          for (final _ in _readTypes) HealthDataAccess.READ,
          HealthDataAccess.WRITE,
        ],
      );
    } catch (e, st) {
      debugHealthError('requestReadPermissions', e, st);
      return false;
    }
  }

  /// Today's steps from midnight to now.
  ///
  /// Uses the platform's own total (`getTotalStepsInInterval`), which
  /// de-duplicates overlapping records from multiple sources. Summing raw
  /// records — what this used to do — double counted every step that both the
  /// phone and a watch had recorded.
  Future<int?> get todaySteps async {
    final today = await fetchToday();
    return today.steps;
  }

  /// Today's total calories burned, including basal / BMR when the platform
  /// provides it, otherwise active energy.
  Future<double?> get todayCaloriesBurned async {
    final today = await fetchToday();
    return today.caloriesBurned;
  }

  /// Reads everything the dashboard needs in one pass.
  ///
  /// [HealthToday.ok] is false only when a read threw or health access is
  /// unavailable; a day with no activity yet is still `ok` with null values.
  Future<HealthToday> fetchToday() async {
    if (!isPlatformSupported) return const HealthToday.unavailable();
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    int? steps;
    double? totalCalories;
    double? activeCalories;
    var ok = false;

    try {
      final total = await _health.getTotalStepsInInterval(startOfDay, now);
      if (total != null) {
        steps = total;
        ok = true;
      }
    } catch (e, st) {
      debugHealthError('fetchToday(steps)', e, st);
    }

    try {
      final data = await _health.getHealthDataFromTypes(
        types: _readTypes,
        startTime: startOfDay,
        endTime: now,
      );
      if (steps == null) {
        final stepPoints = data
            .where((d) => d.type == HealthDataType.STEPS)
            .toList();
        if (stepPoints.isNotEmpty) {
          var sum = 0.0;
          for (final d in stepPoints) {
            final v = d.value is NumericHealthValue
                ? (d.value as NumericHealthValue).numericValue
                : null;
            if (v != null) sum += v;
          }
          steps = sum.round();
        }
      }

      double? sumOf(HealthDataType type) {
        final points = data.where((d) => d.type == type).toList();
        if (points.isEmpty) return null;
        var sum = 0.0;
        for (final d in points) {
          final v = d.value is NumericHealthValue
              ? (d.value as NumericHealthValue).numericValue
              : null;
          if (v != null) sum += v;
        }
        return sum;
      }

      totalCalories = sumOf(HealthDataType.TOTAL_CALORIES_BURNED);
      activeCalories = sumOf(HealthDataType.ACTIVE_ENERGY_BURNED);
      if (totalCalories != null || activeCalories != null) ok = true;
    } catch (e, st) {
      debugHealthError('fetchToday(calories)', e, st);
    }

    return HealthToday(
      steps: steps,
      // Prefer the total (basal + active); fall back to active energy, which is
      // the only figure most devices write.
      caloriesBurned: totalCalories ?? activeCalories,
      activeCalories: activeCalories,
      ok: ok,
    );
  }

  /// Write a nutrition (food) log into Health Connect / HealthKit.
  ///
  /// [mealName] is the display name (e.g. "Oatmeal + banana").
  /// [calories] is kilocalories for the logged portion.
  /// [protein], [carbs], [fat] are grams.
  ///
  /// Returns true when the write was accepted by the health platform. Returns
  /// false when permission is missing, the platform is unavailable, or the
  /// write was rejected.
  ///
  /// MacroSnap writes nutrition for its own logging; it does not overwrite
  /// other apps' food logs. The meal is recorded as a SNACK by default —
  /// MacroSnap does not split its scans into breakfast / lunch / dinner.
  Future<bool> writeNutrition({
    required String mealName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    if (!isPlatformSupported) return false;
    try {
      final now = DateTime.now();
      return await _health.writeMeal(
        mealType: MealType.SNACK,
        startTime: now,
        endTime: now,
        name: mealName,
        caloriesConsumed: calories,
        protein: protein,
        carbohydrates: carbs,
        fatTotal: fat,
      );
    } catch (e, st) {
      debugHealthError('writeNutrition', e, st);
      return false;
    }
  }
}

/// Log health-service errors to the debug console. The `health` package
/// throws [HealthException] subtypes on platform problems (unavailable,
/// denied, not supported); we swallow them at the call sites and report here
/// so they are visible during development without surfacing to the user.
void debugHealthError(String context, Object error, StackTrace st) {
  if (!kDebugMode) return;
  debugPrint('HealthService.$context: $error');
  if (st != StackTrace.empty) {
    debugPrint(st.toString());
  }
}
