import 'package:shared_preferences/shared_preferences.dart';

/// Local-storage partitioning: one device can hold several accounts, so every
/// user-scoped local store (meals, habits, water, diet profile) must key its
/// data by the signed-in account — otherwise the previous account's data shows
/// up in every other account on the phone.
///
/// The partition id is the `phone` prefs value (the signed-in email the app
/// already uses everywhere: set at login, cleared at logout). A signed-out
/// device (no id, or a `guest_*` id) resolves to an empty suffix and keeps the
/// legacy unprefixed keys/files, so pre-login data and every existing install
/// keep working unchanged.
class AccountPartition {
  AccountPartition._();

  /// Length of the disambiguating hash appended to the sanitised id.
  static const int hashLength = 6;

  /// The account id currently active, from prefs. Never throws.
  static String activeFromPrefs(SharedPreferences p) =>
      p.getString('phone') ?? '';

  /// The filesystem/prefs-safe body of an id: lowercase, alphanumerics kept,
  /// everything else collapsed to `_`.
  static String _sanitised(String lowercased) {
    final buf = StringBuffer();
    for (final unit in lowercased.codeUnits) {
      final isAlnum = (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 122);
      buf.writeCharCode(isAlnum ? unit : 95); // '_'
    }
    return buf.toString();
  }

  /// A short, stable hash of the raw account id (FNV-1a, base36).
  ///
  /// The sanitised form alone is NOT unique: `a.b@x.com` and `a_b@x.com` both
  /// collapse to `a_b_x_com`, so two different accounts on one device shared a
  /// single local partition — each could read the other's meals and habits.
  /// Two characters of the raw string that sanitising erases are enough to
  /// make the collision impossible in practice, and the hash is deterministic
  /// so the same account always lands in the same partition.
  static String _hash(String raw) {
    var hash = 0x811c9dc5;
    for (final unit in raw.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    final buf = StringBuffer();
    var value = hash;
    for (var i = 0; i < hashLength; i++) {
      buf.write(alphabet[value % alphabet.length]);
      value ~/= alphabet.length;
    }
    return buf.toString();
  }

  /// Stable, filesystem-safe suffix for an account id. Empty for guests —
  /// callers then use the legacy key/file.
  static String suffix(String account) {
    final a = account.trim().toLowerCase();
    if (a.isEmpty || a.startsWith('guest_')) return '';
    return '${_sanitised(a)}_${_hash(a)}';
  }

  /// The suffix this build used BEFORE the collision fix (sanitised only).
  ///
  /// Only used by [ensureCurrent] to move an existing install's data onto the
  /// current scheme — never for new writes.
  static String legacySuffix(String account) {
    final a = account.trim().toLowerCase();
    if (a.isEmpty || a.startsWith('guest_')) return '';
    return _sanitised(a);
  }

  /// Partition-scoped prefs key / file base for [base]. Guests use [base]
  /// verbatim; signed-in accounts use `{base}_{suffix}`.
  static String key(String base, String suffix) =>
      suffix.isEmpty ? base : '${base}_$suffix';

  /// Base names of every local store that is keyed per account.
  ///
  /// Prefs keys use `AccountPartition.key(base, suffix)` and the meal store
  /// uses `<base>.json`, so this one list covers both. A new per-account store
  /// must add its base here or account deletion will leave it behind.
  static const List<String> scopedBases = [
    'meals',
    'diet_profile',
    'habits',
    'water_log',
    'water_goal',
    'badges',
    'weight_log',
    'recent_foods',
    'guru_chat',
    'pending_sync',
    'synced_meal_ids',
  ];

  /// Moves the ACTIVE account's local data onto its current suffix.
  ///
  /// Two upgrades need this, and both must preserve data:
  ///
  /// 1. **Collision fix.** Every existing signed-in install has its keys under
  ///    the old sanitised-only suffix. Those are moved to the hashed suffix the
  ///    moment the account is loaded again, so nobody loses their history to a
  ///    scheme change.
  /// 2. **Before sign-in → account.** Onboarding and any pre-login write lands
  ///    on the unprefixed keys (there is no active account yet). When the
  ///    person then signs in, that data becomes their account's.
  ///
  /// Only runs for the active account, and only copies when the destination
  /// does not already exist, so it can never overwrite newer data. Other
  /// accounts' old-suffix keys are left alone and migrate when that account
  /// signs in again — this function has no way to reverse a sanitised suffix
  /// back into an email, and must not guess.
  static Future<void> ensureCurrent(SharedPreferences p) async {
    final account = activeFromPrefs(p);
    final target = suffix(account);
    if (target.isEmpty) return; // Signed out: the legacy keys ARE its partition.

    final legacy = legacySuffix(account);
    if (legacy != target) {
      await _moveKeys(p, from: legacy, to: target);
    }
    // Leftovers from before partitioning existed (or data written before the
    // first sign-in) are the same person's older data.
    await _moveKeys(p, from: '', to: target);
  }

  /// Copies `{base}_{from}` → `{base}_{to}` for every scoped store, then
  /// removes the source only when every value moved.
  static Future<void> _moveKeys(
    SharedPreferences p, {
    required String from,
    required String to,
  }) async {
    if (to.isEmpty || from == to) return;
    final moved = <String>[];
    for (final base in scopedBases) {
      final fromKey = key(base, from);
      final toKey = key(base, to);
      if (fromKey == toKey) continue;
      if (p.containsKey(toKey)) continue; // never overwrite newer data
      final value = p.get(fromKey);
      if (value == null) continue;
      // Re-write through the typed setters: SharedPreferences has no generic
      // set(), and a wrong type would silently corrupt the store.
      if (value is String) {
        await p.setString(toKey, value);
      } else if (value is int) {
        await p.setInt(toKey, value);
      } else if (value is bool) {
        await p.setBool(toKey, value);
      } else if (value is double) {
        await p.setDouble(toKey, value);
      } else if (value is List<String>) {
        await p.setStringList(toKey, value);
      } else {
        continue;
      }
      moved.add(fromKey);
    }
    for (final sourceKey in moved) {
      await p.remove(sourceKey);
    }
  }

  /// Removes ONLY the data belonging to [suffix].
  ///
  /// The account-deletion flow used to call `prefs.clear()`, which wipes the
  /// whole device — including every other account's `habits_<suffix>`,
  /// `water_log_<suffix>` and `badges_<suffix>`. This is the surgical version:
  /// the active account's keys go, every other partition is untouched, and the
  /// guest's unprefixed keys are only removed when the guest is the account
  /// being wiped.
  static Future<void> removeAccountData(
    SharedPreferences prefs, {
    required String suffix,
  }) async {
    for (final prefKey in prefs.getKeys().toList()) {
      for (final base in scopedBases) {
        if (prefKey == key(base, suffix)) {
          await prefs.remove(prefKey);
          break;
        }
      }
    }
  }
}
