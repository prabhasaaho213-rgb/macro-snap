import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Changing the partition suffix is the one change that can delete a user's
/// local history, so the migration is pinned here: old-suffix keys and keys
/// written before the first sign-in must arrive under the new suffix exactly
/// once, and nothing may be overwritten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const email = 'alice@example.com';

  test('old-suffix data moves to the new suffix', () async {
    final legacy = AccountPartition.legacySuffix(email);
    final current = AccountPartition.suffix(email);
    expect(legacy, isNot(current));

    SharedPreferences.setMockInitialValues({
      'phone': email,
      AccountPartition.key('habits', legacy): '[{"id":"h1"}]',
      AccountPartition.key('water_goal', legacy): 9,
    });
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.ensureCurrent(prefs);

    expect(prefs.getString(AccountPartition.key('habits', current)),
        '[{"id":"h1"}]');
    expect(prefs.getInt(AccountPartition.key('water_goal', current)), 9);
    expect(
      prefs.getString(AccountPartition.key('habits', legacy)),
      isNull,
      reason: 'the old key is removed so it cannot be read twice',
    );
  });

  test('pre-sign-in data becomes the account partition at sign-in', () async {
    SharedPreferences.setMockInitialValues({
      'phone': email,
      // Written by onboarding, before any account was active.
      'habits': '[{"id":"pre-login-habit"}]',
      'water_goal': 6,
      'pending_sync': '{"pre-login-meal":"set"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final current = AccountPartition.suffix(email);

    await AccountPartition.ensureCurrent(prefs);

    expect(prefs.getString(AccountPartition.key('habits', current)),
        '[{"id":"pre-login-habit"}]');
    expect(prefs.getInt(AccountPartition.key('water_goal', current)), 6);
    expect(
      prefs.getString(AccountPartition.key('pending_sync', current)),
      '{"pre-login-meal":"set"}',
      reason: 'queued uploads must follow the data they belong to',
    );
    expect(prefs.getString('habits'), isNull);
  });

  test('newer data is never overwritten by a migration', () async {
    final legacy = AccountPartition.legacySuffix(email);
    final current = AccountPartition.suffix(email);

    SharedPreferences.setMockInitialValues({
      'phone': email,
      AccountPartition.key('habits', legacy): '[{"id":"old"}]',
      AccountPartition.key('habits', current): '[{"id":"new"}]',
    });
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.ensureCurrent(prefs);

    expect(prefs.getString(AccountPartition.key('habits', current)),
        '[{"id":"new"}]');
  });

  test('an account id that is not signed in stays on the unprefixed partition',
      () async {
    SharedPreferences.setMockInitialValues({
      'phone': 'guest_abc123',
      'habits': '[{"id":"g"}]',
    });
    final prefs = await SharedPreferences.getInstance();

    await AccountPartition.ensureCurrent(prefs);

    expect(prefs.getString('habits'), '[{"id":"g"}]');
    expect(AccountPartition.suffix('guest_abc123'), isEmpty);
  });

  test('migrating twice changes nothing', () async {
    SharedPreferences.setMockInitialValues({
      'phone': email,
      'habits': '[{"id":"h1"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final current = AccountPartition.suffix(email);

    await AccountPartition.ensureCurrent(prefs);
    final afterFirst = prefs.getString(AccountPartition.key('habits', current));
    await AccountPartition.ensureCurrent(prefs);

    expect(
      prefs.getString(AccountPartition.key('habits', current)),
      afterFirst,
    );
  });
}
