import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/calorie_estimate.dart';

void main() {
  group('CalorieEstimate.activeKcal', () {
    test('scales with steps and body weight', () {
      // 0.0005 kcal per kg per step: a 70 kg person walking 10,000 steps.
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: 70), 350);
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: 90), 450);
    });

    test('a short walk reports a small, honest number', () {
      // 49 steps at 70 kg is ~1.7 kcal — nowhere near the 18 kcal a watch
      // might report from heart rate, which is exactly the mix-up this
      // estimate exists to avoid.
      expect(CalorieEstimate.activeKcal(steps: 49, weightKg: 70), 2);
    });

    test('no steps means no figure, so the tile can say so', () {
      expect(CalorieEstimate.activeKcal(steps: null, weightKg: 70), isNull);
      expect(CalorieEstimate.activeKcal(steps: 0, weightKg: 70), isNull);
    });

    test('a missing or absurd weight falls back instead of failing', () {
      final withDefault = CalorieEstimate.activeKcal(
        steps: 10000,
        weightKg: CalorieEstimate.fallbackWeightKg,
      );
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: null), withDefault);
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: double.nan), withDefault);
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: 4), withDefault);
      expect(CalorieEstimate.activeKcal(steps: 10000, weightKg: 900), withDefault);
    });
  });
}
