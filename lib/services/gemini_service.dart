import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DishItem {
  final String name;
  final String portionDescription;
  final int caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatsPer100g;
  final double fiberPer100g;
  final double sugarPer100g;
  final String suitableFor;

  const DishItem({
    required this.name,
    this.portionDescription = '',
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatsPer100g,
    this.fiberPer100g = 0,
    this.sugarPer100g = 0,
    this.suitableFor = 'both',
  });

  factory DishItem.fromJson(Map<String, dynamic> json) => DishItem(
    name: json['name'] as String? ?? 'Unknown',
    portionDescription: json['portion_description'] as String? ?? '',
    caloriesPer100g: (json['calories_per_100g'] as num?)?.toInt() ?? 0,
    proteinPer100g: (json['protein_g_per_100g'] as num?)?.toDouble() ?? 0,
    carbsPer100g: (json['carbs_g_per_100g'] as num?)?.toDouble() ?? 0,
    fatsPer100g: (json['fats_g_per_100g'] as num?)?.toDouble() ?? 0,
    fiberPer100g: (json['fiber_g_per_100g'] as num?)?.toDouble() ?? 0,
    sugarPer100g: (json['sugar_g_per_100g'] as num?)?.toDouble() ?? 0,
    suitableFor: json['suitable_for'] as String? ?? 'both',
  );

  DishItem withGrams(int g) => DishItem(
    name: name,
    portionDescription: portionDescription,
    caloriesPer100g: (caloriesPer100g * g / 100).round(),
    proteinPer100g: proteinPer100g * g / 100,
    carbsPer100g: carbsPer100g * g / 100,
    fatsPer100g: fatsPer100g * g / 100,
    fiberPer100g: fiberPer100g * g / 100,
    sugarPer100g: sugarPer100g * g / 100,
    suitableFor: suitableFor,
  );
}

class NutritionResult {
  final List<DishItem> dishes;
  final String description;
  final double confidence;
  final int scansUsed;
  final int scansLimit;
  final int grams;

  const NutritionResult({
    required this.dishes,
    this.description = '',
    this.confidence = 0.7,
    this.scansUsed = 0,
    this.scansLimit = 3,
    this.grams = 100,
  });

  int get caloriesPer100g => dishes.fold(0, (sum, d) => sum + d.caloriesPer100g);
  double get proteinPer100g => dishes.fold(0.0, (sum, d) => sum + d.proteinPer100g);
  double get carbsPer100g => dishes.fold(0.0, (sum, d) => sum + d.carbsPer100g);
  double get fatsPer100g => dishes.fold(0.0, (sum, d) => sum + d.fatsPer100g);
  double get fiberPer100g => dishes.fold(0.0, (sum, d) => sum + d.fiberPer100g);
  double get sugarPer100g => dishes.fold(0.0, (sum, d) => sum + d.sugarPer100g);

  String get suitableFor {
    final bulk = dishes.where((d) => d.suitableFor == 'bulk').length;
    final diet = dishes.where((d) => d.suitableFor == 'diet').length;
    if (bulk > diet) return 'bulk';
    if (diet > bulk) return 'diet';
    return 'both';
  }

  int get calories => (caloriesPer100g * grams / 100).round();
  double get protein => proteinPer100g * grams / 100;
  double get carbs => carbsPer100g * grams / 100;
  double get fats => fatsPer100g * grams / 100;
  double get fiber => fiberPer100g * grams / 100;
  double get sugar => sugarPer100g * grams / 100;

  NutritionResult withGrams(int g) {
    return NutritionResult(
      dishes: dishes.map((d) => DishItem(
        name: d.name,
        portionDescription: d.portionDescription,
        caloriesPer100g: d.caloriesPer100g,
        proteinPer100g: d.proteinPer100g,
        carbsPer100g: d.carbsPer100g,
        fatsPer100g: d.fatsPer100g,
        fiberPer100g: d.fiberPer100g,
        sugarPer100g: d.sugarPer100g,
        suitableFor: d.suitableFor,
      )).toList(),
      description: description,
      confidence: confidence,
      scansUsed: scansUsed,
      scansLimit: scansLimit,
      grams: g,
    );
  }

  factory NutritionResult.fromJson(Map<String, dynamic> json) {
    final dishesList = (json['dishes'] as List<dynamic>?)
        ?.map((d) => DishItem.fromJson(d as Map<String, dynamic>))
        .toList() ?? [];
    return NutritionResult(
      dishes: dishesList,
      description: json['description'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
      scansUsed: (json['scans_used'] as num?)?.toInt() ?? 0,
      scansLimit: (json['scans_limit'] as num?)?.toInt() ?? 3,
    );
  }
}

class GeminiService {
  static const _prefsKey = 'server_url';
  static String _serverUrl = 'https://macro-snap-backend.vercel.app';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_prefsKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _serverUrl = savedUrl.trim();
    }
  }

  static Future<void> setServerUrl(String url) async {
    _serverUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _serverUrl);
  }

  static String get serverUrl => _serverUrl;
  static bool get hasServerUrl => _serverUrl.isNotEmpty;

  /// Integration-test hook: when set, [analyzeFoodImage] returns this mock
  /// instead of calling the backend. Used by integration_test/flow_test.dart
  /// so on-device flows run without a live server.
  @visibleForTesting
  static NutritionResult? mockResult;

  static Future<NutritionResult> analyzeFoodImage(String imagePath) async {
    final mock = mockResult;
    if (mock != null) return mock;
    if (!hasServerUrl) {
      throw Exception('Server URL not set. Enter your server URL in Settings.');
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found at: $imagePath');
      }

      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone') ?? '';

      final request = http.MultipartRequest('POST', Uri.parse('$_serverUrl/analyze'));
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      request.fields['phone'] = phone;

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 403) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] == 'scan_limit_reached') {
          throw Exception('Scan limit reached. Subscribe for unlimited scans.');
        }
        throw Exception(body['error'] as String? ?? 'Server error (${response.statusCode})');
      }

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['error'] as String? ?? 'Server error (${response.statusCode})');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return NutritionResult.fromJson(json);
    } on SocketException {
      throw Exception('Cannot reach server at $serverUrl.\nMake sure your phone is on the same WiFi and the backend is running.');
    } on http.ClientException {
      throw Exception('Connection failed. Check that the server is running at $serverUrl.');
    } on FormatException {
      throw Exception('Invalid response from server.');
    }
  }
}