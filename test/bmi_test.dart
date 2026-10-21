import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/bmi.dart';
import 'package:macro_snap/screens/bmi_screen.dart';
import 'package:macro_snap/services/weight_store.dart';
import 'package:macro_snap/widgets/bmi_gauge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BMI is a health number, so the boundaries matter more than the visuals:
/// every band edge is pinned here, the score is checked against a known
/// example, and the screen is checked to open on the user's own numbers.
void main() {
  group('BmiCalculator.value', () {
    test('computes weight / height²', () {
      // 70 kg at 1.70 m → 24.2
      expect(
        BmiCalculator.value(weightKg: 70, heightCm: 170),
        closeTo(24.22, 0.01),
      );
      // The example on the reference design: 59.28 kg, 5'1" (154.9 cm).
      expect(
        BmiCalculator.value(weightKg: 59.28, heightCm: 154.9),
        closeTo(24.7, 0.1),
      );
    });

    test('rejects impossible inputs instead of dividing by zero', () {
      expect(BmiCalculator.value(weightKg: 0, heightCm: 170), isNull);
      expect(BmiCalculator.value(weightKg: 70, heightCm: 0), isNull);
      expect(BmiCalculator.value(weightKg: -70, heightCm: 170), isNull);
    });
  });

  group('BmiCategory boundaries', () {
    void expectBand(double bmi, BmiCategory expected) {
      expect(BmiCalculator.categoryFor(bmi), expected, reason: 'BMI $bmi');
    }

    test('each cut-off goes to the band below it', () {
      expectBand(15.9, BmiCategory.verySeverelyUnderweight);
      expectBand(16.0, BmiCategory.severelyUnderweight);
      expectBand(16.9, BmiCategory.severelyUnderweight);
      expectBand(17.0, BmiCategory.underweight);
      expectBand(18.4, BmiCategory.underweight);
      expectBand(18.5, BmiCategory.normal);
      expectBand(24.9, BmiCategory.normal);
      expectBand(25.0, BmiCategory.overweight);
      expectBand(29.9, BmiCategory.overweight);
      expectBand(30.0, BmiCategory.obeseI);
      expectBand(34.9, BmiCategory.obeseI);
      expectBand(35.0, BmiCategory.obeseII);
      expectBand(39.9, BmiCategory.obeseII);
      expectBand(40.0, BmiCategory.obeseIII);
      expectBand(60.0, BmiCategory.obeseIII);
    });

    test('bands never overlap', () {
      for (var i = 0; i < BmiCategory.values.length - 1; i++) {
        expect(BmiCategory.values[i].max, BmiCategory.values[i + 1].min);
      }
    });
  });

  group('gauge helpers', () {
    test('position is clamped to the arc', () {
      expect(BmiCalculator.gaugePosition(BmiCalculator.scaleMin), 0);
      expect(BmiCalculator.gaugePosition(BmiCalculator.scaleMax), 1);
      expect(BmiCalculator.gaugePosition(2), 0);
      expect(BmiCalculator.gaugePosition(80), 1);
      expect(
        BmiCalculator.gaugePosition(24.9),
        closeTo(0.41, 0.02),
      );
    });

    test('height reads as feet and inches', () {
      expect(BmiCalculator.formatHeight(155), '5\' 1"');
      expect(BmiCalculator.formatHeight(170), '5\' 7"');
      expect(BmiCalculator.formatHeight(183), '6\' 0"');
    });
  });

  group('BmiScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('opens with the calculator, the score and the legend',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BmiScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull);
      expect(find.text('Calculate\nYour BMI'), findsOneWidget);
      expect(find.text('BMI Calculator'), findsOneWidget);
      // 70 kg / 1.70 m with no profile → the sample numbers.
      expect(find.text('24.2'), findsOneWidget);
      expect(find.text('Normal'), findsWidgets);
      expect(
        find.text('Showing sample numbers — finish your diet profile to use your own.'),
        findsOneWidget,
      );
      // Every band is listed with its range.
      for (final category in BmiCategory.values) {
        expect(find.text(category.label), findsWidgets);
        expect(find.text(category.rangeLabel), findsOneWidget);
      }
    });

    testWidgets('editing the weight recalculates the score live', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BmiScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      await tester.tap(find.text('70 kg'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '90');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // 90 kg at 1.70 m → 31.1, Obese Class I.
      expect(find.text('90 kg'), findsOneWidget);
      expect(find.text('31.1'), findsOneWidget);
      expect(find.text('Obese Class I'), findsWidgets);
    });

    testWidgets('shows the weight trend once there is a history', (
      tester,
    ) async {
      final today = DateTime.now();
      WeightStore.instance.resetForTest();
      await WeightStore.instance.load();
      await WeightStore.instance.record(
        72.4,
        date: today.subtract(const Duration(days: 20)),
      );
      await WeightStore.instance.record(
        71.1,
        date: today.subtract(const Duration(days: 9)),
      );
      await WeightStore.instance.record(70.5, date: today);
      addTearDown(WeightStore.instance.resetForTest);

      await tester.pumpWidget(const MaterialApp(home: BmiScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Your trend'), findsOneWidget);
      expect(find.text('Down 1.9 kg in 20 days'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('72.4 kg'), findsOneWidget, reason: 'high of the window');
      expect(find.text('70.5 kg'), findsWidgets, reason: 'low = now');
    });

    testWidgets('the gauge paints without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BmiGauge(bmi: 24.7, size: 200, animate: false),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
