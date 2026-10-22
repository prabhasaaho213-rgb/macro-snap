import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../core/app_limits.dart';
import 'auth_http.dart';

/// One component of a detected dish — "Grilled chicken breast 150 g".
///
/// The scan prompt asks the model to break a dish into its visible parts so
/// the result card can list ingredients the way a nutrition label does. Older
/// servers send no ingredient list at all, so [DishItem.ingredients] is
/// allowed to be empty and the card falls back to the dish itself.
class DishIngredient {
  final String name;

  /// Estimated edible weight of this component, in grams. 0 when unknown.
  final double grams;

  /// The server's own 0–5 judgment, if it sent one; the card derives a score
  /// from the parent dish's macros otherwise.
  final int? healthScore;

  const DishIngredient({required this.name, this.grams = 0, this.healthScore});

  factory DishIngredient.fromJson(Map<String, dynamic> json) => DishIngredient(
    name: (json['name'] as String? ?? '').trim(),
    grams: ((json['grams'] as num?)?.toDouble() ?? 0).clamp(0, 5000),
    healthScore: (json['health_score'] as num?)?.toInt().clamp(0, 5),
  );
}

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

  /// Weight of this dish alone, in grams. 0 when the server did not say (the
  /// result card then shows the whole-photo weight for a single dish, or an
  /// apportioned estimate for a multi-item photo).
  final double grams;

  /// Visible components, in the order the model listed them. Empty for a scan
  /// that did not break the dish down.
  final List<DishIngredient> ingredients;

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
    this.grams = 0,
    this.ingredients = const [],
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
    grams: ((json['grams'] as num?)?.toDouble() ?? 0).clamp(0, 5000),
    // Tolerant parse: one malformed ingredient must not discard the dish.
    ingredients:
        (json['ingredients'] as List<dynamic>?)
            ?.whereType<Map>()
            .map(
              (i) => DishIngredient.fromJson(Map<String, dynamic>.from(i)),
            )
            .where((i) => i.name.isNotEmpty)
            .toList() ??
        const [],
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
    grams: grams * g / 100,
    ingredients: ingredients
        .map(
          (i) => DishIngredient(
            name: i.name,
            grams: i.grams * g / 100,
            healthScore: i.healthScore,
          ),
        )
        .toList(),
  );
}

// Total weight of all dishes, used when the server did not send one at the
// top level. Each dish weight is already clamped 0–5000; the sum is then
// clamped to the card's serving range, or 100 g when nothing was usable.
int _dishSum(List<DishItem> dishes) {
  final sum = dishes.fold<double>(0, (s, d) => s + d.grams);
  if (sum <= 0) return 100;
  return sum.clamp(5, 3000).toInt();
}

class NutritionResult {
  final List<DishItem> dishes;
  final String description;
  final double confidence;
  final int scansUsed;
  final int scansLimit;
  final int grams;

  /// True when [scansUsed]/[scansLimit] came from the SERVER (rather than
  /// being the local defaults). The server is the authority on the free-scan
  /// allowance, so only a server-sent count may be trusted — see ScanGate.
  final bool serverScansKnown;

  /// When the free allowance resets (next IST midnight, UTC), as sent by the
  /// server; null when the server did not send one.
  final DateTime? serverResetAt;

  const NutritionResult({
    required this.dishes,
    this.description = '',
    this.confidence = 0.7,
    this.scansUsed = 0,
    this.scansLimit = AppLimits.freeScansPerDay,
    this.grams = 100,
    this.serverScansKnown = false,
    this.serverResetAt,
  });

