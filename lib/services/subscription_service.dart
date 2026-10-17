import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_identity.dart';
import 'meal_store.dart';
import 'gemini_service.dart';
import 'sync_status_service.dart';

/// Central reactive store for the Pro subscription flag.
///
/// Replaces ad-hoc `prefs.getBool('subscribed')` reads scattered across
/// screens and services. Screens read [isSubscribed] / [subscribedAt] and can
/// listen for changes so an activation (Razorpay, UPI verification, server
/// poll) immediately updates every open screen.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const String _subscribedKey = 'subscribed';
  static const String _subscribedAtKey = 'subscribed_at';
  static const String _trialEndsAtKey = 'trial_ends_at';

  /// ISO end date of a server-granted Pro window (referral reward).
  /// Display-only: the server decides, this only mirrors the date it reported.
  static const String _proUntilKey = 'pro_until';

  /// The owner account — always gets Pro for free, forever.
  static const String adminEmail = 'prabhasaaho213@gmail.com';

  bool _subscribed = false;
  bool _paid = false;
  String? _subscribedAt;
  String? _proUntil;
  DateTime? _trialEndsAt;

  /// True while the account is inside its one-time 30-day free plan and has
  /// not paid. [trialDaysLeft] counts down from the server-issued end date,
  /// which is persisted so the countdown survives restarts and works offline.
  bool get isPaid => _paid;
  bool get trialActive =>
      !_paid && _trialEndsAt != null && DateTime.now().isBefore(_trialEndsAt!);
  int get trialDaysLeft {
    final end = _trialEndsAt;
    if (end == null || _paid) return 0;
    final left = end.difference(DateTime.now()).inDays + 1;
    return left < 1 ? 0 : left;
  }

  bool get isSubscribed => _subscribed;
  String? get subscribedAt => _subscribedAt;

  /// ISO end date of the current Pro window (referral reward), as last
  /// reported by the server. Null for plain paid Pro (no end date).
  String? get proUntil => _proUntil;

  /// True when the currently signed-in email is the owner/admin account.
  /// The admin gets a permanent, free Pro subscription.
  Future<bool> isAdmin() async {
    final p = await SharedPreferences.getInstance();
    final email = (p.getString('email') ?? '').trim().toLowerCase();
    return email == adminEmail.toLowerCase();
  }

  /// Loads the persisted flag. Called once at app startup, but safe to call
  /// again — re-reads prefs and only notifies when the value changed.
  ///
  /// Admin override: the owner's email always yields Pro for free, forever.
  /// Non-admin guard: a persisted lifetime grant (the `1900` marker) must
  /// never transfer to another user who signs in on the same device, so it is
  /// cleared when the current user isn't the admin.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    var subscribed = p.getBool(_subscribedKey) ?? false;
    var at = p.getString(_subscribedAtKey);
    final subscribedNow = subscribed;

    if (await isAdmin()) {
      // Owner: force lifetime Pro, regardless of any previous paid state.
      if (at != _lifetimeDate) {
        await _grantLifetimeAdmin();
      }
      subscribed = true;
      at = _lifetimeDate;
    } else if (at == _lifetimeDate) {
      // A non-owner signed in on a device where the owner granted lifetime
      // Pro — strip the grant so it doesn't leak to them.
      await p.remove(_subscribedAtKey);
      await p.setBool(_subscribedKey, false);
      subscribed = false;
      at = null;
    }

    // ── One-time 30-day free plan ──────────────────────────
    // An unexpired trial counts as Pro everywhere. The server-issued end
    // date is persisted so the countdown survives restarts and works
    // offline; an expired marker is cleared here and never re-granted (the
    // backend owns the one-time grant).
    DateTime? trialEnd;
    final trialRaw = p.getString(_trialEndsAtKey);
    if (!subscribedNow && trialRaw != null) {
      trialEnd = DateTime.tryParse(trialRaw);
      if (trialEnd == null || !DateTime.now().isBefore(trialEnd)) {
        await p.remove(_trialEndsAtKey);
        trialEnd = null;
      }
    }
    final paid = subscribedNow;
    if (!subscribedNow && trialEnd != null) subscribed = true;
    final until = p.getString(_proUntilKey);

    if (subscribed != _subscribed ||
        at != _subscribedAt ||
        paid != _paid ||
        until != _proUntil ||
        trialEnd != _trialEndsAt) {
      _subscribed = subscribed;
      _subscribedAt = at;
      _paid = paid;
      _proUntil = until;
      _trialEndsAt = trialEnd;
      notifyListeners();
    }
  }

  /// Marker timestamp shown for the admin's lifetime subscription.
  static final String _lifetimeDate = '1900-01-01T00:00:00.000';

  Future<void> _grantLifetimeAdmin() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_subscribedKey, true);
    await p.setString(_subscribedAtKey, _lifetimeDate);
    _subscribed = true;
    _subscribedAt = _lifetimeDate;
    notifyListeners();
    try {
      MealStore.instance.changeNotifier.value++;
    } catch (e) { debugPrint("Error: $e"); }
  }

  /// Asks the backend for this account's one-time 30-day free plan. The
  /// backend grants it on the first ever check and computes expiry — the
  /// app only mirrors the server-issued end date. Offline, the persisted
  /// date keeps the countdown honest and never re-grants anything.
  Future<void> _verifyTrial() async {
    // Paying users don't need it. Trial-derived Pro does NOT skip this
    // check: the server must get the last word, or a stale local marker
    // (another account on this device, or an account deleted elsewhere)
    // would keep showing Pro after the backend refused to re-grant it.
    if (_paid) return;
    final p = await SharedPreferences.getInstance();
    final phone = p.getString('phone') ?? '';
    final email = p.getString('email') ?? '';
    if (phone.isEmpty && email.isEmpty) return; // guest — no identity
    try {
      // Identity comes from the token — no identifier goes in the URL.
      final uri = Uri.parse('${GeminiService.serverUrl}/trial/status');
      final res = await AuthHttp.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['active'] == true && data['endsAt'] is String) {
        final end = DateTime.tryParse(data['endsAt'] as String);
        if (end != null) {
          await p.setString(_trialEndsAtKey, end.toIso8601String());
          if (_trialEndsAt != end || !_subscribed) {
            _trialEndsAt = end;
            _subscribed = true;
            notifyListeners();
          }
        }
      } else if (data['expired'] == true || data['active'] == false) {
        // expired      -> the countdown finished.
        // active:false -> the server has NO trial for this identity — it
        //   never claimed one, or its account was deleted and the backend
        //   refused to re-grant it (deletion tombstone). Either way, drop
        //   the stale local marker so it can never show Pro again.
        await p.remove(_trialEndsAtKey);
        if (_trialEndsAt != null) {
          _trialEndsAt = null;
          notifyListeners();
        }
      }
    } catch (_) {
      // Offline or server unreachable — the persisted trial state stands.
    }
  }

  /// Verifies the paid subscription from **Firestore** — the source of truth
  /// for payments and subscription state after the Phase-3 migration.
  ///
  /// Reads `users/{uid}.subscribed` (written by the backend's Razorpay
  /// webhook/verify via the Admin SDK). Falls back to the legacy
  /// `/subscription/status` backend call when Firestore has no user doc yet
  /// (Phase-1/2 backfill not caught up) or when Firestore is unreachable.
  ///
  /// Called at app startup and after sign-in so a paying user who reinstalls
  /// or switches devices gets Pro restored without opening the subscription
  /// screen. A network failure never deactivates — but a SUCCESSFUL
  /// `subscribed: false` answer with no active trial is authoritative and
  /// clears the saved Pro flag, so a cancelled subscription or an expired
  /// referral window stops showing the Pro look right away.
  Future<void> verifyServerSubscription() async {
    // The admin's lifetime Pro is local-only; don't override it.
    if (await isAdmin()) return;

    // One-time 30-day free plan: checked at startup AND after every login,
    // which is how existing users receive theirs right after updating.
    await _verifyTrial();

    // ── Firestore first: users/{uid}.subscribed ────────────────────────
    try {
      final uid = await FirebaseIdentity.currentUid();
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 8));
        if (doc.exists) {
          final subscribed = doc.data()?['subscribed'] == true;
          if (subscribed && !_subscribed) {
            // Activation from Firestore is authoritative.
            await activate();
            return;
          }
          // `subscribed == false` is NOT authoritative during the migration
          // window (a Firestore doc can be stale while Postgres says paid) —
          // fall through to the backend check below to confirm.
        }
      }
    } catch (_) {
      // Firestore unavailable — fall through to the backend check.
    }

    // ── Backend fallback: Postgres /subscription/status ─────────────────
    final p = await SharedPreferences.getInstance();
    final email = p.getString('email');
    final phone = p.getString('phone');
    if ((email == null || email.isEmpty) &&
        (phone == null || phone.isEmpty)) {
      return; // Guest — nothing to verify.
    }
    try {
      final uri = Uri.parse('${GeminiService.serverUrl}/subscription/status');
      final res = await AuthHttp.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['subscribed'] == true) {
        // Remember the end date of a server-granted window (referral
        // reward) so Settings can show when Pro ends; null clears a
        // stale one.
        final until = data['pro_until'] is String
            ? data['pro_until'] as String
            : null;
        if (until != null) {
          await p.setString(_proUntilKey, until);
        } else {
          await p.remove(_proUntilKey);
        }
        final proUntilChanged = _proUntil != until;
        _proUntil = until;
        if (!_subscribed) {
          await activate();
        } else if (proUntilChanged) {
          notifyListeners();
        }
      } else if (!trialActive) {
        // The server answered SUCCESSFULLY: this account is free and has
        // no active trial (cancelled subscription, expired referral
        // window). Non-200 answers return earlier and network errors land
        // in the catch below, so a bad connection never downgrades anyone.
        await _deactivate();
      }
    } catch (_) {
      // Offline or server unreachable — keep the local state as-is, but
      // surface the dead backend so the user isn't silently cut off from
      // cloud features (same signal the meal/habit sync uses).
      SyncStatusService.instance.reportFailure('Subscription check failed');
    }
  }

  /// Activates Pro: persists the flag + timestamp, runs the post-activation
  /// side effects (pro reminder notifications + refresh of the meal-store
  /// change notifier so scan counts update), and notifies listeners.
  ///
  /// Centralizing the side effects here removes the duplication that used to
  /// live in both [RazorpayService] and the subscription screen.
  Future<void> activate() async {
    final now = DateTime.now().toIso8601String();
    final p = await SharedPreferences.getInstance();
    await p.setString(_subscribedAtKey, now);
    await p.setBool(_subscribedKey, true);
    _subscribed = true;
    _subscribedAt = now;
    notifyListeners();

    // ── Post-activation side effect (best-effort, never throw) ──
    // Refresh scan counts. Reminder scheduling is NOT here —
    // NotificationService listens to this notifier and applies the plan on
    // every state change.
    try {
      MealStore.instance.changeNotifier.value++;
    } catch (e) { debugPrint("Error: $e"); }
  }

  /// Clears the locally saved Pro flag after the server has AUTHORITATIVELY
  /// said the account is free (cancelled subscription, expired referral
  /// window). Only reached from a successful 200 /subscription/status
  /// answer — network failures keep the local state untouched.
  Future<void> _deactivate() async {
    if (!_subscribed && _proUntil == null) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_subscribedKey);
    await p.remove(_subscribedAtKey);
    await p.remove(_proUntilKey);
    _subscribed = false;
    _paid = false;
    _subscribedAt = null;
    _proUntil = null;
    notifyListeners();

    // Same side effect as activate(): scan counts and the Pro-only
    // notification plan must refresh down to the free tier.
    try {
      MealStore.instance.changeNotifier.value++;
    } catch (e) { debugPrint("Error: $e"); }
  }

}
