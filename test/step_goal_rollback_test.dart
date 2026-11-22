import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/step_goal_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guard for the step streak rollback.
///
/// `recordToday` takes a day back when a later read comes below the goal (a
/// Health Connect record deleted, a source correcting its total, the phone's
/// step sensor restarting after a reboot). It used to clear the "last goal day"
/// as well, so when the steps recovered on the same day `_lastGoalDay ==
/// yesterday` was false and the streak restarted at 1 — a two-second dip cost
/// the whole run.
String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = StepGoalService.instance;

  test('a dip below the goal keeps the run recoverable', () async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    SharedPreferences.setMockInitialValues({
      'health_step_goal': 10000,
      'health_step_streak_day': _dayKey(yesterday),
      'health_step_streak_count': 4,
      'health_step_streak_best': 4,
    });
    await service.reload();
    expect(service.streak, 4, reason: 'yesterday kept the run alive');

    // Reaching the goal today extends the run.
    await service.recordToday(12000);
    expect(service.streak, 5);
    expect(service.reachedToday, isTrue);

    // A temporary dip takes today back...
    await service.recordToday(3000);
    expect(service.streak, 4);
    expect(service.reachedToday, isFalse);

    // ...and meeting the goal again the same day restores 5, not 1.
    await service.recordToday(12500);
    expect(service.streak, 5);
    expect(service.reachedToday, isTrue);
  });

  test('a run that drops to zero starts over cleanly', () async {
    SharedPreferences.setMockInitialValues({
      'health_step_goal': 10000,
    });
    await service.reload();
    expect(service.streak, 0);

    await service.recordToday(11000);
    expect(service.streak, 1);

    await service.recordToday(100);
    expect(service.streak, 0);
    expect(service.reachedToday, isFalse);

    await service.recordToday(11000);
    expect(service.streak, 1, reason: 'a broken run restarts at 1');
  });
}
