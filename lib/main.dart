import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
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

Future<void> main() async {
  // ── Global crash safety net ────────────────────────────────────────
  // Last line of defense behind the guarded startup steps: any framework
  // error and any uncaught platform/zone error is logged and swallowed
  // instead of terminating the isolate. Previously an unhandled error at
  // launch left the app stuck on a black screen, unable to open.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('❌ Flutter framework error: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('❌ Uncaught platform error: $error');
    // Swallow in release (the app must never die for users) but rethrow in
    // debug so developers still see uncaught errors loudly during dev.
    return kReleaseMode;
  };
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // One quick platform call, and it decides how the first frame is laid
      // out — so it stays ahead of `runApp`.
      await _guard(
        () => SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]),
        'orientation lock',
      );

      // ── First frame first ─────────────────────────────────────────
      // Startup work used to be awaited *before* `runApp`, so the app showed
      // nothing but the native launch window (black in dark mode) until
      // Firebase, the notification plugin and every local store had finished
      // — several seconds on a cold start or a busy device. The splash now
      // paints immediately and `_bootstrap()` runs behind it.
      runApp(MacroSnapApp(startup: _bootstrap()));
    },
    (error, stack) {
      debugPrint('❌ Uncaught zone error: $error\n$stack');
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
    _guard(_initFirebase, 'Firebase.initializeApp'),
    _guard(() => GeminiService.init(), 'GeminiService.init'),
    _guard(() async => RazorpayService.init(), 'RazorpayService.init'),
    _guard(
      () => SubscriptionService.instance.load(),
      'SubscriptionService.load',
    ),
    _guard(() => NotificationService().init(), 'NotificationService.init'),
  ]);

  // Verify the paid subscription against the backend Postgres database — the
  // source of truth — so paying users get Pro restored on reinstall/device
  // change even before opening the subscription screen. (Fire-and-forget, so
  // a slow network never delays the first screen.)
  unawaited(_guard(
    () => SubscriptionService.instance.verifyServerSubscription(),
    'SubscriptionService.verifyServerSubscription',
  ));

  // ── Phase 2: local data ──────────────────────────────────────────
  // Each of these is an independent prefs/file read, so they run together
  // instead of one after another. Local data is what the first real screen
  // draws; cloud restore stays in the background.
  await Future.wait<void>([
    _guard(() => MealStore.instance.load(), 'MealStore.load'),
    _guard(() => RecentFoodService.instance.load(), 'RecentFoodService.load'),
    _guard(() => DietPlanService.instance.load(), 'DietPlanService.load'),
    _guard(() => HabitStore.instance.load(), 'HabitStore.load'),
    _guard(() => WeightStore.instance.load(), 'WeightStore.load'),
  ]);

  // ── Phase 3: background restore (never blocks the UI) ────────────
  // Restore user preferences from cloud (theme, name) if local is missing.
  unawaited(_guard(() async {
    final prefs = await SharedPreferences.getInstance();
    final cloudPrefs = await MealSyncService.fetchPreferences();
    if (cloudPrefs != null) {
      // Only restore if local doesn't have a value set by the user.
      // Type-check instead of a blind cast: a non-string from the cloud
      // used to throw and abort the whole preference restore.
      final cloudTheme = cloudPrefs['themeMode'];
      if (!prefs.containsKey('theme_mode') && cloudTheme is String) {
        await prefs.setString('theme_mode', cloudTheme);
      }
      final cloudName = cloudPrefs['name'];
      if (!prefs.containsKey('name') && cloudName is String) {
        await prefs.setString('name', cloudName);
      }
    }
  }, 'Preferences cloud restore'));

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

Future<void> _initFirebase() async {
  await Firebase.initializeApp();
  debugPrint('✅ Firebase initialized successfully');
}

/// Runs a single startup step, swallowing any error so one failure can
/// never block the app. Returns normally even when [fn] throws.
Future<void> _guard(Future<void> Function() fn, String label) async {
  try {
    await fn();
  } catch (e) {
    debugPrint('❌ $label failed: $e');
  }
}
