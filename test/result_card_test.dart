import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/screens/result_screen.dart';
import 'package:macro_snap/widgets/nutrition_tile.dart';

/// The result card is the screen users see after every scan, so its shape is
/// pinned here: a health verdict, the 2×2 macro grid, an ingredient breakdown
/// and a tastiness verdict — plus no editors when the meal is already logged.
void main() {
  MealRecord salad() => MealRecord(
    id: 'm1',
    date: DateTime.now(),
    name: 'Grilled Chicken Salad',
    category: '',
    calories: 350,
    protein: 35,
    carbs: 15,
    fats: 10,
    fiber: 4,
    serving: 'A bowl of salad',
  );

  Future<void> pump(WidgetTester tester, MealRecord meal) async {
    await tester.pumpWidget(
      MaterialApp(home: ResultScreen(imagePath: '', existingMeal: meal)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('card shows the health score, four macro tiles and ingredients', (
    tester,
  ) async {
    await pump(tester, salad());

    // Title.
    expect(find.text('Grilled Chicken Salad'), findsWidgets);

    // Health score: lean + high fibre ⇒ full marks.
    expect(find.text('Health Score: '), findsOneWidget);
    expect(find.text('5/5'), findsOneWidget);
    expect(find.textContaining('Excellent'), findsOneWidget);

    // The 2×2 grid, one tile per macro. Scoped to the tiles because the
    // "Nutrition Details" list below intentionally repeats the same labels.
    expect(find.byType(NutritionTile), findsNWidgets(4));
    Finder inTile(String text) => find.descendant(
      of: find.byType(NutritionTile),
      matching: find.text(text),
    );
    for (final label in ['Calories', 'Carbs', 'Proteins', 'Fats']) {
      expect(inTile(label), findsOneWidget, reason: '$label tile');
    }
    expect(inTile('350'), findsOneWidget); // calories
    expect(inTile('15'), findsOneWidget); // carbs
    expect(inTile('35'), findsOneWidget); // protein
    expect(inTile('10'), findsOneWidget); // fats

    // Ingredient breakdown: the dish's weight and its own score.
    expect(find.text('INGREDIENTS'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);

    // Tastiness verdict is offered on every result.
    expect(find.text('Tastiness'), findsOneWidget);
    expect(find.text('Delicious'), findsOneWidget);
    expect(find.text('Just okay'), findsOneWidget);
    expect(find.text('Not for me'), findsOneWidget);
  });

  testWidgets('a logged meal is read-only: no pencils, no Edit button', (
    tester,
  ) async {
    await pump(tester, salad());

    expect(
      find.byType(EditPencil),
      findsNothing,
      reason: 'a logged meal must not pretend its numbers can be edited',
    );
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('a tile pencil calls back, and is absent without onEdit', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: NutritionTile(
                label: 'Proteins',
                value: '35',
                unit: 'g',
                color: Colors.red,
                icon: Icons.fitness_center_rounded,
                onEdit: () => edits++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditPencil));
    expect(edits, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: NutritionTile(
                label: 'Proteins',
                value: '35',
                unit: 'g',
                color: Colors.red,
                icon: Icons.fitness_center_rounded,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(EditPencil), findsNothing);
  });

  test('tastiness survives a save/load round-trip, and old meals stay valid', () {
    final rated = salad().toJson()
      ..['tastiness'] = 'delicious';
    expect(MealRecord.fromJson(rated).tastiness, 'delicious');

    // A meal logged before tastiness existed has neither the key nor a value.
    final old = salad().toJson()..remove('tastiness');
    expect(MealRecord.fromJson(old).tastiness, isNull);
    expect(MealRecord.fromJson(old).name, 'Grilled Chicken Salad');
  });
}
