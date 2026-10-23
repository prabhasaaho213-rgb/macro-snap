import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/diet_profile.dart';
import '../models/habit.dart';
import 'habit_reminder_service.dart';
import 'meal_store.dart';
import 'notification_branding.dart';
import 'reminder_copy.dart';

/// Declarative description of one repeating reminder. Everything a reminder
/// needs — id, channel, importance, cadence, subscriber gating and copy —
/// lives in one row so scheduling and startup restore can never drift
/// apart.
class ReminderSpec {
  final int id;
  final String channelId;
  final String channelName;
  final String channelDescription;
  final Importance importance;
  final Priority priority;

  /// How the reminder repeats; null means a one-off notification.
  final DateTimeComponents? match;

  /// Whether only subscribers get this reminder.
  final bool subscriberOnly;

  /// Next fire time; return null to skip (e.g. an expiry date already past).
  final tz.TZDateTime? Function(String? subscribedDate) next;

  /// Title/body, computed at schedule time so it can reference real data
  /// (yesterday's calories, current streak, weekly stats). Must never
  /// throw — callers fall back to the generic copy on any data error.
  final Future<({String title, String body})> Function(String? subscribedDate)
  copy;

  /// When set, [ReminderRegistry] checks this prefs marker before arming:
  /// if it holds today's date, the reminder is scheduled from tomorrow
  /// instead of today. This is how a suppression (e.g. "already logged
  /// today") survives a later restore/subscription re-arm — otherwise
  /// re-arming would silently undo the suppression and nag the user again.
  final String? suppressMarkerKey;

  const ReminderSpec({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    required this.importance,
    required this.priority,
    required this.match,
    required this.subscriberOnly,
    required this.next,
    required this.copy,
    this.suppressMarkerKey,
  });
}

