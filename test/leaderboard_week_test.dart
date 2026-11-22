import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/leaderboard_remote.dart';

/// The server scores in Asia/Kolkata. These pin the client's week id and day
/// key to that calendar rather than to the device's timezone, which is what
/// made a phone in another zone (or with a skewed clock) query a board the
/// user's row was never written to.
void main() {
  group('weekId uses the IST calendar', () {
    test('a Sunday-night UTC instant is already next week in IST', () {
      // 2026-11-22 20:00 UTC = 2026-11-23 01:30 IST (Monday, W48).
      expect(
        LeaderboardRemote.weekId(DateTime.utc(2026, 11, 22, 20)),
        '2026-W48',
      );
    });

    test('the same day before 18:30 UTC is still the current week', () {
      // 2026-11-20 06:00 UTC = 11:30 IST on Friday, W47.
      expect(
        LeaderboardRemote.weekId(DateTime.utc(2026, 11, 20, 6)),
        '2026-W47',
      );
    });

    test('the IST boundary is exact: 18:29Z vs 18:30Z', () {
      expect(
        LeaderboardRemote.weekId(DateTime.utc(2026, 11, 22, 18, 29)),
        '2026-W47',
      );
      expect(
        LeaderboardRemote.weekId(DateTime.utc(2026, 11, 22, 18, 30)),
        '2026-W48',
      );
    });
  });

  group('istDayKey', () {
    test('rolls over at 18:30 UTC', () {
      expect(
        LeaderboardRemote.istDayKey(DateTime.utc(2026, 11, 22, 18, 29)),
        '2026-11-22',
      );
      expect(
        LeaderboardRemote.istDayKey(DateTime.utc(2026, 11, 22, 18, 30)),
        '2026-11-23',
      );
    });

    test('is zero-padded for the weight document id', () {
      expect(
        LeaderboardRemote.istDayKey(DateTime.utc(2026, 1, 5, 6)),
        '2026-01-05',
      );
    });
  });
}
