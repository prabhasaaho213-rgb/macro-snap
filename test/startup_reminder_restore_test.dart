import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Unit tests for [NotificationService.restoreAllReminders] — the startup
/// safety net that re-creates every reminder after the OS drops scheduled
/// alarms (reinstall / update / force-stop). The flutter_local_notifications
/// plugin routes through a method channel, which we mock to record every
/// scheduled notification; both the free path and the subscribed path are
/// pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  /// Records every `zonedSchedule` invocation as (id, payload).
  List<(int, String)> captureCalls() {
    final calls = <(int, String)>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'zonedSchedule') {
            final args = Map<dynamic, dynamic>.from(call.arguments as Map);
            calls.add((args['id'] as int, args['payload'] as String? ?? ''));
          }
          return null;
        });
    return calls;
  }

  Habit habit(String id, {bool reminder = true}) => Habit(
    id: id,
    name: 'Habit $id',
    emoji: '💧',
    colorValue: 0xFF00E65C,
    reminderEnabled: reminder,
    reminderHour: 9,
    reminderMinute: 0,
  );

  setUp(() {
    // Mirrors NotificationService.init(): the timezone database must be
    // initialized or tz.local throws before any scheduling can happen.
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    // Route plugin calls through the channel-based Android implementation so
    // every schedule lands on the mocked method channel (no real platform).
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'free path: schedules daily + streak + every enabled habit, skips disabled',
    () async {
      final calls = captureCalls();

      await NotificationService().restoreAllReminders([
        habit('enabled-a'),
        habit('enabled-b'),
        habit('disabled-c', reminder: false),
      ]);

      // 2 repeating built-ins (daily meal id 4, streak id 6) + 2 enabled
      // habits = 4 zonedSchedule calls. The disabled habit must never appear.
      expect(calls.length, 4);
      final ids = calls.map((c) => c.$1).toSet();
      expect(ids, containsAll(<int>{4, 6}));

      final habitPayloads = calls
          .where((c) => c.$1 != 4 && c.$1 != 6)
          .map((c) => c.$2)
          .toList();
      expect(habitPayloads, containsAll(<String>['enabled-a', 'enabled-b']));
      expect(habitPayloads, isNot(contains('disabled-c')));
    },
  );

  test(
    'subscribed path: also re-arms expiry, expired and weekly reminders',
    () async {
      final calls = captureCalls();

      await NotificationService().restoreAllReminders([
        habit('enabled-a'),
      ], subscribedDate: DateTime.now().toIso8601String());

      // 2 built-ins + 1 habit + expiry (2) + expired (3) + weekly = 6 calls.
      expect(calls.length, 6);
      final ids = calls.map((c) => c.$1).toSet();
      expect(ids, containsAll(<int>{2, 3, 4, 6}));
      expect(ids, isNot(contains('n/a')));
    },
  );
}
