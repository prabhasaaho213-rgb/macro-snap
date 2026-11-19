import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crash_reporting.dart';

/// Opens MacroSnap's Play Store page, and remembers when the user has been
/// there to rate.
///
/// The AUTOMATIC prompt used to live here: a custom dialog on a launch counter
/// that read "Enjoying MacroSnap?" with a single button labelled "Rate 5 Stars
/// ⭐". Two things were wrong with it. It told the user what to rate, which is
/// the solicitation pattern Play's policy treats as fake engagement, and it
/// asked after three launches regardless of whether anything had been logged.
/// The automatic ask is now Play's own in-app review sheet, raised after the
/// third saved meal (see [InAppReviewService]); this file keeps only the
/// deliberate paths — Settings' "Rate us" row and the same action on the
/// What's New screen — plus the explicit-intent store launcher they share.
///
/// The launcher matters: the plain `market://` scheme is hijacked by OEM stores
/// such as V-Appstore on several devices, which sent "Rate Us" to the wrong
/// store. The native channel targets the Play Store package explicitly, with
/// url_launcher as the fallback.
class RateUsService {
  static const String _packageName = 'com.macrosnap.macro_snap';

  /// Set once the user has actually been taken to the store page.
  static const String _ratedKey = 'rate_done';

  static const MethodChannel _launcher = MethodChannel('macrosnap/launcher');

  /// Opens the Play Store listing for MacroSnap.
  static Future<bool> openPlayStore() async {
    final market = Uri.parse('market://details?id=$_packageName');
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_packageName',
    );

    // 1) Native explicit intent (Play Store package only).
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

  /// The Settings / What's New "Rate us" action: opens the listing directly.
  /// Only marked as rated once the store page actually launched, so a failed
  /// launch does not silently suppress anything.
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
}
