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

/// Which health permissions this app actually holds.
///
/// Health Connect grants access per record type, and a device can refuse one
/// type while allowing the rest. Checking the three types as one list —
/// `hasPermissions([STEPS, TOTAL, ACTIVE])` — answers "are ALL of these
/// granted?", so a phone that does not grant total-calories (most of them:
/// many devices never write that record) reported the whole dashboard as
/// disconnected on every launch, even though steps and active energy were
/// granted. Hence one flag per type.
class HealthAccess {
  final bool steps;
  final bool activeEnergy;
  final bool totalEnergy;
  final bool nutritionWrite;

  const HealthAccess({
    this.steps = false,
    this.activeEnergy = false,
    this.totalEnergy = false,
    this.nutritionWrite = false,
  });

  const HealthAccess.none()
    : steps = false,
      activeEnergy = false,
      totalEnergy = false,
      nutritionWrite = false;

  /// True when at least one activity figure can be read. This — not
  /// "everything was granted" — is what makes the dashboard connected.
  bool get canReadActivity => steps || activeEnergy || totalEnergy;
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

  /// Asks the platform whether ONE type is granted.
  ///
  /// Each check is its own call because Health Connect answers
  /// "all of the listed types?" — and throws when the list contains a type
  /// this build is not allowed to request. A throw is reported as "not
  /// granted" rather than being allowed to fail the whole check.
  Future<bool> _has(HealthDataType type) async {
    try {
      final result = await _health.hasPermissions([type]);
      return result ?? false;
    } catch (e, st) {
      debugHealthError('hasPermissions(${type.name})', e, st);
      return false;
    }
  }

  /// Which of the three activity permissions (and the nutrition write) are
  /// currently granted.
  Future<HealthAccess> checkAccess() async {
    if (!isPlatformSupported) return const HealthAccess.none();
    final steps = await _has(HealthDataType.STEPS);
    final active = await _has(HealthDataType.ACTIVE_ENERGY_BURNED);
    final total = await _has(HealthDataType.TOTAL_CALORIES_BURNED);
    final nutrition = await _has(HealthDataType.NUTRITION);
    return HealthAccess(
      steps: steps,
      activeEnergy: active,
      totalEnergy: total,
      nutritionWrite: nutrition,
    );
  }

  /// Whether the user has already granted MacroSnap read access to steps and
  /// calories burned.
  ///
  /// Best-effort: returns false if the platform is unreachable, the SDK is
  /// missing, or permission was never granted / was revoked.
  Future<bool> get hasReadPermission async =>
      (await checkAccess()).canReadActivity;

  /// Requests one type, swallowing the platform's refusal.
  ///
  /// Requesting a SET of types is all-or-nothing in the same way the check is:
  /// one type the device will not grant (or a build that forgot the matching
  /// manifest permission) made [requestAuthorization] answer false even after
  /// the user tapped "Allow" on steps. One call per type means a partial grant
  /// is reported as the partial grant it really is.
  Future<bool> _request(HealthDataType type, HealthDataAccess access) async {
    try {
      return await _health.requestAuthorization([type], permissions: [access]);
    } catch (e, st) {
      debugHealthError('requestAuthorization(${type.name})', e, st);
      return false;
    }
  }

  /// Ask the user to grant read access to steps + calories burned.
  ///
  /// Everything still missing is requested in ONE dialog (Health Connect shows
  /// a single permission sheet for the whole set), then the grants are
  /// re-checked type by type. If that combined request is refused outright —
  /// one type this device does not support can do that — steps is asked for on
  /// its own, because a dashboard that shows steps is still useful.
  ///
  /// The nutrition write is requested too, but a refused write never makes the
  /// read side look disconnected.
  Future<bool> requestReadPermissions() async {
    if (!isPlatformSupported) return false;
    final access = await checkAccess();
    if (access.canReadActivity) return true;

    final types = <HealthDataType>[];
    final grants = <HealthDataAccess>[];
    if (!access.steps) {
      types.add(HealthDataType.STEPS);
      grants.add(HealthDataAccess.READ);
    }
    if (!access.activeEnergy) {
      types.add(HealthDataType.ACTIVE_ENERGY_BURNED);
      grants.add(HealthDataAccess.READ);
    }
    if (!access.totalEnergy) {
      types.add(HealthDataType.TOTAL_CALORIES_BURNED);
      grants.add(HealthDataAccess.READ);
    }
    if (!access.nutritionWrite) {
      types.add(HealthDataType.NUTRITION);
      grants.add(HealthDataAccess.WRITE);
    }
    if (types.isEmpty) return true;

    try {
      await _health.requestAuthorization(types, permissions: grants);
    } catch (e, st) {
      debugHealthError('requestAuthorization(all)', e, st);
    }

    // A granted dialog is not proof the platform recorded the grant (revoked
    // mid-session, work profile, ...). This is the same check the dashboard
    // makes on launch, so "connected" means the same thing in both places.
    final fresh = await checkAccess();
    if (fresh.canReadActivity) return true;

    // Steps alone is the last resort: it is the one type the dashboard cannot
    // work without, and the per-type call cannot be sunk by a sibling type.
    if (!fresh.steps) {
      await _request(HealthDataType.STEPS, HealthDataAccess.READ);
    }
    return (await checkAccess()).canReadActivity;
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
  /// [HealthToday.ok] is false only when no read worked at all; a day with no
  /// activity yet is still `ok` with null values.
  ///
  /// Each type is read in its own call. Health Connect throws for the WHOLE
  /// request when a single listed type is not granted, so bundling steps with
  /// two calorie types — one of which most devices never grant — used to make
  /// the step read fail as well and left the dashboard frozen on an old
  /// number whenever the calories permission was missing.
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

    /// Sums one record type, or null when it is unauthorised / has no data.
    Future<double?> sumOf(HealthDataType type) async {
      try {
        final data = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: startOfDay,
          endTime: now,
        );
        if (data.isEmpty) return null;
        var sum = 0.0;
        var found = false;
        for (final d in data) {
          final v = d.value is NumericHealthValue
              ? (d.value as NumericHealthValue).numericValue
              : null;
          if (v != null) {
            sum += v;
            found = true;
          }
        }
        return found ? sum : null;
      } catch (e, st) {
        debugHealthError('fetchToday(${type.name})', e, st);
        return null;
      }
    }

    activeCalories = await sumOf(HealthDataType.ACTIVE_ENERGY_BURNED);
    totalCalories = await sumOf(HealthDataType.TOTAL_CALORIES_BURNED);
    if (totalCalories != null || activeCalories != null) ok = true;

    // Last resort for steps: if the platform total failed, fall back to the
    // step records themselves so a phone whose aggregate call is unavailable
    // still reports movement.
    if (steps == null) {
      final recordSum = await sumOf(HealthDataType.STEPS);
      if (recordSum != null) {
        steps = recordSum.round();
        ok = true;
      }
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
