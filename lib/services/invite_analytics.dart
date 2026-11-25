import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini_service.dart';

/// Invite-funnel counters.
///
/// The flow has four steps that can each fail silently — the store carried the
/// referrer, the app read it, the league screen opened, the join succeeded —
/// and until now nothing recorded any of them. Each call writes one event
/// server-side (`inviteEvents`), so "do invites convert?" is a query instead of
/// a guess.
///
/// Never awaited on a user path and never throws: counting is not worth failing
/// a join over.
class InviteAnalytics {
  InviteAnalytics._();

  /// Event names the backend accepts. Anything else is rejected there.
  static const String referrer = 'referrer';
  static const String linkOpen = 'link_open';
  static const String screenOpen = 'screen_open';
  static const String joinAttempt = 'join_attempt';
  static const String joinOk = 'join_ok';
  static const String joinFail = 'join_fail';

  static Future<void> log(String event, {String? code}) async {
    try {
      await http
          .post(
            Uri.parse('${GeminiService.serverUrl}/join/event'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': event,
              if (code != null && code.isNotEmpty) 'code': code,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Offline, backend down, endpoint not deployed yet: all fine.
    }
  }
}
