import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/barcode_db.dart';
import 'package:macro_snap/services/barcode_lookup.dart';

/// The scan flow depends on [BarcodeService.foodFromOpenFoodFacts] turning a
/// real API payload into something loggable. Getting this wrong is invisible
/// on the device — the card simply shows zeros — so every rule is pinned here.
void main() {
  Map<String, dynamic> hit({
    String? name = 'Masala Oats',
    dynamic brands = 'Saffola, Marico',
    Map<String, dynamic>? nutriments,
  }) => {
    'status': 1,
    'product': {
      'product_name': name,
      'brands': brands,
      'nutriments':
          nutriments ??
          {
            'energy-kcal_100g': 380,
            'proteins_100g': 8.5,
            'carbohydrates_100g': 61.2,
            'fat_100g': 10.4,
            'fiber_100g': 4.0,
            'sugars_100g': 6.1,
          },
    },
  };

  group('foodFromOpenFoodFacts — happy path', () {
    test('maps per-100g nutriments onto the barcode food model', () {
      final food = BarcodeService.foodFromOpenFoodFacts(hit(), '8901234567890')!;

      expect(food.barcode, '8901234567890');
      expect(food.name, 'Masala Oats');
      expect(food.brand, 'Saffola', reason: 'only the first brand is shown');
      expect(food.caloriesPer100g, 380);
      expect(food.proteinPer100g, 8.5);
      expect(food.carbsPer100g, 61.2);
      expect(food.fatsPer100g, 10.4);
      expect(food.fiberPer100g, 4.0);
      expect(food.sugarPer100g, 6.1);
    });

    test('numeric strings from the API are parsed, not dropped', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        hit(
          nutriments: {
            'energy-kcal_100g': '250',
            'proteins_100g': '5.5',
            'carbohydrates_100g': '40',
            'fat_100g': '8',
          },
        ),
        '12345678',
      )!;

      expect(food.caloriesPer100g, 250);
      expect(food.proteinPer100g, 5.5);
      expect(food.carbsPer100g, 40);
      expect(food.fatsPer100g, 8);
    });

    test('kilojoules-only products are converted to kcal', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        hit(
          nutriments: {
            'energy_100g': 1590, // kJ
            'proteins_100g': 10,
            'carbohydrates_100g': 50,
            'fat_100g': 12,
          },
        ),
        '12345678',
      )!;

      expect(food.caloriesPer100g, 380); // 1590 / 4.184
    });

    test('a missing brand falls back instead of showing an empty line', () {
      final food = BarcodeService.foodFromOpenFoodFacts(
        hit(brands: ' '),
        '12345678',
      )!;
      expect(food.brand, 'Packaged food');
    });
  });

  group('foodFromOpenFoodFacts — misses', () {
    test('status 0 (unknown barcode) returns null', () {
      expect(
        BarcodeService.foodFromOpenFoodFacts({
          'status': 0,
          'status_verbose': 'product not found',
        }, '0000000000000'),
        isNull,
      );
    });

    test('a nameless product is not loggable', () {
      expect(BarcodeService.foodFromOpenFoodFacts(hit(name: '  '), '1'), isNull);
    });

    test('a product with no nutrition at all is not loggable', () {
      expect(
        BarcodeService.foodFromOpenFoodFacts(hit(nutriments: {}), '1'),
        isNull,
      );
    });

    test('malformed payloads return null rather than throwing', () {
      expect(BarcodeService.foodFromOpenFoodFacts({}, '1'), isNull);
      expect(
        BarcodeService.foodFromOpenFoodFacts({'status': 1, 'product': 'x'}, '1'),
        isNull,
      );
    });
  });

  group('isProductBarcode', () {
    test('accepts EAN-8 to EAN-13 style digits', () {
      expect(BarcodeService.isProductBarcode('12345678'), isTrue);
      expect(BarcodeService.isProductBarcode('8901234567890'), isTrue);
    });

    test('rejects QR payloads, short codes and blanks', () {
      expect(BarcodeService.isProductBarcode('https://x.co'), isFalse);
      expect(BarcodeService.isProductBarcode('123'), isFalse);
      expect(BarcodeService.isProductBarcode(''), isFalse);
      expect(BarcodeService.isProductBarcode('8901234A67890'), isFalse);
    });
  });

  group('lookup', () {
    test('answers from the bundled table without touching the network', () async {
      const known = '8901063010138'; // Parle Marie Gold, in BarcodeDb
      final food = await BarcodeService.lookup(known);
      expect(food, isNotNull);
      expect(food!.name, BarcodeDb.lookup(known)!.name);
    });
  });
}
