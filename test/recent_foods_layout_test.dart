import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/recent_foods_screen.dart';
import 'package:macro_snap/services/recent_food_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Recent Foods card packs a name, a category chip, three macros, an age,
/// a calorie pill and an add button into one row. Its meta line used to be an
/// unconstrained Row inside a ~100 px column: it overflowed and the calorie
/// pill painted over the end of it ("the texts are overlapping").
void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    if (RecentFoodService.instance.foods.isEmpty) {
      await RecentFoodService.instance.add(
        RecentFood(
          id: 'a',
          name: 'Cadbury Dairy Milk Silk Fruit and Nut Chocolate Bar',
          calories: 3210,
          protein: 45,
          carbs: 342,
          fats: 186,
          scannedAt: DateTime.now(),
        ),
      );
    }

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const MaterialApp(home: RecentFoodsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a long name does not overflow at 360 dp', (tester) async {
    await pumpScreen(tester, width: 360);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Cadbury Dairy Milk Silk'), findsOneWidget);
  });

  testWidgets('a long name does not overflow at 320 dp with large text', (
    tester,
  ) async {
    await pumpScreen(tester, width: 320, textScale: 1.4);
    expect(tester.takeException(), isNull);
  });
}
