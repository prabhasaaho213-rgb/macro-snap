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
  /// 0 (worst) to 5 (best). Meaningless when [scored] is false.
  final int score;

  /// False when there is nothing to score — the dish was not identified, or no
  /// nutrition numbers came back at all. Such a card shows "—", not a verdict:
  /// "5/5 Excellent" for a plate of zeros is worse than saying nothing.
  final bool scored;

  /// Human-readable reasons, strongest signal first. Empty for a perfect 5.
  final List<String> reasons;

  const HealthScore(this.score, this.reasons, {this.scored = true});

  /// Nothing to judge. [score] carries no meaning.
  static const HealthScore unscored = HealthScore(0, [], scored: false);

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
    String? name,
  }) {
    // ── Nothing to score ────────────────────────────────────────────────
    // The backend turns missing numbers into 0, so a failed identification
    // arrives as a dish called "Unknown" with all-zero macros. The rule that
    // recognises a zero-calorie drink then matched it and awarded 5/5
    // "Excellent" — the best possible score for knowing nothing.
    final named = name?.trim().toLowerCase();
    if (named == 'unknown' || named == '') return unscored;
    if (caloriesPer100g <= 0 &&
        proteinPer100g <= 0 &&
        carbsPer100g <= 0 &&
        fatsPer100g <= 0) {
      return unscored;
    }

    // A drink is mostly water: low energy, little protein, little fat. It is
    // scored on what is IN it (sugar) rather than judged like a meal. Without
    // this, water scored 1/5 for having no protein and no fibre, and milk
    // scored 2/5 — a scale that calls milk bad teaches the user to ignore it.
    final isDrink = caloriesPer100g <= 60 &&
        proteinPer100g < 6 &&
        fatsPer100g <= 4;

    // Neutral start: an unknown dish is neither praised nor punished.
    var score = 3;
    final reasons = <String>[];

    if (proteinPer100g >= 10) {
      score++;
      reasons.add('High protein');
    } else if (proteinPer100g < 3 && !isDrink) {
      // A drink is not expected to carry protein, so its absence is not a
      // fault — only a food that should have some is penalised for lacking it.
      score--;
      reasons.add('Very little protein');
    }

    if (fiberPer100g >= 3) {
      score++;
      reasons.add('Good fibre');
    } else if (fiberPer100g < 1 && carbsPer100g >= 15) {
      // Fibre is only expected where there are carbohydrates to carry it. A
      // steak, eggs and cheese have none, and docking them for "low fibre"
      // made every low-carb food look worse than a pastry.
      score--;
      reasons.add('Low fibre');
    }

    // 10 g/100 g is the line for a drink (a cola is ~10.6) and for a dessert;
    // a savoury dish rarely crosses it. 25 g is confectionery.
    if (sugarPer100g >= 10) {
      score--;
      reasons.add('High sugar');
    }
    if (sugarPer100g >= 25) {
      score--;
      reasons.add('Very high sugar');
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
    if (!scored) return 'Not scored';
    if (score >= 5) return 'Excellent';
    if (score == 4) return 'Good';
    if (score == 3) return 'Fair';
    // "Indulgent" describes the food, not the person eating it. "Heavy" read
    // like a comment on the user, and it was also wrong for water and milk.
    return 'Indulgent';
  }

  /// True when the dish earns the full five — used to pick the badge colour.
  bool get isExcellent => scored && score >= 5;

  /// "4/5" — the exact form the card shows. A dash when there is no score.
  String get fraction => scored ? '$score/$max' : '—';
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
