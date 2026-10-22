import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/services/auth_http.dart';
import 'package:macro_snap/services/scan_gate.dart';
import 'package:macro_snap/services/subscription_service.dart';

/// The free AI-scan allowance is 3 per IST day and the SERVER is the
/// authority: the local counter is only a display estimate, a count the server
/// sent is trusted only when it arrived today, and a 403 means "0 left".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fresh prefs + subscription state for each test (the subscription service
  /// is a singleton, so its state would otherwise leak between tests).
  Future<void> reset({bool subscribed = false}) async {
    SharedPreferences.setMockInitialValues(
      subscribed ? {'subscribed': true} : {},
    );
    await SubscriptionService.instance.load();
  }

  setUp(() async {
    AuthHttp.tokenOverride = ({required forceRefresh}) async => 'tok';
    AuthHttp.client = MockClient(
      (_) async => http.Response('{"subscribed":false}', 200),
    );
  });

  tearDown(() {
    AuthHttp.tokenOverride = null;
    AuthHttp.client = http.Client();
  });

  test('the day boundary is IST midnight, not UTC', () {
    // 18:29 UTC is 23:59 IST on the 16th; one minute later it is the 17th.
    expect(
      ScanGate.istDayKey(DateTime.utc(2026, 10, 16, 18, 29)),
      '2026-10-16',
    );
    expect(
      ScanGate.istDayKey(DateTime.utc(2026, 10, 16, 18, 30)),
      '2026-10-17',
    );
    // 05:30 UTC is 11:00 IST, still the same IST day.
    expect(ScanGate.istDayKey(DateTime.utc(2026, 10, 17, 5, 30)), '2026-10-17');
    expect(ScanGate.freeLimitPerDay, 3);
  });

  test('a server count received today drives the display', () async {
    await reset();
    await ScanGate.recordServerCounts(used: 2, limit: 3);

    expect(await ScanGate.getScansRemaining(), 1);
    expect(await ScanGate.getScansUsed(), 2);
    expect(await ScanGate.canScan(), isTrue);
  });

  test('an exhausted LOCAL estimate alone never blocks a scan', () async {
    await reset();
    // Burn far past the limit with no server number at all.
    for (var i = 0; i < 5; i++) {
      await ScanGate.incrementScan();
    }

    expect(
      await ScanGate.getScansRemaining(),
      0,
      reason: 'the local estimate says 0 left',
    );
    expect(
      await ScanGate.canScan(),
      isTrue,
      reason: 'the server decides — the request must still go out',
    );
  });

  test('a server count of 3/3 today stops offering scans', () async {
    await reset();
    await ScanGate.recordServerCounts(used: 3, limit: 3);

    expect(await ScanGate.getScansRemaining(), 0);
    expect(await ScanGate.canScan(), isFalse);
  });

  test("yesterday's server count is ignored", () async {
    SharedPreferences.setMockInitialValues({
      'server_scan_used': 3,
      'server_scan_limit': 3,
      'server_scan_day': '2020-01-01',
    });
    await SubscriptionService.instance.load();

    expect(
      await ScanGate.canScan(),
      isTrue,
      reason: 'a stale count must never block today',
    );
    expect(
      await ScanGate.getScansRemaining(),
      ScanGate.freeLimitPerDay,
      reason: 'nor may it be shown as today\'s usage',
    );
  });

  test('the local estimate resets when the IST day changes', () async {
    SharedPreferences.setMockInitialValues({
      'scan_count': 3,
      'scan_day': '2020-01-01',
    });
    await SubscriptionService.instance.load();

    expect(await ScanGate.getScansRemaining(), ScanGate.freeLimitPerDay);
  });

  test(
    'a 403 sets the stored count to the limit, so the UI shows 0 left',
    () async {
      await reset();
      await ScanGate.markLimitReached();

      expect(await ScanGate.getScansRemaining(), 0);
      expect(await ScanGate.getScansUsed(), ScanGate.freeLimitPerDay);
      expect(await ScanGate.canScan(), isFalse);
    },
  );

  test('Pro shows unlimited and is never blocked', () async {
    await reset(subscribed: true);
    // Even a used-up free count must not gate a paying user.
    await ScanGate.recordServerCounts(used: 3, limit: 3);

    expect(await ScanGate.getScansRemaining(), 999);
    expect(await ScanGate.canScan(), isTrue);
  });

  test('refreshFromServer adopts the numbers the server reports', () async {
    await reset();
    AuthHttp.client = MockClient((req) async {
      expect(req.url.path, '/me/entitlements');
      expect(req.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode({
          'subscribed': false,
          'scans_used': 1,
          'scans_limit': 3,
          'scans_remaining': 2,
          'scan_day': '2026-10-16',
          'reset_at': '2026-10-16T18:30:00.000Z',
        }),
        200,
      );
    });

    expect(await ScanGate.refreshFromServer(), isTrue);
    expect(await ScanGate.getScansRemaining(), 2);
    expect(
      await ScanGate.getResetAt(),
      DateTime.parse('2026-10-16T18:30:00.000Z'),
      reason: 'the reset time is kept for the countdown',
    );
  });

  test('a failed refresh leaves the current state alone', () async {
    await reset();
    AuthHttp.client = MockClient(
      (_) async => http.Response('{"error":"unauthenticated"}', 401),
    );

    expect(await ScanGate.refreshFromServer(), isFalse);
    expect(await ScanGate.getScansRemaining(), ScanGate.freeLimitPerDay);
    expect(await ScanGate.canScan(), isTrue);
  });
}
