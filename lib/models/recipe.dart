class RecipeIngredient {
  String name;
  double grams;
  double caloriesPer100g;
  double proteinPer100g;
  double carbsPer100g;
  double fatsPer100g;
  double fiberPer100g;

  RecipeIngredient({
    required this.name,
    this.grams = 50,
    this.caloriesPer100g = 0,
    this.proteinPer100g = 0,
    this.carbsPer100g = 0,
    this.fatsPer100g = 0,
    this.fiberPer100g = 0,
  });

  double get calories => (caloriesPer100g * grams / 100);
  double get protein => proteinPer100g * grams / 100;
  double get carbs => carbsPer100g * grams / 100;
  double get fats => fatsPer100g * grams / 100;
  double get fiber => fiberPer100g * grams / 100;

  Map<String, dynamic> toJson() => {
    'name': name,
    'grams': grams,
    'caloriesPer100g': caloriesPer100g,
    'proteinPer100g': proteinPer100g,
    'carbsPer100g': carbsPer100g,
    'fatsPer100g': fatsPer100g,
    'fiberPer100g': fiberPer100g,
  };

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) =>
      RecipeIngredient(
        name: json['name'] as String? ?? '',
        grams: (json['grams'] as num?)?.toDouble() ?? 0,
        caloriesPer100g: (json['caloriesPer100g'] as num?)?.toDouble() ?? 0,
        proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble() ?? 0,
        carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble() ?? 0,
        fatsPer100g: (json['fatsPer100g'] as num?)?.toDouble() ?? 0,
        fiberPer100g: (json['fiberPer100g'] as num?)?.toDouble() ?? 0,
      );
}

class Recipe {
  final String id;
  String name;
  int servings;
  List<RecipeIngredient> ingredients;

  Recipe({
    required this.id,
    this.name = '',
    this.servings = 4,
    List<RecipeIngredient>? ingredients,
  }) : ingredients = ingredients ?? [];

  double get totalCalories => ingredients.fold(0.0, (s, i) => s + i.calories);
  double get totalProtein => ingredients.fold(0.0, (s, i) => s + i.protein);
  double get totalCarbs => ingredients.fold(0.0, (s, i) => s + i.carbs);
  double get totalFats => ingredients.fold(0.0, (s, i) => s + i.fats);
  double get totalFiber => ingredients.fold(0.0, (s, i) => s + i.fiber);

  double get perServingCalories => totalCalories / servings;
  double get perServingProtein => totalProtein / servings;
  double get perServingCarbs => totalCarbs / servings;
  double get perServingFats => totalFats / servings;
  double get perServingFiber => totalFiber / servings;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'servings': servings,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
  };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    servings: (json['servings'] as num?)?.toInt() ?? 4,
    ingredients:
        (json['ingredients'] as List<dynamic>?)
            ?.map((i) => RecipeIngredient.fromJson(i as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
