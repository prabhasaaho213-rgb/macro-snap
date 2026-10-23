import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/services/auth_http.dart';
import 'package:macro_snap/services/subscription_service.dart';

/// Regression tests for the "Pro never turns off" audit finding.
///
/// * A SUCCESSFUL /subscription/status answer of `subscribed: false` must
///   clear the saved Pro flag (cancelled subscription, expired referral
///   window, or a stale trial marker — trials are gone).
/// * A network failure must never downgrade anyone.
/// * `pro_until` from the server is stored so Settings can show the end date.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthHttp.client = http.Client();
  });

  /// `/trial/status` answers [trial] (503 by default → treated as "unknown"),
  /// `/subscription/status` answers [status].
  void routeTo({http.Response? trial, http.Response? status}) {
    AuthHttp.client = MockClient((req) async {
      if (req.url.path.endsWith('/trial/status')) {
        return trial ?? http.Response('', 503);
      }
      return status ?? http.Response('', 503);
    });
  }

  test('subscribed:false from the server clears the saved Pro flag', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'user@example.com',
      'subscribed': true,
      'subscribed_at': '2026-01-01T00:00:00.000',
      'pro_until': '2026-12-31T00:00:00.000',
    });
    await SubscriptionService.instance.load();
    expect(SubscriptionService.instance.isSubscribed, isTrue);

    routeTo(status: http.Response('{"subscribed": false}', 200));
    await SubscriptionService.instance.verifyServerSubscription();

    expect(
      SubscriptionService.instance.isSubscribed,
      isFalse,
      reason: 'an authoritative subscribed:false must downgrade',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('subscribed'), isNot(true));
    expect(prefs.getString('subscribed_at'), isNull);
    expect(prefs.getString('pro_until'), isNull);
  });

  test('a 500 from the server never downgrades', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'user@example.com',
      'subscribed': true,
    });
    await SubscriptionService.instance.load();

    routeTo(status: http.Response('boom', 500));
    await SubscriptionService.instance.verifyServerSubscription();

    expect(SubscriptionService.instance.isSubscribed, isTrue);
  });

  test('a network exception never downgrades', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'user@example.com',
      'subscribed': true,
    });
    await SubscriptionService.instance.load();

    AuthHttp.client = MockClient((_) async => throw Exception('offline'));
    await SubscriptionService.instance.verifyServerSubscription();

    expect(SubscriptionService.instance.isSubscribed, isTrue);
  });

  test('a stale trial marker does not keep Pro — subscribed:false downgrades', () async {
    // Trials are removed for everyone. A trial_ends_at marker left by an old
    // install (load() wipes it) must never keep Pro alive once the server
    // authoritatively answers subscribed:false.
    SharedPreferences.setMockInitialValues({
      'email': 'user@example.com',
      'subscribed': true,
      'trial_ends_at': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
    });
    await SubscriptionService.instance.load();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('trial_ends_at'), isNull, reason: 'the marker is dropped on load');

    routeTo(status: http.Response('{"subscribed": false}', 200));
    await SubscriptionService.instance.verifyServerSubscription();

    expect(
      SubscriptionService.instance.isSubscribed,
      isFalse,
      reason: 'a stale trial marker must not survive subscribed:false',
    );
  });

  test(
    'subscribed:true stores pro_until so Settings can show the end date',
    () async {
      final until = DateTime.now()
          .add(const Duration(days: 25))
          .toIso8601String();
      SharedPreferences.setMockInitialValues({'email': 'user@example.com'});
      await SubscriptionService.instance.load();

      routeTo(
        status: http.Response(
          '{"subscribed": true, "pro_until": "$until"}',
          200,
        ),
      );
      await SubscriptionService.instance.verifyServerSubscription();

      expect(SubscriptionService.instance.isSubscribed, isTrue);
      expect(SubscriptionService.instance.proUntil, until);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pro_until'), until);
    },
  );
}
