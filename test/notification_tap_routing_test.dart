import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/notification_service.dart';
import 'package:macro_snap/services/reminder_registry.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pins the notification TAP ROUTING fix: previously a tap on any built-in
/// reminder (daily meal, streak, weekly, expiry) did nothing because only
/// habit reminders carry a payload. Now built-ins route by notification id,
/// and the resume hook re-arms reminders when the app returns to foreground.
/// Pumps the event loop until [condition] holds (bounded — never hangs). The
/// resume re-arm runs an async chain (tz fetch → registry sync → per-reminder
/// zonedSchedule through the mocked channel), so a fixed delay is flaky under
/// parallel test load; polling waits for the actual work to land.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  });

  // ─── BUILT-IN ROUTING BY ID (pure decision function) ──────────

  test('meal, streak and weekly taps go to Home', () {
    for (final id in [
      ReminderRegistry.dailyMealId,
      ReminderRegistry.streakId,
      ReminderRegistry.weeklySummaryId,
    ]) {
      expect(
        NotificationService.notificationTapDestination(id),
        NotificationTapDestination.home,
        reason: 'notification id $id must open Home',
      );
    }
  });

  test('expiry and expired taps go to the Subscription screen', () {
    for (final id in [
      ReminderRegistry.expiryReminderId,
      ReminderRegistry.expiredId,
    ]) {
      expect(
        NotificationService.notificationTapDestination(id),
        NotificationTapDestination.subscription,
        reason: 'notification id $id must open the Subscription screen',
      );
    }
  });

  test('unknown ids and the removed welcome id route nowhere', () {
    expect(
      NotificationService.notificationTapDestination(null),
      NotificationTapDestination.none,
    );
    expect(
      NotificationService.notificationTapDestination(1),
      NotificationTapDestination.none,
      reason: 'id 1 (removed welcome notification) must not route anywhere',
    );
    expect(
      NotificationService.notificationTapDestination(999),
      NotificationTapDestination.none,
    );
  });

  // ─── RESUME SELF-HEAL ─────────────────────────────────────────

  test('didChangeAppLifecycleState(resumed) re-arms reminders', () async {
    final service = NotificationService();

    // Capture every zonedSchedule the plugin is asked to make through the
    // mocked channel during the resume re-arm.
    final scheduledIds = <int>[];
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'zonedSchedule') {
              final args = Map<dynamic, dynamic>.from(call.arguments as Map);
              scheduledIds.add(args['id'] as int);
            }
            return null;
          },
        );

    // Any timezone fetch throws MissingPluginException in tests — that must
    // NOT block the restore (the tz refresh is best-effort).
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    // The registry schedules built-ins SEQUENTIALLY (id 4 lands before id 6),
    // so wait for the whole expected set, not just the first one.
    await waitFor(
      () => scheduledIds.toSet().containsAll(<int>{
        ReminderRegistry.dailyMealId,
        ReminderRegistry.streakId,
      }),
    );

    expect(scheduledIds, contains(ReminderRegistry.dailyMealId));
    expect(scheduledIds, contains(ReminderRegistry.streakId));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
  });

  test('didChangeAppLifecycleState(resumed) throttles rapid re-arms', () async {
    final service = NotificationService();
    // The singleton persists the cooldown across tests in this file — reset
    // it so this test observes a clean first-resume re-arm.
    service.resetResumeCooldown();

    final scheduledIds = <int>[];
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            if (call.method == 'zonedSchedule') {
              final args = Map<dynamic, dynamic>.from(call.arguments as Map);
              scheduledIds.add(args['id'] as int);
            }
            return null;
          },
        );

    // First resume re-arms everything. The free restore re-creates 2
    // built-ins (daily meal + streak) — wait for the whole chain to land so
    // the snapshot is stable.
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await waitFor(() => scheduledIds.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final firstRun = scheduledIds.length;
    expect(firstRun, greaterThan(0), reason: 'the first resume must re-arm');

    // Second resume within the cooldown is an app-switcher flick — skipped.
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      scheduledIds.length,
      firstRun,
      reason: 'a rapid second resume must not re-arm again (cooldown)',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          null,
        );
  });
}
