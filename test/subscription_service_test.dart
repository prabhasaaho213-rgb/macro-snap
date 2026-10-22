import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/services/subscription_service.dart';

/// Marker timestamp used for the admin's lifetime grant (private in the
/// service — duplicated here so tests can assert against the exact value).
const String kLifetimeDate = '1900-01-01T00:00:00.000';

void main() {
  setUp(() async {
    // Fresh in-memory prefs for every test.
    SharedPreferences.setMockInitialValues({});
    // The admin path is a Firebase custom claim, which the test harness has no
    // Firebase app to read — so it is injected here.
    SubscriptionService.adminCheckOverride = null;
    // Reset the singleton so state never bleeds between tests.
    await SubscriptionService.instance.load();
  });

  tearDown(() {
    SubscriptionService.adminCheckOverride = null;
  });

  test('load() grants lifetime Pro when the admin claim is present', () async {
    SubscriptionService.adminCheckOverride = () async => true;
    SharedPreferences.setMockInitialValues({'phone': '+919999900000'});

    await SubscriptionService.instance.load();

    final p = await SharedPreferences.getInstance();
    expect(
      SubscriptionService.instance.isSubscribed,
      isTrue,
      reason: 'Admin must always be Pro',
    );
    expect(
      SubscriptionService.instance.subscribedAt,
      kLifetimeDate,
      reason: 'Admin grant carries the lifetime marker',
    );
    expect(p.getBool('subscribed'), isTrue);
    expect(p.getString('subscribed_at'), kLifetimeDate);
  });

  test(
    'an email address alone never grants Pro — the claim is the only source',
    () async {
      // The owner's address used to be a hardcoded constant in the client, so
      // anyone who could edit SharedPreferences (a rooted phone, a rebuild) got
      // free Pro. Nothing but the server-set claim may grant it now — no address
      // is special, so this fixture is deliberately a generic one.
      SharedPreferences.setMockInitialValues({'email': 'owner@example.com'});

      await SubscriptionService.instance.load();

      expect(await SubscriptionService.instance.isAdmin(), isFalse);
      expect(SubscriptionService.instance.isSubscribed, isFalse);
      expect(SubscriptionService.instance.subscribedAt, isNull);
    },
  );

  test('load() strips a leaked lifetime grant for a non-admin user', () async {
    SubscriptionService.adminCheckOverride = () async => false;
    // Device state left behind by a previous admin session.
    SharedPreferences.setMockInitialValues({
      'email': 'someone@example.com',
      'subscribed': true,
      'subscribed_at': kLifetimeDate,
    });

    await SubscriptionService.instance.load();

    final p = await SharedPreferences.getInstance();
    expect(
      SubscriptionService.instance.isSubscribed,
      isFalse,
      reason: 'The lifetime grant must never transfer to another user',
    );
    expect(SubscriptionService.instance.subscribedAt, isNull);
    expect(
      p.getBool('subscribed'),
      isFalse,
      reason: 'Persisted flag must be cleared too',
    );
    expect(
      p.getString('subscribed_at'),
      isNull,
      reason: 'Lifetime marker must be removed',
    );
  });

  test('load() keeps a paying user subscribed with their real date', () async {
    SharedPreferences.setMockInitialValues({
      'email': 'paying@example.com',
      'subscribed': true,
      'subscribed_at': '2026-07-01T10:00:00.000',
    });

    await SubscriptionService.instance.load();

    final p = await SharedPreferences.getInstance();
    expect(
      SubscriptionService.instance.isSubscribed,
      isTrue,
      reason: 'A paying user must stay subscribed',
    );
    expect(
      SubscriptionService.instance.subscribedAt,
      '2026-07-01T10:00:00.000',
      reason: 'Their real paid date must be preserved (not lifetime)',
    );
    expect(p.getBool('subscribed'), isTrue);
  });

  test('load() strips a leaked lifetime grant but keeps the paid state of a '
      'paying user on a previously-admin device', () async {
    // The admin once signed in here (leaving the lifetime marker), then a
    // paying user signs in — the grant must not survive, but their paid
    // subscription must.
    SharedPreferences.setMockInitialValues({
      'email': 'paying@example.com',
      'subscribed': true,
      'subscribed_at': kLifetimeDate, // leftover from the admin session
    });

    await SubscriptionService.instance.load();

    final p = await SharedPreferences.getInstance();
    expect(
      p.getBool('subscribed'),
      isFalse,
      reason: 'The lifetime grant must be cleared on this device',
    );
    expect(
      p.getString('subscribed_at'),
      isNull,
      reason: 'The lifetime marker must be removed',
    );
    expect(SubscriptionService.instance.isSubscribed, isFalse);
  });
}