  int get caloriesPer100g =>
      dishes.fold(0, (sum, d) => sum + d.caloriesPer100g);
  double get proteinPer100g =>
      dishes.fold(0.0, (sum, d) => sum + d.proteinPer100g);
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
      dishes: dishes
          .map(
            (d) => DishItem(
              name: d.name,
              portionDescription: d.portionDescription,
              caloriesPer100g: d.caloriesPer100g,
              proteinPer100g: d.proteinPer100g,
              carbsPer100g: d.carbsPer100g,
              fatsPer100g: d.fatsPer100g,
              fiberPer100g: d.fiberPer100g,
              sugarPer100g: d.sugarPer100g,
              suitableFor: d.suitableFor,
              grams: d.grams,
              ingredients: d.ingredients,
            ),
          )
          .toList(),
      description: description,
      confidence: confidence,
      scansUsed: scansUsed,
      scansLimit: scansLimit,
      grams: g,
      serverScansKnown: serverScansKnown,
      serverResetAt: serverResetAt,
    );
  }

  factory NutritionResult.fromJson(Map<String, dynamic> json) {
    final dishesList =
        (json['dishes'] as List<dynamic>?)
            ?.map((d) => DishItem.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [];
    final rawGrams = (json['grams'] as num?)?.toInt();
    return NutritionResult(
      dishes: dishesList,
      description: json['description'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.7,
      scansUsed: (json['scans_used'] as num?)?.toInt() ?? 0,
      scansLimit:
          (json['scans_limit'] as num?)?.toInt() ?? AppLimits.freeScansPerDay,
      // The server always sends both on a successful /analyze; only then may
      // the numbers it reports be trusted over the local estimate.
      serverScansKnown:
          json.containsKey('scans_used') && json.containsKey('scans_limit'),
      serverResetAt: DateTime.tryParse(json['reset_at'] as String? ?? ''),
      // Total weight of everything visible, estimated by the server and
      // clamped there to 5–3000 g. When the server did not send one (an older  // prompt) the per-dish weights it did send are summed before anything
  // falls back to 100 g — a single egg must not open at 100 g just
  // because the total was missing.
      grams: rawGrams == null || rawGrams <= 0
          ? _dishSum(dishesList)
          : rawGrams.clamp(5, 3000).toInt(),
    );
  }
}

class GeminiService {
  /// The backend URL is a build-time constant.
  ///
  /// This used to be overridable through a `server_url` preference, but no
  /// screen ever wrote that key — the error message it implied ("enter your
  /// server URL in Settings") pointed at a setting that does not exist.
  static const String _serverUrl = 'https://macro-snap-backend.vercel.app';

  /// Kept as a no-op so startup ordering does not change: nothing needs to be
  /// read before the first request.
  static Future<void> init() async {}

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
      // There is no in-app setting for this — it can only be missing if the
      // build itself is misconfigured, so never send the user looking for one.
      throw Exception(
        'The scan service is not configured in this build. '
        'Please update MacroSnap.',
      );
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Image file not found at: $imagePath');
      }

      // AuthHttp identifies the user with their Firebase ID token — no phone
      // is sent (the backend ignores client identifiers entirely).
      final response = await AuthHttp.multipart(
        Uri.parse('$_serverUrl/analyze'),
        fileField: 'image',
        filePath: imagePath,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 403) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] == 'scan_limit_reached') {
          throw Exception('Scan limit reached. Subscribe for unlimited scans.');
        }
        throw Exception(
          body['error'] as String? ?? 'Server error (${response.statusCode})',
        );
      }

      if (response.statusCode == 401) {
        throw Exception('Please sign in again to use AI scans.');
      }

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(
          body['error'] as String? ?? 'Server error (${response.statusCode})',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return NutritionResult.fromJson(json);
    } on TimeoutException {
      // A 30 s timeout used to escape as a raw TimeoutException and surface as
      // an unexplained error screen. Give the user something actionable.
      throw Exception(
        'The scan took too long. Check your connection and try again.',
      );
    } on SocketException {
      // No server addresses, WiFi instructions or stack details in user copy.
      throw Exception(
        'Cannot reach MacroSnap right now. Check your internet connection and '
        'try again.',
      );
    } on http.ClientException {
      throw Exception(
        'The connection dropped while scanning. Please try again.',
      );
    } on FormatException {
      throw Exception(
        'The server sent an unexpected response. Please try again.',
      );
    }
  }
}
