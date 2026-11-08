import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/meal_streak_service.dart';

/// Pins the pure streak math behind MealStreakService: the calorie-goal
/// streak works like a habit's daily streak — every day the goal is met is
/// banked as a date marker, the current streak is the run of consecutive
/// banked days ending today (or yesterday while today is still pending),
/// and the best streak is the longest run on record.
void main() {
  DateTime day(int y, int m, int d) => DateTime(y, m, d);
  String dateKeyOf(int y, int m, int d) => dateKey(day(y, m, d));

  group('computeCurrentStreakFor', () {
    test('a banked today is counted, then the run continues backwards', () {
      final streak = MealStreakService.computeCurrentStreakFor(
        hitDates: [
          for (var i = 0; i < 5; i++) dateKeyOf(2026, 8, 10 - i),
        ],
        today: day(2026, 8, 10),
      );
      expect(streak, 5);
    });

    test('today not banked yet: counts from yesterday (goal still pending)', () {
      final streak = MealStreakService.computeCurrentStreakFor(
        hitDates: [
          dateKeyOf(2026, 8, 8),
          dateKeyOf(2026, 8, 9),
          dateKeyOf(2026, 8, 5),
        ],
        today: day(2026, 8, 10),
      );
      expect(streak, 2);
    });

    test('fresh start, nothing banked, today not met: streak is 0', () {
      final streak = MealStreakService.computeCurrentStreakFor(
        hitDates: const [],
        today: day(2026, 8, 10),
      );
      expect(streak, 0);
    });

    test('a missed day breaks the run — like a habit completion missing', () {
      final streak = MealStreakService.computeCurrentStreakFor(
        hitDates: [
          dateKeyOf(2026, 8, 1),
          dateKeyOf(2026, 8, 2),
          // 3rd missed
          dateKeyOf(2026, 8, 4),
          dateKeyOf(2026, 8, 5),
        ],
        today: day(2026, 8, 5),
      );
      expect(streak, 2);
    });
  });

  group('computeBestStreakFor', () {
    test('longest run wins, even if it is not the current one', () {
      final best = MealStreakService.computeBestStreakFor(
        hitDates: [
          dateKeyOf(2026, 7, 1),
          dateKeyOf(2026, 7, 2),
          dateKeyOf(2026, 7, 3),
          dateKeyOf(2026, 7, 4),
          dateKeyOf(2026, 7, 5),
          // a separate 3-day run later
          dateKeyOf(2026, 8, 1),
          dateKeyOf(2026, 8, 2),
          dateKeyOf(2026, 8, 3),
        ],
      );
      expect(best, 5);
    });

    test('empty history has no best', () {
      expect(
        MealStreakService.computeBestStreakFor(hitDates: const []),
        0,
      );
    });
  });
}
