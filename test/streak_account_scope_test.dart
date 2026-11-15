import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:macro_snap/services/meal_streak_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The calorie-goal streak used to live in one global preferences key, so a
/// second account on the same phone inherited the first one's banked days —
/// and the streak badges backfilled from them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MealStreakService.resetForTest();
  });

  test('two accounts on one phone have separate streaks', () async {
    final accountA = AccountPartition.suffix('a@example.com');
    final accountB = AccountPartition.suffix('b@example.com');
    SharedPreferences.setMockInitialValues({
      'phone': 'a@example.com',
      AccountPartition.key('calorie_goal_hit_dates', accountA): [
        '2026-11-08',
        '2026-11-09',
        '2026-11-10',
      ].join(','),
      AccountPartition.key('calorie_goal_hit_dates', accountB): '2026-11-10',
    });

    MealStreakService.resetForTest();
    await MealStreakService.load();
    // getBest is date-independent: the banked days are in the past relative to
    // whenever this test runs.
    expect(await MealStreakService.getBest(), 3);

    // Switch account: the cached set must be dropped and re-read.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', 'b@example.com');
    await MealStreakService.reload();
    expect(await MealStreakService.getBest(), 1);
  });

  test('a legacy global key seeds once, then stops leaking across accounts',
      () async {
    SharedPreferences.setMockInitialValues({
      'phone': 'a@example.com',
      'calorie_goal_hit_dates': '2026-11-09,2026-11-10',
    });

    MealStreakService.resetForTest();
    await MealStreakService.load();
    expect(await MealStreakService.getBest(), 2);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey('calorie_goal_hit_dates'),
      isFalse,
      reason: 'the global key must be removed after it seeds an account',
    );
  });

  test('a streak across a DST change counts calendar days, not 24h steps', () {
    // 2026-03-08 is the US spring-forward day; the pure helpers never touch
    // time zones, but the check documents that consecutive calendar keys are
    // what the streak follows.
    final best = MealStreakService.computeBestStreakFor(
      hitDates: ['2026-03-07', '2026-03-08', '2026-03-09'],
    );
    expect(best, 3);
  });
}
