import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'app.dart';
import 'services/currency_service.dart';
import 'services/meal_image_store.dart';
import 'services/nav_ab_test.dart';
import 'services/meal_store.dart';
import 'models/diet_profile.dart';
import 'services/notification_service.dart';
import 'services/gemini_service.dart';
import 'services/razorpay_service.dart';
import 'services/habit_store.dart';
import 'services/weight_store.dart';
import 'services/subscription_service.dart';
import 'services/recent_food_service.dart';
import 'services/meal_sync_service.dart';
import 'services/crash_reporting.dart';
import 'services/badge_service.dart';
import 'services/meal_streak_service.dart';
import 'services/pending_sync_queue.dart';
import 'services/leaderboard_remote.dart';
import 'services/leaderboard_service.dart';
import 'services/step_counter_service.dart';
import 'services/account_partition.dart';
import 'core/app_nav.dart';

Future<void> main() async {
  // ── Global crash safety net ────────────────────────────────────────
  // Last line of defense behind the guarded startup steps: any framework
  // error and any uncaught platform/zone error is logged and swallowed
  // instead of terminating the isolate. Previously an unhandled error at
  // launch left the app stuck on a black screen, unable to open.
  //
  // Both handlers also forward to Crashlytics, so a release crash leaves a
  // trace instead of vanishing into a `debugPrint` nobody reads.
  // These three handlers all SWALLOW the error and let the app keep running,
  // so they are reported as NON-fatal. Marking them fatal inflated the crash
  // count with errors that never crashed anything and dragged the crash-free
  // rate down for every user who hit a single failed frame build. A genuinely
  // fatal crash is still reported as fatal by the platform itself.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashReporting.record(
      details.exception,
      details.stack,
      reason: details.context?.toString() ?? 'Flutter framework error',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashReporting.record(error, stack, reason: 'Uncaught platform error');
    // Swallow in release (the app must never die for users) but tell the user
    // something failed: swallowing alone left the app running with a broken
    // feature and nothing on screen to explain it.
    if (kReleaseMode) _announceUncaughtError();
    // Rethrow in debug so developers still see uncaught errors loudly.
    return kReleaseMode;
  };
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // ── First frame first ─────────────────────────────────────────
      // Startup work used to be awaited *before* `runApp`, so the app showed
      // nothing but the native launch window (black in dark mode) until
      // Firebase, the notification plugin and every local store had finished
      // — several seconds on a cold start or a busy device. The splash now
      // paints immediately and `_bootstrap()` runs behind it.
      runApp(MacroSnapApp(startup: _bootstrap()));

      // One quick platform call for the portrait lock. It used to be AWAITED
      // ahead of runApp — "it decides how the first frame is laid out" — but
      // it is a platform channel like any other: on a handful of devices the
      // answer simply never comes on some launches, and until runApp ran the
      // window showed nothing but the native background. Eight seconds of
      // black for a sidebar of code that does not need to precede the first
      // frame is a bad trade, so it now runs in the background, guarded.
      unawaited(
        _guardStartup(
          () => SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]),
          'orientation lock',
        ),
      );
    },
    (error, stack) {
      CrashReporting.record(error, stack, reason: 'Uncaught zone error');
    },
  );
}

