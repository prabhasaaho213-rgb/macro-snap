import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:macro_snap/widgets/calorie_trend_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CalorieTrendCard is Home's first fl_chart consumer. The existing Home
/// smoke tests only exercise its EMPTY state (the store always starts empty
/// there and the BarChart branch never renders). These tests cover the data
/// path: the BarChart must actually build, show correct daily totals and
/// the goal line, and the 7D/30D toggle must re-render with the right
/// number of rods.
///
/// Seeding runs inside tester.runAsync: MealStore.add() awaits real async
/// work (path_provider + file persistence) that never completes inside the
/// test's FakeAsync zone — it hung the suite until moved into runAsync.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset the singleton so each test starts from a known-empty store.
    // load() swallows path_provider errors, so this is safe without mocks.
    await MealStore.instance.reload();
  });

  MealRecord meal(DateTime date, int kcal) => MealRecord(
        id: '${date.millisecondsSinceEpoch}-$kcal',
        date: date,
        name: 'Test meal',
        category: 'Lunch',
        calories: kcal,
        protein: 10,
        carbs: 20,
        fats: 5,
        fiber: 2,
        serving: '1 plate',
      );

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CalorieTrendCard(goalCalories: 2000)),
      ),
    );
    await tester.pump();
    // Let the BarChart's implicit 350ms animation advance.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('empty store shows the placeholder, not a chart',
      (tester) async {
    await pumpCard(tester);
    expect(find.text('Log a meal to start your trend'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meals render as a BarChart with correct totals, goal line '
      'and a working 30D toggle', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.runAsync(() async {
      await MealStore.instance.add(meal(now, 1800));
      await MealStore.instance.add(
        meal(
          today
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 13)),
          2100,
        ),
      );
      await MealStore.instance.add(
        meal(
          today
              .subtract(const Duration(days: 2))
              .add(const Duration(hours: 19)),
          1650,
        ),
      );
    });

    await pumpCard(tester);

    expect(find.text('Calorie trend'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Goal 2000 kcal'), findsOneWidget);

    // 7-day view: seven rods with the expected daily totals (newest last).
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups.length, 7);
    final totals =
        chart.data.barGroups.map((g) => g.barRods.first.toY).toList();
    expect(totals[totals.length - 1], 1800, reason: "today's total");
    expect(totals[totals.length - 2], 2100, reason: "yesterday's total");
    expect(totals[totals.length - 3], 1650, reason: "two-days-ago total");
    expect(totals[totals.length - 4], 0, reason: "day with no logs is zero");

    // Dashed goal line sits at the configured goal.
    final lines = chart.data.extraLinesData.horizontalLines;
    expect(lines, hasLength(1));
    expect(lines.single.y, 2000);
    expect(tester.takeException(), isNull);

    // 30D toggle: thirty rods, still rendering cleanly.
    await tester.tap(find.text('30D'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final chart30 = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart30.data.barGroups.length, 30);
    expect(
      chart30.data.barGroups.last.barRods.first.toY,
      1800,
      reason: 'today stays the last rod in 30D',
    );
    expect(tester.takeException(), isNull);
  });
}