/// The single place every reminder in the app is defined and scheduled.
///
/// Built-in reminders (daily meal, streak, weekly summary, expiry) and the
/// dynamic per-habit reminders all flow through [restoreAll]'s one loop, so
/// startup restore and subscription-state changes can never diverge — and
/// the earlier bug where a subscribe wipe left habit reminders dead is
/// structurally impossible: every path re-arms habits and nothing ever calls
/// [FlutterLocalNotificationsPlugin.cancelAll] in production.
class ReminderRegistry {
  ReminderRegistry(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// Well-known notification ids (stable, documented for the registry).
  /// Id 1 was the one-off "Welcome to Pro" notification (now removed — the
  /// in-app confirmation dialog replaces it, so no notification id is used).
  static const int expiryReminderId = 2;
  static const int expiredId = 3;
  static const int dailyMealId = 4;
  static const int weeklySummaryId = 5;
  static const int streakId = 6;

  /// Reminders that only exist while the user is subscribed. Cancelling a
  /// subscription cancels exactly these ids — never everything — so the
  /// free built-ins (daily meal, streak) and all habit reminders survive.
  static const List<int> _subscriberGatedIds = [
    expiryReminderId,
    expiredId,
    weeklySummaryId,
  ];

  /// Prefs keys + date values marking that today's streak / daily-meal
  /// nudge was already suppressed after the user logged their first meal
  /// of the day. Separate keys keep the two suppressions independent.
  static const _keyStreakSuppressed = 'streak_reminder_suppressed_date';
  static const _keyMealSuppressed = 'meal_reminder_suppressed_date';

  /// Every repeating built-in reminder in the app, in one place.
  static final List<ReminderSpec> _reminders = [
    // Daily meal reminder (id 4) — always.
    ReminderSpec(
      id: dailyMealId,
      channelId: 'macro_snap_reminder',
      channelName: 'Meal Reminders',
      channelDescription: 'Daily reminders to log meals',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      match: DateTimeComponents.time,
      subscriberOnly: false,
      next: (_) => ReminderCopy.nextDaily(20, 0),
      copy: (_) async => NotificationBranding.dailyMealCopy(
        yesterdayCalories: await _yesterdayCalories(),
      ),
      suppressMarkerKey: _keyMealSuppressed,
    ),
    // Streak reminder (id 6) — always.
    ReminderSpec(
      id: streakId,
      channelId: 'macro_snap_reminder',
      channelName: 'Meal Reminders',
      channelDescription: 'Daily reminders to log meals',
      importance: Importance.high,
      priority: Priority.high,
      match: DateTimeComponents.time,
      subscriberOnly: false,
      next: (_) => ReminderCopy.nextDaily(19, 30),
      copy: (_) async =>
          NotificationBranding.streakCopy(streak: await _currentStreak()),
      suppressMarkerKey: _keyStreakSuppressed,
    ),
    // Weekly summary (id 5) — subscribers only.
    ReminderSpec(
      id: weeklySummaryId,
      channelId: 'macro_snap_weekly',
      channelName: 'Weekly Summary',
      channelDescription: 'Weekly nutrition summary notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      match: DateTimeComponents.dayOfWeekAndTime,
      subscriberOnly: true,
      next: (_) => ReminderCopy.nextSunday(19, 0),
      copy: (_) async => await _weeklyCopy(),
    ),
    // Pro expires in 3 days (id 2) — subscribers only; skip if past.
    ReminderSpec(
      id: expiryReminderId,
      channelId: 'macro_snap_expiry',
      channelName: 'Expiry Reminder',
      channelDescription: 'Subscription expiry reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      match: DateTimeComponents.time,
      subscriberOnly: true,
      next: (sub) => ReminderCopy.daysAfter(sub, 27),
      copy: (_) async => (
        title: 'Pro expires in 3 days',
        body: 'Renew to keep unlimited access to AI meal analysis & tracking.',
      ),
    ),
    // Pro expired (id 3) — subscribers only; skip if past.
    ReminderSpec(
      id: expiredId,
      channelId: 'macro_snap_expiry',
      channelName: 'Expiry Reminder',
      channelDescription: 'Subscription expiry reminders',
      importance: Importance.high,
      priority: Priority.high,
      match: DateTimeComponents.time,
      subscriberOnly: true,
      next: (sub) => ReminderCopy.daysAfter(sub, 30),
      copy: (_) async => (
        title: 'Your Pro subscription has expired',
        // No ₹1 promise here: every expiring subscriber has already used
        // the intro month (it is once per account), and a notification
        // cannot check this account's eligibility — the paywall states the
        // real price on open.
        body: 'Renew now for ₹49/month to get full access again.',
      ),
    ),
  ];

  /// Schedules a single [ReminderSpec] through the branded details factory.
  /// Skips silently when [ReminderSpec.next] returns null (e.g. an expiry
  /// reminder whose date has already passed).
  Future<void> _scheduleReminder(
    ReminderSpec spec,
    String? subscribedDate,
  ) async {
    final nullableWhen = spec.next(subscribedDate);
    if (nullableWhen == null) return;
    // Non-nullable copy: the suppression block below reassigns the schedule
    // time, which would otherwise demote a `var when` back to TZDateTime? and
    // break the zonedSchedule call.
    var when = nullableWhen;

    if (spec.suppressMarkerKey != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(spec.suppressMarkerKey!) ==
            ReminderCopy.dateStr(DateTime.now())) {
          final now = DateTime.now();
          if (when.year == now.year &&
              when.month == now.month &&
              when.day == now.day) {
            when = when.add(const Duration(days: 1));
          }
        }
      } catch (_) {
        // If the marker can't be read, arm as normal — never fail scheduling.
      }
    }

    final copy = await spec.copy(subscribedDate);
    final details = await NotificationBranding.androidDetails(
      channelId: spec.channelId,
      channelName: spec.channelName,
      channelDescription: spec.channelDescription,
      importance: spec.importance,
      priority: spec.priority,
    );

