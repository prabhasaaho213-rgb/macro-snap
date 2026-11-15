import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:macro_snap/services/auth_http.dart';
import 'package:macro_snap/services/referral_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Referral codes are minted server-side and the client only ever names its own
/// account through the ID token. This pins the two things that make that safe:
/// the token is sent, and a failure is reported rather than swallowed into a
/// code the screen would happily paint.
void main() {
  setUp(() {
    AuthHttp.client = http.Client();
    AuthHttp.tokenOverride = null;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AuthHttp.client = http.Client();
    AuthHttp.tokenOverride = null;
  });

  test('generateCode returns the code the server minted', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'id-token';
    var path = '';
    Map<String, String>? headers;
    AuthHttp.client = MockClient((req) async {
      path = req.url.path;
      headers = req.headers;
      return http.Response('{"referral_code":"ABC123"}', 200);
    });

    expect(await ReferralService.generateCode(), 'ABC123');
    expect(path, '/referral/generate');
    expect(headers!['Authorization'], 'Bearer id-token');
  });

  test('generateCode on 401 asks the user to sign in', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => null;
    AuthHttp.client = MockClient(
      (req) async => http.Response('{"error":"unauthenticated"}', 401),
    );

    await expectLater(
      ReferralService.generateCode(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('sign in'),
        ),
      ),
    );
  });

  test('applyCode surfaces the server reason instead of a generic failure',
      () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'id-token';
    AuthHttp.client = MockClient(
      (req) async => http.Response('{"error":"code already used"}', 400),
    );

    await expectLater(
      ReferralService.applyCode('ABC123'),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('code already used'),
        ),
      ),
    );
  });

  test('applyCode returns the credited month on success', () async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'id-token';
    String? body;
    AuthHttp.client = MockClient((req) async {
      body = req.body;
      return http.Response('{"ok":true}', 200);
    });

    expect(await ReferralService.applyCode('ABC123'), 'free_month');
    expect(jsonDecode(body!) as Map<String, dynamic>, {'code': 'ABC123'});
  });

  test('a code cached on device comes back without a network call', () async {
    AuthHttp.client = MockClient(
      (req) async => throw StateError('cachedCode must not hit the network'),
    );
    expect(await ReferralService.cachedCode(), isNull);

    await ReferralService.cacheCode('XYZ789');
    expect(await ReferralService.cachedCode(), 'XYZ789');
  });
}
