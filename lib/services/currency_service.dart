import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One currency, and the reference rate used to re-label an INR price in it.
@immutable
class Currency {
  /// ISO 4217 code, e.g. `INR`, `USD`.
  final String code;

  /// The glyph shown before the amount, e.g. `$`, `₹`, `kr`.
  final String symbol;

  /// How many INR one unit of this currency is worth. The rate table below is
  /// a static reference table, not a live feed — see [CurrencyService].
  final double inrPerUnit;

  /// Fraction digits to show. Yen, won, dong and rupiah have no minor unit.
  final int decimals;

  /// Some currencies read "11 kr" rather than "kr11".
  final bool spaceAfterSymbol;

  const Currency({
    required this.code,
    required this.symbol,
    required this.inrPerUnit,
    this.decimals = 2,
    this.spaceAfterSymbol = false,
  });

  bool get isInr => code == 'INR';
}

/// Shows the Pro price in the currency of the user's own country.
///
/// **What this changes — and what it does not.** The amount charged never
/// moves: Razorpay bills this merchant in INR, so Pro costs ₹49 a month (₹1
/// for the intro month) for every buyer and the bank converts it. What changes
/// here is the *label*. A buyer in the US reads "$0.56 / month" instead of
/// "₹49 / month", which is what their card statement will show — the paywall
/// then states the INR amount alongside it, so nobody is surprised by the
/// charge that lands.
///
/// The rates are a static reference table, so the converted figure is a
/// close approximation rather than a quote; being roughly right beats showing
/// a rupee sign to someone who has never held a rupee.
///
/// The country comes from the device locale, with one correction: a phone
/// number from India wins, because an Indian account using an `en_US` locale
/// (very common) must still be quoted in rupees.
class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  /// Pro's monthly price in INR — the ONE amount Razorpay charges.
  static const double proMonthlyInr = 49;

  /// The intro month in INR (once per account).
  static const double introMonthInr = 1;

  /// Test seam: force a country code instead of reading the device locale.
  /// Set to null again to go back to real detection.
  @visibleForTesting
  static String? countryOverride;

  /// Used when the locale carries no region and the account is not Indian.
  /// Every price in the app was quoted in rupees before this service existed,
  /// so that stays the floor rather than inventing dollars for an unknown
  /// user.
  static const String defaultCountry = 'IN';

  /// Reference rates: INR per one unit of the currency. Update the table when
  /// the rates drift far enough that the label stops being a fair warning.
  static const Map<String, Currency> _currencies = {
    'INR': Currency(code: 'INR', symbol: '\u20B9', inrPerUnit: 1),
    'USD': Currency(code: 'USD', symbol: r'$', inrPerUnit: 88.0),
    'EUR': Currency(code: 'EUR', symbol: '\u20AC', inrPerUnit: 95.0),
    'GBP': Currency(code: 'GBP', symbol: '\u00A3', inrPerUnit: 111.0),
    'CHF': Currency(code: 'CHF', symbol: 'CHF ', inrPerUnit: 100.0),
    'AUD': Currency(code: 'AUD', symbol: r'A$', inrPerUnit: 58.0),
    'CAD': Currency(code: 'CAD', symbol: r'C$', inrPerUnit: 64.0),
    'NZD': Currency(code: 'NZD', symbol: r'NZ$', inrPerUnit: 53.0),
    'SGD': Currency(code: 'SGD', symbol: r'S$', inrPerUnit: 65.0),
    'HKD': Currency(code: 'HKD', symbol: r'HK$', inrPerUnit: 11.3),
    'MYR': Currency(code: 'MYR', symbol: 'RM', inrPerUnit: 20.0),
    'THB': Currency(code: 'THB', symbol: '\u0E3F', inrPerUnit: 2.45),
    'IDR': Currency(code: 'IDR', symbol: 'Rp', inrPerUnit: 0.0055, decimals: 0),
    'PHP': Currency(code: 'PHP', symbol: '\u20B1', inrPerUnit: 1.55),
    'VND': Currency(
      code: 'VND',
      symbol: '\u20AB',
      inrPerUnit: 0.0034,
      decimals: 0,
      spaceAfterSymbol: true,
    ),
    'CNY': Currency(code: 'CNY', symbol: '\u00A5', inrPerUnit: 12.2),
    'JPY': Currency(
      code: 'JPY',
      symbol: '\u00A5',
      inrPerUnit: 0.57,
      decimals: 0,
    ),
    'KRW': Currency(
      code: 'KRW',
      symbol: '\u20A9',
      inrPerUnit: 0.064,
      decimals: 0,
    ),
    'TWD': Currency(code: 'TWD', symbol: r'NT$', inrPerUnit: 2.75, decimals: 0),
    'AED': Currency(code: 'AED', symbol: 'AED ', inrPerUnit: 24.0),
    'SAR': Currency(code: 'SAR', symbol: 'SAR ', inrPerUnit: 23.5),
    'QAR': Currency(code: 'QAR', symbol: 'QAR ', inrPerUnit: 24.2),
    'KWD': Currency(code: 'KWD', symbol: 'KWD ', inrPerUnit: 287.0),
    'BHD': Currency(code: 'BHD', symbol: 'BHD ', inrPerUnit: 233.0),
    'OMR': Currency(code: 'OMR', symbol: 'OMR ', inrPerUnit: 229.0),
    'ILS': Currency(code: 'ILS', symbol: '\u20AA', inrPerUnit: 24.0),
    'TRY': Currency(code: 'TRY', symbol: '\u20BA', inrPerUnit: 2.1),
    'RUB': Currency(code: 'RUB', symbol: '\u20BD', inrPerUnit: 1.0),
    'UAH': Currency(code: 'UAH', symbol: '\u20B4', inrPerUnit: 2.1),
    'ZAR': Currency(code: 'ZAR', symbol: 'R', inrPerUnit: 4.8),
    'NGN': Currency(code: 'NGN', symbol: '\u20A6', inrPerUnit: 0.055),
    'KES': Currency(code: 'KES', symbol: 'KSh', inrPerUnit: 0.68),
    'GHS': Currency(code: 'GHS', symbol: 'GH\u20B5', inrPerUnit: 6.0),
    'EGP': Currency(code: 'EGP', symbol: 'E\u00A3', inrPerUnit: 1.8),
    'MAD': Currency(code: 'MAD', symbol: 'MAD ', inrPerUnit: 9.0),
    'TND': Currency(code: 'TND', symbol: 'TND ', inrPerUnit: 28.0),
    'BDT': Currency(code: 'BDT', symbol: '\u09F3', inrPerUnit: 0.73),
    'PKR': Currency(code: 'PKR', symbol: 'Rs ', inrPerUnit: 0.31),
    'LKR': Currency(code: 'LKR', symbol: 'Rs ', inrPerUnit: 0.30),
    'NPR': Currency(code: 'NPR', symbol: 'Rs ', inrPerUnit: 0.63),
    'MXN': Currency(code: 'MXN', symbol: r'MX$', inrPerUnit: 4.4),
    'BRL': Currency(code: 'BRL', symbol: r'R$', inrPerUnit: 15.5),
    'ARS': Currency(code: 'ARS', symbol: r'AR$', inrPerUnit: 0.06),
    'CLP': Currency(
      code: 'CLP',
      symbol: r'CLP$',
      inrPerUnit: 0.092,
      decimals: 0,
    ),
    'COP': Currency(
      code: 'COP',
      symbol: r'COL$',
      inrPerUnit: 0.022,
      decimals: 0,
    ),
    'PEN': Currency(code: 'PEN', symbol: 'S/', inrPerUnit: 23.5),
    'SEK': Currency(
      code: 'SEK',
      symbol: 'kr',
      inrPerUnit: 8.6,
      spaceAfterSymbol: true,
    ),
    'NOK': Currency(
      code: 'NOK',
      symbol: 'kr',
      inrPerUnit: 8.3,
      spaceAfterSymbol: true,
    ),
    'DKK': Currency(
      code: 'DKK',
      symbol: 'kr',
      inrPerUnit: 12.7,
      spaceAfterSymbol: true,
    ),
    'PLN': Currency(code: 'PLN', symbol: 'z\u0142', inrPerUnit: 22.0),
    'CZK': Currency(code: 'CZK', symbol: 'K\u010D', inrPerUnit: 3.9),
    'HUF': Currency(
      code: 'HUF',
      symbol: 'Ft',
      inrPerUnit: 0.24,
      decimals: 0,
      spaceAfterSymbol: true,
    ),
    'RON': Currency(
      code: 'RON',
      symbol: 'lei',
      inrPerUnit: 19.0,
      spaceAfterSymbol: true,
    ),
    'BGN': Currency(
      code: 'BGN',
      symbol: 'лв',
      inrPerUnit: 48.5,
      spaceAfterSymbol: true,
    ),
    'HRK': Currency(
      code: 'HRK',
      symbol: 'kn',
      inrPerUnit: 12.6,
      spaceAfterSymbol: true,
    ),
    'RSD': Currency(
      code: 'RSD',
      symbol: 'din',
      inrPerUnit: 0.81,
      decimals: 0,
      spaceAfterSymbol: true,
    ),
  };

  /// Which currency each country uses. Only the countries that differ from
  /// [defaultCountry] need an entry.
  static const Map<String, String> _countryToCode = {
    'IN': 'INR',
    'US': 'USD',
    'CA': 'CAD',
    'MX': 'MXN',
    'BR': 'BRL',
    'AR': 'ARS',
    'CL': 'CLP',
    'CO': 'COP',
    'PE': 'PEN',
    'GB': 'GBP',
    'IE': 'EUR',
    'DE': 'EUR',
    'FR': 'EUR',
    'ES': 'EUR',
    'IT': 'EUR',
    'PT': 'EUR',
    'NL': 'EUR',
    'BE': 'EUR',
    'AT': 'EUR',
    'FI': 'EUR',
    'GR': 'EUR',
    'SK': 'EUR',
    'SI': 'EUR',
    'LT': 'EUR',
    'LV': 'EUR',
    'EE': 'EUR',
    'LU': 'EUR',
    'MT': 'EUR',
    'CY': 'EUR',
    'CH': 'CHF',
    'SE': 'SEK',
    'NO': 'NOK',
    'DK': 'DKK',
    'PL': 'PLN',
    'CZ': 'CZK',
    'HU': 'HUF',
    'RO': 'RON',
    'BG': 'BGN',
    'HR': 'HRK',
    'RS': 'RSD',
    'RU': 'RUB',
    'UA': 'UAH',
    'TR': 'TRY',
    'IL': 'ILS',
    'AE': 'AED',
    'SA': 'SAR',
    'QA': 'QAR',
    'KW': 'KWD',
    'BH': 'BHD',
    'OM': 'OMR',
    'EG': 'EGP',
    'MA': 'MAD',
    'TN': 'TND',
    'ZA': 'ZAR',
    'NG': 'NGN',
    'KE': 'KES',
    'GH': 'GHS',
    'AU': 'AUD',
    'NZ': 'NZD',
    'SG': 'SGD',
    'MY': 'MYR',
    'TH': 'THB',
    'ID': 'IDR',
    'PH': 'PHP',
    'VN': 'VND',
    'CN': 'CNY',
    'JP': 'JPY',
    'KR': 'KRW',
    'TW': 'TWD',
    'HK': 'HKD',
    'BD': 'BDT',
    'PK': 'PKR',
    'LK': 'LKR',
    'NP': 'NPR',
  };

  /// The signed-in account's phone, cached so the many synchronous price
  /// labels on the paywall do not each hit SharedPreferences. Null until
  /// [refresh] has run, or for a guest.
  String? _phone;

  /// Call once at startup (before the first paywall can open) so an Indian
  /// account with an `en_US` locale is quoted in rupees.
  Future<void> refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _phone = prefs.getString('phone');
    } catch (_) {
      // No prefs (or a test harness without a binding) — locale still resolves.
    }
  }

  /// The country the price should be quoted in.
  String get countryCode {
    final override = countryOverride;
    if (override != null && override.isNotEmpty) return override.toUpperCase();
    // An Indian number is the strongest signal we have: this is an Indian
    // account whatever the phone's locale happens to be set to.
    final phone = _phone;
    if (phone != null && _looksIndian(phone)) return 'IN';
    return _deviceCountry() ?? defaultCountry;
  }

  /// The currency for [countryCode].
  Currency get currency => _currencies[_countryToCode[countryCode]] ?? inr;

  static final Currency inr = _currencies['INR']!;

  /// True when this price is shown in something other than rupees, i.e. when
  /// the paywall has to say which currency is actually charged.
  bool get isLocalised => !currency.isInr;

  /// The India-specific calling code, in the forms the sign-in flow stores.
  static bool _looksIndian(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return digits.isNotEmpty;
    if (digits.startsWith('91')) return true;
    return phone.startsWith('+91');
  }

  /// The device's region, from the primary locale or the first preferred one
  /// that carries one.
  static String? _deviceCountry() {
    try {
      final locale = PlatformDispatcher.instance.locale;
      final primary = locale.countryCode;
      if (primary != null && primary.isNotEmpty) return primary.toUpperCase();
      for (final l in PlatformDispatcher.instance.locales) {
        final code = l.countryCode;
        if (code != null && code.isNotEmpty) return code.toUpperCase();
      }
    } catch (_) {
      // No platform dispatcher (a pure Dart test) — fall through.
    }
    return null;
  }

  /// The amount alone, without the symbol — for the paywall's large price,
  /// which draws the symbol and the number as separate stacked type.
  String amount(double inrAmount) {
    final c = currency;
    if (c.isInr) {
      // Whole rupees read better without a trailing .00, and every price this
      // app sells is a whole number of rupees.
      final rounded = inrAmount.round();
      return rounded == inrAmount ? '$rounded' : inrAmount.toStringAsFixed(2);
    }
    final value = inrAmount / c.inrPerUnit;
    var text = value.toStringAsFixed(c.decimals);
    // A heavy conversion (₫, Rp) must never round down to a free-looking 0.
    if (c.decimals == 0) {
      final n = int.tryParse(text) ?? 0;
      if (n < 1) text = '1';
    } else if (double.tryParse(text) == 0) {
      text = '0.01';
    }
    return text;
  }

  /// [inrAmount] in the local currency. `₹49` → `₹49`, `$0.56`, `86 ¥`,
  /// `Rp 8,909`.
  String format(double inrAmount) {
    final c = currency;
    final text = amount(inrAmount);
    return c.spaceAfterSymbol ? '$text ${c.symbol}' : '${c.symbol}$text';
  }

  /// The monthly Pro price, e.g. `₹49` or `$0.56`.
  String get monthlyLabel => format(proMonthlyInr);

  /// The ₹1 intro month in local currency.
  String get introLabel => format(introMonthInr);

  /// The line the paywall shows when the price has been converted, so the
  /// user knows which currency their bank will actually settle in.
  /// Null when the price is already in rupees.
  String? get chargeNote => isLocalised
      ? 'Billed as \u20B9${proMonthlyInr.round()} INR \u2014 shown above in '
            'your local currency at an approximate rate.'
      : null;
}
