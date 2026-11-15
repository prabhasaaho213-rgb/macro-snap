import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:macro_snap/services/auth_http.dart';
import 'package:macro_snap/services/gemini_service.dart';

/// Error responses are not all JSON.
///
/// A gateway 502/504 answers with an HTML page and a serverless timeout answers
/// with the platform's own text, so decoding the body before looking at the
/// status turned "the service is down" into a FormatException the user read as
/// "unexpected response". These pin the status-first behaviour.
void main() {
  late File image;

  setUp(() async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'id-token';
    image = File('${Directory.systemTemp.path}/macrosnap_scan_error_test.jpg');
    await image.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() {
    AuthHttp.client = http.Client();
    AuthHttp.tokenOverride = null;
  });

  /// Runs a scan against [status]/[body] and returns the message shown.
  Future<String> scanErrorText(int status, String body) async {
    AuthHttp.client = MockClient((_) async => http.Response(body, status));
    try {
      await GeminiService.analyzeFoodImage(image.path);
    } catch (e) {
      return e.toString();
    }
    fail('analyzeFoodImage should have thrown for HTTP $status');
  }

  test('a 502 HTML page is reported as the service being down', () async {
    final msg = await scanErrorText(502, '<html><body>Bad gateway</body></html>');
    expect(msg.toLowerCase(), contains('down right now'));
    expect(msg, isNot(contains('unexpected response')));
  });

  test('a 504 time-out page is reported as the service being down', () async {
    final msg = await scanErrorText(
      504,
      '<html><body>Gateway Timeout</body></html>',
    );
    expect(msg.toLowerCase(), contains('down right now'));
    expect(msg, isNot(contains('unexpected response')));
  });

  test('a 429 says to wait, not to check the connection', () async {
    final msg = await scanErrorText(429, '<html>rate limited</html>');
    expect(msg, contains('Too many scans'));
    expect(msg.toLowerCase(), isNot(contains('internet connection')));
  });

  test('a 400 keeps the server’s own reason', () async {
    final msg = await scanErrorText(400, '{"error":"image too blurry"}');
    expect(msg, contains('image too blurry'));
  });

  test('a 400 with an HTML body still names the status', () async {
    final msg = await scanErrorText(418, '<html>teapot</html>');
    expect(msg, contains('418'));
  });
}
