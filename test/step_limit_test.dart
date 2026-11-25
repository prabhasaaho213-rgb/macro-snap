import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/step_limit.dart';

/// The free plan records 5,000 steps a day; Pro lifts the ceiling. One helper
/// decides that for the dashboard, the goal, the streak and the leaderboard, so
/// these tests pin the arithmetic all of them share.
void main() {
  tearDown(() => StepLimit.proOverride = null);

  test('the free plan caps steps, the goal and the prompt at 5,000', () {
    StepLimit.proOverride = false;

    expect(StepLimit.cap(0), 0);
    expect(StepLimit.cap(4999), 4999);
    expect(StepLimit.cap(5000), 5000);
    expect(StepLimit.cap(12345), StepLimit.freeDaily);

    expect(StepLimit.reached(4999), isFalse);
    expect(StepLimit.reached(5000), isTrue);
    expect(StepLimit.reached(20000), isTrue);

    // A 10,000 target would be a ring that never fills, so it is pinned.
    expect(StepLimit.goal(10000), 5000);
    expect(StepLimit.goal(5000), 5000);
  });

  test('Pro leaves every number exactly as it was', () {
    StepLimit.proOverride = true;

    expect(StepLimit.cap(12345), 12345);
    expect(StepLimit.reached(20000), isFalse);
    expect(StepLimit.goal(10000), 10000);
  });
}
