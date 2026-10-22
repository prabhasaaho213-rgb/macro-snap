import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_reminder_service.dart';
import 'package:macro_snap/services/habit_store.dart';

/// The method channel the local-notifications plugin invokes on Android.
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// Every (method, arguments) pair the plugin channel received during a test.
final List<(String, Map<dynamic, dynamic>)> _calls = [];

/// Registers the Android platform implementation and routes its method
/// channel to [_channel]'s mock so `zonedSchedule`/`cancel`/`initialize`
/// record their arguments instead of throwing MissingPluginException.
void _registerAndroidPluginMock() {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        final args = call.arguments;
        _calls.add((
          call.method,
          args is Map ? Map<dynamic, dynamic>.from(args) : {},
        ));
        switch (call.method) {
          case 'initialize':
          case 'requestNotificationsPermission':
            return true;
          default:
            return null;
        }
      });
}

void _tearDownMock() {
  debugDefaultTargetPlatformOverride = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

/// The id the plugin was asked to cancel (android passes a map).
List<dynamic> _cancelIds() =>
    _calls.where((c) => c.$1 == 'cancel').map((c) => c.$2['id']).toList();

/// The first zonedSchedule call arguments.
Map<dynamic, dynamic> _firstSchedule() =>
    _calls.firstWhere((c) => c.$1 == 'zonedSchedule').$2;

Habit _habit({
  String id = 'h1',
  String name = 'Run',
  bool reminder = true,
  int hour = 20,
  int minute = 0,
}) => Habit(
  id: id,
  name: name,
  emoji: '🏃',
  colorValue: 0xFF00FF66,
  reminderEnabled: reminder,
  reminderHour: hour,
  reminderMinute: minute,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HabitStore.instance.habits.clear();
    _calls.clear();
    tz_data.initializeTimeZones();
    _registerAndroidPluginMock();
  });

  tearDown(_tearDownMock);

  // ─── ID HELPER STABILITY ───────────────────────────────────

  test('notificationId is stable and snoozeId never collides with it', () {
    final a = _habit(id: 'alpha');
    final b = _habit(id: 'alpha');
    expect(
      HabitReminderService.notificationId(a),
      HabitReminderService.notificationId(b),
      reason: 'same habit id must always map to the same notification id',
    );
    expect(
      HabitReminderService.snoozeId(a),
      isNot(HabitReminderService.notificationId(a)),
      reason: 'the snooze id must be distinct from the daily id',
    );
    expect(HabitReminderService.snoozeId(a), greaterThan(0));
    expect(HabitReminderService.notificationId(a), greaterThan(0));
  });

  // ─── SNOOZE ACTION ─────────────────────────────────────────

  test(
    'snooze() schedules a one-off +10 min at the snooze id with the habit payload',
    () async {
      final h = _habit();
      await HabitReminderService.snooze(h, FlutterLocalNotificationsPlugin());

      expect(_calls.where((c) => c.$1 == 'zonedSchedule'), hasLength(1));
      final args = _firstSchedule();
      expect(args['id'], HabitReminderService.snoozeId(h));
      expect(args['payload'], h.id);

      // The one-off must fire ~10 minutes from now.
      final scheduled = DateTime.parse(
        args['scheduledDateTimeISO8601'] as String,
      );
      final diff = scheduled.difference(DateTime.now());
      expect(
        diff.inMinutes,
        inInclusiveRange(9, 11),
        reason: 'snooze must be a one-off reminder 10 minutes from now',
      );
      expect(
        args.containsKey('matchDateTimeComponents'),
        isFalse,
        reason: 'a snooze is one-off — it must NOT repeat daily',
      );
    },
  );

  // ─── DAILY SCHEDULE (payload + id used by the daily reminder) ──

  test(
    'schedule() creates a daily repeating reminder at the habit time with payload',
    () async {
      final h = _habit(hour: 8, minute: 30);
      await HabitReminderService.schedule(h, FlutterLocalNotificationsPlugin());

      final args = _firstSchedule();
      expect(args['id'], HabitReminderService.notificationId(h));
      expect(args['payload'], h.id);

      final scheduled = DateTime.parse(
        args['scheduledDateTimeISO8601'] as String,
      );
      expect(scheduled.hour, 8);
      expect(scheduled.minute, 30);
      // Repeats daily at the same time.
      expect(args['matchDateTimeComponents'], DateTimeComponents.time.index);
    },
  );

  // ─── MARK-DONE SIDE EFFECT: SUPPRESS TODAY, KEEP FUTURE DAYS ──

  test(
    'rescheduleTomorrow() cancels the daily id then re-creates from tomorrow',
    () async {
      final h = _habit(hour: 8, minute: 30);
      await HabitReminderService.rescheduleTomorrow(
        h,
        FlutterLocalNotificationsPlugin(),
      );

      // Step 1: cancel the existing daily reminder for today.
      expect(_cancelIds(), contains(HabitReminderService.notificationId(h)));

      // Step 2: re-create the daily repeating schedule starting tomorrow.
      // NOTE: the service computes dates in tz.local (UTC in tests), so the
      // expectation must be built in UTC too — comparing against local
      // DateTime.now() would be off by a day during early-morning local hours.
      final args = _firstSchedule();
      expect(args['id'], HabitReminderService.notificationId(h));
      expect(args['payload'], h.id);
      final scheduled = DateTime.parse(
        args['scheduledDateTimeISO8601'] as String,
      );
      final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
      expect(scheduled.year, tomorrow.year);
      expect(scheduled.month, tomorrow.month);
      expect(
        scheduled.day,
        tomorrow.day,
        reason:
            'after Mark done, the next daily reminder must be tomorrow, not today',
      );
      expect(args['matchDateTimeComponents'], DateTimeComponents.time.index);
    },
  );

  test('cancelSnooze() cancels only the one-off snooze id', () async {
    final h = _habit();
    await HabitReminderService.cancelSnooze(
      h,
      FlutterLocalNotificationsPlugin(),
    );

    expect(
      _cancelIds(),
      [HabitReminderService.snoozeId(h)],
      reason: 'cancelSnooze must cancel only the snooze notification',
    );
  });

  // ─── BACKGROUND ISOLATE ACTIONS (app killed) ───────────────

  test('background Mark done completes the habit, saves it, and pushes the '
      'daily reminder to tomorrow', () async {
    final h = _habit();
    await SharedPreferences.getInstance().then(
      (p) => p.setString('habits', jsonEncode([h.toJson()])),
    );

    await handleHabitReminderActionBackground(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: HabitReminderService.doneAction,
        payload: h.id,
      ),
    );

    // The habit must now be completed for today, persisted to prefs.
    final raw = (await SharedPreferences.getInstance()).getString('habits')!;
    final saved = Habit.fromJson(
      Map<String, dynamic>.from((jsonDecode(raw) as List).first as Map),
    );
    expect(
      saved.completedDates,
      contains(dateKey(DateTime.now())),
      reason: 'Mark done must persist today\'s completion',
    );

    // Snoozed reminder cleared AND today's daily reminder pushed to tomorrow.
    expect(_cancelIds(), contains(HabitReminderService.snoozeId(h)));
    expect(_cancelIds(), contains(HabitReminderService.notificationId(h)));
    expect(_calls.where((c) => c.$1 == 'zonedSchedule'), hasLength(1));
  });

  test('background Snooze schedules a one-off +10 min', () async {
    final h = _habit();
    await SharedPreferences.getInstance().then(
      (p) => p.setString('habits', jsonEncode([h.toJson()])),
    );

    await handleHabitReminderActionBackground(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: HabitReminderService.snoozeAction,
        payload: h.id,
      ),
    );

    expect(_calls.where((c) => c.$1 == 'zonedSchedule'), hasLength(1));
    final args = _firstSchedule();
    expect(args['id'], HabitReminderService.snoozeId(h));
    expect(args['payload'], h.id);
  });

  test('background action with an unknown habit id is a safe no-op', () async {
    await SharedPreferences.getInstance().then(
      (p) => p.setString('habits', jsonEncode([_habit().toJson()])),
    );

    await handleHabitReminderActionBackground(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: HabitReminderService.doneAction,
        payload: 'does-not-exist',
      ),
    );

    expect(
      _calls.where((c) => c.$1 == 'zonedSchedule'),
      isEmpty,
      reason: 'an unknown habit id must not schedule anything',
    );
  });

  // ─── HabitStore.completeToday (in-app Mark done path) ──────

  test(
    'HabitStore.completeToday marks done and persists (pure data, no reminders)',
    () async {
      final h = _habit();
      HabitStore.instance.habits.add(h);

      await HabitStore.instance.completeToday(h);

      expect(
        h.completedDates,
        contains(dateKey(DateTime.now())),
        reason: 'completeToday must mark the habit done for today',
      );
      final raw = (await SharedPreferences.getInstance()).getString('habits')!;
      expect(raw, contains(h.id), reason: 'the completion must be persisted');

      // completeToday is pure data — the reminder suppression (snooze-cancel +
      // push-to-tomorrow) is the NOTIFICATION layer's job, done by
      // NotificationService._completeHabit / the background handler.
      expect(
        _calls.where((c) => c.$1 == 'cancel'),
        isEmpty,
        reason: 'completeToday must not touch reminders itself',
      );
      expect(
        _calls.where((c) => c.$1 == 'zonedSchedule'),
        isEmpty,
        reason: 'completeToday must not re-schedule anything',
      );
    },
  );

  test('tz helper: dateKey returns the expected YYYY-MM-DD format', () {
    expect(dateKey(DateTime(2026, 8, 3)), '2026-08-03');
    expect(dateKey(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
