import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/leaderboard_service.dart';

/// The movement rule the product asked for: "for every 5k steps they get 10
/// points". It is exercised on [LeaderboardService.movementPointsFor] rather
/// than through the singleton so the table can be checked without any device
/// state — the same numbers are pinned on the server in
/// backend/test/leaderboard.test.js.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every complete 5,000 steps pays 10 points', () {
    expect(LeaderboardService.movementPointsFor(0), 0);
    expect(LeaderboardService.movementPointsFor(4999), 0);
    expect(LeaderboardService.movementPointsFor(5000), 10);
    expect(LeaderboardService.movementPointsFor(9999), 10);
    expect(LeaderboardService.movementPointsFor(10000), 20);
    expect(LeaderboardService.movementPointsFor(25000), 50);
    expect(LeaderboardService.movementPointsFor(49999), 90);
    expect(LeaderboardService.movementPointsFor(50000), 100);
  });

  test('a corrupt count cannot exceed the movement ceiling', () {
    expect(
      LeaderboardService.movementPointsFor(200000),
      LeaderboardService.movementDailyCap,
    );
    expect(
      LeaderboardService.movementPointsFor(-5),
      0,
      reason: 'a negative reading is no steps, never negative points',
    );
  });

  test('the daily maximum is the sum of the bucket caps', () {
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
}
