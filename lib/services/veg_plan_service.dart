import '../models/diet_profile.dart';
import 'food_database.dart';

/// One meal slot of the generated vegetarian day plan.
class VegMealSlot {
  const VegMealSlot({
    required this.title,
    required this.time,
    required this.items,
  });

  final String title;
  final String time;
  final List<FoodItem> items;

  int get calories => items.fold(0, (sum, i) => sum + i.calories);
  double get protein => items.fold(0, (sum, i) => sum + i.protein);
  double get carbs => items.fold(0, (sum, i) => sum + i.carbs);
  double get fats => items.fold(0, (sum, i) => sum + i.fats);
}

/// A whole day of vegetarian meals sized against one calorie target.
class VegDayPlan {
  const VegDayPlan({required this.slots, required this.targetCalories});

  final List<VegMealSlot> slots;
  final int targetCalories;

  int get totalCalories => slots.fold(0, (sum, s) => sum + s.calories);
  double get totalProtein => slots.fold(0, (sum, s) => sum + s.protein);
  double get totalCarbs => slots.fold(0, (sum, s) => sum + s.carbs);
  double get totalFats => slots.fold(0, (sum, s) => sum + s.fats);
}

/// A category heading in the "every veg food" list.
class VegCategoryGroup {
  const VegCategoryGroup({required this.category, required this.items});

  final String category;
  final List<FoodItem> items;
}

/// Builds the vegetarian day plan shown on the Veg Plan screen.
///
/// Everything here comes from [FoodDatabase.vegetarian], so meat, fish and
/// egg entries can never reach the plan. The selection is deterministic:
/// the same day number and target always produce the same plan, and the
/// plan rotates day to day so the user is not served one static menu.
class VegPlanService {
  VegPlanService._();

  /// Fallback target when the user never filled in Diet Plan.
  static const int defaultTargetCalories = 2000;

  /// Cap so one slot never turns into a buffet.
  static const int maxItemsPerSlot = 5;

  /// Calorie split across the day - mirrors DietPlanScreen's own breakdown.
  static const List<_SlotSpec> _specs = [
    _SlotSpec('Breakfast', '7:00 - 9:00 AM', 0.25,
        ['Breakfast', 'South Indian']),
    _SlotSpec('Mid-Morning Snack', '11:00 AM', 0.10, ['Fruits', 'Dairy']),
    _SlotSpec('Lunch', '12:30 - 2:00 PM', 0.30, ['Lunch/Dinner', 'Rice/Bread']),
    _SlotSpec('Evening Snack', '5:00 - 6:30 PM', 0.10,
        ['Snacks', 'Salads/Soups']),
    _SlotSpec('Dinner', '7:30 - 9:00 PM', 0.25,
        ['Lunch/Dinner', 'South Indian', 'Salads/Soups']),
  ];

  /// A plan for [profile]'s targets (or [defaultTargetCalories] without one),
  /// rotated by [day] - pass the current day number to vary it daily.
  static VegDayPlan dayPlan({DietProfile? profile, int day = 0}) {
    final target = profile?.targetCalories ?? defaultTargetCalories;
    final preferProtein = profile?.goal == Goal.gainMuscle;
    final used = <String>{};
    final slots = <VegMealSlot>[];
    for (final spec in _specs) {
      final budget = (target * spec.share).round();
      slots.add(VegMealSlot(
        title: spec.title,
        time: spec.time,
        items: _fill(spec, budget, day, used, preferProtein),
      ));
    }
    return VegDayPlan(slots: slots, targetCalories: target);
  }

  /// Every vegetarian food in the database, grouped under its category in
  /// database order - the "all veg" suggestion list.
  static List<VegCategoryGroup> suggestions() {
    final groups = <String, List<FoodItem>>{};
    for (final item in FoodDatabase.vegetarian) {
      groups.putIfAbsent(item.category, () => <FoodItem>[]).add(item);
    }
    return [
      for (final entry in groups.entries)
        VegCategoryGroup(category: entry.key, items: entry.value),
    ];
  }

  /// How many vegetarian foods the suggestion list offers.
  static int get suggestionCount => FoodDatabase.vegetarian.length;

  /// Fills one slot up to [budget] without repeating anything already used
  /// this day. Ranked highest-value first with a day-seeded wobble, so a
  /// muscle-gain profile sees protein-dense picks while every other goal
  /// sees the best calorie fit, and tomorrow's order differs from today's.
  static List<FoodItem> _fill(
    _SlotSpec spec,
    int budget,
    int day,
    Set<String> used,
    bool preferProtein,
  ) {
    var pool = <FoodItem>[
      for (final category in spec.categories) ...FoodDatabase.getByCategory(category),
    ].where((item) => item.isVeg && !used.contains(item.name)).toList();
    if (pool.isEmpty) {
      // Every candidate in this slot is already used - fall back to anything
      // vegetarian rather than showing an empty meal.
      pool = FoodDatabase.vegetarian
          .where((item) => !used.contains(item.name))
          .toList();
    }
    if (pool.isEmpty) return const [];

    final ranked = <_Ranked>[
      for (var i = 0; i < pool.length; i++) _Ranked(pool[i], i),
    ];
    ranked.sort((a, b) {
      final sa = _score(a.item, a.index, day, preferProtein);
      final sb = _score(b.item, b.index, day, preferProtein);
      if (sa != sb) return sb.compareTo(sa);
      return a.index.compareTo(b.index);
    });

    final chosen = <FoodItem>[];
    var total = 0;
    for (final candidate in ranked) {
      if (chosen.length >= maxItemsPerSlot) break;
      if (total + candidate.item.calories > budget) continue;
      chosen.add(candidate.item);
      total = total + candidate.item.calories;
      if (total >= budget * 0.9) break;
    }
    if (chosen.isEmpty) {
      // Budget is below even the cheapest item - take that item anyway so
      // the slot still suggests something instead of coming up empty.
      final smallest = [...pool]
        ..sort((a, b) => a.calories.compareTo(b.calories));
      chosen.add(smallest.first);
    }
    used.addAll(chosen.map((item) => item.name));
    return chosen;
  }

  static double _score(
    FoodItem item,
    int index,
    int day,
    bool preferProtein,
  ) {
    final base = preferProtein ? item.protein * 4 : item.calories.toDouble();
    final jitter = (((index * 37) + (day * 101)) % 61) - 30;
    return base + (preferProtein ? jitter * 0.35 : jitter.toDouble());
  }
}

class _SlotSpec {
  const _SlotSpec(this.title, this.time, this.share, this.categories);

  final String title;
  final String time;
  final double share;
  final List<String> categories;
}

class _Ranked {
  const _Ranked(this.item, this.index);

  final FoodItem item;
  final int index;
}
