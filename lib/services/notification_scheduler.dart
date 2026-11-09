import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'crash_reporting.dart';

/// Schedules a zoned notification, preferring Android's exact alarm mode and
/// falling back to the old inexact mode when the platform refuses.
///
/// Reminders used to be armed with [AndroidScheduleMode.inexactAllowWhileIdle],
/// which lets Android drift them by minutes — and by far more in Doze — so a
/// 9:00 habit reminder could arrive at 9:20. Exact alarms need
/// `SCHEDULE_EXACT_ALARM`, a permission the user can revoke; on a device that
/// refuses it an exact schedule *throws* rather than degrading, so the retry
/// below is what keeps the reminder alive instead of silently losing it.
Future<void> scheduleZoned({
  required FlutterLocalNotificationsPlugin plugin,
  required int id,
  required String? title,
  required String? body,
  required tz.TZDateTime when,
  required NotificationDetails details,
  DateTimeComponents? matchDateTimeComponents,
  String? payload,
}) async {
  Future<void> attempt(AndroidScheduleMode mode) => plugin.zonedSchedule(
    id,
    title,
    body,
    when,
    details,
    androidScheduleMode: mode,
    matchDateTimeComponents: matchDateTimeComponents,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: payload,
  );

  try {
    await attempt(AndroidScheduleMode.exactAllowWhileIdle);
    return;
  } catch (e, st) {
    // Not fatal and not worth alarming the user about: the reminder is still
    // armed, just with the platform's best-effort timing.
    logError('scheduleZoned: exact alarm refused, using inexact', e, st);
  }
  await attempt(AndroidScheduleMode.inexactAllowWhileIdle);
}

/// Asks for the exact-alarm permission once per process when the platform
/// says it is missing.
///
/// Called from notification setup, where the app is already on screen — asking
/// mid-schedule would throw a system dialog over whatever the user was doing.
/// Best-effort: a missing plugin, an old Android, or a refusal all leave the
/// inexact path working.
Future<void> requestExactAlarmPermissionOnce(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (_askedForExactAlarm) return;
  _askedForExactAlarm = true;
  try {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    final allowed = await android.canScheduleExactNotifications();
    if (allowed == true) return;
    await android.requestExactAlarmsPermission();
  } catch (e, st) {
    logError('requestExactAlarmPermissionOnce', e, st);
  }
}

bool _askedForExactAlarm = false;
