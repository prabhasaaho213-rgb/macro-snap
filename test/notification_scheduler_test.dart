
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:macro_snap/services/notification_scheduler.dart';

/// The channel the local-notifications plugin uses on Android.
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// Every `zonedSchedule` the plugin was asked to make, as its raw arguments —
/// the schedule mode is one of them, and keeping the map means the assertions
/// do not depend on the exact key the plugin uses.
final List<String> _schedules = [];

/// How many upcoming schedules should be refused, to exercise the fallback.
int _refusals = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  setUp(() {
    _schedules.clear();
    _refusals = 0;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'zonedSchedule') {
            _schedules.add(call.arguments.toString());
            if (_refusals > 0) {
              _refusals--;
              throw PlatformException(
                code: 'exact_alarms_not_permitted',
                message: 'Exact alarms are not permitted',
              );
            }
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> scheduleOnce() => scheduleZoned(
    plugin: FlutterLocalNotificationsPlugin(),
    id: 7,
    title: 'Time for Run',
    body: 'Tap to mark this habit done.',
    when: tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
    details: const NotificationDetails(
      android: AndroidNotificationDetails('habit_reminders', 'Habit reminders'),
    ),
    matchDateTimeComponents: DateTimeComponents.time,
    payload: 'h1',
  );

  test('arms the reminder inexactly — no exact-alarm permission is used', () async {
    // `SCHEDULE_EXACT_ALARM` is restricted on Google Play to alarm/calendar
    // apps, so the app must never ask the platform for an exact alarm: the
    // attempt itself is what a policy review finds in the build.
    await scheduleOnce();

    expect(_schedules, hasLength(1), reason: 'one schedule, no exact attempt');
    expect(
      _schedules.single.toLowerCase(),
      contains('inexact'),
      reason: 'reminders are inexact by design',
    );
    expect(
      _schedules.single.toLowerCase(),
      isNot(contains('schedulemode: exactallowwhileidle')),
      reason: 'an exact alarm must never be requested',
    );
  });

  test('a refused schedule surfaces instead of silently vanishing', () async {
    _refusals = 1;

    // There is no fallback mode any more, so the failure must reach the
    // caller's guard (which logs it) rather than being swallowed here.
    await expectLater(scheduleOnce(), throwsA(isA<PlatformException>()));
    expect(_schedules, hasLength(1));
  });
}
