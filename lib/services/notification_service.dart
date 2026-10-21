import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_nav.dart';
import '../models/habit.dart';
import 'account_partition.dart';
import 'habit_reminder_service.dart';
import 'habit_store.dart';
import 'meal_store.dart';
import 'notification_branding.dart';
import 'reminder_registry.dart';
import 'subscription_service.dart';

/// Where a built-in (non-habit) notification tap should take the user.
enum NotificationTapDestination { home, subscription, none }

/// Facade over [ReminderRegistry]: owns plugin init, tap handling, the
/// resume self-heal and the public reminder API. All scheduling logic lives
/// in the registry so built-ins and habit reminders share one definition
/// and one restore loop.
class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  late final ReminderRegistry _registry = ReminderRegistry(_plugin);
  bool _initialized = false;

  /// When the last resume re-arm ran. The re-arm re-creates 5+ reminders,
  /// so a quick app-switcher flick (background → resume within seconds)
  /// must not re-run it — the alarms are seconds old. Real backgrounding
  /// (the OS-dropped-alarm case) is minutes away, so this only skips flurries.
  DateTime? _lastResumeRearm;
  static const Duration _resumeRearmCooldown = Duration(seconds: 30);

  /// Test hook: clears the cooldown so a test can observe a fresh first
  /// resume re-arm (the singleton persists state across tests).
  @visibleForTesting
  void resetResumeCooldown() => _lastResumeRearm = null;

  /// The name of the device timezone (e.g. "Asia/Kolkata"), persisted so the
  /// background isolate (which re-creates everything from scratch) can set
  /// `tz.local` correctly for snooze scheduling.
  static const _keyTz = 'device_timezone_name';

  Future<void> init() async {
    if (_initialized) return;
    try {
      // POST_NOTIFICATIONS is NOT requested here any more.
      //
      // It used to be, and because it was awaited, launch blocked on a system
      // dialog that appeared on top of a still-unpainted window — the app sat
      // on the launch screen (black in dark mode) until the user answered,
      // every time the permission was still undetermined. The ask now happens
      // once the UI is up and interactive, via the in-app prompt
      // (maybeShowNotificationPrompt), which also explains WHY before
      // Android's dialog appears.
      //
      // Scheduling below does not depend on the answer: reminders are
      // scheduled either way, so granting later still delivers them.
      tz_data.initializeTimeZones();
      // CRITICAL: without this, tz.local stays UTC and every scheduled
      // reminder fires at the wrong wall-clock time (e.g. 5.5h late in IST).
      final tzName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(tzName));
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyTz, tzName);
      } catch (e) { debugPrint("Error: $e"); }

      // Warm the large-icon asset cache before any reminder is scheduled.
      await NotificationBranding.prewarm();

      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_notification',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
        onDidReceiveBackgroundNotificationResponse:
            handleHabitReminderActionBackground,
      );
      _initialized = true;

      // Reminder-policy listeners, wired once here so every UI/service state
      // change funnels through ONE path (the registry) — the UI can't forget:
      //
      // 1. mealAddedNotifier (NOT the generic changeNotifier): fires only when
      //    a meal is actually added, so the "first meal logged" suppression of
      //    today's nagging reminders can never be tripped accidentally by a
      //    scan-count refresh (e.g. subscription activation bumping
      //    changeNotifier).
      // 2. SubscriptionService: subscribe / cancel / admin-strip / verify-
      //    restore all apply the reminder plan through scheduleForSubscription-
      MealStore.instance.mealAddedNotifier.addListener(_onMealsChanged);
      SubscriptionService.instance.addListener(_onSubscriptionChanged);
      HabitStore.instance.remindersChangedNotifier.addListener(_onHabitsChanged);
      WidgetsBinding.instance.addObserver(this);

      // The launch `resumed` lifecycle event fires immediately after runApp —
      // but main.dart already ran the full startup restore. Seed the cooldown
      // so that first event is a no-op instead of a second full re-arm.
      _lastResumeRearm = DateTime.now();
    } catch (e, st) {
      // Ignore notification initialization failures; app should still run.
      debugPrint('❌ NotificationService.init failed: $e\n$st');
    }
  }

  /// Self-heal after the app returns to the foreground:
  ///
  /// 1. The user may have travelled — re-derive the device timezone and
  ///    re-apply `tz.local` so every repeating reminder fires at the right
  ///    wall-clock time.
  /// 2. The OS can drop scheduled alarms while the app is backgrounded
  ///    (aggressive OEM battery savers, Doze, reboot) — re-running the
  ///    restore re-creates anything lost, without waiting for the next
  ///    full launch.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (_lastResumeRearm != null &&
        now.difference(_lastResumeRearm!) < _resumeRearmCooldown) {
      return; // App-switcher flick — alarms were just re-armed.
    }
    _lastResumeRearm = now;
    unawaited(_rearmAfterResume());
  }

  Future<void> _rearmAfterResume() async {
    // Timezone re-derivation is best-effort: a failure must NOT block the
    // restore — the alarms still need re-creating even if the tz read fails.
    try {
      final tzName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(tzName));
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyTz, tzName);
      } catch (e) { debugPrint("Error: $e"); }
    } catch (e) {
      debugPrint('⚠️ resume tz refresh failed (continuing restore): $e');
    }
    try {
      await restoreAllReminders(
        HabitStore.instance.habits,
        subscribedDate: SubscriptionService.instance.subscribedAt,
      );
    } catch (e) {
      debugPrint('❌ reminder resume re-arm failed: $e');
    }
  }

  void _onMealsChanged() {
    _registry.onMealsChanged();
  }

  /// Fired when the habit reminder plan changes (add / edit / toggle /
  /// remove / cloud-restore). Reconciles the whole habit plan — the single
  /// funnel, so HabitStore never needs to know about notifications.
  void _onHabitsChanged() {
    unawaited(applyHabitPlan());
  }

  /// Fired on every [SubscriptionService] state change (subscribe, cancel,
  /// admin grant/strip, verify-restore). Applies the reminder plan for the
  /// current state — the single transition funnel, so the UI and services
  /// never need to remember to touch reminders themselves.
  void _onSubscriptionChanged() {
    unawaited(applySubscriptionState());
  }

  /// Applies the reminder plan matching [SubscriptionService]'s current state:
  /// subscribed → every built-in + every habit; free → cancel only the
  /// subscriber-gated ids and re-arm the free plan + habits. Never throws.
  Future<void> applySubscriptionState() async {
    try {
      await _registry.sync(
        habits: HabitStore.instance.habits,
        subscribedDate: SubscriptionService.instance.subscribedAt,
      );
    } catch (e) {
      debugPrint('❌ applySubscriptionState failed: $e');
    }
  }

  /// Handles taps and action buttons on notifications.
  ///
  /// Habit reminders carry the habit id as the payload, so we can snooze,
  /// mark the habit done, or open the Habits tab right from the shade.
  /// Built-in reminders (daily meal, streak, weekly summary, expiry) carry
  /// no payload — they're routed by notification id instead, so tapping any
  /// MacroSnap notification opens something useful (never a dead end).
  void _onNotificationTap(NotificationResponse response) {
    final actionId = response.actionId;
    final habitId = response.payload;

    if (habitId != null && habitId.isNotEmpty) {
      if (actionId == HabitReminderService.snoozeAction) {
        _snoozeHabit(habitId);
      } else if (actionId == HabitReminderService.doneAction) {
        _completeHabit(habitId);
      } else {
        // Plain tap on the habit reminder -> open the Habits tab.
        openShellTab(2);
      }
      return;
    }

    switch (notificationTapDestination(response.id)) {
      case NotificationTapDestination.home:
        // "Time to log your meals" / streak / weekly summary -> Home.
        openShellTab(0);
      case NotificationTapDestination.subscription:
        // "Pro expires / expired" -> the Subscription screen.
        openSubscriptionScreen();
      case NotificationTapDestination.none:
        break;
    }
  }

  /// What a built-in (non-habit) notification tap should open, decided by
  /// notification id. Pure — unit-tested in isolation.
  static NotificationTapDestination notificationTapDestination(int? id) {
    switch (id) {
      case ReminderRegistry.dailyMealId:
      case ReminderRegistry.streakId:
      case ReminderRegistry.weeklySummaryId:
        return NotificationTapDestination.home;
      case ReminderRegistry.expiryReminderId:
      case ReminderRegistry.expiredId:
        return NotificationTapDestination.subscription;
      default:
        return NotificationTapDestination.none;
    }
  }

  Habit? _findHabit(String habitId) {
    for (final h in HabitStore.instance.habits) {
      if (h.id == habitId) return h;
    }
    return null;
  }

  /// Fallback for notification actions: the in-memory store can be stale or
  /// empty (long backgrounded session, a reload that failed) while the habit
  /// still exists in prefs. Read the habit straight from SharedPreferences —
  /// the same source the background isolate uses — so Mark done / Snooze
  /// always act on the real habit.
  Future<Habit?> _findHabitFromPrefs(String habitId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final suffix =
          AccountPartition.suffix(AccountPartition.activeFromPrefs(p));
      final raw = p.getString(AccountPartition.key('habits', suffix));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      for (final e in decoded.whereType<Map>()) {
        final h = Habit.fromJson(Map<String, dynamic>.from(e));
        if (h.id == habitId) return h;
      }
    } catch (e) {
      debugPrint('❌ habit lookup from prefs failed: $e');
    }
    return null;
  }

  Future<void> _snoozeHabit(String habitId) async {
    try {
      await HabitStore.instance.load();
      var habit = _findHabit(habitId);
      habit ??= await _findHabitFromPrefs(habitId);
      if (habit == null) {
        debugPrint('⚠️ Snooze: habit $habitId not found anywhere');
        return;
      }
      await HabitReminderService.snooze(habit, _plugin);
      debugPrint('🔔 Snoozed habit ${habit.name} for 10 minutes');
    } catch (e) {
      debugPrint('❌ Snooze action failed: $e');
      // Never let a notification action crash the app.
    }
  }

  Future<void> _completeHabit(String habitId) async {
    try {
      await HabitStore.instance.load();
      var habit = _findHabit(habitId);
      final fromPrefs = habit == null;
      habit ??= await _findHabitFromPrefs(habitId);
      if (habit == null) {
        debugPrint('⚠️ Mark done: habit $habitId not found anywhere');
        return;
      }
      if (fromPrefs) {
        // Stale/empty store: persist the completion DIRECTLY to prefs (same
        // as the background isolate). Routing through completeToday would
        // serialize the empty store list over prefs and erase the habit, and
        // push the stale list to the cloud.
        await _persistCompletionToPrefs(habit);
      } else {
        await HabitStore.instance.completeToday(habit);
      }
      // Mark done from the tap: clear the snoozed one-off AND push today's
      // upcoming daily reminder to tomorrow so it never fires again today.
      // (HabitStore.completeToday is pure data — these one-offs are the
      // notification layer's job, mirroring the background handler.)
      await cancelHabitReminderSnooze(habit);
      await rescheduleHabitReminderFromTomorrow(habit);
      debugPrint('✅ Mark done: ${habit.name} completed for today');
    } catch (e) {
      debugPrint('❌ Mark done action failed: $e');
      // Never let a notification action crash the app.
    }
  }

  /// Completes a habit found only in prefs (the store is stale/empty) by
  /// writing the change straight to SharedPreferences — never through the
  /// store, whose `save()` serializes its own (empty) list.
  Future<void> _persistCompletionToPrefs(Habit habit) async {
    final p = await SharedPreferences.getInstance();
    final suffix =
        AccountPartition.suffix(AccountPartition.activeFromPrefs(p));
    final habitsKey = AccountPartition.key('habits', suffix);
    final raw = p.getString(habitsKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    final habits = decoded
        .whereType<Map>()
        .map((e) => Habit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final index = habits.indexWhere((h) => h.id == habit.id);
    if (index < 0) return;
    final saved = habits[index];
    final key = dateKey(DateTime.now());
    if (!saved.completedDates.contains(key)) {
      saved.completedDates.add(key);
      saved.skippedDates.remove(key);
    }
    habits[index] = saved;
    await p.setString(
      habitsKey,
      jsonEncode(habits.map((h) => h.toJson()).toList()),
    );
  }

  /// The subscriber-gated reminder ids (for tests / diagnostics).
  static List<int> get subscriberGatedIds => ReminderRegistry.subscriberGatedIds;

  /// Human-readable plan of the built-in reminders plus the current
  /// subscription state and enabled-habit count, logged at startup.
  static List<String> debugDescribe() => ReminderRegistry.debugDescribe(
        subscribed: SubscriptionService.instance.isSubscribed,
        enabledHabits: HabitStore.instance.habits
            .where((h) => h.reminderEnabled)
            .length,
      );

  /// Reconciles every habit reminder against the current list — arms every
  /// enabled habit and cancels every disabled one. THE single funnel for all
  /// habit-reminder changes (add / edit / toggle / cloud restore), so the
  /// registry stays the only place that decides what is armed.
  Future<void> applyHabitPlan() async {
    try {
      await _registry.applyHabitPlan(HabitStore.instance.habits);
    } catch (e) {
      debugPrint('❌ applyHabitPlan failed: $e');
    }
  }

  /// Cancel the reminder for a single habit (used when the habit is about to
  /// be removed — once it leaves the list, the plan can no longer see it).
  Future<void> cancelHabitReminder(Habit h) async {
    try {
      await HabitReminderService.cancel(h, _plugin);
    } catch (e) { debugPrint("Error: $e"); }
  }

  /// Cancel just the one-off snoozed reminder (keeps the daily one).
  Future<void> cancelHabitReminderSnooze(Habit h) async {
    try {
      await HabitReminderService.cancelSnooze(h, _plugin);
    } catch (e) { debugPrint("Error: $e"); }
  }

  /// Suppress today's remaining daily reminder for [h] by cancelling the
  /// repeating schedule and re-creating it from tomorrow. Called after the
  /// habit is marked done today so it never re-reminds the same day.
  Future<void> rescheduleHabitReminderFromTomorrow(Habit h) async {
    try {
      await HabitReminderService.rescheduleTomorrow(h, _plugin);
    } catch (e) { debugPrint("Error: $e"); }
  }

  /// Full startup safety net: re-create every reminder so a lost alarm
  /// (reinstall, app update, force-stop) can never silently disable
  /// notifications. Each reminder restores independently — one failure
  /// never blocks the others. Subscribers additionally re-arm the expiry
  /// reminders and the weekly summary (same ids are replaced, idempotent).
  Future<void> restoreAllReminders(
    List<Habit> habits, {
    String? subscribedDate,
  }) async {
    await _registry.sync(habits: habits, subscribedDate: subscribedDate);
  }

  /// Best-effort diagnostic: how many alarms the OS actually holds right
  /// now, logged next to the reminder plan so a support session can spot a
  /// plan-vs-OS mismatch ("plan says 5, OS holds 0"). READ-ONLY — never
  /// acted on, and a failure is swallowed: the pending-request read path is
  /// exactly what R8/TypeToken broke before, so it must never gate logic.
  Future<void> logPendingCount() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      debugPrint('📋 Pending notifications held by OS: ${pending.length}');
    } catch (e) {
      debugPrint('⚠️ Could not read pending notification count: $e');
    }
  }
}
