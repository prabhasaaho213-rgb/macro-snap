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
  });

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