/// Everything that used to block `runApp()`.
///
/// Every step is guarded so a corrupted local file, an unreachable backend,
/// or a plugin failure can never leave the user stuck on the splash. The
/// independent steps of each phase run together: the phases themselves stay
/// ordered (plugins → local data → background restore) because later steps
/// assume the earlier ones are ready.
Future<void> _bootstrap() async {
  // ── Phase 1: plugins and account state ───────────────────────────
  await Future.wait<void>([
    _guardStartup(_initFirebase, 'Firebase.initializeApp'),
    _guardStartup(() => GeminiService.init(), 'GeminiService.init'),
    _guardStartup(() async => RazorpayService.init(), 'RazorpayService.init'),
    _guardStartup(
      () => SubscriptionService.instance.load(),
      'SubscriptionService.load',
    ),
    _guardStartup(
      () => NotificationService().init(),
      'NotificationService.init',
    ),
    // Which currency the Pro price is shown in. Read once here so every
    // submit price label on the paywall (and in the reminder copy) is already
    // resolved when the first screen builds.
    _guardStartup(
      () => CurrencyService.instance.refresh(),
      'CurrencyService.refresh',
    ),
    // Which bottom-nav design this install draws for the A/B test — and how
    // long meal photos are kept, both plain prefs reads.
    _guardStartup(() => NavAbTest.instance.load(), 'NavAbTest.load'),
    _guardStartup(
      () => MealImageStore.loadRetention(),
      'MealImageStore.loadRetention',
    ),
  ]);

  // Bind the admin-claim listener: Firebase restores the session after
  // `load()` has already run, so this is what grants lifetime Pro to the
  // owner (and strips a leaked marker when someone else signs in).
  SubscriptionService.instance.bindAuth();

  // Verify the paid subscription against the server (Firestore user doc, then
  // the backend as a backfill fallback) — the source of truth — so paying
  // users get Pro restored on reinstall/device change even before opening the
  // subscription screen. (Fire-and-forget, so a slow network never delays the
  // first screen.)
  unawaited(
    _guard(
      () => SubscriptionService.instance.verifyServerSubscription(),
      'SubscriptionService.verifyServerSubscription',
    ),
  );

  // ── Phase 2: local data ──────────────────────────────────────────
  // Move the active account's stored data onto its current partition suffix
  // BEFORE any store reads it: this is what carries an existing install
  // through the collision fix, and onboarding's pre-login data into the
  // account that has since signed in.
  await _guardStartup(
    () async => AccountPartition.ensureCurrent(
      await SharedPreferences.getInstance(),
    ),
    'AccountPartition.ensureCurrent',
  );

  // Each of these is an independent prefs/file read, so they run together
  // instead of one after another. Local data is what the first real screen
  // draws; cloud restore stays in the background.
  await Future.wait<void>([
    _guardStartup(() => MealStore.instance.load(), 'MealStore.load'),
    _guardStartup(
      () => RecentFoodService.instance.load(),
      'RecentFoodService.load',
    ),
    _guardStartup(
      () => DietPlanService.instance.load(),
      'DietPlanService.load',
    ),
    _guardStartup(() => HabitStore.instance.load(), 'HabitStore.load'),
    _guardStartup(() => WeightStore.instance.load(), 'WeightStore.load'),
  ]);

  // Cloud writes that failed in an earlier session are replayed from here on:
  // the queue needs the loaded history to do it, and it re-arms itself on
  // every resume so a phone that comes back onto WiFi catches up on its own.
  PendingSyncQueue.instance.mealSource = () => MealStore.instance.allMeals;
  PendingSyncQueue.instance.start();

  // The phone's own step counter — NOT Health Connect. It is started on every
  // launch so a day's walking is counted and scored even for a user who never
  // installed or authorised a health app; the permission dialog itself belongs
  // to the Health tab, so this only resumes a grant that already exists.
  unawaited(
    _guard(() async {
      await StepCounterService.instance.start();
    }, 'StepCounterService.start'),
  );

  // Leaderboard points are derived from the stores loaded above (meals,
  // habits, water, weigh-ins), so it is attached once they are ready and then
  // keeps itself current by listening to them and to the step sensor.
  unawaited(
    _guard(
      LeaderboardService.instance.attach,
      'LeaderboardService.attach',
    ).then(
      // Restore the join from the server first (a reinstall has no local
      // flag, and asking a joined account to join again was the bug), then push
      // this device's activity so the week is scored server-side.
      (_) => _guard(() async {
        await LeaderboardRemote.instance.restoreFromServer();
        await LeaderboardRemote.instance.syncWithServer();
      }, 'LeaderboardRemote.restore+sync'),
    ),
  );
  // Every point change (a meal, a habit, water, a weigh-in, a step batch) is
  // pushed to the server shortly after it happens. Without this the server only
  // heard from a device that opened the Rank page, so a user who never opened
  // it lost yesterday's movement when the app was reinstalled.
  LeaderboardService.instance.addListener(_scheduleLeaderboardPush);

  unawaited(
    _guard(PendingSyncQueue.instance.drain, 'PendingSyncQueue.drain'),
  );

  // Achievements shipped after these users had already been logging, so their
  // history holds milestones the badge store has no record of. Re-apply them
  // silently (no toast for something earned weeks ago); this also repairs a
  // device change, where the local trophy case starts empty.
  await _guardStartup(_backfillBadges, 'BadgeService.backfill');

  // ── Phase 3: background restore (never blocks the UI) ────────────
  // Run the achievements backfill again once the cloud merge lands: on a new
  // phone the local meal list is empty at launch, so the check in Phase 2 has
  // nothing to count. Idempotent, so the second pass only adds what the merge
  // brought in.
  unawaited(
    _guard(() async {
      await MealStore.instance.cloudSynced;
      await _backfillBadges();
    }, 'BadgeService.backfill after cloud restore'),
  );

  // One-time local cleanup for versions pre-1.5: the recipe feature is gone,
  // but a device that upgraded carries its leftover keys — the legacy
  // 'recipes' store and one 'recipes_<account>' blob per signed-in account —
  // and nothing else ever deletes them. Remove them all; now that nothing
  // reads them, they are dead data (the privacy policy promises no custom
  // recipes are collected, so nothing should linger either).
  // The obsolete 'theme_mode' pref goes too: the app is dark-only and reads
  // nothing there.
  unawaited(
    _guard(() async {
      final prefs = await SharedPreferences.getInstance();
      final leftovers = prefs.getKeys().where((k) {
        return k == 'recipes' || k.startsWith('recipes_') || k == 'theme_mode';
      }).toList();
      for (final key in leftovers) {
        await prefs.remove(key);
      }
      if (leftovers.isNotEmpty) {
        debugPrint('🧹 removed ${leftovers.length} obsolete prefs: $leftovers');
      }
    }, 'Remove obsolete recipe/theme prefs'),
  );

  // Restore user preferences from cloud (name) if local is missing.
  unawaited(
    _guard(() async {
      final prefs = await SharedPreferences.getInstance();
      final cloudPrefs = await MealSyncService.fetchPreferences();
      if (cloudPrefs != null) {
        // Only restore if local doesn't have a value set by the user.
        // Type-check instead of a blind cast: a non-string from the cloud
        // used to throw and abort the whole preference restore.
        final cloudName = cloudPrefs['name'];
        if (!prefs.containsKey('name') && cloudName is String) {
          await prefs.setString('name', cloudName);
        }
        // The calorie-goal streak is part of the account, not the device: a
        // reinstall used to start it at zero (and the streak badge backfill
        // then "found" it months later with today's date).
        final cloudStreak = cloudPrefs['streakDates'];
        if (cloudStreak is String && cloudStreak.isNotEmpty) {
          await MealStreakService.mergeCloudDates(
            MealStreakService.jsonList(cloudStreak),
          );
        }
      }
    }, 'Preferences cloud restore'),
  );

  // Restore ALL reminders every launch — the OS drops scheduled alarms
  // on reinstall/update/force-stop, and without this, reminders
  // silently stop working. (Fire-and-forget, error-guarded.)
  unawaited(
    _guard(() async {
      debugPrint(
        '📋 Reminder plan:\n${NotificationService.debugDescribe().join('\n')}',
      );
      await NotificationService().restoreAllReminders(
        HabitStore.instance.habits,
        subscribedDate: SubscriptionService.instance.subscribedAt,
      );
      // Best-effort diagnostic: plan-vs-OS mismatch visibility (e.g.
      // "plan says 5, OS holds 0" when alarms were silently dropped).
      await NotificationService().logPendingCount();
    }, 'NotificationService reminders'),
  );
}

