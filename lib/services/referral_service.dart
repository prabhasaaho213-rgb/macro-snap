import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_http.dart';
import 'firebase_identity.dart';
import '../services/gemini_service.dart';

/// Referral codes, authenticated by the caller's Firebase ID token.
///
/// Phase 2: the account identifier is no longer part of the URL — the server
/// reads it from the token, so `/me/referral-code` can only ever return the
/// caller's own code and `/referral/apply` can only ever credit the caller's
/// own account. A guest (no token) gets a 401 instead of someone else's code.
class ReferralService {
  static String get _baseUrl => GeminiService.serverUrl;

  static const String _signedOut = 'Please sign in to use referrals';

  /// The code this account was last issued, kept on device. The screen paints
  /// it from here first, so opening Refer a Friend never shows a spinner while
  /// a network round-trip regenerates a code that has not changed.
  static const String _cachePrefix = 'referral_code_';

  static Future<String?> cachedCode() async {
    try {
      final uid = await FirebaseIdentity.currentUid() ?? 'guest';
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('$_cachePrefix$uid');
      return (code == null || code.isEmpty) ? null : code;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheCode(String code) async {
    try {
      final uid = await FirebaseIdentity.currentUid() ?? 'guest';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$uid', code);
    } catch (_) {
      // A failed cache write must never break the screen.
    }
  }

  /// (Re)generates the caller's referral code server-side.
  static Future<String> generateCode() async {
    final resp = await _post('/referral/generate', const <String, dynamic>{});
    if (resp.statusCode == 401) throw Exception(_signedOut);
    if (resp.statusCode == 429) {
      throw Exception('Too many requests. Wait a minute and try again.');
    }
    if (resp.statusCode >= 500) {
      throw Exception('Our server is having trouble. Try again in a moment.');
    }
    if (resp.statusCode != 200) throw Exception('Failed to generate code');
    // The body is only decoded once the status says it is worth decoding:
    // a gateway 502 page is HTML and `as Map` threw a FormatException whose
    // text ended up on screen.
    final code = _jsonBody(resp.body)?['referral_code'];
    if (code is! String || code.isEmpty) {
      throw Exception('The server sent an unexpected response.');
    }
    return code;
  }

  /// Applies a friend's code to the signed-in account.
  static Future<String> applyCode(String code) async {
    final resp = await _post('/referral/apply', {'code': code});
    if (resp.statusCode == 401) throw Exception(_signedOut);
    if (resp.statusCode == 429) {
      throw Exception('Too many attempts. Wait a minute and try again.');
    }
    if (resp.statusCode >= 500) {
      throw Exception('Our server is having trouble. Try again in a moment.');
    }
    if (resp.statusCode != 200) {
      final body = _jsonBody(resp.body);
      throw Exception(body?['error'] as String? ?? 'Failed to apply code');
    }
    return 'free_month';
  }

  /// POST with a bounded wait and a friendly transport failure.
  ///
  /// Without the timeout a hung request left the screen on its spinner, and a
  /// raw `SocketException: Failed host lookup…` reached the user as-is.
  static Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await AuthHttp.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception('That took too long. Check your connection and try again.');
    } catch (e) {
      // SocketException / ClientException / DNS: all the same story to a user.
      throw Exception('Could not reach the server. Check your connection.');
    }
  }

  static Map<String, dynamic>? _jsonBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
