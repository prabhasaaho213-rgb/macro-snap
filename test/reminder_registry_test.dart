import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_reminder_service.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/reminder_copy.dart';
import 'package:macro_snap/services/reminder_registry.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Pins the registry behaviors that fix real reminder bugs:
///  1. scheduleAllForSubscriber() must re-arm habit reminders — cancelAll()
///     would otherwise silently wipe them (the pre-registry bug).
///  2. suppressStreakReminder() cancels id 6 and re-arms it from tomorrow.
///  3. onMealsChanged() suppresses today's streak nudge at most once per day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <String>[];
  final scheduledIds = <int>[];
  final cancelledIds = <int>[];

  /// (id, ISO date) of every zonedSchedule, for date-shift assertions.
  final scheduledDates = <(int, String)>[];

  void resetCalls() {
    calls.clear();
    scheduledIds.clear();
    cancelledIds.clear();
    scheduledDates.clear();
  }

  void registerPluginMock() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments is Map
              ? Map<dynamic, dynamic>.from(call.arguments as Map)
              : <dynamic, dynamic>{};
          switch (call.method) {
            case 'zonedSchedule':
              calls.add('zonedSchedule');
              final id = args['id'] as int;
              scheduledIds.add(id);
              final iso = args['scheduledDateTimeISO8601'] as String?;
              if (iso != null) scheduledDates.add((id, iso));
              break;
            case 'cancel':
              calls.add('cancel');
              cancelledIds.add(args['id'] as int);
              break;
            case 'cancelAll':
              calls.add('cancelAll');
              break;
            case 'initialize':
            case 'requestNotificationsPermission':
              return true;
          }
          return null;
        });
  }

  Habit habit(String id, {bool reminder = true}) => Habit(
    id: id,
    name: 'Habit $id',
    emoji: '💧',
    colorValue: 0xFF00FF66,
    reminderEnabled: reminder,
    reminderHour: 9,
    reminderMinute: 0,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HabitStore.instance.habits.clear();
    resetCalls();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    registerPluginMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'subscribed plan arms every built-in + every enabled habit, no cancelAll',
    () async {
      HabitStore.instance.habits
        ..add(habit('keep-a'))
        ..add(habit('keep-b'));

      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.sync(
        habits: HabitStore.instance.habits,
        subscribedDate: DateTime.now().toIso8601String(),
      );

      // The subscribed plan must NEVER cancelAll (that wiped habit reminders
      // in the pre-registry bug) — it arms everything by id instead.
      expect(
        calls,
        isNot(contains('cancelAll')),
        reason:
            'subscribe must never cancelAll — it would wipe habit reminders',
      );

      // Every repeating built-in (2..6) + both habits armed.
      final ids = scheduledIds.toSet();
      expect(ids, containsAll(<int>{2, 3, 4, 5, 6}));
      expect(
        ids,
        contains(HabitReminderService.notificationId(habit('keep-a'))),
        reason: 'subscription must never wipe habit reminders',
      );
      expect(
        ids,
        contains(HabitReminderService.notificationId(habit('keep-b'))),
      );
    },
  );

  test(
    'suppressStreakReminder cancels id 6 and re-arms it from tomorrow',
    () async {
      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.suppressStreakReminder();

      expect(
        cancelledIds,
        contains(ReminderRegistry.streakId),
        reason: 'today\'s streak nudge must be cancelled',
      );
      expect(
        scheduledIds,
        contains(ReminderRegistry.streakId),
        reason: 'the streak reminder must be re-armed from tomorrow',
      );
    },
  );

  test(
    'suppressStreakReminderOncePerDay is idempotent within the same day',
    () async {
      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());

      // First call: no marker in prefs, so the nudge is silenced.
      await registry.suppressStreakReminderOncePerDay();
      expect(cancelledIds, contains(ReminderRegistry.streakId));
      final firstCancels = List<int>.from(cancelledIds);

      // Second call the same day: idempotent — no second cancellation.
      await registry.suppressStreakReminderOncePerDay();
      expect(
        cancelledIds,
        firstCancels,
        reason: 'the suppression must only happen once per day',
      );
    },
  );

  // ─── CANCEL PATH: never wipe free reminders or habits ───────────

  test(
    'free plan cancels ONLY subscriber-gated ids, keeps free + habits',
    () async {
      HabitStore.instance.habits.add(habit('keep-habit'));

      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      // Simulate a subscribed state first, then the user cancels.
      await registry.sync(
        habits: HabitStore.instance.habits,
        subscribedDate: DateTime.now().toIso8601String(),
      );
      resetCalls();

      await registry.sync(
        habits: HabitStore.instance.habits,
        subscribedDate: null,
      );

      // Cancelled: only the subscriber-gated ids (2, 3, 5).
      expect(
        cancelledIds,
        containsAll(<int>{2, 3, 5}),
        reason: 'weekly + expiry reminders must be cancelled on cancel',
      );
      expect(
        calls,
        isNot(contains('cancelAll')),
        reason:
            'the cancel path must NEVER cancelAll — that would wipe everything',
      );
      expect(
        cancelledIds,
        isNot(contains(ReminderRegistry.dailyMealId)),
        reason: 'the free daily nudge must survive a cancel',
      );
      expect(
        cancelledIds,
        isNot(contains(ReminderRegistry.streakId)),
        reason: 'the free streak nudge must survive a cancel',
      );

      // Re-armed: free built-ins + habit reminder.
      final ids = scheduledIds.toSet();
      expect(
        ids,
        containsAll(<int>{
          ReminderRegistry.dailyMealId,
          ReminderRegistry.streakId,
        }),
        reason: 'free reminders must be re-armed after cancel',
      );
      expect(
        ids,
        contains(HabitReminderService.notificationId(habit('keep-habit'))),
        reason: 'habit reminders must survive a cancel',
      );
    },
  );

  // ─── DAILY MEAL SUPPRESSION (after first log) ───────────────────

  test(
    'suppressDailyMealReminderOncePerDay cancels id 4 and re-arms it',
    () async {
      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.suppressDailyMealReminderOncePerDay();

      expect(
        cancelledIds,
        contains(ReminderRegistry.dailyMealId),
        reason: 'today\'s daily meal nudge must be cancelled after first log',
      );
      expect(
        scheduledIds,
        contains(ReminderRegistry.dailyMealId),
        reason: 'the daily meal reminder must be re-armed from tomorrow',
      );
    },
  );

  test(
    'daily meal suppression is once per day, independent of streak marker',
    () async {
      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());

      await registry.suppressDailyMealReminderOncePerDay();
      final firstCancels = List<int>.from(cancelledIds);
      await registry.suppressDailyMealReminderOncePerDay();
      expect(
        cancelledIds,
        firstCancels,
        reason: 'daily meal suppression must only happen once per day',
      );
    },
  );

  // ─── HABIT PLAN RECONCILIATION (single funnel) ────────────────

  test(
    'applyHabitPlan arms enabled habits AND cancels disabled ones',
    () async {
      HabitStore.instance.habits
        ..add(habit('enabled-habit'))
        ..add(habit('disabled-habit', reminder: false));

      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.applyHabitPlan(HabitStore.instance.habits);

      final ids = scheduledIds.toSet();
      expect(
        ids,
        contains(HabitReminderService.notificationId(habit('enabled-habit'))),
        reason: 'every enabled habit must be armed',
      );
      expect(
        cancelledIds,
        contains(HabitReminderService.notificationId(habit('disabled-habit'))),
        reason: 'every disabled habit must be cancelled — a toggle-off must ',
      );
      expect(
        ids,
        isNot(
          contains(
            HabitReminderService.notificationId(habit('disabled-habit')),
          ),
        ),
        reason: 'a disabled habit must never be scheduled',
      );
    },
  );

  test(
    'applyHabitPlan is idempotent: re-running arms the same id set',
    () async {
      HabitStore.instance.habits.add(habit('stable-habit'));

      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.applyHabitPlan(HabitStore.instance.habits);
      final firstRun = scheduledIds.toSet();
      await registry.applyHabitPlan(HabitStore.instance.habits);

      expect(
        scheduledIds.toSet(),
        firstRun,
        reason:
            're-running the plan must arm the exact same ids (zonedSchedule '
            'replaces by id — no drift, no orphans)',
      );
    },
  );

  test('applyHabitPlan orphan-sweeps an id that leaves the list', () async {
    HabitStore.instance.habits.add(habit('orphan-habit'));
    final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());

    // First arm the habit.
    await registry.applyHabitPlan(HabitStore.instance.habits);
    final orphanId = HabitReminderService.notificationId(habit('orphan-habit'));
    expect(scheduledIds, contains(orphanId));

    // The habit is removed from the list (account switch / deletion) and
    // the plan re-runs with the new list.
    resetCalls();
    HabitStore.instance.habits.clear();
    await registry.applyHabitPlan(HabitStore.instance.habits);

    expect(
      cancelledIds,
      contains(orphanId),
      reason:
          'an id this registry armed but is no longer wanted must be '
          'cancelled — never left firing for a ghost habit',
    );
  });

  test(
    'applyHabitPlan keeps an id that stays in the list (no false sweep)',
    () async {
      HabitStore.instance.habits.add(habit('stay-habit'));
      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());

      await registry.applyHabitPlan(HabitStore.instance.habits);
      final stayId = HabitReminderService.notificationId(habit('stay-habit'));
      resetCalls();

      // Same plan again — the id must NOT be swept (it's still wanted).
      await registry.applyHabitPlan(HabitStore.instance.habits);
      expect(
        cancelledIds,
        isNot(contains(stayId)),
        reason: 'a still-wanted habit must never be cancelled by the sweep',
      );
      expect(scheduledIds, contains(stayId));
    },
  );

  // ─── STARTUP RESTORE NEVER LEAVES STALE SUBSCRIBER ALARMS ───

  test('free sync cancels subscriber-gated ids (admin-strip safety)', () async {
    final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
    await registry.sync(habits: [], subscribedDate: null);

    // A free user must never carry stale weekly/expiry alarms from a
    // previous owner session on a shared device.
    expect(cancelledIds, containsAll(<int>{2, 3, 5}));
  });

  test('subscribed sync does NOT cancel gated ids', () async {
    final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
    await registry.sync(
      habits: [],
      subscribedDate: DateTime.now().toIso8601String(),
    );

    expect(
      cancelledIds,
      isEmpty,
      reason: 'a subscribed user must keep their gated reminders',
    );
  });

  // ─── SUPPRESSION SURVIVES RESTORE (re-arm must respect markers) ──

  test(
    'restoreAll arms a suppressed reminder from TOMORROW, not today',
    () async {
      final prefs = await SharedPreferences.getInstance();
      // Mark today's streak nudge as already-suppressed (first meal logged).
      await prefs.setString(
        'streak_reminder_suppressed_date',
        ReminderCopy.dateStr(DateTime.now()),
      );

      final registry = ReminderRegistry(FlutterLocalNotificationsPlugin());
      await registry.sync(habits: [], subscribedDate: null);

      // The streak reminder (id 6) must be re-armed for TOMORROW — a restore
      // must never silently undo the suppression by re-arming today.
      final streakEntry = scheduledDates
          .where((e) => e.$1 == ReminderRegistry.streakId)
          .toList();
      expect(
        streakEntry,
        isNotEmpty,
        reason: 'streak reminder must still be armed',
      );
      final when = DateTime.parse(streakEntry.first.$2);
      final now = DateTime.now();
      final tomorrow = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      expect(when.year, tomorrow.year);
      expect(when.month, tomorrow.month);
      expect(
        when.day,
        tomorrow.day,
        reason: 'a suppressed reminder must re-arm from tomorrow, never today',
      );
    },
  );

  // ─── DIAGNOSTICS ───────────────────────────────────────────────

  test('debugDescribe lists every built-in reminder with its gating', () {
    // 2 state lines + 5 built-in reminder lines.
    final plan = ReminderRegistry.debugDescribe();
    expect(plan, hasLength(7));
    expect(plan.join('\n'), contains('#4 Meal Reminders'));
    expect(plan.join('\n'), contains('#5 Weekly Summary (subscriber only)'));
    expect(plan.join('\n'), contains('#6 Meal Reminders'));
    expect(plan.join('\n'), contains('#2 Expiry Reminder (subscriber only)'));
    expect(plan.join('\n'), contains('#3 Expiry Reminder (subscriber only)'));
    expect(ReminderRegistry.subscriberGatedIds, <int>{2, 3, 5});
  });

  test('debugDescribe reports subscription state and enabled-habit count', () {
    final plan = ReminderRegistry.debugDescribe(
      subscribed: true,
      enabledHabits: 3,
    );
    expect(plan.join('\n'), contains('Subscription: active'));
    expect(plan.join('\n'), contains('Habits with reminders: 3'));

    final free = ReminderRegistry.debugDescribe();
    expect(free.join('\n'), contains('Subscription: free'));
    expect(free.join('\n'), contains('Habits with reminders: 0'));
  });
}
