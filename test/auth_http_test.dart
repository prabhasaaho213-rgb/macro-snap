import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:macro_snap/services/auth_http.dart';

/// Every call to our backend must carry the signed-in user's Firebase ID
/// token, and a 401 must be retried exactly once with a refreshed token.
/// Guests (no token) send no Authorization header at all.
void main() {
  setUp(() {
    AuthHttp.tokenOverride = null;
    AuthHttp.client = http.Client();
  });

  tearDown(() {
    AuthHttp.tokenOverride = null;
    AuthHttp.client = http.Client();
  });

  test('a signed-in request carries the Firebase ID token', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'id-token-1';
    Map<String, String>? seen;
    AuthHttp.client = MockClient((req) async {
      seen = req.headers;
      return http.Response('{"ok":true}', 200);
    });

    final res = await AuthHttp.get(Uri.parse('https://api.test/me/entitlements'));

    expect(res.statusCode, 200);
    expect(seen!['Authorization'], 'Bearer id-token-1');
  });

  test('a guest sends no Authorization header', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => null;
    Map<String, String>? seen;
    AuthHttp.client = MockClient((req) async {
      seen = req.headers;
      return http.Response('{"error":"unauthenticated"}', 401);
    });

    await AuthHttp.get(Uri.parse('https://api.test/trial/status'));

    expect(seen!.containsKey('Authorization'), isFalse,
        reason: 'guests must not send a token');
  });

  test('a 401 refreshes the token once and retries', () async {
    var refreshes = 0;
    AuthHttp.tokenOverride = ({required forceRefresh}) async {
      if (forceRefresh) refreshes++;
      return forceRefresh ? 'fresh-token' : 'stale-token';
    };

    var attempts = 0;
    final sentTokens = <String?>[];
    AuthHttp.client = MockClient((req) async {
      attempts++;
      sentTokens.add(req.headers['Authorization']);
      if (attempts == 1) return http.Response('{"error":"unauthenticated"}', 401);
      return http.Response('{"subscribed":false}', 200);
    });

    final res = await AuthHttp.get(Uri.parse('https://api.test/subscription/status'));

    expect(res.statusCode, 200, reason: 'the retry must succeed');
    expect(attempts, 2, reason: 'exactly one retry');
    expect(refreshes, 1, reason: 'the token is refreshed once');
    expect(sentTokens, ['Bearer stale-token', 'Bearer fresh-token']);
  });

  test('a persistent 401 is not retried forever', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'tok';
    var attempts = 0;
    AuthHttp.client = MockClient((req) async {
      attempts++;
      return http.Response('{"error":"unauthenticated"}', 401);
    });

    final res = await AuthHttp.get(Uri.parse('https://api.test/chat'));

    expect(res.statusCode, 401);
    expect(attempts, 2, reason: 'one original attempt plus one retry');
  });

  test('post keeps the body and adds the token', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'tok';
    String? body;
    Map<String, String>? seen;
    AuthHttp.client = MockClient((req) async {
      body = req.body;
      seen = req.headers;
      return http.Response('{"subscribed":true}', 200);
    });

    await AuthHttp.post(
      Uri.parse('https://api.test/register'),
      headers: {'Content-Type': 'application/json'},
      body: '{"name":"Aarav"}',
    );

    expect(seen!['Authorization'], 'Bearer tok');
    expect(seen!['Content-Type'], 'application/json');
    expect(body, '{"name":"Aarav"}');
  });

  test('multipart uploads the file and authenticates', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'tok';
    final file = File(
      '${Directory.systemTemp.path}/auth_http_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsStringSync('fake-jpeg-bytes');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    var attempts = 0;
    String? body;
    Map<String, String>? seen;
    AuthHttp.client = MockClient((req) async {
      attempts++;
      body = req.body;
      seen = req.headers;
      // First attempt: an expired token; the retry must rebuild the multipart
      // request (a StreamedRequest can only be sent once).
      if (attempts == 1) return http.Response('{"error":"unauthenticated"}', 401);
      return http.Response('{"scans_used":1,"scans_limit":3}', 200);
    });

    final res = await AuthHttp.multipart(
      Uri.parse('https://api.test/analyze'),
      fileField: 'image',
      filePath: file.path,
    );

    expect(res.statusCode, 200);
    expect(attempts, 2);
    expect(seen!['Authorization'], 'Bearer tok');
    expect(seen!['Content-Type'], contains('multipart/form-data'));
    expect(body, contains('name="image"'), reason: 'the file field is sent');
    expect(body, contains('fake-jpeg-bytes'), reason: 'the file bytes are sent');
  });
}
