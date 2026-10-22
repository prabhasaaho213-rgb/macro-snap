import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_reminder_service.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pins the last untested links of the reminder funnel:
///
/// 1. The listener wiring — `NotificationService.init()` registers a listener
///    on `HabitStore.remindersChangedNotifier`, so a plain `HabitStore.add()`
///    (no direct notification calls anywhere in the store) must end up armed
///    through the registry, and a `remove()` must end up cancelled by the
///    orphan sweep. If someone ever bypasses the funnel again, these fail.
/// 2. `logPendingCount` — the best-effort OS-pending diagnostic must never
///    throw, on both the happy path and a platform failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notifChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const tzChannel = MethodChannel('flutter_timezone');

  Habit habit(String id, {bool reminder = true}) => Habit(
    id: id,
    name: 'Habit $id',
    emoji: '💧',
    colorValue: 0xFF00E65C,
    reminderEnabled: reminder,
    reminderHour: 9,
    reminderMinute: 0,
  );

  setUp(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    // The real device timezone fetch must succeed so init() can set tz.local.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, (call) async {
          if (call.method == 'getLocalTimezone') {
            return {'identifier': 'Asia/Kolkata'};
          }
          return null;
        });
    // Reset singleton state that persists across tests in this file.
    HabitStore.instance.habits.clear();
    HabitStore.instance.remindersChangedNotifier.value = 0;
    NotificationService().resetResumeCooldown();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, null);
  });

  /// Records every `zonedSchedule` id and every `cancel` id the plugin is
  /// asked to make, so tests can assert what the funnel actually armed.
  ({List<int> scheduled, List<int> cancelled}) captureCalls() {
    final scheduled = <int>[];
    final cancelled = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async {
          if (call.method == 'zonedSchedule') {
            final args = Map<dynamic, dynamic>.from(call.arguments as Map);
            scheduled.add(args['id'] as int);
          } else if (call.method == 'cancel') {
            final args = Map<dynamic, dynamic>.from(call.arguments as Map);
            cancelled.add(args['id'] as int);
          } else if (call.method == 'initialize') {
            // The Android plugin's initialize returns `Future<bool>` — a null
            // reply would crash with a FutureOr<bool> type error.
            return true;
          }
          return null;
        });
    return (scheduled: scheduled, cancelled: cancelled);
  }

  test('init() wires the funnel: adding a habit arms its reminder', () async {
    final calls = captureCalls();
    final h = habit('wired-habit');

    await NotificationService().init();
    await HabitStore.instance.add(h);

    // Let the unawaited _onHabitsChanged → applyHabitPlan finish.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      calls.scheduled,
      contains(HabitReminderService.notificationId(h)),
      reason:
          'a plain HabitStore.add() must reach the registry through the '
          'remindersChangedNotifier listener — the single funnel',
    );
  });

  test(
    'removing a habit through the funnel cancels its orphan alarm',
    () async {
      final calls = captureCalls();
      final h = habit('wired-remove');

      await NotificationService().init();
      await HabitStore.instance.add(h);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(calls.scheduled, contains(HabitReminderService.notificationId(h)));

      await HabitStore.instance.remove(h);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        calls.cancelled,
        contains(HabitReminderService.notificationId(h)),
        reason:
            'once the habit leaves the list the orphan sweep must cancel its '
            'alarm through the same funnel',
      );
    },
  );

  test(
    'Mark-done action on a habit notification completes the habit (foreground path)',
    () async {
      final h = habit('wired-mark-done');
      HabitStore.instance.habits.add(h);
      final calls = captureCalls();

      await NotificationService().init();

      // Simulate the Android action tap: the plugin dispatches an incoming
      // 'didReceiveNotificationResponse' method call to the foreground
      // callback (onDidReceiveNotificationResponse), which must route the
      // habit_done action to _completeHabit and mark the habit done today.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'dexterous.com/flutter/local_notifications',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', <String, Object?>{
                'notificationId': HabitReminderService.notificationId(h),
                'actionId': HabitReminderService.doneAction,
                'payload': h.id,
                'notificationResponseType': 1, // selectedNotificationAction
              }),
            ),
            (_) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final store = HabitStore.instance;
      final saved = store.habits.firstWhere((x) => x.id == h.id);
      expect(
        saved.completedDates,
        contains(dateKey(DateTime.now())),
        reason:
            'Mark done from the notification shade must complete the habit '
            'for today',
      );
      // And the daily reminder must be pushed to tomorrow (snooze cleared).
      expect(
        calls.cancelled,
        containsAll(<int>[
          HabitReminderService.snoozeId(h),
          HabitReminderService.notificationId(h),
        ]),
      );
    },
  );

  test(
    'Mark done works even when the habit is only in prefs (stale store)',
    () async {
      final h = habit('wired-prefs-only');
      // The in-memory store is EMPTY (long backgrounded session / reload that
      // failed) but the habit exists in prefs — the action must still find it
      // via the prefs fallback and complete it.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('habits', jsonEncode([h.toJson()]));
      await NotificationService().init();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'dexterous.com/flutter/local_notifications',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', <String, Object?>{
                'notificationId': HabitReminderService.notificationId(h),
                'actionId': HabitReminderService.doneAction,
                'payload': h.id,
                'notificationResponseType': 1, // selectedNotificationAction
              }),
            ),
            (_) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final raw = prefs.getString('habits')!;
      final saved = Habit.fromJson(
        Map<String, dynamic>.from((jsonDecode(raw) as List).first as Map),
      );
      expect(
        saved.completedDates,
        contains(dateKey(DateTime.now())),
        reason:
            'Mark done must complete the habit from prefs when the store '
            'is stale',
      );
    },
  );

  test('logPendingCount never throws on the happy path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async {
          if (call.method == 'pendingNotificationRequests') {
            return <Map<dynamic, dynamic>>[
              {'id': 4, 'title': 't', 'body': 'b', 'payload': null},
            ];
          }
          return null;
        });

    await NotificationService().logPendingCount();
    // Completing without throwing is the whole contract (best-effort).
  });

  test(
    'logPendingCount swallows a platform failure (read path is fragile)',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notifChannel, (call) async {
            if (call.method == 'pendingNotificationRequests') {
              throw PlatformException(
                code: 'error',
                message: 'R8 stripped the generic signature',
              );
            }
            return null;
          });

      await NotificationService().logPendingCount();
      // The pending-request read path is exactly what R8/TypeToken broke
      // before — a failure must be swallowed, never surfaced.
    },
  );
}
