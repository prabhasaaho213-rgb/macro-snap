import 'package:flutter/material.dart';

/// BMI bands, in the order they appear on the gauge and in the legend.
///
/// The ranges match the WHO cut-offs that Indian health apps use, including the
/// narrow 16.0–16.9 and 17.0–18.4 bands, so the score lands in the same place
/// here as in any other calculator the user has seen.
enum BmiCategory {
  verySeverelyUnderweight,
  severelyUnderweight,
  underweight,
  normal,
  overweight,
  obeseI,
  obeseII,
  obeseIII,
}

extension BmiCategoryInfo on BmiCategory {
  String get label => switch (this) {
    BmiCategory.verySeverelyUnderweight => 'Very Severely Underweight',
    BmiCategory.severelyUnderweight => 'Severely Underweight',
    BmiCategory.underweight => 'Underweight',
    BmiCategory.normal => 'Normal',
    BmiCategory.overweight => 'Overweight',
    BmiCategory.obeseI => 'Obese Class I',
    BmiCategory.obeseII => 'Obese Class II',
    BmiCategory.obeseIII => 'Obese Class III',
  };

  /// Printed exactly as the legend shows it.
  String get rangeLabel => switch (this) {
    BmiCategory.verySeverelyUnderweight => '< 16.0',
    BmiCategory.severelyUnderweight => '16.0 - 16.9',
    BmiCategory.underweight => '17.0 - 18.4',
    BmiCategory.normal => '18.5 - 24.9',
    BmiCategory.overweight => '25.0 - 29.9',
    BmiCategory.obeseI => '30.0 - 34.9',
    BmiCategory.obeseII => '35.0 - 39.9',
    BmiCategory.obeseIII => '40.0 <',
  };

  /// Lower bound of the band (inclusive).
  double get min => switch (this) {
    BmiCategory.verySeverelyUnderweight => 0,
    BmiCategory.severelyUnderweight => 16,
    BmiCategory.underweight => 17,
    BmiCategory.normal => 18.5,
    BmiCategory.overweight => 25,
    BmiCategory.obeseI => 30,
    BmiCategory.obeseII => 35,
    BmiCategory.obeseIII => 40,
  };

  /// Upper bound (exclusive), so adjacent bands never overlap.
  double get max => switch (this) {
    BmiCategory.verySeverelyUnderweight => 16,
    BmiCategory.severelyUnderweight => 17,
    BmiCategory.underweight => 18.5,
    BmiCategory.normal => 25,
    BmiCategory.overweight => 30,
    BmiCategory.obeseI => 35,
    BmiCategory.obeseII => 40,
    BmiCategory.obeseIII => 100,
  };

  /// Band colour. Deliberately its own ramp rather than the macro colours:
  /// blue → green → amber → red reads as a scale at a glance, and the
  /// highlighted legend row repeats the exact hue from the gauge.
  Color get color => switch (this) {
    BmiCategory.verySeverelyUnderweight => const Color(0xFF2F80ED),
    BmiCategory.severelyUnderweight => const Color(0xFF56CCF2),
    BmiCategory.underweight => const Color(0xFF9B7BFF),
    BmiCategory.normal => const Color(0xFF2FA45F),
    BmiCategory.overweight => const Color(0xFFF4A340),
    BmiCategory.obeseI => const Color(0xFFF2703F),
    BmiCategory.obeseII => const Color(0xFFE8489B),
    BmiCategory.obeseIII => const Color(0xFFC81E3A),
  };

  /// Short, friendly line under the score — the label alone ("Overweight") is
  /// a diagnosis, this says what it means for the user's plan.
  String get advice => switch (this) {
    BmiCategory.verySeverelyUnderweight =>
      'Very low for your height. Worth talking to a doctor.',
    BmiCategory.severelyUnderweight =>
      'Low for your height — build up steadily with calorie-dense meals.',
    BmiCategory.underweight =>
      'A little under the healthy range. A small surplus helps.',
    BmiCategory.normal => 'Right in the healthy range. Keep it up.',
    BmiCategory.overweight =>
      'Just above the healthy range — a small deficit goes a long way.',
    BmiCategory.obeseI => 'Above the healthy range. Steady, sustainable losses win.',
    BmiCategory.obeseII =>
      'Well above the healthy range. A plan and a doctor make this easier.',
    BmiCategory.obeseIII =>
      'High for your height. Please work with a doctor on this.',
  };
}

/// Pure BMI maths — no widgets, no storage, so the boundaries can be tested
/// directly instead of through the UI.
class BmiCalculator {
  /// The gauge's own scale. Below 13 and above 42 the needle would sit in the
  /// caps, so the marker is clamped rather than drawn off the arc.
  static const double scaleMin = 13;
  static const double scaleMax = 42;

  /// `weight / height²`, or null when the inputs cannot make sense.
  static double? value({required double weightKg, required double heightCm}) {
    if (weightKg <= 0 || heightCm <= 0) return null;
    final metres = heightCm / 100;
    final bmi = weightKg / (metres * metres);
    if (bmi.isNaN || bmi.isInfinite) return null;
    return bmi;
  }

  static BmiCategory categoryFor(double bmi) {
    for (final category in BmiCategory.values) {
      if (bmi < category.max) return category;
    }
    return BmiCategory.obeseIII;
  }

  /// Where [bmi] sits on the 0..1 gauge scale.
  static double gaugePosition(double bmi) =>
      ((bmi - scaleMin) / (scaleMax - scaleMin)).clamp(0.0, 1.0);

  /// Height in the feet/inches form the card shows next to the score.
  static String formatHeight(double heightCm) {
    if (heightCm <= 0) return '—';
    final totalInches = (heightCm / 2.54).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return "$feet' $inches\"";
  }
}
