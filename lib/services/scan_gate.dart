import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_http.dart';
import 'gemini_service.dart';
import '../core/app_limits.dart';
import 'subscription_service.dart';

/// The free AI-scan allowance.
///
/// THE SERVER IS THE AUTHORITY. `/analyze` enforces [freeLimitPerDay] free
/// scans per IST day for the signed-in user and returns the real
/// `scans_used` / `scans_limit` / `reset_at`; `GET /me/entitlements` reports
/// the same numbers. Everything in this class is a *display estimate* that
/// decides what the UI shows — [canScan] never blocks a scan on its own, it
/// only declines to offer one when a count the server sent **today** says the
/// allowance is spent. Without such a count the request goes out and the
/// server has the final word.
///
/// The day boundary is IST midnight (Asia/Kolkata), exactly like the server's,
/// so a stale number from yesterday is never presented as today's.
class ScanGate {
  ScanGate._();

  /// Free AI scans per day. The ONE place the plan is defined — the server
  /// mirrors it in SCAN_LIMIT_FREE (macro-snap-backend/server.js).
  /// Single client-side copy of the allowance (see [AppLimits]); the server
  /// still sends the authoritative per-account limit.
  static const int freeLimitPerDay = AppLimits.freeScansPerDay;

  /// Local estimate of today's usage (display only).
  static const String _usedKey = 'scan_count';
  static const String _dayKey = 'scan_day';

  /// The last numbers the SERVER reported, and the IST day they belong to.
  static const String _serverUsedKey = 'server_scan_used';
  static const String _serverLimitKey = 'server_scan_limit';
  static const String _serverDayKey = 'server_scan_day';
  static const String _serverResetKey = 'server_scan_reset';

  /// Now, in IST (UTC+5:30, no DST).
  static DateTime istNow([DateTime? now]) => (now ?? DateTime.now())
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30));

  /// The IST calendar day as `yyyy-MM-dd` — the key the counter resets on.
  static String istDayKey([DateTime? now]) {
    final d = istNow(now);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Whether the UI should still offer a free scan.
  ///
  /// True unless the server told us (today) that the allowance is gone. There
  /// is deliberately NO local limit check: a stale local counter may never
  /// block a request, because the server decides and it may well disagree.
  static Future<bool> canScan() async {
    if (_isSubscribed()) return true;
    final server = await _serverState();
    if (!server.isFresh) return true;
    if (server.limit == null) return true; // unlimited (Pro/admin)
    return server.used < server.limit!;
  }

  /// Scans left to show in the UI (999 = unlimited).
  static Future<int> getScansRemaining() async {
    if (_isSubscribed()) return 999;
    final server = await _serverState();
    if (server.isFresh && server.limit != null) {
      return (server.limit! - server.used).clamp(0, server.limit!);
    }
    // Nothing trustworthy from the server yet — show the local estimate.
    final prefs = await SharedPreferences.getInstance();
    final used = await _localUsed(prefs);
    return (freeLimitPerDay - used).clamp(0, freeLimitPerDay);
  }

  /// Today's usage as far as the UI knows.
  static Future<int> getScansUsed() async {
    if (_isSubscribed()) return 0;
    final server = await _serverState();
    if (server.isFresh) return server.used;
    final prefs = await SharedPreferences.getInstance();
    return _localUsed(prefs);
  }

  /// The server's `reset_at` (next IST midnight) when we know it.
  static Future<DateTime?> getResetAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serverResetKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Stores the numbers the server reported (after a successful /analyze, or
  /// from GET /me/entitlements). Only a same-day report is ever trusted, so
  /// the IST day is recorded alongside them.
  static Future<void> recordServerCounts({
    required int used,
    int? limit,
    DateTime? resetAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_serverUsedKey, used);
    if (limit == null) {
      await prefs.remove(_serverLimitKey);
    } else {
      await prefs.setInt(_serverLimitKey, limit);
    }
    await prefs.setString(_serverDayKey, istDayKey());
    if (resetAt != null) {
      await prefs.setString(_serverResetKey, resetAt.toIso8601String());
    }
    // Keep the local estimate in step so the two can't disagree on screen.
    await prefs.setInt(_usedKey, used);
    await prefs.setString(_dayKey, istDayKey());
  }

  /// The server answered 403 `scan_limit_reached`: today's allowance is gone.
  /// Records the limit as used so the UI immediately shows 0 scans left.
  static Future<void> markLimitReached({DateTime? resetAt}) =>
      recordServerCounts(
        used: freeLimitPerDay,
        limit: freeLimitPerDay,
        resetAt: resetAt,
      );

  /// Bumps the LOCAL estimate by one. Display only — the server counts the
  /// scans that actually happened.
  static Future<int> incrementScan() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (await _localUsed(prefs)) + 1;
    await prefs.setInt(_usedKey, count);
    await prefs.setString(_dayKey, istDayKey());
    return count;
  }

  /// Asks the server for the authoritative numbers (`GET /me/entitlements`).
  /// Best-effort: a failure or a guest leaves the current state untouched and
  /// returns false, and the next scan simply lets the server decide.
  static Future<bool> refreshFromServer() async {
    try {
      final res = await AuthHttp.get(
        Uri.parse('${GeminiService.serverUrl}/me/entitlements'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['subscribed'] == true) {
        // Pro/admin: no limit to track.
        await recordServerCounts(used: 0, limit: null);
        return true;
      }
      final used = (data['scans_used'] as num?)?.toInt();
      if (used == null) return false;
      await recordServerCounts(
        used: used,
        limit: (data['scans_limit'] as num?)?.toInt() ?? freeLimitPerDay,
        resetAt: DateTime.tryParse(data['reset_at'] as String? ?? ''),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads the already-loaded subscription state.
  ///
  /// This used to call `SubscriptionService.load()` on every check, which
  /// re-read prefs and could fire notifications — i.e. checking the scan
  /// allowance had the side effect of flipping Pro state mid-scan. Startup and
  /// the purchase flow own loading; this is a plain read.
  static bool _isSubscribed() => SubscriptionService.instance.isSubscribed;

  /// Today's local estimate, resetting when the IST day changes.
  static Future<int> _localUsed(SharedPreferences prefs) async {
    final today = istDayKey();
    if (prefs.getString(_dayKey) != today) {
      await prefs.setInt(_usedKey, 0);
      await prefs.setString(_dayKey, today);
      return 0;
    }
    return prefs.getInt(_usedKey) ?? 0;
  }

  /// The last server report, and whether it belongs to today (IST).
  static Future<({int used, int? limit, bool isFresh})> _serverState() async {
    final prefs = await SharedPreferences.getInstance();
    final fresh = prefs.getString(_serverDayKey) == istDayKey();
    return (
      used: prefs.getInt(_serverUsedKey) ?? 0,
      limit: prefs.getInt(_serverLimitKey),
      isFresh: fresh,
    );
  }
}
