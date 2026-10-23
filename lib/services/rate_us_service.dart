import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../widgets/gradient_button.dart';
import 'crash_reporting.dart';

/// Redirects users to the MacroSnap Play Store listing to leave a rating,
/// and shows a polite, once-in-a-while rate prompt (inspired by Spotify,
/// Duolingo and other apps). Respects "no thanks" and offers "remind later".
class RateUsService {
  static const String _packageName = 'com.macrosnap.macro_snap';

  // SharedPreferences keys
  static const String _launchKey = 'rate_launch_count';
  static const String _laterKey = 'rate_later_count';
  static const String _ratedKey = 'rate_done';
  static const String _dismissedKey = 'rate_dismissed';

  /// Minimum launches before the first prompt appears (gives the user time
  /// to actually experience the app first).
  static const int _minLaunchesBeforePrompt = 3;

  /// How many launches to wait after each "Later" before asking again.
  static const int _launchesPerReminder = 5;

  /// Maximum number of "Later" reminders before we stop asking.
  static const int _maxReminders = 3;

  /// Opens the Play Store page for MacroSnap.
  ///
  /// The primary path is a native explicit intent pinned to the Play Store
  /// package (see MainActivity.openPlayStore) — the plain `market://` scheme
  /// is hijacked by OEM stores like V-Appstore on several devices, which
  /// sent "Rate Us" to the wrong store. Falls back to launching the URLs
  /// directly when the channel is unavailable (e.g. widget tests).
  static const MethodChannel _launcher = MethodChannel('macrosnap/launcher');

  static Future<bool> openPlayStore() async {
    final market = Uri.parse('market://details?id=$_packageName');
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageName',
    );

    // 1) Native explicit intent (Play Store package only) — can't be
    //    intercepted by V-Appstore / GetApps / etc.
    try {
      final opened = await _launcher.invokeMethod<bool>('openPlayStore');
      if (opened == true) return true;
    } on PlatformException catch (e) {
      debugPrint('Play Store channel failed: $e');
    } on MissingPluginException {
      // Channel absent (tests / non-Android) — use url_launcher below.
    }

    // 2) url_launcher fallback: market:// first, then the web listing.
    try {
      final opened = await launchUrl(
        market,
        mode: LaunchMode.externalApplication,
      );
      if (opened) return true;
    } catch (e, st) {
      logError('RateUsService.openPlayStore (market)', e, st);
    }

    try {
      return await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      logError('RateUsService.openPlayStore (web)', e, st);
    }
    return false;
  }

  /// Registers a fresh app launch and decides whether to show the prompt.
  /// Call this once per app startup (fire-and-forget).
  static Future<void> onAppLaunch(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Never show again once rated or explicitly dismissed forever.
      if (prefs.getBool(_ratedKey) ?? false) return;
      if (prefs.getBool(_dismissedKey) ?? false) return;

      final launches = (prefs.getInt(_launchKey) ?? 0) + 1;
      await prefs.setInt(_launchKey, launches);

      final reminders = prefs.getInt(_laterKey) ?? 0;
      if (reminders >= _maxReminders) return;

      final needed =
          _minLaunchesBeforePrompt + (reminders * _launchesPerReminder);
      if (launches < needed) return;

      // Wait a moment so the prompt never overlaps the first screen build.
      await Future.delayed(const Duration(milliseconds: 900));
      if (!context.mounted) return;
      await _showPrompt(context);
    } catch (_) {
      // Rating prompt is best-effort; never break startup over it.
    }
  }

  /// A manual "Rate Us" action (e.g. from Settings) that opens Play Store
  /// directly without the prompt dialog. Only marks the user as rated once
  /// the store page actually launches, so a failed launch doesn't suppress
  /// future prompts.
  static Future<void> rateNowFromSettings() async {
    final opened = await openPlayStore();
    if (opened) {
      await prefsMarkRated();
    }
  }

  static Future<void> prefsMarkRated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ratedKey, true);
    } catch (e, st) {
      logError('RateUsService.prefsMarkRated', e, st);
    }
  }

  /// One-shot "Rate us" button shown to brand-new users right after their
  /// first login. Tapping it opens the Play Store rating page directly.
  /// Shown only once per install, then never again.
  static const String _newUserShownKey = 'rate_new_user_shown';

  static Future<void> showNewUserRatingButton(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Someone who already rated (or opted out) is never asked again — even
      // on a fresh install, where this async first-login dialog would show.
      if (prefs.getBool(_ratedKey) ?? false) return;
      if (prefs.getBool(_dismissedKey) ?? false) return;
      if (prefs.getBool(_newUserShownKey) ?? false) return;
      await prefs.setBool(_newUserShownKey, true);
      if (!context.mounted) return;
      await _showNewUserDialog(context);
    } catch (_) {
      // Best-effort — never break login over the rating prompt.
    }
  }

  static Future<void> _showNewUserDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stars row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.star_rounded,
                    size: 32,
                    color: MacroSnapTheme.neonYellow.withValues(
                      alpha: 1 - (i * 0.08),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Text(
              'Enjoying MacroSnap?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If you love it, a quick rating on the Play Store helps '
              'more people discover the app. Thanks for your support!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GradientButton(
                label: 'Rate us on Play Store ⭐',
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await rateNowFromSettings();
                },
                height: 50,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Later',
                style: TextStyle(
                  fontSize: 13,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The prompt dialog: "Enjoying MacroSnap? Rate us 5 stars!"
  static Future<void> _showPrompt(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final action = await showDialog<RatePromptAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stars row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.star_rounded,
                    size: 32,
                    color: MacroSnapTheme.neonYellow.withValues(
                      alpha: 1 - (i * 0.08),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Text(
              'Enjoying MacroSnap?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your rating helps us reach more people '
              'and keeps the app free. Thanks for your support!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GradientButton(
                label: 'Rate 5 Stars ⭐',
                onPressed: () => Navigator.of(ctx).pop(RatePromptAction.rate),
                height: 50,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(RatePromptAction.later),
                  child: Text(
                    'Later',
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(RatePromptAction.noThanks),
                  child: Text(
                    "No, thanks",
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    switch (action) {
      case RatePromptAction.rate:
        await prefs.setBool(_ratedKey, true);
        await openPlayStore();
        break;
      case RatePromptAction.later:
      case null:
        // "Later" or barrier-tap dismiss — ask again in a few launches.
        await prefs.setInt(_laterKey, (prefs.getInt(_laterKey) ?? 0) + 1);
        break;
      case RatePromptAction.noThanks:
        await prefs.setBool(_dismissedKey, true);
        break;
    }
  }
}

enum RatePromptAction { rate, later, noThanks }
