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
  });

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

  /// Get the N most recent foods (for quick display).
  List<RecentFood> recent({int count = 10}) => _foods.take(count).toList();

  /// Search recent foods by name.
  List<RecentFood> search(String query) {
    final q = query.toLowerCase();
    return _foods.where((f) => f.name.toLowerCase().contains(q)).toList();
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
