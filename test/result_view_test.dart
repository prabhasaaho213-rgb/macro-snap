import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/screens/result_screen.dart';

/// Pins the view-mode behavior: tapping a logged meal on Home opens
/// ResultScreen with [existingMeal] set, which must render the meal's stored
/// nutrition in the same layout as a scan result — without running an AI
/// analysis, and without the edit/log actions (the meal is already logged).
void main() {
  testWidgets('view mode shows logged meal nutrition, no analysis/actions', (
    tester,
  ) async {
    final meal = MealRecord(
      id: 'm1',
      date: DateTime.now(),
      name: 'Chocolate Cake',
      category: '',
      calories: 371,
      protein: 5.2,
      carbs: 48.0,
      fats: 18.5,
      fiber: 2.1,
      serving: 'A whole chocolate cake topped with slices',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(imagePath: '', existingMeal: meal),
      ),
    );
    // The entrance animation must settle before asserting on visible text.
    await tester.pumpAndSettle();

    // Same nutrition layout as right after a scan. The four highlighted
    // macros live in the 2×2 tiles above; "Nutrition Details" keeps only
    // what they do not show (fiber, sugar).
    expect(find.text('Nutrition Details'), findsOneWidget);
    expect(find.text('5.2 g'), findsNothing); // protein nutrient row, gone
    expect(find.text('48.0 g'), findsNothing); // carbs nutrient row, gone
    expect(find.text('18.5 g'), findsNothing); // fats nutrient row, gone
    expect(find.text('2.1 g'), findsOneWidget); // fiber nutrient row

    // View mode = read-only: no gram slider, no edit/log buttons.
    expect(find.text('Total Serving'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Log This Meal'), findsNothing);

    // No AI breakdown framing for an already-logged meal — the stored
    // serving text is shown plainly instead.
    expect(find.text('Meal Description'), findsOneWidget);
    expect(find.textContaining('confidence'), findsNothing);
  });
}
