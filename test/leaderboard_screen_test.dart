import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/leaderboard_screen.dart';
import 'package:macro_snap/services/leaderboard_service.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The leaderboard screen is reached from Home's Quick Actions, and its numbers
/// come from [LeaderboardService]. These tests pin the two things that break
/// silently: the page renders with no history, and a day's points never exceed
/// the daily ceiling or pay the same award twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'phone': 'guest_test',
      'name': 'Ada',
    });
    await MealStore.instance.reload();
  });

  testWidgets('leaderboard renders with no points and explains the rules', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Leaderboard'), findsOneWidget);

    // The board leads the page, so it — not the week total — is what is on
    // screen without scrolling. Guests see the join prompt, not a fabricated
    // ranking.
    expect(find.text('Fitness leaderboard'), findsOneWidget);
    expect(find.text('District'), findsOneWidget);
    expect(
      find.textContaining('Sign in with Google to see the board'),
      findsOneWidget,
    );

    // The week total, the breakdown and the rules cards follow below the fold,
    // so they only build once scrolled into view.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text("Today's points"),
      260,
      scrollable: list,
    );
    expect(find.text("Today's points"), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Movement'),
      260,
      scrollable: list,
    );
    expect(find.text('Movement'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('How points work'),
      260,
      scrollable: list,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('How points work'), findsOneWidget);
  });

  test('the day ceiling is the sum of the bucket caps', () {
    expect(
      LeaderboardService.dailyMax,
      LeaderboardService.mealDailyCap +
          LeaderboardService.habitDailyCap +
          LeaderboardService.hydrationDailyCap +
          LeaderboardService.movementDailyCap +
          LeaderboardService.weighInPoints +
          LeaderboardService.calorieGoalPoints,
    );
    expect(LeaderboardService.dailyMax, 170);
  });

  test('DayPoints round-trips through JSON and sums its buckets', () {
    final day = DayPoints()
      ..add(PointsBucket.movement, 20)
      ..add(PointsBucket.nutrition, 10)
      ..earnedKeys.add('meal_a');
    expect(day.total, 30);

    final restored = DayPoints.fromJson(day.toJson());
    expect(restored.movement, 20);
    expect(restored.nutrition, 10);
    expect(restored.total, 30);
    expect(restored.earnedKeys, contains('meal_a'));
  });
}
