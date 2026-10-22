import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/health_score.dart';

/// The health score is derived, not asked of the AI — so it has to behave
/// predictably for food everyone has intuition about. These cases pin the
/// direction of the scale: salad high, soda low, and the middle stays middle.
void main() {
  group('HealthScore', () {
    test('a lean, high-fibre dish earns full marks', () {
      // Grilled chicken salad, per 100 g.
      final score = HealthScore.of(
        caloriesPer100g: 117,
        proteinPer100g: 12,
        carbsPer100g: 5,
        fatsPer100g: 3.3,
        fiberPer100g: 3.5,
        sugarPer100g: 2,
      );

      expect(score.score, 5);
      expect(score.label, 'Excellent');
      expect(score.isExcellent, isTrue);
      expect(score.reasons, contains('High protein'));
      expect(score.reasons, contains('Good fibre'));
    });

    test('a sugary drink is judged on its sugar, not on missing protein', () {
      // A cola: 10.6 g sugar per 100 ml. It is docked for the sugar — that is
      // the whole point — but not for "very little protein" or "low fibre",
      // which no drink is expected to carry.
      final score = HealthScore.of(
        caloriesPer100g: 42,
        proteinPer100g: 0,
        carbsPer100g: 10.6,
        fatsPer100g: 0,
        fiberPer100g: 0,
        sugarPer100g: 10.6,
      );

      expect(score.score, 2);
      expect(score.label, 'Indulgent');
      expect(score.reasons, contains('High sugar'));
      expect(score.reasons, isNot(contains('Very little protein')));
      expect(score.reasons, isNot(contains('Low fibre')));
    });

    test('a dish with no data is not scored at all, not praised', () {
      // The backend turns missing numbers into 0, so a failed identification
      // arrives as all-zero macros. It used to match the "zero-calorie drink"
      // rule and come back 5/5 Excellent — the best score for knowing nothing.
      final zero = HealthScore.of(caloriesPer100g: 0, proteinPer100g: 0);
      expect(zero.scored, isFalse);
      expect(zero.label, 'Not scored');
      expect(zero.fraction, '—');
      expect(zero.isExcellent, isFalse);
    });

    test('a dish the model could not name is not scored', () {
      // Real-looking macros, but the name is "Unknown": we do not know what it
      // is, so the card shows a dash rather than a confident verdict.
      final unknown = HealthScore.of(
        name: 'Unknown',
        caloriesPer100g: 250,
        proteinPer100g: 12,
      );
      expect(unknown.scored, isFalse);
      expect(unknown.label, 'Not scored');

      // Case and whitespace do not make it "identified".
      expect(
        HealthScore.of(
          name: '  unknown ',
        caloriesPer100g: 250,
          proteinPer100g: 12,
        ).scored,
        isFalse,
      );
    });

    test('a name alone does not rescue a dish with no numbers', () {
      // "Water" and a failed scan look identical in the data (all zeros), and
      // there is no honest way to tell them apart — so neither gets a verdict.
      final water = HealthScore.of(
        name: 'Water',
        caloriesPer100g: 0,
        proteinPer100g: 0,
      );
      expect(water.scored, isFalse, reason: 'no numbers to judge');
    });

    test('milk is not treated as junk food', () {
      // Whole milk, per 100 ml: it has no fibre and little protein per 100 g,
      // but neither is a fault in a drink.
      final score = HealthScore.of(
        caloriesPer100g: 61,
        proteinPer100g: 3.4,
        carbsPer100g: 4.8,
        fatsPer100g: 3.3,
        fiberPer100g: 0,
        sugarPer100g: 4.8,
      );
      expect(score.score, 3);
      expect(score.label, 'Fair');
    });

    test('lean protein is not docked for low fibre', () {
      // Chicken breast and eggs carry no carbohydrate, so no fibre — that is
      // not a flaw, and it used to cap every low-carb food at 3/5.
      final chicken = HealthScore.of(
        caloriesPer100g: 165,
        proteinPer100g: 31,
        carbsPer100g: 0,
        fatsPer100g: 3.6,
        fiberPer100g: 0,
      );
      expect(chicken.score, 4);
      expect(chicken.reasons, contains('High protein'));
      expect(chicken.reasons, isNot(contains('Low fibre')));

      final eggs = HealthScore.of(
        caloriesPer100g: 155,
        proteinPer100g: 13,
        carbsPer100g: 1.1,
        fatsPer100g: 11,
        fiberPer100g: 0,
      );
      expect(eggs.score, 4);
    });

    test('carb-heavy food with no fibre is still docked', () {
      // White bread: this is where the fibre penalty belongs.
      final score = HealthScore.of(
        caloriesPer100g: 265,
        proteinPer100g: 9,
        carbsPer100g: 49,
        fatsPer100g: 3.2,
        fiberPer100g: 0.5,
      );
      expect(score.score, 2);
      expect(score.reasons, contains('Low fibre'));
    });

    test('an ordinary dish lands in the middle', () {
      final score = HealthScore.of(
        caloriesPer100g: 200,
        proteinPer100g: 6,
        carbsPer100g: 25,
        fatsPer100g: 8,
        fiberPer100g: 2,
        sugarPer100g: 3,
      );

      expect(score.score, 3, reason: 'nothing is extreme, so nothing moves');
      expect(score.label, 'Fair');
      expect(score.reasons, isEmpty);
    });

    test('very fatty, dense, high-sugar food is penalised', () {
      final score = HealthScore.of(
        caloriesPer100g: 600,
        proteinPer100g: 6,
        carbsPer100g: 45,
        fatsPer100g: 45,
        fiberPer100g: 2,
        sugarPer100g: 20,
      );

      expect(score.score, 0);
      expect(score.reasons, contains('Very high fat'));
      expect(score.reasons, contains('Very energy dense'));
      expect(score.reasons, contains('High sugar'));
    });

    test('a sugary dessert is penalised twice, never praised', () {
      final cake = HealthScore.of(
        caloriesPer100g: 350,
        proteinPer100g: 5,
        carbsPer100g: 50,
        fatsPer100g: 15,
        fiberPer100g: 1,
        sugarPer100g: 35,
      );
      expect(cake.score, 1);
      expect(cake.reasons, contains('High sugar'));
      expect(cake.reasons, contains('Very high sugar'));
      expect(cake.label, 'Indulgent');
    });

    test('the score never leaves 0–5 and formats as n/5', () {
      for (final calories in [0, 100, 300, 500, 900]) {
        final score = HealthScore.of(
          caloriesPer100g: calories.toDouble(),
          proteinPer100g: 0,
          fiberPer100g: 0,
          sugarPer100g: 40,
          fatsPer100g: 50,
        );
        expect(score.score, inInclusiveRange(0, HealthScore.max));
        expect(score.fraction, '${score.score}/5');
      }
    });
  });

  group('Tastiness', () {
    test('ids round-trip, unknown and empty ids are null', () {
      for (final value in Tastiness.values) {
        expect(Tastiness.fromId(value.id), value);
      }
      expect(Tastiness.fromId(null), isNull);
      expect(Tastiness.fromId(''), isNull);
      expect(Tastiness.fromId('spicy'), isNull);
    });

    test('copy is the three-way verdict, never a weight-loss signal', () {
      expect(Tastiness.values.map((t) => t.label), [
        'Delicious',
        'Just okay',
        'Not for me',
      ]);
    });
  });
}
