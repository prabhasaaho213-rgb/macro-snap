import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_record.dart';
import '../services/account_partition.dart';
import '../services/meal_sync_service.dart';
import 'crash_reporting.dart';

/// A scanned food item saved for quick re-add.
class RecentFood {
  final String id;
  final String name;
  final int calories;
  final double protein;
  final double carbs;
  final double fats;
  final double fiber;
  final String serving;
  final DateTime scannedAt;
  final String? imagePath; // optional thumbnail

  /// True when the user starred this food (long-press on the card) so it can
  /// resurface first. Optional on purpose: foods saved before the star existed
  /// are simply not favorites, and the parser treats a missing key the same.
  final bool favorite;

  const RecentFood({
    required this.id,
    required this.name,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fats = 0,
    this.fiber = 0,
    this.serving = '',
    required this.scannedAt,
    this.imagePath,
    this.favorite = false,
  });

  /// A quick 'what kind of food is this' tag the Recent Foods chips row
  /// filters by. Derived from the macros, never stored: the same food can't
  /// carry two tags and a bulk edit could never disagree with the list.
  String get tag {
    if (protein >= 15 && protein >= carbs && protein >= fats) {
      return 'Protein-heavy';
    }
    if (calories <= 200) return 'Light bite';
    if (calories >= 500) return 'Filling meal';
    return 'Balanced';
  }

  /// Every tag shown in the filter row, always the same order.
  static const List<String> tags = [
    'Protein-heavy',
    'Light bite',
    'Filling meal',
    'Balanced',
  ];

  /// Convert to a MealRecord for logging.
  MealRecord toMealRecord() => MealRecord(
    id: id,
    date: DateTime.now(),
    name: name,
    category: 'recent',
    calories: calories,
    protein: protein,
    carbs: carbs,
    fats: fats,
    fiber: fiber,
    serving: serving,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fats': fats,
    'fiber': fiber,
    'serving': serving,
    'scannedAt': scannedAt.toIso8601String(),
    'imagePath': imagePath,
    // Omitted when false, like the other optional keys: an old build reading
    // this list must not stumble over a key it has never seen.
    if (favorite) 'favorite': true,
  };

  factory RecentFood.fromJson(Map<String, dynamic> json) => RecentFood(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Unknown',
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    protein: (json['protein'] as num?)?.toDouble() ?? 0,
    carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
    fats: (json['fats'] as num?)?.toDouble() ?? 0,
    fiber: (json['fiber'] as num?)?.toDouble() ?? 0,
    serving: json['serving'] as String? ?? '',
    scannedAt:
        DateTime.tryParse(json['scannedAt'] as String? ?? '') ?? DateTime.now(),
    imagePath: json['imagePath'] as String?,
    favorite: json['favorite'] as bool? ?? false,
  );
}

/// Manages a recently-scanned foods list (max 50 items).
///
/// Foods are saved automatically after a successful scan. Users can tap a
/// recent food to instantly log it without re-scanning.
class RecentFoodService {
  static final RecentFoodService _instance = RecentFoodService._();
  static RecentFoodService get instance => _instance;
  RecentFoodService._();

  static const _prefsKey = 'recent_foods';
  static const _maxItems = 50;

  List<RecentFood> _foods = [];
  List<RecentFood> get foods => List.unmodifiable(_foods);

  /// Load recent foods from disk, then merge from cloud in background.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final suffix = AccountPartition.suffix(
        AccountPartition.activeFromPrefs(prefs),
      );
      final key = AccountPartition.key(_prefsKey, suffix);
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _foods = list
            .map((e) => RecentFood.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _foods = [];
      }
    } catch (_) {
      _foods = [];
    }
    // Cloud restore merges missing foods in background.
    unawaited(_syncFromCloud());
  }

  /// Save a scanned food to the top of the list.
  /// Deduplicates by name (case-insensitive) — replaces old entry if exists.
  Future<void> add(RecentFood food) async {
    // Remove duplicate by name
    _foods.removeWhere((f) => f.name.toLowerCase() == food.name.toLowerCase());
    // Add to top
    _foods.insert(0, food);
    // Trim to max
    if (_foods.length > _maxItems) {
      _foods = _foods.sublist(0, _maxItems);
    }
    await _save();
    // Auto-sync to cloud (fire-and-forget)
    _syncToCloud();
  }

  /// Remove a specific food by id.
  Future<void> remove(String id) async {
    _foods.removeWhere((f) => f.id == id);
    await _save();
    _syncToCloud();
  }

  /// Clear all recent foods.
  Future<void> clear() async {
    _foods.clear();
    await _save();
    _syncToCloud();
  }

  /// Get the N most recent foods (for quick display). Favorites keep their
  /// recency order but always sort ahead of the rest, so a starred food can
  /// never drift below 50 other scans.
  List<RecentFood> recent({int count = 10}) => sortedFoods.take(count).toList();

  /// The full list with favorites first (relative order preserved) — what the
  /// Recent Foods screen shows when no tag filter is active.
  List<RecentFood> get sortedFoods {
    final favs = _foods.where((f) => f.favorite).toList();
    final rest = _foods.where((f) => !f.favorite).toList();
    return [...favs, ...rest];
  }

  /// Stars (or unstars) one food and persists the change.
  Future<void> toggleFavorite(String id) async {
    final index = _foods.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final f = _foods[index];
    _foods[index] = RecentFood(
      id: f.id,
      name: f.name,
      calories: f.calories,
      protein: f.protein,
      carbs: f.carbs,
      fats: f.fats,
      fiber: f.fiber,
      serving: f.serving,
      scannedAt: f.scannedAt,
      imagePath: f.imagePath,
      favorite: !f.favorite,
    );
    await _save();
    _syncToCloud();
  }

  /// Foods tagged [tag].
  List<RecentFood> tagged(String tag) =>
      _foods.where((f) => f.tag == tag).toList();

  /// Search recent foods by name (favorites still sort first).
  List<RecentFood> search(String query) {
    final q = query.toLowerCase();
    final matches = _foods
        .where((f) => f.name.toLowerCase().contains(q))
        .toList();
    final favs = matches.where((f) => f.favorite).toList();
    final rest = matches.where((f) => !f.favorite).toList();
    return [...favs, ...rest];
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final suffix = AccountPartition.suffix(
        AccountPartition.activeFromPrefs(prefs),
      );
      final key = AccountPartition.key(_prefsKey, suffix);
      final raw = jsonEncode(_foods.map((f) => f.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (e, st) {
      logError('RecentFoodService._save', e, st);
    }
  }

  /// Auto-sync to cloud (fire-and-forget).
  void _syncToCloud() {
    try {
      final json = _foods.map((f) => f.toJson()).toList();
      MealSyncService.syncRecentFoods(json);
    } catch (e) {
      debugPrint('RecentFoodService._syncToCloud failed: $e');
    }
  }

  /// Merge missing foods from cloud (background restore on load).
  Future<void> _syncFromCloud() async {
    try {
      final cloudFoods = await MealSyncService.fetchRecentFoods();
      if (cloudFoods == null || cloudFoods.isEmpty) return;
      final localIds = _foods.map((f) => f.id).toSet();
      bool added = false;
      for (final f in cloudFoods) {
        final food = RecentFood.fromJson(f);
        if (!localIds.contains(food.id)) {
          _foods.add(food);
          added = true;
        }
      }
      if (added) {
        // Trim to max and save locally.
        if (_foods.length > _maxItems) {
          _foods = _foods.sublist(0, _maxItems);
        }
        await _save();
      }
    } catch (e) {
      debugPrint('RecentFoodService._syncFromCloud failed: $e');
    }
  }
}
