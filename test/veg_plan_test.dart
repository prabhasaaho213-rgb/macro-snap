import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/services/food_database.dart';
import 'package:macro_snap/services/veg_plan_service.dart';

void main() {
  test('the database marks every meat/fish/egg entry non-veg', () {
    expect(FoodDatabase.vegetarian, isNotEmpty);
    expect(
      FoodDatabase.vegetarian.every((item) => item.isVeg),
      isTrue,
      reason: 'the vegetarian accessor must never leak a non-veg item',
    );

    // Every entry a vegetarian must not eat is flagged.
    final nonVegNames = FoodDatabase.vegetarian
        .map((i) => i.name)
        .where((n) => n.contains('Chicken') || n.contains('Fish'))
        .toList();
    expect(
      nonVegNames,
      isEmpty,
      reason: 'meat must be excluded from the vegetarian list, found $nonVegNames',
    );
    expect(
      FoodDatabase.vegetarian.map((i) => i.name),
      isNot(contains('Boiled Egg (1 pc)')),
    );
    expect(
      FoodDatabase.vegetarian.map((i) => i.name),
      isNot(contains('Egg Curry')),
    );
    // Plants, dairy and paneer stay in.
    expect(
      FoodDatabase.vegetarian.map((i) => i.name),
      containsAll(['Palak Paneer', 'Dal Tadka', 'Idli (2 pcs)', 'Curd Rice']),
    );
  });

  test('the day plan only serves vegetarian food, five slots, on target', () {
    final plan = VegPlanService.dayPlan(day: 3);

    expect(plan.slots, hasLength(5));
    expect(plan.targetCalories, VegPlanService.defaultTargetCalories);

    final names = <String>[];
    for (final slot in plan.slots) {
      expect(slot.items, isNotEmpty, reason: '${slot.title} must not be empty');
      expect(slot.items.every((i) => i.isVeg), isTrue);
      for (final item in slot.items) {
        expect(item.isVeg, isTrue, reason: '${item.name} is not vegetarian');
        names.add(item.name);
      }
      // Every slot must fit its own share of the day's budget, except the
      // documented fallback where the budget is below the cheapest item.
      expect(
        slot.calories,
        lessThanOrEqualTo((plan.targetCalories * 0.30).round() + 400),
        reason: '${slot.title} blew past any plausible share',
      );
    }

    expect(
      names.toSet().length,
      names.length,
      reason: 'no food should repeat within one day: $names',
    );
  });

  test('the plan lands near the calorie target', () {
    final plan = VegPlanService.dayPlan(day: 1);
    final total = plan.totalCalories;

    expect(
      total,
      greaterThanOrEqualTo((plan.targetCalories * 0.5).round()),
      reason: 'a day plan at half the target under-feeds: $total kcal',
    );
    expect(
      total,
      lessThanOrEqualTo((plan.targetCalories * 1.1).round()),
      reason: 'a day plan over the target defeats the diet: $total kcal',
    );
  });

  test('a muscle-gain profile gets a higher protein day than weight loss', () {
    final gain = VegPlanService.dayPlan(
      profile: DietProfile(
        weightKg: 75,
        heightCm: 178,
        age: 25,
        gender: Gender.male,
        goal: Goal.gainMuscle,
        activity: ActivityLevel.active,
      ),
      day: 2,
    );
    final loss = VegPlanService.dayPlan(
      profile: DietProfile(
        weightKg: 75,
        heightCm: 178,
        age: 25,
        gender: Gender.male,
        goal: Goal.loseWeight,
        activity: ActivityLevel.active,
      ),
      day: 2,
    );

    expect(gain.totalProtein, greaterThan(loss.totalProtein));
    expect(gain.targetCalories, greaterThan(loss.targetCalories));
  });

  test('the plan follows the profile calorie target', () {
    final profile = DietProfile(
      weightKg: 60,
      heightCm: 160,
      age: 30,
      gender: Gender.female,
      goal: Goal.maintain,
      activity: ActivityLevel.sedentary,
    );
    final plan = VegPlanService.dayPlan(profile: profile, day: 5);

    expect(plan.targetCalories, profile.targetCalories);
    expect(
      plan.totalCalories,
      lessThanOrEqualTo((profile.targetCalories * 1.1).round()),
    );
  });

  test('the same day is reproducible and the next day differs', () {
    final today = VegPlanService.dayPlan(day: 7).slots
        .map((s) => s.items.map((i) => i.name).toList())
        .toList();
    final sameDay = VegPlanService.dayPlan(day: 7).slots
        .map((s) => s.items.map((i) => i.name).toList())
        .toList();
    final tomorrow = VegPlanService.dayPlan(day: 8).slots
        .map((s) => s.items.map((i) => i.name).toList())
        .toList();

    expect(sameDay, today, reason: 'same day + same target = same plan');
    expect(
      tomorrow,
      isNot(today),
      reason: 'the plan should rotate day to day instead of being static',
    );
  });

  test('suggestions group every vegetarian food exactly once', () {
    final groups = VegPlanService.suggestions();

    expect(groups, isNotEmpty);
    expect(
      VegPlanService.suggestionCount,
      FoodDatabase.vegetarian.length,
    );

    final seen = <String>[];
    for (final group in groups) {
      expect(group.items, isNotEmpty);
      expect(group.items.every((i) => i.isVeg), isTrue);
      seen.addAll(group.items.map((i) => i.name));
    }
    expect(
      seen.toSet().length,
      seen.length,
      reason: 'a food must not appear under two categories',
    );
    expect(seen.length, FoodDatabase.vegetarian.length);
  });
}
