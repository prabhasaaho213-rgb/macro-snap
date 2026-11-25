import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:macro_snap/services/leaderboard_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guards for the leaderboard's two account bugs.
///
/// 1. Every prefs key was global, so on a shared phone the next account
///    inherited the previous one's points, opt-in, district and published-board
///    history.
/// 2. [LeaderboardService] is a singleton that never re-read, so even once the
///    keys were partitioned the previous account's state stayed in memory — and
///    the next publish would have put it on a board under the new name.
///
/// Plus: the step award is provisional and must be reversed when a later
/// Health Connect read comes back below the goal.
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = LeaderboardService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await service.reload();
  });

  test('leaderboard state is per account and reloads on a switch', () async {
    final alice = AccountPartition.suffix('alice@example.com');
    final today = _dayKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      'phone': 'alice@example.com',
      AccountPartition.key('leaderboard_days_v1', alice): jsonEncode({
        'days': {
          today: {
            'n': 10,
            'k': ['meal_a'],
          },
        },
      }),
      AccountPartition.key('leaderboard_opt_in', alice): true,
      AccountPartition.key('leaderboard_state_key', alice): 'maharashtra',
      AccountPartition.key('leaderboard_district', alice): 'Pune',
    });
    final prefs = await SharedPreferences.getInstance();

    await service.reload();
    expect(service.weekPoints, 10, reason: "alice's own points");
    expect(service.optIn, isTrue);
    expect(service.district, 'Pune');

    // A second account signs in on the same phone. None of the first account's
    // state may follow it.
    await prefs.setString('phone', 'bob@example.com');
    await service.reload();
    expect(service.weekPoints, 0);
    expect(service.optIn, isFalse);
    expect(service.district, isNull);
    expect(service.stateKey, isNull);

    // Switching back restores alice's state intact.
    await prefs.setString('phone', 'alice@example.com');
    await service.reload();
    expect(service.weekPoints, 10);
    expect(service.optIn, isTrue);
    expect(service.district, 'Pune');
    expect(service.stateKey, 'maharashtra');
  });

  test('writes land in the active partition, never in a global key', () async {
    final alice = AccountPartition.suffix('alice@example.com');
    SharedPreferences.setMockInitialValues({'phone': 'alice@example.com'});
    final prefs = await SharedPreferences.getInstance();
    await service.reload();

    await service.setProfile(
      optIn: true,
      stateKey: 'maharashtra',
      district: 'Pune',
    );

    expect(prefs.getBool('leaderboard_opt_in'), isNull);
    expect(
      prefs.getBool(AccountPartition.key('leaderboard_opt_in', alice)),
      isTrue,
    );
    expect(
      prefs.getString(AccountPartition.key('leaderboard_district', alice)),
      'Pune',
    );
  });

  test('movement pays per 5,000 steps and is never taken back', () async {
    SharedPreferences.setMockInitialValues({'phone': 'alice@example.com'});
    await service.reload();

    // 12,000 steps in a day, but a free account is capped at its daily step
    // limit, so the day is worth the capped total (10), not the raw distance.
    await service.noteSteps(12000);
    expect(service.todayPoints, 10);

    // A later read coming back lower (a reboot, a fresh sensor, a corrected
    // source) must not walk the day backwards: the stored total only grows.
    await service.noteSteps(4200);
    expect(service.todayPoints, 10);
  });

  // The "server score is shown for the week it was scored for" case was
  // removed with the local server-score cache: the board's number now comes
  // from the Firestore rows the backend writes, so there is no per-week local
  // copy left to test.

  test('account deletion removes the leaderboard partition only', () async {
    final alice = AccountPartition.suffix('alice@example.com');
    final bob = AccountPartition.suffix('bob@example.com');
    SharedPreferences.setMockInitialValues({
      'phone': 'alice@example.com',
      AccountPartition.key('leaderboard_opt_in', alice): true,
      AccountPartition.key('leaderboard_district', alice): 'Pune',
      AccountPartition.key('leaderboard_days_v1', alice): '{"days":{}}',
      AccountPartition.key('leaderboard_opt_in', bob): true,
    });
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.removeAccountData(prefs, suffix: alice);

    expect(
      prefs.getBool(AccountPartition.key('leaderboard_opt_in', alice)),
      isNull,
    );
    expect(
      prefs.getString(AccountPartition.key('leaderboard_district', alice)),
      isNull,
    );
    expect(
      prefs.getString(AccountPartition.key('leaderboard_days_v1', alice)),
      isNull,
    );
    // The other account on this phone is untouched.
    expect(
      prefs.getBool(AccountPartition.key('leaderboard_opt_in', bob)),
      isTrue,
    );
  });
}
