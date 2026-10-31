import 'dart:convert';
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
    final resp = await AuthHttp.post(
      Uri.parse('$_baseUrl/referral/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(const <String, dynamic>{}),
    );
    if (resp.statusCode == 401) throw Exception(_signedOut);
    if (resp.statusCode != 200) throw Exception('Failed to generate code');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['referral_code'] as String;
  }

  /// Applies a friend's code to the signed-in account.
  static Future<String> applyCode(String code) async {
    final resp = await AuthHttp.post(
      Uri.parse('$_baseUrl/referral/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    if (resp.statusCode == 401) throw Exception(_signedOut);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception(body['error'] as String? ?? 'Failed to apply code');
    }
    return 'free_month';
  }
}
