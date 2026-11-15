import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import 'barcode_db.dart';

/// Resolves a scanned barcode to per-100 g nutrition.
///
/// Two sources, in order:
///   1. [BarcodeDb] — the small bundled table of common Indian products. It
///      answers instantly and works offline.
///   2. Open Food Facts — a public, keyless product database. Before this
///      existed, any barcode outside those ~50 bundled entries dead-ended on
///      "Product Not Found", which is what almost every real package did.
///
/// Every failure returns null rather than throwing: a lookup is a convenience,
/// and the caller falls back to manual entry.
class BarcodeService {
  BarcodeService._();

  /// Open Food Facts asks clients to identify themselves; a generic Dart
  /// user-agent gets rate-limited. Contact is the app's support address.
  ///
  /// The version comes from [kAppVersion] so it cannot drift again — it was
  /// hardcoded to 1.5.9 while the app shipped 1.5.16.
  static const String userAgent =
      'MacroSnap/$kAppVersion (Android; macrosnap7@gmail.com)';

  /// Anything above these per 100 g is a data error, not a food.
  static const double maxKcalPer100g = 900;
  static const double maxMacroPer100g = 100;

  static const Duration timeout = Duration(seconds: 8);

  /// Only digits are looked up remotely — a QR code, a URL or a Wi-Fi code
  /// carved into the "barcode" field is not a product.
  static bool isProductBarcode(String code) =>
      code.isNotEmpty && code.length >= 8 && code.length <= 14
      && RegExp(r'^\d+$').hasMatch(code);

  /// Local table first, then the network.
  static Future<BarcodeFood?> lookup(String barcode) async {
    final local = BarcodeDb.lookup(barcode);
    if (local != null) return local;
    return remoteLookup(barcode);
  }

  static Future<BarcodeFood?> remoteLookup(
    String barcode, {
    http.Client? client,
  }) async {
    if (!isProductBarcode(barcode)) return null;
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode.json', {
      'fields': 'product_name,brands,nutriments,quantity',
    });
    // A Client created here has to be closed here: the old code built a new
    // one per lookup and never disposed it, so every scan leaked a connection
    // pool (and its sockets stayed open until GC).
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            uri,
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return foodFromOpenFoodFacts(decoded, barcode);
    } catch (_) {
      // Offline, DNS failure, timeout, malformed JSON — all mean "no answer".
      return null;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// Pure parser, so the mapping rules can be tested without a network.
  ///
  /// Open Food Facts reports nutrients per 100 g/ml, exactly the basis the
  /// result card and the meal record use, so nothing is rescaled here.
  static BarcodeFood? foodFromOpenFoodFacts(
    Map<String, dynamic> body,
    String barcode,
  ) {
    // v2 API: status is 1 for a hit, 0 for "product not found".
    if (_asInt(body['status']) != 1) return null;
    final product = body['product'];
    if (product is! Map) return null;

    final name = _asText(product['product_name']);
    if (name == null) return null;

    final nutriments = product['nutriments'] is Map
        ? product['nutriments'] as Map
        : const {};

    final protein = _saneMacro(_asDouble(nutriments['proteins_100g']));
    final carbs = _saneMacro(_asDouble(nutriments['carbohydrates_100g']));
    final fats = _saneMacro(_asDouble(nutriments['fat_100g']));

    // Open Food Facts often has the macros but no energy figure, and logging
    // a 300 kcal snack as 0 kcal is worse than estimating: fall back to the
    // Atwater factors (4/4/9 kcal per gram).
    final calories =
        _saneCalories(_caloriesPer100g(nutriments)) ??
        _caloriesFromMacros(protein: protein, carbs: carbs, fats: fats);

    // A product with a name and nothing else cannot be logged; treat it as a
    // miss so the user gets the manual form instead of a card full of zeros.
    if (calories == null &&
        protein == null &&
        carbs == null &&
        fats == null) {
      return null;
    }

    return BarcodeFood(
      barcode: barcode,
      name: name,
      brand: _asText(product['brands'])?.split(',').first.trim() ?? 'Packaged food',
      caloriesPer100g: (calories ?? 0).round(),
      proteinPer100g: protein ?? 0,
      carbsPer100g: carbs ?? 0,
      fatsPer100g: fats ?? 0,
      fiberPer100g: _asDouble(nutriments['fiber_100g']) ?? 0,
      sugarPer100g: _asDouble(nutriments['sugars_100g']) ?? 0,
    );
  }

  /// 4/4/9 estimate for a product that reports macros but no energy.
  static double? _caloriesFromMacros({
    double? protein,
    double? carbs,
    double? fats,
  }) {
    if (protein == null && carbs == null && fats == null) return null;
    final kcal = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fats ?? 0) * 9;
    return kcal > 0 ? kcal : null;
  }

  /// A macro above 100 g per 100 g is impossible — reject it rather than
  /// logging a pack of, say, 900 g of protein.
  static double? _saneMacro(double? value) {
    if (value == null) return null;
    if (value.isNaN || value < 0 || value > maxMacroPer100g) return null;
    return value;
  }

  /// Likewise for energy: pure fat is ~900 kcal per 100 g, so anything above
  /// that is a data error (Open Food Facts carries a few such rows).
  static double? _saneCalories(double? value) {
    if (value == null) return null;
    if (value.isNaN || value <= 0 || value > maxKcalPer100g) return null;
    return value;
  }

  /// kcal per 100 g, falling back to the kilojoule figure some labels carry.
  static double? _caloriesPer100g(Map nutriments) {
    final kcal = _asDouble(nutriments['energy-kcal_100g']);
    if (kcal != null && kcal > 0) return kcal;
    final kj = _asDouble(nutriments['energy_100g']);
    if (kj != null && kj > 0) return kj / 4.184;
    return kcal;
  }

  static String? _asText(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