    await _plugin.zonedSchedule(
      spec.id,
      copy.title,
      copy.body,
      when,
      NotificationDetails(
        android: details,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: spec.match,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedules the built-in (non-habit) reminders that apply to the current
  /// subscription state.
  Future<void> _scheduleBuiltIns(String? subscribedDate) async {
    // Lifetime subscribers (admin) never get expiry reminders — the
    // '1900-01-01T00:00:00.000' marker means the subscription never expires.
    final isLifetime =
        subscribedDate != null && subscribedDate.startsWith('1900');
    for (final spec in _reminders) {
      if (spec.subscriberOnly &&
          (subscribedDate == null || subscribedDate.isEmpty)) {
        continue;
      }
      // Skip expiry/expired reminders for lifetime subscribers.
      if (isLifetime && (spec.id == expiryReminderId || spec.id == expiredId)) {
        continue;
      }
      await _safe(() => _scheduleReminder(spec, subscribedDate));
    }
  }

  /// Habit notification ids this registry has armed, so the plan can cancel
  /// anything it armed that is no longer wanted (orphan sweep). Without this,
  /// a habit that leaves the list wholesale — account switch (reload → new
  /// habit set), cloud replace — would keep its alarm firing forever.
  final Set<int> _armedHabitIds = <int>{};

  /// Reconciles habit reminders with the current habit list — the SINGLE
  /// funnel for every habit-reminder change (add / edit / toggle / cloud
  /// restore / account switch).
  ///
  /// 1. Arms every enabled habit (idempotent — zonedSchedule replaces by id).
  /// 2. Cancels every disabled habit still in the list.
  /// 3. ORPHAN SWEEP: cancels any id this registry armed previously that is
  ///    no longer in the list — so a removed habit or an account switch that
  ///    replaces the whole set can never leave a stale alarm behind.
  Future<void> applyHabitPlan(List<Habit> habits) async {
    final desired = <int>{
      for (final h in habits)
        if (h.reminderEnabled) HabitReminderService.notificationId(h),
    };

    // Orphan sweep: cancel anything we armed that is no longer desired.
    for (final id in _armedHabitIds.toList()) {
      if (!desired.contains(id)) {
        await _safe(() => _plugin.cancel(id));
        _armedHabitIds.remove(id);
      }
    }

    // Explicitly cancel disabled habits still in the list. Covers habits
    // that were armed BEFORE the registry tracked ids (e.g. a toggle made
    // before this app version ran) — cancelling a non-existent alarm is a
    // plugin no-op, so this is belt-and-suspenders, never a false positive.
    for (final h in habits) {
      if (!h.reminderEnabled) {
        await _safe(() => HabitReminderService.cancel(h, _plugin));
      }
    }

    // Arm what is desired.
    for (final h in habits) {
      if (h.reminderEnabled) {
        await _safe(() => HabitReminderService.schedule(h, _plugin));
        _armedHabitIds.add(HabitReminderService.notificationId(h));
      }
    }
  }

  /// THE one entry point for "what should be armed right now": every
  /// built-in that applies to the subscription state, then the habit plan
  /// (with orphan sweep). Used by startup restore, subscription transitions
  /// and the resume self-heal — so restore and transitions can never
  /// diverge.
  ///
  /// [subscribedDate] non-empty ⇒ the full plan (all built-ins + habits).
  /// [subscribedDate] null/empty ⇒ cancel ONLY the subscriber-gated
  /// reminders (weekly summary + expiry) and re-arm the free plan: daily
  /// meal, streak, and every enabled habit. The free path must NEVER call
  /// [FlutterLocalNotificationsPlugin.cancelAll] — that would silently wipe
  /// habit reminders and the free nudge.
  Future<void> sync({
    required List<Habit> habits,
    String? subscribedDate,
  }) async {
    final subscribed = subscribedDate != null && subscribedDate.isNotEmpty;
    final isLifetime = subscribed && subscribedDate.startsWith('1900');
    if (subscribed) {
      await _scheduleBuiltIns(subscribedDate);
    } else {
      // A FREE user must never carry subscriber-only alarms (admin-strip on
      // a shared device, cancelled subscription, etc.).
      for (final id in _subscriberGatedIds) {
        await _safe(() => _plugin.cancel(id));
      }
      await _scheduleBuiltIns(null);
    }
    // Lifetime subscribers never get expiry reminders — cancel any stale ones.
    if (isLifetime) {
      await _safe(() => _plugin.cancel(expiryReminderId));
      await _safe(() => _plugin.cancel(expiredId));
    }
    await applyHabitPlan(habits);
  }

  /// Called when meals change (MealStore's changeNotifier). Once the user
  /// has logged their first meal of the day, today's nagging reminders are
  /// silenced and pushed to tomorrow: the 19:30 streak nudge AND the 20:00
  /// daily meal nudge. A day you've already logged needs no reminders.
  /// Each suppression is idempotent (guarded by its own date marker).
  Future<void> onMealsChanged() async {
    try {
      if (MealStore.instance.todayMeals.isEmpty) return;
      await suppressStreakReminderOncePerDay();
      await suppressDailyMealReminderOncePerDay();
    } catch (_) {
      // Never let meal tracking break because a suppression failed.
    }
  }

  /// Suppresses today's streak nudge, but at most once per calendar day.
  /// The date marker is stored in prefs, so repeated meal-change events (or
  /// repeated calls from anywhere) never double-suppress or double-re-arm.
  Future<void> suppressStreakReminderOncePerDay() =>
      _suppressOncePerDay(streakId, _keyStreakSuppressed, 19, 30);

  /// Cancels today's streak reminder and re-creates it from tomorrow so the
  /// day is quiet but future days stay armed.
  Future<void> suppressStreakReminder() => _suppressReminder(streakId, 19, 30);

  /// Suppresses today's daily meal nudge, at most once per calendar day.
  Future<void> suppressDailyMealReminderOncePerDay() =>
      _suppressOncePerDay(dailyMealId, _keyMealSuppressed, 20, 0);

  /// Shared once-per-day guard + suppression. Cancels [id] and re-creates
  /// the same repeating reminder starting tomorrow, so the day is quiet
  /// while future days stay armed. Never double-fires within one calendar
  /// day thanks to the prefs marker.
  Future<void> _suppressOncePerDay(
    int id,
    String markerKey,
    int hour,
    int minute,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = ReminderCopy.dateStr(DateTime.now());
      if (prefs.getString(markerKey) == today) return;

      await _suppressReminder(id, hour, minute);
      await prefs.setString(markerKey, today);
    } catch (_) {
      // Never let a failed suppression surface.
    }
  }

  /// Cancels the reminder [id] and re-creates it from tomorrow at
  /// [hour]:[minute]. The next day's occurrence is armed with the same
  /// personalized copy path as a fresh schedule.
  Future<void> _suppressReminder(int id, int hour, int minute) async {
    await _plugin.cancel(id);
    final now = tz.TZDateTime.now(tz.local);
    final tomorrow = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
    final spec = _reminders.firstWhere((s) => s.id == id);
    final copy = await spec.copy(null);
    final details = await NotificationBranding.androidDetails(
      channelId: spec.channelId,
      channelName: spec.channelName,
      channelDescription: spec.channelDescription,
      importance: spec.importance,
      priority: spec.priority,
    );
    await _plugin.zonedSchedule(
      id,
      copy.title,
      copy.body,
      tomorrow,
      NotificationDetails(
        android: details,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ── Data + copy helpers (pure logic lives in [ReminderCopy]) ───

  /// Total calories logged yesterday, or null if unknown. Falls back
  /// gracefully so a data error can never break scheduling.
  static Future<int?> _yesterdayCalories() async {
    try {
      await MealStore.instance.load();
      return ReminderCopy.yesterdayCalories(meals: MealStore.instance.allMeals);
    } catch (_) {
      return null;
    }
  }

  /// Current meal streak, or 0 when unknown. Never throws.
  static Future<int> _currentStreak() => ReminderCopy.currentStreak();

  /// Weekly summary copy: real numbers from the last 7 days of the meal log
  /// (days where every macro target was hit >= 90%, and total calories),
  /// with the generic copy as fallback when there is no data.
  static Future<({String title, String body})> _weeklyCopy() async {
    try {
      await MealStore.instance.load();
      final profile = DietPlanService.instance.profile;
      if (profile == null) {
        return NotificationBranding.weeklyCopy(daysHit: 0, totalCalories: 0);
      }
      final stats = ReminderCopy.weeklyStats(
        meals: MealStore.instance.allMeals,
        profile: profile,
      );
      return NotificationBranding.weeklyCopy(
        daysHit: stats.daysHit,
        totalCalories: stats.totalCalories,
      );
    } catch (_) {
      return NotificationBranding.weeklyCopy(daysHit: 0, totalCalories: 0);
    }
  }

  /// The subscriber-gated reminder ids (visible for tests / diagnostics).
  static List<int> get subscriberGatedIds => _subscriberGatedIds;

  /// Human-readable plan of every built-in reminder (id, channel, cadence,
  /// gating) plus the current subscription state and how many habits have
  /// reminders enabled. Logged once at startup so a support session can see
  /// what the app *intends* to arm without querying the device.
  static List<String> debugDescribe({
    bool subscribed = false,
    int enabledHabits = 0,
  }) => [
    'Subscription: ${subscribed ? 'active' : 'free'}',
    'Habits with reminders: $enabledHabits',
    for (final spec in _reminders)
      '#${spec.id} ${spec.channelName} '
          '${spec.subscriberOnly ? '(subscriber only)' : '(always)'} '
          '${spec.match == DateTimeComponents.dayOfWeekAndTime ? '(weekly)' : '(daily)'}',
  ];

  Future<void> _safe(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('❌ reminder restore failed: $e');
    }
  }
}
