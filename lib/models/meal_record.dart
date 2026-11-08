/// One visible component of a logged meal — "2 Chapati", "Dal 120 g" —
/// stored so the meal detail view can render the scan's per-item breakdown
/// later: item names, gram weights, and the per-dish nutrition cards.
///
/// Values here are the DISH's own basis, exactly as the scan reported them:
/// [calories]/[protein]/[carbs]/[fats]/[fiber] are per-100 g, and [grams] is
/// the item's estimated weight. A stored meal also carries the total serving
/// weight ([MealRecord.servingGrams]), so the view re-derives the totals the
/// home card shows from the same math the scan screen used.
class MealItem {
  final String name;

  /// Portion description from the scan ("1 medium bowl"), or ''.
  final String serving;

  /// Estimated weight of this item, in grams. 0 when unknown.
  final double grams;

  /// Per-100 g nutrition, exactly as the scan reported it.
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final double fiber;

  /// Fine-grained components inside this item ("Grilled chicken 90 g").
  final List<MealIngredient> ingredients;

  const MealItem({
    required this.name,
    this.serving = '',
    this.grams = 0,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    this.fiber = 0,
    this.ingredients = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (serving.isNotEmpty) 'serving': serving,
    if (grams > 0) 'grams': grams,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fats': fats,
    if (fiber > 0) 'fiber': fiber,
    if (ingredients.isNotEmpty)
      'ingredients': [for (final i in ingredients) i.toJson()],
  };

  /// Tolerant parse: one malformed item becomes null and is dropped rather
  /// than throwing the whole meal's breakdown away.
  static MealItem? tryFromJson(Map<String, dynamic> json) {
    try {
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static MealItem fromJson(Map<String, dynamic> json) => MealItem(
    name: json['name'] as String? ?? '',
    serving: json['serving'] as String? ?? '',
    grams: (json['grams'] as num?)?.toDouble() ?? 0,
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    protein: (json['protein'] as num?)?.toDouble() ?? 0,
    carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
    fats: (json['fats'] as num?)?.toDouble() ?? 0,
    fiber: (json['fiber'] as num?)?.toDouble() ?? 0,
    ingredients:
        (json['ingredients'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => MealIngredient.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList() ??
        const [],
  );
}

/// A fine-grained component inside a [MealItem] — "Rice 150 g".
class MealIngredient {
  final String name;

  /// Estimated weight of this component, in grams. 0 when unknown.
  final double grams;

  const MealIngredient({required this.name, this.grams = 0});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (grams > 0) 'grams': grams,
  };

  static MealIngredient fromJson(Map<String, dynamic> json) => MealIngredient(
    name: json['name'] as String? ?? '',
    grams: (json['grams'] as num?)?.toDouble() ?? 0,
  );
}

class MealRecord {
  final String id;
  final DateTime date;
  final String name;
  final String category;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final double fiber;
  final String serving;

  /// The user's own "how did it taste" verdict (`delicious` / `okay` /
  /// `bland`), or null when they never rated it. Optional on purpose: meals
  /// logged before this existed, and meals logged without rating, are valid.
  final String? tastiness;

  /// The scan's stored breakdown (item names, grams, per-100 g nutrition).
  /// Empty for meals logged before this existed, and for manual/barcode
  /// entries which never had one — the detail view then falls back to the
  /// single aggregate row.
  final List<MealItem> items;

  /// The total serving weight the scan reported for the logged meal. Null
  /// for records logged before this existed; the detail view then derives
  /// it from [items] or falls back to 100 g.
  final int? servingGrams;

  /// Path to the photo this meal was logged from, in app storage — or null,
  /// which is the normal state: manual entries never had one, and a scanned
  /// meal's photo is deleted 24 hours after it was taken (see
  /// [MealImageStore]). A path here is therefore a *maybe*: it is only ever
  /// shown after the file is confirmed to still exist.
  final String? imagePath;

  MealRecord({
    required this.id,
    required this.date,
    required this.name,
    required this.category,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.fiber,
    required this.serving,
    this.tastiness,
    this.items = const [],
    this.servingGrams,
    this.imagePath,
  });

  /// A copy of this record with a different (or cleared) photo path. Used by
  /// the store when the file behind [imagePath] has aged out.
  MealRecord withImagePath(String? path) => MealRecord(
    id: id,
    date: date,
    name: name,
    category: category,
    calories: calories,
    protein: protein,
    carbs: carbs,
    fats: fats,
    fiber: fiber,
    serving: serving,
    tastiness: tastiness,
    items: items,
    servingGrams: servingGrams,
    imagePath: path,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'name': name,
    'category': category,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fats': fats,
    'fiber': fiber,
    'serving': serving,
    if (tastiness != null) 'tastiness': tastiness,
    // Omitted rather than written as null: an old build reading this file must
    // not stumble over a key it has never seen, and the parser treats a missing
    // key and a null the same way.
    if (imagePath != null) 'imagePath': imagePath,
    if (items.isNotEmpty)
      'items': [for (final item in items) item.toJson()],
    if (servingGrams != null) 'servingGrams': servingGrams,
  };

  factory MealRecord.fromJson(Map<String, dynamic> json) => MealRecord(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    name: json['name'] as String,
    category: json['category'] as String? ?? '',
    calories: (json['calories'] as num).toInt(),
    protein: (json['protein'] as num).toDouble(),
    carbs: (json['carbs'] as num).toDouble(),
    fats: (json['fats'] as num).toDouble(),
    fiber: (json['fiber'] as num).toDouble(),
    serving: json['serving'] as String? ?? '',
    tastiness: json['tastiness'] as String?,
    items:
        (json['items'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((e) => MealItem.tryFromJson(Map<String, dynamic>.from(e)))
            .whereType<MealItem>()
            .toList() ??
        const [],
    servingGrams: (json['servingGrams'] as num?)?.toInt(),
    imagePath: json['imagePath'] as String?,
  );

  /// Parses one stored/cloud record, returning null instead of throwing when
  /// it is malformed (missing id/date, wrong types, a truncated write).
  ///
  /// Stores parse lists record-by-record through this: one bad row used to
  /// throw out of the whole list, and the surrounding catch reset the user's
  /// entire meal history to empty.
  static MealRecord? tryFromJson(Map<String, dynamic> json) {
    try {
      return MealRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  bool get isToday =>
      date.year == DateTime.now().year &&
      date.month == DateTime.now().month &&
      date.day == DateTime.now().day;
}
