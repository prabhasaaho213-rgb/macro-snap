import 'dart:convert';

import 'package:http/http.dart' as http;

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
  static const String userAgent =
      'MacroSnap/1.5.9 (Android; macrosnap7@gmail.com)';

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
    try {
      final response = await (client ?? http.Client())
          .get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return foodFromOpenFoodFacts(decoded, barcode);
    } catch (_) {
      // Offline, DNS failure, timeout, malformed JSON — all mean "no answer".
      return null;
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

    final calories = _caloriesPer100g(nutriments);
    final protein = _asDouble(nutriments['proteins_100g']);
    final carbs = _asDouble(nutriments['carbohydrates_100g']);
    final fats = _asDouble(nutriments['fat_100g']);

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
