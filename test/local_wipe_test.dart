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
    final alice = AccountPartition.suffix('alice@example.com');
    final bob = AccountPartition.suffix('bob@example.com');
    SharedPreferences.setMockInitialValues({
      'phone': 'alice@example.com',
      AccountPartition.key('habits', alice): '[{"id":"a"}]',
      AccountPartition.key('water_log', alice): '{"2026-11-08":3}',
      AccountPartition.key('badges', alice): '{"firstBite":"2026-11-01"}',
      AccountPartition.key('habits', bob): '[{"id":"b"}]',
      AccountPartition.key('water_log', bob): '{"2026-11-08":1}',
      AccountPartition.key('weight_log', bob): '[]',
      'guru_chat': '[]',
    });
    final prefs = await SharedPreferences.getInstance();
    final suffix = AccountPartition.suffix(
      AccountPartition.activeFromPrefs(prefs),
    );
    expect(suffix, startsWith('alice_example_com_'));

    await AccountPartition.removeAccountData(prefs, suffix: suffix);

    expect(
      prefs.getString(AccountPartition.key('habits', suffix)),
      isNull,
    );
    expect(
      prefs.getString(AccountPartition.key('water_log', suffix)),
      isNull,
    );
    expect(prefs.getString(AccountPartition.key('badges', suffix)), isNull);

    // The other account on this device is untouched...
    expect(prefs.getString(AccountPartition.key('habits', bob)), '[{"id":"b"}]');
    expect(
      prefs.getString(AccountPartition.key('water_log', bob)),
      '{"2026-11-08":1}',
    );
    expect(prefs.getString(AccountPartition.key('weight_log', bob)), '[]');
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
