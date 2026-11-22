import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:macro_snap/services/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guards for the "two Google accounts on one phone" leaks.
///
/// 1. The display name was a shared `nickname`/`name` pair: renaming one
///    account made every other account on the phone show (and publish) that
///    name.
/// 2. The step sensor's day/baseline keys were global, so the second account
///    inherited the first one's walking for the rest of the day.
/// 3. Health Connect totals are device-wide, so both accounts read the same
///    steps and calories.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the display name belongs to the account that set it', () async {
    SharedPreferences.setMockInitialValues({'phone': 'satya@example.com'});
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.setDisplayName(prefs, 'Satya');
    expect(AccountPartition.displayName(prefs), 'Satya');

    // A second account signs in on the same phone: it starts with no name of
    // its own, not with the first account's.
    await prefs.setString('phone', 'other@example.com');
    expect(AccountPartition.displayName(prefs), isNull);

    await AccountPartition.setDisplayName(prefs, 'Other');
    expect(AccountPartition.displayName(prefs), 'Other');

    // And back again: neither account's name was overwritten by the other.
    await prefs.setString('phone', 'satya@example.com');
    expect(AccountPartition.displayName(prefs), 'Satya');
  });

  test('a blank name never erases a stored one', () async {
    SharedPreferences.setMockInitialValues({'phone': 'satya@example.com'});
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.setDisplayName(prefs, 'Satya');
    await AccountPartition.setDisplayName(prefs, '   ');
    expect(AccountPartition.displayName(prefs), 'Satya');
  });

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
      'health_day',
      'health_baseline_steps',
      'health_baseline_cals',
      'health_baseline_active',
      AccountPartition.displayNameBase,
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

  test('the Health Connect baseline is subtracted, never negative', () {
    final adjusted = HealthService.applyBaseline(
      steps: 4200,
      calories: 180.5,
      active: 60,
      baseSteps: 4000,
      baseCals: 150,
      baseActive: 80,
    );
    expect(adjusted.steps, 200);
    expect(adjusted.calories, closeTo(30.5, 0.001));
    expect(
      adjusted.active,
      0,
      reason: 'a total below the baseline is zero activity, not negative',
    );
  });

  test('a missing reading stays missing after the baseline', () {
    final adjusted = HealthService.applyBaseline(
      steps: null,
      calories: null,
      active: null,
      baseSteps: 100,
      baseCals: 10,
      baseActive: 5,
    );
    expect(adjusted.steps, isNull);
    expect(adjusted.calories, isNull);
    expect(adjusted.active, isNull);
  });
}