Timer? _leaderboardPushTimer;

/// Debounced push of this week's activity to the server.
///
/// Debounced on purpose: three water glasses, a meal and a step batch are one
/// request, and the backend rate-limits the route to 12/minute. A user who has
/// not joined sends nothing — browsing a board must not publish a score.
void _scheduleLeaderboardPush() {
  final service = LeaderboardService.instance;
  if (!service.optIn || !service.hasLocation) return;
  _leaderboardPushTimer?.cancel();
  _leaderboardPushTimer = Timer(const Duration(seconds: 8), () {
    unawaited(LeaderboardRemote.instance.syncWithServer());
  });
}

/// Rebuilds the trophy case from what is already on this device.
///
/// Badges are stored locally, so a new phone starts with an empty case even
/// for an account that has logged a hundred meals. Recomputing from the store
/// each launch makes the board self-healing: the same check awards the badge
/// on the next launch after a reinstall, with no server round-trip.
Future<void> _backfillBadges() async {
  await BadgeService.instance.backfillFromHistory(
    totalMeals: MealStore.instance.allMeals.length,
    streakDays: await MealStreakService.getCurrent(),
    // Not `entries.isNotEmpty`: the BMI screen seeds the profile weight, and
    // counting a seed would award "First Weigh-In" on the next launch — the
    // badge fix would have been undone here instead of at the seed.
    hasWeighIn: WeightStore.instance.hasRealWeighIn,
    // Streak badges record the day the run was completed, not the day this
    // launch noticed it.
    hitDates: await MealStreakService.bankedDates(),
  );
}

