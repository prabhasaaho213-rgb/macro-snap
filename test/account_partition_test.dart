import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/account_partition.dart';
import 'package:macro_snap/services/habit_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountPartition', () {
    test('suffix is empty for guests and legacy guest ids', () {
      expect(AccountPartition.suffix(''), isEmpty);
      expect(AccountPartition.suffix('guest_abc'), isEmpty);
      expect(AccountPartition.suffix('   '), isEmpty);
    });

    test('suffix is stable, lowercased and filesystem-safe', () {
      final suffix = AccountPartition.suffix('PrabhasAaHo213@Gmail.com');
      expect(suffix, startsWith('prabhasaaho213_gmail_com_'));
      // Same account, same partition — every launch, every store.
      expect(
        AccountPartition.suffix('prabhasaaho213@gmail.com'),
        suffix,
        reason: 'case and surrounding space must not move the partition',
      );
      expect(
        RegExp(r'^[a-z0-9_]+$').hasMatch(suffix),
        isTrue,
        reason: 'the suffix is used in file names',
      );
    });

    test('two ids that sanitise to the same text get different partitions', () {
      // `a.b@x.com` and `a_b@x.com` both flatten to `a_b_x_com`. Before the
      // hash they shared one partition, so each account could read the
      // other's meals and habits.
      expect(
        AccountPartition.suffix('a.b@x.com'),
        isNot(AccountPartition.suffix('a_b@x.com')),
      );
      expect(
        AccountPartition.legacySuffix('a.b@x.com'),
        AccountPartition.legacySuffix('a_b@x.com'),
        reason: 'the old scheme is the reason the fix exists',
      );
    });

    test('key keeps the legacy base for guests', () {
      expect(AccountPartition.key('habits', ''), 'habits');
      expect(AccountPartition.key('habits', 'a_b'), 'habits_a_b');
    });
  });

  group('HabitStore account isolation', () {
    test('habits never leak across accounts on the same device', () async {
      final habit = Habit(
        id: 'h1',
        name: 'Run',
        emoji: '🏃',
        colorValue: 0xFF00CC52,
        frequency: 'Daily',
      );

      // Account A signs in right after the partition update: the legacy
      // (pre-partitioning) data migrates into A's partition and the legacy
      // key is deleted so no other account can ever inherit it.
      SharedPreferences.setMockInitialValues({
        'phone': 'a@gmail.com',
        'habits': jsonEncode([habit.toJson()]),
      });
      await HabitStore.instance.reload();
      expect(
        HabitStore.instance.habits.any((h) => h.id == 'h1'),
        isTrue,
        reason: 'A migrates the legacy habits into their own partition',
      );
      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('habits'),
        isNull,
        reason:
            'legacy key is deleted after migration so B can never '
            'inherit A\u2019s data',
      );
      expect(
        prefs.getString(
          AccountPartition.key('habits', AccountPartition.suffix('a@gmail.com')),
        ),
        isNotNull,
      );

      // Account B signs in on the same device: must NOT see A's habits.
      prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', 'b@gmail.com');
      await HabitStore.instance.reload();
      expect(
        HabitStore.instance.habits,
        isEmpty,
        reason: 'B sees an empty partition, never A\u2019s habits',
      );

      // Switching back to account A restores A's partition.
      await prefs.setString('phone', 'a@gmail.com');
      await HabitStore.instance.reload();
      expect(
        HabitStore.instance.habits.any((h) => h.id == 'h1'),
        isTrue,
        reason: 'A\u2019s data is still there when they log back in',
      );
    });

    test(
      'a signed-in account writing habits never touches the guest keys',
      () async {
        SharedPreferences.setMockInitialValues({'phone': 'a@gmail.com'});
        final store = HabitStore.instance;
        await store.reload();
        store.habits.clear();
        await store.add(
          Habit(
            id: 'g1',
            name: 'Drink water',
            emoji: '💧',
            colorValue: 0xFF00CC52,
            frequency: 'Daily',
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(
            AccountPartition.key(
              'habits',
              AccountPartition.suffix('a@gmail.com'),
            ),
          ),
          isNotNull,
        );
        expect(prefs.getString('habits'), isNull);

        // Logout (phone cleared) → guest reads the legacy keys, which are empty.
        await prefs.remove('phone');
        await store.reload();
        expect(store.habits, isEmpty);
      },
    );
  });
}
