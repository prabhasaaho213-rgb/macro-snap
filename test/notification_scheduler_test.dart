
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

  test('arms the reminder with an exact alarm when the platform allows it', () async {
    await scheduleOnce();

    expect(_schedules, hasLength(1), reason: 'one schedule, no retry');
    expect(
      _schedules.single.toLowerCase(),
      contains('exact'),
      reason: 'reminders must fire at the minute the user picked',
    );
  });

  test('falls back to an inexact alarm when exact is refused', () async {
    _refusals = 1;

    await scheduleOnce();

    expect(
      _schedules,
      hasLength(2),
      reason: 'a refused exact alarm must be retried, not dropped',
    );
    expect(
      _schedules.first.toLowerCase(),
      contains('exact'),
      reason: 'exact is attempted first',
    );
    expect(
      _schedules.last.toLowerCase(),
      contains('inexact'),
      reason: 'the reminder still arms, with best-effort timing',
    );
  });
}
