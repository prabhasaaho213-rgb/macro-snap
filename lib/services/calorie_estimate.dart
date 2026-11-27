/// Estimates the energy burned from the steps the phone counted.
///
/// Health Connect is the source of truth when it is connected — it knows about
/// the watch, the record start times and the platform's own totals. Without it
/// the app still owes the user a burn figure, so this derives one from the two
/// things it does have: the steps its own sensor counted and the weight on the
/// diet profile.
///
/// The constant is the walking energy cost per kilogram per step. Level
/// walking costs roughly 1 kcal per kg per kilometre and a step covers about
/// 0.7 m, which puts a step near 0.0007 kcal/kg — a little high for slow
/// walking, a little low for brisk. 0.0005 is used deliberately: it errs
/// conservative rather than over-reporting a burn the user would then eat back.
class CalorieEstimate {
  CalorieEstimate._();

  /// Kilocalories per kilogram of body weight per step.
  static const double kcalPerKgPerStep = 0.0005;

  /// Used when the profile holds no usable weight, so the tile still answers
  /// instead of showing a dash for a user who simply skipped that step.
  static const double fallbackWeightKg = 70;

  /// Active kilocalories for [steps], or null when nothing has been counted.
  ///
  /// [weightKg] comes from the diet profile. An absent, non-finite or absurd
  /// value falls back to [fallbackWeightKg] rather than returning nothing.
  static int? activeKcal({required int? steps, required double? weightKg}) {
    if (steps == null || steps <= 0) return null;
    final weight =
        (weightKg != null &&
            weightKg.isFinite &&
            weightKg > 20 &&
            weightKg < 400)
        ? weightKg
        : fallbackWeightKg;
    return (steps * weight * kcalPerKgPerStep).round();
  }
}
