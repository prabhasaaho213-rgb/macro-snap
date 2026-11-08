import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guards for account deletion.
///
/// The wipe used to be `prefs.clear()`, which took EVERY account's data on the
/// device: habits, water, weight history, recent foods and badges are all
/// stored as `<base>_<suffix>`. These pin the surgical behaviour instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting one account leaves the other account alone', () async {
    SharedPreferences.setMockInitialValues({
      'phone': 'alice@example.com',
      'habits_alice_example_com': '[{"id":"a"}]',
      'water_log_alice_example_com': '{"2026-11-08":3}',
      'badges_alice_example_com': '{"firstBite":"2026-11-01"}',
      'habits_bob_example_com': '[{"id":"b"}]',
      'water_log_bob_example_com': '{"2026-11-08":1}',
      'weight_log_bob_example_com': '[]',
      'guru_chat': '[]',
    });
    final prefs = await SharedPreferences.getInstance();
    final suffix = AccountPartition.suffix(
      AccountPartition.activeFromPrefs(prefs),
    );
    expect(suffix, 'alice_example_com');

    await AccountPartition.removeAccountData(prefs, suffix: suffix);

    expect(prefs.getString('habits_alice_example_com'), isNull);
    expect(prefs.getString('water_log_alice_example_com'), isNull);
    expect(prefs.getString('badges_alice_example_com'), isNull);

    // The other account on this device is untouched...
    expect(prefs.getString('habits_bob_example_com'), '[{"id":"b"}]');
    expect(prefs.getString('water_log_bob_example_com'), '{"2026-11-08":1}');
    expect(prefs.getString('weight_log_bob_example_com'), '[]');
    // ...and so is the guest's unprefixed key.
    expect(prefs.getString('guru_chat'), '[]');
  });

  test('a guest wipe removes the guest keys only', () async {
    SharedPreferences.setMockInitialValues({
      'phone': 'guest_123',
      'habits': '[]',
      'water_goal': '8',
      'habits_someone_else': '[{"id":"x"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final suffix = AccountPartition.suffix(
      AccountPartition.activeFromPrefs(prefs),
    );
    expect(suffix, '');

    await AccountPartition.removeAccountData(prefs, suffix: suffix);

    expect(prefs.getKeys(), isNot(contains('habits')));
    expect(prefs.getKeys(), isNot(contains('water_goal')));
    expect(prefs.getString('habits_someone_else'), '[{"id":"x"}]');
  });

  test('every account-scoped store is on the wipe list', () {
    // A new per-account store that is missing here would survive a deletion.
    expect(
      AccountPartition.scopedBases,
      containsAll(<String>[
        'meals',
        'diet_profile',
        'habits',
        'water_log',
        'water_goal',
        'badges',
        'weight_log',
        'recent_foods',
        'guru_chat',
      ]),
    );
  });
}
