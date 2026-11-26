import 'dart:async';

import 'dart:convert';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../services/account_partition.dart';
import 'bmi.dart';
import '../services/meal_sync_service.dart';
import '../services/crash_reporting.dart';

enum Goal { loseWeight, maintain, gainMuscle }

enum ActivityLevel { sedentary, light, moderate, active, veryActive }

enum Gender { male, female }

/// Food preference for the suggested meal plan. Vegetarian is the default, so
/// a profile saved before this option existed keeps the plan it already had.
enum DietPreference { vegetarian, nonVegetarian }

class DietProfile {
  /// Absolute daily-intake floors. A "deficit" that lands below these stops
  /// being a diet: below roughly 1200 kcal (women) / 1500 kcal (men) it is very
  /// hard to meet basic nutrient needs without medical supervision. A 45 kg,
  /// 150 cm, 25-year-old woman on a plain TDEE − 500 deficit used to be given
  /// 822 kcal a day; the target is now floored at the larger of BMR and these.
  static const int safeMinimumCaloriesFemale = 1200;
  static const int safeMinimumCaloriesMale = 1500;

  /// Below this the "weight loss" goal is a health risk, not a plan.
  ///
  /// Taken from the BMI scale itself ([BmiCategory.normal] starts here) so the
  /// gate can never drift from the band the BMI screen prints.
  static double get underweightBmi => BmiCategory.normal.min;

  /// Grams of protein per kg of body weight, by goal.
  ///
  /// A deficit sits at the high end of the 1.6–2.0 g/kg range because protein
  /// is what keeps lean mass while calories are down; maintenance takes the
  /// RDA-plus floor for adults who train; a surplus takes the top of the
  /// evidence range.
  static const double proteinPerKgLoss = 1.8;
  static const double proteinPerKgMaintain = 1.6;
  static const double proteinPerKgGain = 2.2;

  /// Absolute ceiling for the daily target.
  ///
  /// Scaling grams by body weight alone gave a 110 kg user 242 g of protein a
  /// day — a number nobody needs, that no plan can make appetising, and that
  /// pushed carbohydrate out of the remaining calories. Above ~2 g/kg the
  /// extra grams stop buying anything.
  static const double maxProteinGrams = 180;

  final double weightKg;
  final double heightCm;
  final int age;
  final Gender gender;
  final Goal goal;
  final ActivityLevel activity;
  final DietPreference diet;
  final String avatar;

  DietProfile({
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.gender,
    required this.goal,
    required this.activity,
    this.diet = DietPreference.vegetarian,
    this.avatar = '😎',
  });

  double get bmr {
    if (gender == Gender.male) {
      return 10 * weightKg + 6.25 * heightCm - 5 * age + 5;
    } else {
      return 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
    }
  }

  double get tdee {
    final multipliers = {
      ActivityLevel.sedentary: 1.2,
      ActivityLevel.light: 1.375,
      ActivityLevel.moderate: 1.55,
      ActivityLevel.active: 1.725,
      ActivityLevel.veryActive: 1.9,
    };
    return bmr * (multipliers[activity] ?? 1.2);
  }

  /// Body-mass index for this profile, or null when the numbers are unusable.
  double? get bmi {
    if (weightKg <= 0 || heightCm <= 0) return null;
    final metres = heightCm / 100;
    final value = weightKg / (metres * metres);
    return value.isFinite ? value : null;
  }

  bool get isUnderweight {
    // Compare the number the UI shows (one decimal) rather than the raw value:
    // 18.47 prints as "18.5", and calling that underweight produced copy that
    // read "Your BMI is 18.5, below the healthy range (18.5–24.9)".
    final value = bmi;
    return value != null && BmiCalculator.isUnderweight(value);
  }

  int get safeMinimumCalories => gender == Gender.male
      ? safeMinimumCaloriesMale
      : safeMinimumCaloriesFemale;

  int get targetCalories {
    final raw = switch (goal) {
      Goal.loseWeight => (tdee - 500).round(),
      Goal.maintain => tdee.round(),
      Goal.gainMuscle => (tdee + 300).round(),
    };
    // The safety floor exists for DEFICITS: never prescribe below BMR or the
    // sex-specific safe minimum, whichever is higher.
    //
    // It is deliberately not applied to maintain/gain. For a small sedentary
    // user whose TDEE is under 1,500, the floor used to RAISE a maintain target
    // above maintenance — "Maintain" handing out a surplus is a worse error
    // than a low-but-truthful maintenance figure, and gain already adds its
    // own surplus on top.
    if (goal != Goal.loseWeight) return raw;
    final floor = math.max(bmr.round(), safeMinimumCalories);
    return raw < floor ? floor : raw;
  }

  /// Protein per kg for this goal, before the ceiling is applied.
  double get proteinPerKg => switch (goal) {
    Goal.loseWeight => proteinPerKgLoss,
    Goal.maintain => proteinPerKgMaintain,
    Goal.gainMuscle => proteinPerKgGain,
  };

  double get targetProtein =>
      math.min(weightKg * proteinPerKg, maxProteinGrams);

  double get targetFats => (targetCalories * 0.25 / 9);

  /// Whatever the protein and fat targets leave, never a negative number.
  ///
  /// The protein ceiling makes this real: without it a very heavy user on a
  /// small calorie budget could see a negative carbohydrate target.
  double get targetCarbs => math.max(
    0,
    (targetCalories - (targetProtein * 4) - (targetFats * 9)) / 4,
  );

  Map<String, dynamic> toJson() => {
    'weightKg': weightKg,
    'heightCm': heightCm,
    'age': age,
    'gender': gender.name,
    'goal': goal.name,
    'activity': activity.name,
    'diet': diet.name,
    'avatar': avatar,
  };

