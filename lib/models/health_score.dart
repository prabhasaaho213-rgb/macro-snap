/// The two ratings on a result card: a 0–5 health score derived from the
/// nutrition numbers, and the user's own tastiness verdict.
///
/// Why the health score is computed rather than asked of the AI: the backend
/// already returns per-100 g calories, protein, carbs, fats, fiber and sugar,
/// so a score built from those is reproducible, unit-tested and impossible to
/// hallucinate. An "AI says 5/5" number would be unexplainable to the user and
/// could disagree with the macros printed right beside it.
library;

/// A 0–5 health score with the reasons behind it.
///
/// The scale is deliberately blunt (0–5 like the reference card), because it
/// is a nudge, not a diagnosis: it rewards protein and fibre, and penalises
/// added sugar, very high fat and extreme energy density. Every rule is listed
/// in [reasons], so the score can be explained instead of asserted.
class HealthScore {
  /// 0 (worst) to 5 (best).
  final int score;

  /// Human-readable reasons, strongest signal first. Empty for a perfect 5.
  final List<String> reasons;

  const HealthScore(this.score, this.reasons);

  static const int max = 5;

  /// Scores per-100 g so it is independent of how much the user ate — a huge
  /// portion of a good dish must not read as an unhealthy dish.
  factory HealthScore.of({
    required double caloriesPer100g,
    required double proteinPer100g,
    double carbsPer100g = 0,
    double fatsPer100g = 0,
    double fiberPer100g = 0,
    double sugarPer100g = 0,
  }) {
    // Neutral start: an unknown dish is neither praised nor punished.
    var score = 3;
    final reasons = <String>[];

    if (proteinPer100g >= 10) {
      score++;
      reasons.add('High protein');
    } else if (proteinPer100g < 3) {
      score--;
      reasons.add('Very little protein');
    }

    if (fiberPer100g >= 3) {
      score++;
      reasons.add('Good fibre');
    } else if (fiberPer100g < 1) {
      score--;
      reasons.add('Low fibre');
    }

    // 10 g/100 g is the line for a drink (a cola is ~10.6) and for a dessert;
    // a savoury dish rarely crosses it.
    if (sugarPer100g >= 10) {
      score--;
      reasons.add('High sugar');
    }

    if (fatsPer100g >= 25) {
      score--;
      reasons.add('Very high fat');
    }

    if (caloriesPer100g >= 400) {
      score--;
      reasons.add('Very energy dense');
    }

    return HealthScore(
      score.clamp(0, max),
      List<String>.unmodifiable(reasons),
    );
  }

  /// Short verdict shown next to the score.
  String get label {
    if (score >= 5) return 'Excellent';
    if (score == 4) return 'Good';
    if (score == 3) return 'Fair';
    return 'Heavy';
  }

  /// True when the dish earns the full five — used to pick the badge colour.
  bool get isExcellent => score >= 5;

  /// "4/5" — the exact form the card shows.
  String get fraction => '$score/$max';
}

/// The user's own verdict on how the dish tasted.
///
/// This is feedback, not a judgement of the person: it is stored on the logged
/// meal and is never used to gate, rank or nag. Nothing here rewards weight
/// loss — the only thing a rating can do is make future suggestions better.
enum Tastiness {
  delicious('delicious', 'Delicious'),
  okay('okay', 'Just okay'),
  bland('bland', 'Not for me');

  const Tastiness(this.id, this.label);

  /// Stable key for persistence; never rename an existing value.
  final String id;

  /// Copy shown on the pill.
  final String label;

  static Tastiness? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final value in Tastiness.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}
