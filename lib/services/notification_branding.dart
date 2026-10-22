import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Single source of truth for every visual choice on MacroSnap's
/// notifications: the brand color, the small status-bar icon, and the large
/// logo icon. Every reminder in the app builds its
/// [AndroidNotificationDetails] through [androidDetails], so icon /
/// largeIcon / color can never drift again — the earlier NPE and
/// invalid_icon bugs were both configuration drift between blocks.
class NotificationBranding {
  NotificationBranding._();

  /// MacroSnap brand green (matches ic_launcher_background #059669).
  static const Color color = Color(0xFF059669);

  /// Small status-bar icon. Android small icons must be a drawable resource
  /// (looked up by string via Resources.getIdentifier), so this stays in
  /// res/drawable + keep.xml — it cannot be a Flutter asset.
  static const String smallIcon = '@drawable/ic_notification';

  /// Large logo icon as a Flutter asset. Bundled into the APK as an asset,
  /// R8's resource optimizer can never strip it — no keep.xml entry needed.
  static const String largeIconAsset =
      'assets/images/ic_notification_large.png';

  static Uint8List? _largeIconBytes;

  /// PNG bytes of the large logo, cached after first load. Returns null if
  /// the asset can't be read (e.g. a background isolate before prewarm) —
  /// callers then simply omit the large icon while staying fully branded.
  static Future<Uint8List?> largeIconBytes() async {
    if (_largeIconBytes != null) return _largeIconBytes;
    try {
      final data = await rootBundle.load(largeIconAsset);
      _largeIconBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } catch (_) {
      return null;
    }
    return _largeIconBytes;
  }

  /// Loads and caches the large icon bytes. Called from init() so the bytes
  /// are ready for every scheduled reminder.
  static Future<void> prewarm() async {
    await largeIconBytes();
  }

  /// The one branded [AndroidNotificationDetails] every reminder uses.
  static Future<AndroidNotificationDetails> androidDetails({
    required String channelId,
    required String channelName,
    required String channelDescription,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    List<AndroidNotificationAction>? actions,
  }) async {
    final large = await largeIconBytes();
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      color: color,
      icon: smallIcon,
      largeIcon: large == null ? null : ByteArrayAndroidBitmap(large),
      actions: actions,
    );
  }

  /// ── Personalised copy builders (pure, unit-testable) ──────────────

  /// Daily meal reminder. When we know yesterday's intake, the reminder
  /// references it — far more engaging than a generic nudge.
  static ({String title, String body}) dailyMealCopy({int? yesterdayCalories}) {
    if (yesterdayCalories != null && yesterdayCalories > 0) {
      return (
        title: 'Time to log your meals',
        body:
            'You logged $yesterdayCalories kcal yesterday — snap today\'s meals to keep tracking.',
      );
    }
    return (
      title: 'Time to log your meals',
      body: 'Snap a photo of your meal to track calories and macros.',
    );
  }

  /// Streak reminder. When the user has an active streak, name it — naming
  /// the streak makes it feel real and worth protecting.
  static ({String title, String body}) streakCopy({int streak = 0}) {
    if (streak > 0) {
      return (
        title: 'Keep your streak alive',
        body:
            'You\'re on a $streak-day streak. Log a meal today to keep it going.',
      );
    }
    return (
      title: 'Keep your streak alive',
      body:
          'You haven\'t logged a meal today. Snap a photo to keep your streak going.',
    );
  }

  /// Weekly summary copy. When the last 7 days have real numbers, name them
  /// (days every macro target was hit and total calories); otherwise fall
  /// back to the generic summary line.
  static ({String title, String body}) weeklyCopy({
    required int daysHit,
    required int totalCalories,
  }) {
    if (daysHit == 0 && totalCalories == 0) {
      return (
        title: 'Your weekly nutrition summary',
        body: 'See how your macros looked this week. Open MacroSnap to check.',
      );
    }
    return (
      title: 'Your weekly nutrition summary',
      body:
          'You hit your macro targets on $daysHit of the last 7 days and logged $totalCalories kcal. Open MacroSnap to check.',
    );
  }
}
