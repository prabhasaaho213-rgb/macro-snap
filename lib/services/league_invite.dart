import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';
import 'invite_analytics.dart';

/// A friends-league invite carried by a link.
///
/// Two shapes arrive here:
///   * `https://macro-snap-backend.vercel.app/join/ABC123` — the shared link,
///     which Android opens in the app when it is installed (and the backend
///     sends to the Play Store otherwise)
///   * `macrosnap://join/ABC123` — custom-scheme fallback
///
/// Only a well-formed six-character code is accepted, so a random deep link
/// cannot put junk in front of the join call.
class LeagueInvite {
  LeagueInvite._();

  /// Where an invite waits between the link arriving and the shell being ready.
  ///
  /// A cold start delivers the link before sign-in has been resolved, so the
  /// code is parked here and taken by [MainShell] once the account is known.
  static const String prefsKey = 'pending_league_invite';

  /// The Play Install Referrer channel (Android only, see MainActivity).
  static const MethodChannel _referrerChannel = MethodChannel(
    'macrosnap/install_referrer',
  );

  /// Set once the referrer has been read, so later launches do not bind Play's
  /// service again: the referrer describes the install that already happened.
  static const String referrerReadKey = 'install_referrer_checked';

  /// The code that has already been auto-opened once, so a saved invite is not
  /// pushed in front of the user on every launch.
  static const String autoShownKey = 'pending_league_invite_shown';

  static final RegExp _codeShape = RegExp(r'^[A-Za-z0-9]{6}$');

  /// The league code inside [uri], or null when the link is not an invite.
  static String? codeFromUri(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // https://host/join/ABC123
    if (segments.length == 2 && segments.first == 'join') {
      return normalize(segments.last);
    }
    // macrosnap://join/ABC123 parses as host "join", one path segment.
    if (uri.scheme == 'macrosnap' &&
        uri.host == 'join' &&
        segments.length == 1) {
      return normalize(segments.first);
    }
    return null;
  }

  /// Whether [uri] is a league-invite link, even a malformed one.
  ///
  /// Used to swallow a bad invite instead of letting it fall through as a
  /// Navigator route (which has no generator and would show an error page).
  static bool isJoinLink(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty && segments.first == 'join';
  }

  /// Uppercases and validates a raw code (the server's codes are 6 characters).
  static String? normalize(String raw) {
    final code = raw.trim().toUpperCase();
    return _codeShape.hasMatch(code) ? code : null;
  }

  /// The invite code inside a Play referrer string.
  ///
  /// The backend's store link carries `referrer=join_code=CODE`, and Play
  /// hands that back with the URL encoding already removed. A query string is
  /// still parsed rather than string-matched, so extra parameters ride along
  /// harmlessly; a bare code is accepted too, for a referrer written by hand.
  static String? codeFromReferrer(String referrer) {
    var trimmed = referrer.trim();
    if (trimmed.isEmpty) return null;
    // Play normally decodes the referrer for us, but a redirect or a share
    // client can hand it back still encoded (`join_code%3DABC123`). Undo one
    // layer when that is what arrived, so the invite is not lost to encoding.
    if (!trimmed.contains('=') && trimmed.toLowerCase().contains('%3d')) {
      try {
        trimmed = Uri.decodeComponent(trimmed);
      } catch (_) {
        // Malformed escape: keep the raw value and let validation reject it.
      }
    }
    try {
      final fromQuery = Uri.splitQueryString(trimmed)['join_code'];
      if (fromQuery != null) return normalize(fromQuery);
    } on FormatException {
      // Not a query string — fall through and try the whole value.
    }
    return normalize(trimmed);
  }

  static Future<void>? _referrerCapture;

  /// Reads the Play Install Referrer once and parks any invite code in it.
  ///
  /// An invite for someone who does not have the app goes to the Play Store
  /// with the code as the install referrer, so the code arrives with the
  /// install and not with a link. This is the only read of it: without it the
  /// friend installed, saw a normal home screen, and had to tap the invite a
  /// second time.
  ///
  /// Memoised, so the read `main()` starts at launch and the one [MainShell]
  /// awaits before taking the invite are the same single read.
  static Future<void> captureInstallReferrer() =>
      _referrerCapture ??= _captureInstallReferrer();

  static Future<void> _captureInstallReferrer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(referrerReadKey) == true) return;
    // Play's API only exists on Android; the store link is Android-only too.
    if (!Platform.isAndroid) return;
    String? referrer;
    // Play reports SERVICE_UNAVAILABLE for a few seconds right after an
    // install — the normal case here — so retry in-session instead of waiting
    // for a next launch many people never make.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        referrer = await _referrerChannel
            .invokeMethod<String>('getReferrer')
            .timeout(const Duration(seconds: 5));
      } on MissingPluginException catch (e, st) {
        // No channel in this build: retrying cannot help.
        logError('LeagueInvite.captureInstallReferrer', e, st);
        return;
      } catch (e, st) {
        logError('LeagueInvite.captureInstallReferrer', e, st);
      }
      if (referrer != null) break;
      await Future<void>.delayed(Duration(seconds: attempt == 0 ? 2 : 5));
    }
    // null is "the read failed"; an empty string is Play saying this install
    // had no referrer, which is as final as a hit.
    if (referrer == null) return;
    await prefs.setBool(referrerReadKey, true);
    final code = codeFromReferrer(referrer);
    if (code != null) {
      await save(code);
      await InviteAnalytics.log('referrer', code: code);
    }
  }

  /// The pending code, WITHOUT consuming it.
  ///
  /// The code is cleared only once the join actually happened (or the code is
  /// proven dead), so a friend who is not Pro yet keeps the invite through the
  /// paywall, a back press and a relaunch.
  static Future<String?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    return normalize(prefs.getString(prefsKey) ?? '');
  }

  /// Drops the pending invite — after a successful join, or when the code no
  /// longer points at a league.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  /// Whether [code] has already been auto-opened once.
  static Future<bool> wasAutoShown(String code) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(autoShownKey) == code;
  }

  static Future<void> markAutoShown(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(autoShownKey, code);
  }

  static Future<void> save(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, code);
  }

  /// Reads and clears the pending invite, so it is applied exactly once.
  static Future<String?> take() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw != null) await prefs.remove(prefsKey);
    return raw == null ? null : normalize(raw);
  }
}
