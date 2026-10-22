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

    test('a sugary drink scores at the bottom', () {
      final score = HealthScore.of(
        caloriesPer100g: 42,
        proteinPer100g: 0,
        carbsPer100g: 10.6,
        fatsPer100g: 0,
        fiberPer100g: 0,
        sugarPer100g: 10.6,
      );

      expect(score.score, 0);
      expect(score.label, 'Heavy');
      expect(score.reasons, contains('Very little protein'));
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
