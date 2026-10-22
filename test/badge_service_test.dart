import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/app_badge.dart';
import 'package:macro_snap/services/badge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The achievement rules: every badge here rewards *logging* — a meal, a
/// weigh-in, a streak — and nothing ever inspects a weight or a calorie
/// deficit. Also pins the per-account partition: two accounts on one phone
/// must not share a trophy case.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BadgeService.instance.resetForTest();
  });

  tearDown(() {
    BadgeService.instance.resetForTest();
  });

  test('no badge is earned before anything is logged', () async {
    await BadgeService.instance.load();
    expect(BadgeService.instance.earnedCount, 0);
    expect(BadgeService.instance.locked.length, AppBadge.all.length);
  });

  test('first meal earns First Bite and nothing else', () async {
    await BadgeService.instance.noteMealLogged(1);
    expect(BadgeService.instance.isEarned('first_bite'), isTrue);
    expect(BadgeService.instance.isEarned('ten_plates'), isFalse);
    expect(BadgeService.instance.earnedCount, 1);
  });

  test('ten meals earns Ten Plates', () async {
    await BadgeService.instance.noteMealLogged(10);
    expect(BadgeService.instance.isEarned('first_bite'), isTrue);
    expect(BadgeService.instance.isEarned('ten_plates'), isTrue);
  });

  test(
    'one weigh-in earns First Weigh-In — the value is never inspected',
    () async {
      await BadgeService.instance.noteWeighIn();
      expect(BadgeService.instance.isEarned('first_weigh_in'), isTrue);
    },
  );

  test('7-day streak earns Week Warrior, not the fortnight badge', () async {
    await BadgeService.instance.noteStreak(7);
    expect(BadgeService.instance.isEarned('week_warrior'), isTrue);
    expect(BadgeService.instance.isEarned('fortnight_flame'), isFalse);
  });

  test('14-day streak earns both streak badges', () async {
    await BadgeService.instance.noteStreak(14);
    expect(BadgeService.instance.isEarned('week_warrior'), isTrue);
    expect(BadgeService.instance.isEarned('fortnight_flame'), isTrue);
  });

  test('a short streak earns nothing', () async {
    await BadgeService.instance.noteStreak(3);
    expect(BadgeService.instance.earnedCount, 0);
  });

  test('justEarned fires once per new badge, not on re-award', () async {
    await BadgeService.instance.load();
    await BadgeService.instance.noteMealLogged(1);
    expect(BadgeService.instance.justEarned.value?.id, 'first_bite');
    BadgeService.instance.justEarned.value = null;

    // Same badge again: no second celebration.
    await BadgeService.instance.noteMealLogged(2);
    expect(BadgeService.instance.justEarned.value, isNull);
  });

  test('badges persist across a reload', () async {
    await BadgeService.instance.noteMealLogged(1);
    BadgeService.instance.resetForTest();
    await BadgeService.instance.load();
    expect(BadgeService.instance.isEarned('first_bite'), isTrue);
  });

  test('two accounts on one phone have separate boards', () async {
    SharedPreferences.setMockInitialValues({
      'phone': 'alice@example.com',
      'badges_alice_example_com': '{"first_bite":"2026-10-20T10:00:00.000"}',
    });
    BadgeService.instance.resetForTest();
    await BadgeService.instance.load();
    expect(BadgeService.instance.isEarned('first_bite'), isTrue);

    // Bob signs in: his partition starts empty.
    SharedPreferences.setMockInitialValues({
      'phone': 'bob@example.com',
      'badges_alice_example_com': '{"first_bite":"2026-10-20T10:00:00.000"}',
    });
    BadgeService.instance.resetForTest();
    await BadgeService.instance.load();
    expect(BadgeService.instance.isEarned('first_bite'), isFalse);
  });

  test(
    'a stale badge id from a future/old build never crashes the board',
    () async {
      SharedPreferences.setMockInitialValues({
        'badges': '{"no_such_badge":"2026-01-01T00:00:00.000"}',
      });
      BadgeService.instance.resetForTest();
      await BadgeService.instance.load();
      expect(BadgeService.instance.earnedCount, 0);
      expect(AppBadge.byId('no_such_badge'), isNull);
    },
  );
}