  factory DietProfile.fromJson(Map<String, dynamic> json) {
    final genderName = json['gender'] as String?;
    final goalName = json['goal'] as String?;
    final activityName = json['activity'] as String?;

    return DietProfile(
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 70,
      heightCm: (json['heightCm'] as num?)?.toDouble() ?? 170,
      age: (json['age'] as num?)?.toInt() ?? 28,
      gender: Gender.values.firstWhere(
        (g) => g.name == genderName,
        orElse: () => Gender.male,
      ),
      goal: Goal.values.firstWhere(
        (g) => g.name == goalName,
        // A profile with no saved goal must never inherit "weight loss" by
        // accident — maintain is the neutral default.
        orElse: () => Goal.maintain,
      ),
      activity: ActivityLevel.values.firstWhere(
        (a) => a.name == activityName,
        orElse: () => ActivityLevel.sedentary,
      ),
      // Missing on profiles saved before the option existed - orElse keeps
      // them on the vegetarian plan they were already being shown.
      diet: DietPreference.values.firstWhere(
        (d) => d.name == json['diet'],
        orElse: () => DietPreference.vegetarian,
      ),
      avatar: json['avatar'] as String? ?? '😎',
    );
  }
}

class DietPlanService {
  static final DietPlanService _instance = DietPlanService._();
  static DietPlanService get instance => _instance;
  DietPlanService._();

  DietProfile? _profile;
  DietProfile? get profile => _profile;

  /// The last disk write started by [save]. [load] waits for it, because the
  /// profile editor saves as it closes and Profile re-reads straight after —
  /// without this the read could land mid-write and return the old values.
  static Future<void> _pendingWrite = Future<void>.value();

  /// The account whose profile is in memory. Null until the first [load].
  String? _loadedSuffix;

  Future<void> load() async {
    // Land any write already in flight before reading, or the caller sees the
    // values it just replaced and reports the edit as lost.
    await _pendingWrite;
    var readSucceeded = false;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();
      final suffix = AccountPartition.suffix(
        AccountPartition.activeFromPrefs(prefs),
      );
      // A stale in-memory profile from ANOTHER account must never linger. A
      // re-read for the same account, though, keeps the current profile on
      // screen while the disk (and, on a fresh device, the cloud) answers:
      // blanking it first made Profile paint "No height, weight or goal saved
      // yet" and swap back on every open — the flicker it was reported for.
      if (_loadedSuffix != suffix) _profile = null;
      _loadedSuffix = suffix;
      final file = File(
        '${dir.path}/${AccountPartition.key('diet_profile', suffix)}.json',
      );
      if (!await file.exists() && suffix.isNotEmpty) {
        // One-shot migration: attribute the legacy pre-partitioning file to
        // this account; the move deletes the legacy file so a later
        // different account can never inherit it.
        final legacy = File('${dir.path}/diet_profile.json');
        if (await legacy.exists()) {
          await legacy.rename(file.path);
        }
      }
      if (await file.exists()) {
        _profile = DietProfile.fromJson(jsonDecode(await file.readAsString()));
      }
      readSucceeded = true;
      // Cloud restore: if no local profile, try to fetch from Firestore
      if (_profile == null) {
        final cloudProfile = await MealSyncService.fetchDietProfile();
        if (cloudProfile != null) {
          _profile = DietProfile.fromJson(cloudProfile);
          // Save locally for offline access
          await file.writeAsString(jsonEncode(cloudProfile));
        }
      }
    } catch (e, st) {
      logError('DietPlanService.load', e, st);
      // The local store could not be read at all. Keep what is in memory only
      // when the read itself succeeded above (an absent file is a real answer
      // and the profile stays); a failed read must not present a profile the
      // app cannot vouch for.
      if (!readSucceeded) _profile = null;
    }
  }

  Future<void> save(DietProfile profile) async {
    _profile = profile;
    final write = _writeToDisk(profile);
    _pendingWrite = write.catchError((_) {});
    await write;
  }

  Future<void> _writeToDisk(DietProfile profile) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final prefs = await SharedPreferences.getInstance();
      final suffix = AccountPartition.suffix(
        AccountPartition.activeFromPrefs(prefs),
      );
      final file = File(
        '${dir.path}/${AccountPartition.key('diet_profile', suffix)}.json',
      );
      await file.writeAsString(jsonEncode(profile.toJson()));
      // Auto-sync to cloud (fire-and-forget)
      unawaited(MealSyncService.syncDietProfile(profile.toJson()));
    } catch (e, st) {
      logError('DietPlanService.save', e, st);
    }
  }

  static String goalLabel(Goal g) {
    switch (g) {
      case Goal.loseWeight:
        return 'Weight Loss';
      case Goal.maintain:
        return 'Maintain';
      case Goal.gainMuscle:
        return 'Muscle Gain';
    }
  }

  static String dietLabel(DietPreference d) {
    switch (d) {
      case DietPreference.vegetarian:
        return 'Vegetarian';
      case DietPreference.nonVegetarian:
        return 'Non-Vegetarian';
    }
  }

  static String activityLabel(ActivityLevel a) {
    switch (a) {
      case ActivityLevel.sedentary:
        return 'Sedentary (desk job)';
      case ActivityLevel.light:
        return 'Light (1-2 days/week)';
      case ActivityLevel.moderate:
        return 'Moderate (3-5 days/week)';
      case ActivityLevel.active:
        return 'Active (6-7 days/week)';
      case ActivityLevel.veryActive:
        return 'Very Active (twice/day)';
    }
  }
}
