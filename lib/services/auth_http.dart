import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// HTTP client for the **MacroSnap backend**: every request carries
/// `Authorization: Bearer <Firebase ID token>`, so the server can identify the
/// caller from the token instead of trusting anything in the body or URL.
///
/// Use this for our own backend ONLY. Third-party URLs (Google Gemini,
/// Razorpay's hosted page, …) must keep using `http` directly — the token must
/// never leave our server.
///
/// * Guests (nobody signed in, or Firebase not initialized) send no header at
///   all; the backend answers 401 for the endpoints that need an account.
/// * On a 401 the token is refreshed once and the request retried, which
///   covers the common "the cached token just expired" case without the user
///   seeing an error.
class AuthHttp {
  AuthHttp._();

  /// Test seam: swap in an `http.Client` (e.g. `MockClient`) to assert the
  /// headers and the refresh-and-retry behaviour without a network.
  @visibleForTesting
  static http.Client client = http.Client();

  /// Test seam: stands in for Firebase when a test needs a specific token
  /// (there is no Firebase app in the test environment).
  @visibleForTesting
  static Future<String?> Function({required bool forceRefresh})? tokenOverride;

  /// The signed-in user's current ID token, or null for a guest.
  /// Never throws: a sign-in state mid-restore, or an uninitialized Firebase
  /// in tests, simply means "no token".
  static Future<String?> idToken({bool forceRefresh = false}) async {
    final override = tokenOverride;
    if (override != null) return override(forceRefresh: forceRefresh);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }

  /// Request headers for the backend: the caller's headers plus the bearer
  /// token when there is one. The caller's own headers always win.
  static Future<Map<String, String>> headers({
    Map<String, String>? extra,
    bool forceRefresh = false,
  }) async {
    final token = await idToken(forceRefresh: forceRefresh);
    return <String, String>{
      ...?extra,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _send((h) => client.get(url, headers: h), headers);

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _send(
    (h) => client.post(url, headers: h, body: body, encoding: encoding),
    headers,
  );

  /// Authenticated multipart POST (image upload). The request is rebuilt for
  /// the retry because a `MultipartRequest` can only be sent once.
  static Future<http.Response> multipart(
    Uri url, {
    required String fileField,
    required String filePath,
    Map<String, String> fields = const {},
  }) async {
    Future<http.Response> attempt({required bool refresh}) async {
      final request = http.MultipartRequest('POST', url);
      request.headers.addAll(await headers(forceRefresh: refresh));
      request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
      return http.Response.fromStream(await client.send(request));
    }

    var response = await attempt(refresh: false);
    if (response.statusCode == 401) {
      response = await attempt(refresh: true);
    }
    return response;
  }

  /// Sends [attempt] with the bearer token, and retries ONCE with a fresh
  /// token when the server answers 401.
  static Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) attempt,
    Map<String, String>? extra,
  ) async {
    var response = await attempt(await headers(extra: extra));
    if (response.statusCode == 401) {
      response = await attempt(await headers(extra: extra, forceRefresh: true));
    }
    return response;
  }
}
