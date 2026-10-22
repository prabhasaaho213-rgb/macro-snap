import 'package:shared_preferences/shared_preferences.dart';

/// Local-storage partitioning: one device can hold several Google accounts,
/// so every user-scoped local store (meals, habits, water, diet
/// profile) must key its data by the signed-in account — otherwise the
/// previous account's data shows up in every other account on the phone.
///
/// The partition id is the `phone` prefs value (the signed-in email the app
/// already uses everywhere: set at login, cleared at logout). Guests (no
/// account, or a legacy `guest_*` id) resolve to an empty suffix and keep the
/// legacy unprefixed keys/files, so the guest flow and all pre-existing data
/// keep working unchanged.
class AccountPartition {
  AccountPartition._();

  /// The account id currently active, from prefs. Never throws.
  static String activeFromPrefs(SharedPreferences p) =>
      p.getString('phone') ?? '';

  /// Stable, filesystem-safe suffix for an account id. Empty for guests —
  /// callers then use the legacy key/file.
  static String suffix(String account) {
    final a = account.trim().toLowerCase();
    if (a.isEmpty || a.startsWith('guest_')) return '';
    final buf = StringBuffer();
    for (final unit in a.codeUnits) {
      final isAlnum = (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 122);
      buf.writeCharCode(isAlnum ? unit : 95); // '_'
    }
    return buf.toString();
  }

  /// Partition-scoped prefs key / file base for [base]. Guests use [base]
  /// verbatim; signed-in accounts use `{base}_{suffix}`.
  static String key(String base, String suffix) =>
      suffix.isEmpty ? base : '${base}_$suffix';
}