Future<void> _initFirebase() async {
  await Firebase.initializeApp();
  debugPrint('✅ Firebase initialized successfully');
  // Crash reporting needs a live Firebase app, so it starts here rather than
  // in `main()`. Release-only and best-effort by design (see CrashReporting).
  await CrashReporting.init();
  await _initAppCheck();
}

bool _uncaughtErrorAnnounced = false;

/// Tells the user that something failed while the app kept running.
///
/// Once per session — a burst of uncaught async errors must not bury the screen
/// in snackbars — and only when the app is actually mounted, so an error during
/// startup says nothing rather than leaving a message nobody is there to read.
void _announceUncaughtError() {
  if (_uncaughtErrorAnnounced) return;
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  _uncaughtErrorAnnounced = true;
  messenger.showSnackBar(
    const SnackBar(
      content: Text(
        'Something went wrong. If the app misbehaves, restart it.',
      ),
    ),
  );
}

/// Attests that requests come from this app, not from a script holding the
/// Firebase API key (which ships inside `google-services.json` and is therefore
/// public). Releases use Play Integrity; debug builds use the debug provider,
/// whose token must be added in Firebase Console → App Check → Manage debug
/// tokens.
///
/// **Enforcement is a console setting, not this call.** Until App Check is
/// enforced for Firestore/Authentication, this only *collects* attestation.
/// Turning enforcement on before the console shows verified traffic would
/// reject every request from every install, so it stays off until the
/// dashboard has real data. Activation is best-effort and never blocks startup.
Future<void> _initAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (e, st) {
    logError('main._initAppCheck', e, st);
  }
}

/// Runs a single startup step, swallowing any error so one failure can
/// never block the app. Returns normally even when [fn] throws.
///
/// No timeout here: this is used for background work (cloud restore, reminder
/// rescheduling) that is allowed to take its time.
Future<void> _guard(Future<void> Function() fn, String label) async {
  try {
    await fn();
  } catch (e, st) {
    logError('main._guard($label)', e, st);
  }
}

/// A step the first screen actually waits for.
///
/// Bounded per step, so one wedged platform channel fails on its own after
/// [limit] instead of holding the splash until the app-level safety timeout —
/// which used to let every screen build on half-loaded data. The app-level
/// timeout in `app.dart` is now only a last resort.
Future<void> _guardStartup(
  Future<void> Function() fn,
  String label, {
  Duration limit = const Duration(seconds: 8),
}) async {
  try {
    await fn().timeout(limit);
  } on TimeoutException catch (e, st) {
    logError(
      'main._guardStartup($label) timed out after ${limit.inSeconds}s',
      e,
      st,
    );
  } catch (e, st) {
    logError('main._guardStartup($label)', e, st);
  }
}
