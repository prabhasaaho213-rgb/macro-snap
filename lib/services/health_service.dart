import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Thin wrapper around the `health` package (Health Connect on Android,
/// HealthKit on iOS) so the rest of the app never touches HealthDataType
/// constants directly.
///
/// For now MacroSnap only needs three things from health data:
///   * read today's step count
///   * read today's calories burned (total, including BMR)
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
  /// `health` plugin at all (Android or iOS). Web/desktop always false.
  bool get isPlatformSupported => true;

  /// Quick check whether Health Connect (Android) or HealthKit (iOS) is
  /// reachable on this device. Returns true only when the SDK is present and
  /// the app can actually talk to it.
  ///
  /// On Android 13 and lower this also implies the separate Health Connect
  /// app from Play Store is installed (or the OS has it built in).
  Future<bool> get isHealthAvailable => _health.isHealthConnectAvailable();

  /// The kinds of health data MacroSnap reads or writes.
  static const _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.TOTAL_CALORIES_BURNED,
  ];

  /// Whether the user has already granted MacroSnap read access to steps and
  /// calories burned.
  ///
  /// Best-effort: returns false if the platform is unreachable, the SDK is
  /// missing, or permission was never granted / was revoked.
  Future<bool> get hasReadPermission async {
    final result = await _health.hasPermissions(_readTypes);
    return result ?? false;
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
    try {
      return await _health.requestAuthorization(_readTypes);
    } catch (e, st) {
      debugHealthError('requestReadPermissions', e, st);
      return false;
    }
  }

  /// Read today's total step count (midnight → now on the device's calendar).
  ///
  /// Returns null when Health Connect / HealthKit is unavailable, permission
  /// was not granted, or no step data exists for today.
  Future<int?> get todaySteps async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final data = await _health.getHealthDataFromTypes(
        types: _readTypes,
        startTime: startOfDay,
        endTime: now,
      );
      final steps =
          data.where((d) => d.type == HealthDataType.STEPS).toList();
      if (steps.isEmpty) return null;
      int total = 0;
      for (final d in steps) {
        final v = d.value is NumericHealthValue
            ? (d.value as NumericHealthValue).numericValue
            : null;
        if (v != null) total += v.toInt();
      }
      return total;
    } catch (e, st) {
      debugHealthError('todaySteps', e, st);
      return null;
    }
  }

  /// Read today's total calories burned (including basal / BMR), in kcal.
  ///
  /// Returns null when Health Connect / HealthKit is unavailable, permission
  /// was not granted, or no calorie data exists for today.
  Future<double?> get todayCaloriesBurned async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final data = await _health.getHealthDataFromTypes(
        types: _readTypes,
        startTime: startOfDay,
        endTime: now,
      );
      final cals = data
          .where((d) => d.type == HealthDataType.TOTAL_CALORIES_BURNED)
          .toList();
      if (cals.isEmpty) return null;
      double total = 0;
      for (final d in cals) {
        final v = d.value is NumericHealthValue
            ? (d.value as NumericHealthValue).numericValue
            : null;
        if (v != null) total += v;
      }
      return total;
    } catch (e, st) {
      debugHealthError('todayCaloriesBurned', e, st);
      return null;
    }
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
