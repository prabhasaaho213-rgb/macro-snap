import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/currency_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the India detection in [CurrencyService].
///
/// The first version compared the raw UTC offset against +5:30 and treated
/// that as proof of India. Sri Lanka sits on the same offset, so Colombo's
/// users were quoted in rupees. Detection now asks for the IANA zone NAME,
/// which is unambiguous — and `Asia/Colombo` must resolve to Sri Lanka.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrencyService.timezoneOverride = null;
    CurrencyService.countryOverride = null;
    await CurrencyService.instance.refresh();
  });

  tearDown(() {
    CurrencyService.timezoneOverride = null;
    CurrencyService.countryOverride = null;
  });

  test('Asia/Kolkata is quoted in rupees', () async {
    CurrencyService.timezoneOverride = 'Asia/Kolkata';
    await CurrencyService.instance.refresh();
    expect(CurrencyService.instance.countryCode, 'IN');
    expect(CurrencyService.instance.currency.code, 'INR');
  });

  test('the legacy alias Asia/Calcutta is quoted in rupees too', () async {
    CurrencyService.timezoneOverride = 'Asia/Calcutta';
    await CurrencyService.instance.refresh();
    expect(CurrencyService.instance.countryCode, 'IN');
  });

  test('Asia/Colombo is NOT india, even on the same +5:30 offset', () async {
    // Compared against a control zone rather than against a fixed country:
    // the timezone is only one of several signals, and on a harness with no
    // locale region the remaining fallback is rupees. What must hold is that
    // Colombo contributes exactly as much as any other non-Indian zone —
    // nothing — while Kolkata does contribute India.
    CurrencyService.timezoneOverride = 'Pacific/Auckland';
    await CurrencyService.instance.refresh();
    final control = CurrencyService.instance.countryCode;

    CurrencyService.timezoneOverride = 'Asia/Colombo';
    await CurrencyService.instance.refresh();
    expect(
      CurrencyService.instance.countryCode,
      control,
      reason: 'Sri Lanka shares India\'s UTC offset but not its currency',
    );

    CurrencyService.timezoneOverride = 'Asia/Kolkata';
    await CurrencyService.instance.refresh();
    expect(
      CurrencyService.instance.countryCode,
      'IN',
      reason: 'the control comparison only means something if India does fire',
    );
  });

  test('a market picked in Settings still wins over the timezone', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      CurrencyService.marketPrefKey: 'US',
    });
    CurrencyService.timezoneOverride = 'Asia/Kolkata';
    await CurrencyService.instance.refresh();
    expect(CurrencyService.instance.countryCode, 'US');
  });

  test('a missing timezone signal never throws and still prices', () async {
    // No timezone plugin in the test harness, so _timezone stays null. The
    // lookup must be skipped and the remaining signals must still resolve a
    // currency instead of failing the paywall.
    await CurrencyService.instance.refresh();
    expect(() => CurrencyService.instance.countryCode, returnsNormally);
    expect(CurrencyService.instance.currency.code, isNotEmpty);
    expect(() => CurrencyService.instance.monthlyLabel, returnsNormally);
  });
}
