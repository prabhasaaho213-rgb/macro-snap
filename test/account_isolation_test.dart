import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guards for the "two Google accounts on one phone" leaks.
///
/// Scope note: this file used to also guard a scoped `name` pref and a Health
/// Connect baseline subtraction. Neither exists in this build — the display
/// name comes from the signed-in Google account (published through
/// `userNameNotifier`), and Health Connect de-duplicates its own totals now, so
/// the dashboard reads them directly. Those two tests referenced APIs that were
/// never in the codebase and kept the suite red; what is left here guards the
/// partitioning that is actually shipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the phone-level readings are all in scopedBases', () {
    // Every one of these used to be a global key. If a base is missing here the
    // next account on the phone inherits it, and account deletion leaves it
    // behind.
    for (final base in const [
      'sensor_steps_day',
      'sensor_steps_baseline',
      'sensor_steps_carried',
      'sensor_steps_today',
      'sensor_steps_last_total',
      'calorie_goal_hit_dates',
      'leaderboard_days_v1',
      'leaderboard_opt_in',
    ]) {
      expect(AccountPartition.scopedBases, contains(base), reason: base);
    }
  });

  test('sensor keys resolve differently for two accounts', () {
    final alice = AccountPartition.suffix('alice@example.com');
    final bob = AccountPartition.suffix('bob@example.com');
    expect(
      AccountPartition.key('sensor_steps_carried', alice),
      isNot(AccountPartition.key('sensor_steps_carried', bob)),
    );
  });

  test('ids that sanitise to the same body still get different partitions', () {
    // The collision the hash exists for: both collapse to `a_b_x_com`.
    expect(
      AccountPartition.suffix('a.b@x.com'),
      isNot(AccountPartition.suffix('a_b@x.com')),
    );
  });

  test('data written before sign-in moves onto the account', () async {
    SharedPreferences.setMockInitialValues({'meals': 'guest-meals'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', 'satya@example.com');

    await AccountPartition.ensureCurrent(prefs);

    final suffix = AccountPartition.suffix('satya@example.com');
    expect(
      prefs.getString(AccountPartition.key('meals', suffix)),
      'guest-meals',
      reason: 'a guest\'s meals become the account\'s when it signs in',
    );
    expect(
      prefs.getString('meals'),
      isNull,
      reason: 'the unprefixed copy is removed once it has moved',
    );
  });

  test('a second account never inherits the first account\'s keys', () async {
    SharedPreferences.setMockInitialValues({
      'meals': 'guest-meals',
      'phone': 'satya@example.com',
    });
    final prefs = await SharedPreferences.getInstance();
    await AccountPartition.ensureCurrent(prefs);

    final satya = AccountPartition.suffix('satya@example.com');
    final other = AccountPartition.suffix('other@example.com');
    expect(prefs.getString(AccountPartition.key('meals', satya)), isNotNull);
    expect(
      prefs.getString(AccountPartition.key('meals', other)),
      isNull,
      reason: 'the other account starts empty',
    );
  });
}
