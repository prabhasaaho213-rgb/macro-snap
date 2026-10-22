import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/habit.dart';
import 'account_partition.dart';
import 'notification_branding.dart';
import 'crash_reporting.dart';

class HabitReminderService {
  /// Public action ids referenced by [NotificationService] so the handler
  /// never drifts from the ids declared on the notification itself.
  static const String snoozeAction = 'habit_snooze';
  static const String doneAction = 'habit_done';

  static int notificationId(Habit h) {
    var value = 17;
    for (final codeUnit in h.id.codeUnits) {
      value = (value * 31 + codeUnit) & 0x7fffffff;
    }
    return value;
  }

  /// A second, stable id used for the one-off "snoozed" notification so it
  /// never collides with the daily repeating one for the same habit.
  static int snoozeId(Habit h) => (notificationId(h) + 100000) & 0x7fffffff;

  /// Habit-reminder details, built through the shared [NotificationBranding]
  /// factory so icon / largeIcon / brand color can never drift from the rest
  /// of the app's notifications. The snooze + mark-done actions live here.
  static Future<NotificationDetails> _details() async {
    final android = await NotificationBranding.androidDetails(
      channelId: 'habit_reminders',
      channelName: 'Habit reminders',
      channelDescription: 'Reminders for your habits',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(snoozeAction, 'Snooze 10 min'),
        AndroidNotificationAction(doneAction, 'Mark done'),
      ],
    );
    return NotificationDetails(android: android);
  }

  /// Shared daily-repeating schedule used by [schedule] and
  /// [rescheduleTomorrow] so the two never drift apart.
  static Future<void> _scheduleDailyAt(
    Habit h,
    tz.TZDateTime when,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    final details = await _details();
    await notifications.zonedSchedule(
      notificationId(h),
      'Time for ${h.name} ${h.emoji}',
      'Tap to mark this habit done and keep your streak going.',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: h.id,
    );
  }

  static Future<void> schedule(
    Habit h,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    if (!h.reminderEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      h.reminderHour,
      h.reminderMinute,
    );
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    await _scheduleDailyAt(h, when, notifications);
  }

  /// Schedule a one-off reminder 10 minutes from now (used by the Snooze
  /// action on the notification itself).
  static Future<void> snooze(
    Habit h,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
    final details = await _details();
    await notifications.zonedSchedule(
      snoozeId(h),
      'Time for ${h.name} ${h.emoji}',
      'Tap to mark this habit done and keep your streak going.',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: h.id,
    );
  }

  static Future<void> cancel(
    Habit h,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    await notifications.cancel(notificationId(h));
    await notifications.cancel(snoozeId(h));
  }

  /// Cancel just the one-off snoozed reminder (keeps the daily one).
  static Future<void> cancelSnooze(
    Habit h,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    await notifications.cancel(snoozeId(h));
  }

  /// Suppress today's remaining daily reminder by cancelling the repeating
  /// schedule and re-creating it starting tomorrow (at the same time, still
  /// repeating daily). Used after the habit is marked done today so it never
  /// re-reminds the same day while future days stay intact.
  static Future<void> rescheduleTomorrow(
    Habit h,
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    if (!h.reminderEnabled) return;
    await notifications.cancel(notificationId(h));
    final now = tz.TZDateTime.now(tz.local);
    final tomorrow = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      h.reminderHour,
      h.reminderMinute,
    );
    await _scheduleDailyAt(h, tomorrow, notifications);
  }
}

/// Top-level entry point invoked in a **background isolate** when the user
/// taps Snooze or Mark done on a habit reminder while the app is terminated.
///
/// The background isolate has its own memory, so it must not rely on app
/// singletons like [HabitStore.instance]. Instead it re-reads the habit
/// directly from SharedPreferences and drives the plugin with its own
/// instance. Errors are swallowed so a failure here can never crash launch.
@pragma('vm:entry-point')
Future<void> handleHabitReminderActionBackground(
  NotificationResponse response,
) async {
  final actionId = response.actionId;
  final habitId = response.payload;
  if (habitId == null || habitId.isEmpty) return;

  try {
    tz_data.initializeTimeZones();
    final prefs = await SharedPreferences.getInstance();
    // Match the main isolate: tz.local must be the device timezone or the
    // snoozed reminder fires at the wrong wall-clock time.
    final savedTz = prefs.getString('device_timezone_name');
    if (savedTz != null && savedTz.isNotEmpty) {
      try {
        tz.setLocalLocation(tz.getLocation(savedTz));
      } catch (e, st) {
        logError('handleHabitReminderActionBackground', e, st);
      }
    }
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );

    // Partition by the active account (same rule as HabitStore) so a
    // notification action can never read or write another account's habits.
    final habitsKey = AccountPartition.key(
      'habits',
      AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs)),
    );
    final raw = prefs.getString(habitsKey);
    if (raw == null || raw.isEmpty) {
      debugPrint('⚠️ Notification action: no habits saved to act on');
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      debugPrint('⚠️ Notification action: corrupted habits data');
      return;
    }

    final habits = decoded
        .whereType<Map>()
        .map((e) => Habit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final index = habits.indexWhere((h) => h.id == habitId);
    if (index < 0) {
      debugPrint('⚠️ Notification action: habit $habitId not in saved list');
      return;
    }
    final habit = habits[index];

    if (actionId == HabitReminderService.snoozeAction) {
      await HabitReminderService.snooze(habit, plugin);
    } else if (actionId == HabitReminderService.doneAction) {
      final key = dateKey(DateTime.now());
      if (!habit.completedDates.contains(key)) {
        habit.completedDates.add(key);
        habit.skippedDates.remove(key);
      }
      habits[index] = habit;
      await prefs.setString(
        habitsKey,
        jsonEncode(habits.map((h) => h.toJson()).toList()),
      );
      // Mark done from the shade: clear the snoozed one-off AND push today's
      // upcoming daily reminder to tomorrow so it never fires again today.
      await plugin.cancel(HabitReminderService.snoozeId(habit));
      await HabitReminderService.rescheduleTomorrow(habit, plugin);
    }
  } catch (e) {
    debugPrint('❌ Background notification action failed: $e');
    // Never let a background action failure affect app startup.
  }
}
