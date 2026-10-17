import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:macro_snap/widgets/calorie_reveal.dart';

/// The calorie reveal spins up from 0 as the AI's answer arrives, and glides
/// quietly when the user later edits the grams. [GoalFit] decides whether the
/// meal earns confetti.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MealStore.instance.reload();
  });

  /// The number currently drawn (the widget's only Text).
  int? shownNumber(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final n = int.tryParse((t.data ?? '').trim());
      if (n != null) return n;
    }
    return null;
  }

  DietProfile profile({
    Goal goal = Goal.loseWeight,
    double weightKg = 70,
  }) =>
      DietProfile(
        weightKg: weightKg,
        heightCm: 175,
        age: 30,
        gender: Gender.male,
        goal: goal,
        activity: ActivityLevel.moderate,
        diet: DietPreference.vegetarian,
      );

  group('CalorieReveal', () {
    testWidgets('spins up from 0 and lands exactly on the target',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: CalorieReveal(calories: 420, protein: 10))),
      ));

      expect(shownNumber(tester), 0, reason: 'the reveal starts at 0');

      await tester.pump(const Duration(milliseconds: 500)); // start delay
      await tester.pump(const Duration(milliseconds: 700)); // mid-spin
      final mid = shownNumber(tester)!;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(420), reason: 'still spinning');

      await tester.pump(const Duration(milliseconds: 1200)); // finish
      expect(shownNumber(tester), 420, reason: 'it must land on the exact value');
      expect(tester.takeException(), isNull);
    });

    testWidgets('animate: false shows the number immediately', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CalorieReveal(calories: 512, protein: 20, animate: false),
          ),
        ),
      ));
      await tester.pump();

      expect(shownNumber(tester), 512,
          reason: 'a saved meal must not replay the spin');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an edited value glides to the new number', (tester) async {
      var calories = 400;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                CalorieReveal(calories: calories, protein: 5),
                ElevatedButton(
                  onPressed: () => setState(() => calories = 600),
                  child: const Text('edit grams'),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1700));
      expect(shownNumber(tester), 400);

      await tester.tap(find.text('edit grams'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(shownNumber(tester), 600,
          reason: 'the number follows the edited grams');
      expect(tester.takeException(), isNull);
    });
  });

  group('GoalFit', () {
    test('no saved profile means no celebration', () async {
      // Clear the singleton: earlier tests may have saved a profile.
      await DietPlanService.instance.load();
      expect(DietPlanService.instance.profile, isNull);

      expect(GoalFit.check(calories: 300, protein: 30), isNull);
    });

    test('losing weight celebrates while the meal fits today\'s budget',
        () async {
      final p = profile(goal: Goal.loseWeight);
      await DietPlanService.instance.save(p);
      final budget = p.targetCalories; // nothing logged yet today

      expect(GoalFit.check(calories: budget - 10, protein: 20), isTrue);
      expect(GoalFit.check(calories: budget + 10, protein: 20), isFalse,
          reason: 'a meal over the remaining budget earns no confetti');
      expect(GoalFit.check(calories: budget, protein: 20), isTrue);
    });

    test('gaining muscle needs 20% of the daily protein target', () async {
      final p = profile(goal: Goal.gainMuscle);
      await DietPlanService.instance.save(p);
      final proteinTarget = p.targetProtein;

      expect(
        GoalFit.check(calories: 200, protein: proteinTarget * 0.20),
        isTrue,
      );
      expect(
        GoalFit.check(calories: 200, protein: proteinTarget * 0.19),
        isFalse,
        reason: 'just under a fifth of the protein target is not a win',
      );
    });

    test('maintaining uses the same calorie-budget rule', () async {
      final p = profile(goal: Goal.maintain);
      await DietPlanService.instance.save(p);

      expect(GoalFit.check(calories: p.targetCalories - 5, protein: 5), isTrue);
      expect(GoalFit.check(calories: p.targetCalories + 5, protein: 5), isFalse);
    });
  });
}
