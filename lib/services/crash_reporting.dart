import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Production crash reporting.
///
/// Before this existed every uncaught error was swallowed and printed, so a
/// release build could crash for real users without leaving a trace anywhere.
/// Crashlytics was already one dependency away (the project ships Firebase and
/// `google-services.json`), so it is the sink we use.
///
/// Everything here is best-effort and can never throw: startup must survive a
/// missing Firebase app, no Play Services, or the plugin being unavailable in
/// tests. In debug builds collection stays OFF so developer crashes don't
/// pollute the production dashboard — but [record] still prints locally.
class CrashReporting {
  CrashReporting._();

  static bool _enabled = false;

  /// True once collection has actually started. Until then [record] only logs.
  static bool get isEnabled => _enabled;

  /// Starts collection. Call once Firebase is initialised; safe to call again.
  ///
  /// Returns whether collection is on. Never throws.
  static Future<bool> init() async {
    if (_enabled) return true;
    // Debug/profile builds: keep the dashboard clean, keep the console noisy.
    if (!kReleaseMode) return false;
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('Crash reporting skipped: Firebase is not initialised');
        return false;
      }
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      _enabled = true;
      return true;
    } catch (e) {
      // A reporting failure must never take the app down with it.
      debugPrint('Crash reporting unavailable: $e');
      return false;
    }
  }

  /// Records an error. [fatal] marks the crash that ended a session; caught
  /// errors are non-fatal so they show up as issues without polluting the
  /// crash-free rate.
  static void record(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    // Always visible in the local log, whatever the build mode.
    debugPrint('❌ ${reason ?? 'error'}: $error');
    if (!_enabled) return;
    try {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: reason,
          fatal: fatal,
        ),
      );
    } catch (_) {
      // Nothing to do: reporting failed, the local log above still has it.
    }
  }
}

/// Logs a caught error together with **where it was caught**, and reports it to
/// Crashlytics as a non-fatal issue in release builds.
///
/// Replaces the twenty-four context-free error prints that used to make every
/// swallowed exception untraceable: no place, no stack, nothing in the
/// dashboard. [where] is a short `Class.method` label.
void logError(String where, Object error, [StackTrace? stack]) {
  CrashReporting.record(error, stack, reason: where);
}
