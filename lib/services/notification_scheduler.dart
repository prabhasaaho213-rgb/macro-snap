import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules a zoned notification with Android's INEXACT wake-up mode.
///
/// Reminders used to prefer `exactAllowWhileIdle` and fall back to inexact when
/// the platform refused. That preference is gone on purpose: exact alarms need
/// `SCHEDULE_EXACT_ALARM`, which Google Play only allows for apps whose core
/// function is an alarm clock or a calendar. A meal or habit reminder is not
/// that, so keeping the permission in the manifest was a release risk — a
/// rejected update costs every user, while a reminder that lands a few minutes
/// late costs nothing. The app now ships without the permission and never asks
/// for it, which also removes the "Alarms & reminders" settings hop from
/// notification setup.
///
/// Inexact scheduling with `allowWhileIdle` still fires in Doze (it is the
/// mode Android provides for exactly this) and drifts by minutes, not hours,
/// outside of deep battery savers.
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
  await plugin.zonedSchedule(
    id,
    title,
    body,
    when,
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: matchDateTimeComponents,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: payload,
  );
}
