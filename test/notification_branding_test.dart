import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/notification_branding.dart';
import 'package:macro_snap/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pins the notification branding: every details block must come out of the
/// single [NotificationBranding] factory with the icon, large icon and
/// brand color present — so the earlier NPE / invalid_icon bugs (blocks
/// missing the icon) can never regress. Also pins the personalized copy
/// builders and the declarative reminder registry's id coverage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationBranding.androidDetails', () {
    test(
      'every details block carries icon, largeIcon and brand color',
      () async {
        final details = await NotificationBranding.androidDetails(
          channelId: 'test_channel',
          channelName: 'Test Channel',
          channelDescription: 'A test channel',
        );

        expect(
          details.color,
          const Color(0xFF059669),
          reason: 'the brand green must be present on every notification',
        );
        expect(
          details.icon,
          '@drawable/ic_notification',
          reason: 'the small icon must never be omitted',
        );
        expect(
          details.largeIcon,
          isNotNull,
          reason: 'the large logo icon must never be omitted',
        );

        // Large icon must be the byte-array (Flutter asset) flavor — R8 can
        // never strip a Flutter asset, which is exactly why we moved it there.
        expect(details.largeIcon, isA<ByteArrayAndroidBitmap>());
        final bytes = await NotificationBranding.largeIconBytes();
        expect(bytes, isNotNull);
        expect(
          bytes!.length,
          greaterThan(1000),
          reason: 'the large icon must be a real PNG, not an empty stub',
        );
      },
    );

    test('habit channel keeps the snooze + mark-done actions', () async {
      // The habit reminder details are built through the same factory — but
      // the actions live in habit_reminder_service. The factory must accept
      // actions so the branding can never drift from the actions.
      final details = await NotificationBranding.androidDetails(
        channelId: 'habit_reminders',
        channelName: 'Habit reminders',
        channelDescription: 'Reminders for your habits',
        importance: Importance.high,
        priority: Priority.high,
        actions: const [
          AndroidNotificationAction('habit_snooze', 'Snooze 10 min'),
          AndroidNotificationAction('habit_done', 'Mark done'),
        ],
      );
      expect(details.actions, hasLength(2));
      expect(details.actions!.first.id, 'habit_snooze');
    });
  });

  group('personalized copy builders', () {
    test('daily meal copy references yesterday calories when known', () {
      final copy = NotificationBranding.dailyMealCopy(yesterdayCalories: 1840);
      expect(copy.title, 'Time to log your meals');
      expect(copy.body, contains('1840 kcal yesterday'));
    });

    test('daily meal copy falls back to the generic nudge without data', () {
      final copy = NotificationBranding.dailyMealCopy(yesterdayCalories: null);
      expect(copy.title, 'Time to log your meals');
      expect(copy.body, isNot(contains('kcal yesterday')));
    });

    test('streak copy names the streak when one is active', () {
      final copy = NotificationBranding.streakCopy(streak: 6);
      expect(copy.title, 'Keep your streak alive');
      expect(copy.body, contains('6-day streak'));
    });

    test('streak copy falls back when there is no streak', () {
      final copy = NotificationBranding.streakCopy(streak: 0);
      expect(copy.title, 'Keep your streak alive');
      expect(copy.body, isNot(contains('streak.')));
    });

    test('weekly copy names real stats from the last 7 days', () {
      final copy = NotificationBranding.weeklyCopy(
        daysHit: 5,
        totalCalories: 12400,
      );
      expect(copy.title, 'Your weekly nutrition summary');
      expect(copy.body, contains('5 of the last 7 days'));
      expect(copy.body, contains('12400 kcal'));
    });

    test('weekly copy falls back to the generic line without data', () {
      final copy = NotificationBranding.weeklyCopy(
        daysHit: 0,
        totalCalories: 0,
      );
      expect(copy.title, 'Your weekly nutrition summary');
      expect(copy.body, isNot(contains('last 7 days')));
    });
  });

  group('declarative reminder registry', () {
    test('subscriber restore arms every built-in id (2,3,4,5,6)', () async {
      final calls = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'zonedSchedule') {
              final args = Map<dynamic, dynamic>.from(call.arguments as Map);
              calls.add(args['id'] as int);
            }
            return null;
          });

      await NotificationService().restoreAllReminders([
        Habit(
          id: 'h1',
          name: 'Test',
          emoji: '💧',
          colorValue: 0xFF00FF66,
          reminderEnabled: false,
        ),
      ], subscribedDate: DateTime.now().toIso8601String());

      expect(
        calls.toSet(),
        containsAll(<int>{2, 3, 4, 5, 6}),
        reason: 'the registry must arm every built-in reminder for subscribers',
      );
    });

    test('free restore arms only the non-subscriber ids (4,6)', () async {
      final calls = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'zonedSchedule') {
              final args = Map<dynamic, dynamic>.from(call.arguments as Map);
              calls.add(args['id'] as int);
            }
            return null;
          });

      await NotificationService().restoreAllReminders([
        Habit(
          id: 'h1',
          name: 'Test',
          emoji: '💧',
          colorValue: 0xFF00FF66,
          reminderEnabled: false,
        ),
      ]);

      expect(
        calls.toSet(),
        <int>{4, 6},
        reason: 'weekly (5) and expiry (2,3) must stay subscriber-only',
      );
    });
  });
}
