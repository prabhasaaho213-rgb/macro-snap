import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'auth_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crash_reporting.dart';
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

  // Was the free-trial end marker; the trial no longer exists, so the key
  // is only ever REMOVED below — never read or written again.
  static const String _trialEndsAtKey = 'trial_ends_at';

  /// ISO end date of a server-granted Pro window (referral reward).
  /// Display-only: the server decides, this only mirrors the date it reported.
  static const String _proUntilKey = 'pro_until';

  /// Test seam: replaces the Firebase token lookup so the admin path can be
  /// exercised without a signed-in Firebase session (the test harness has no
  /// Firebase app). Never set in production code.
  @visibleForTesting
  static Future<bool> Function()? adminCheckOverride;

  bool _subscribed = false;
  bool _paid = false;
  String? _subscribedAt;
  String? _proUntil;

  /// True while the account paid through Razorpay (or the referral/admin
  /// grants it). The old 30-day free trial no longer exists — the first
  /// month costs ₹1 (collected as an upfront addon) and the ₹49 autopay
  /// starts 30 days later via Razorpay's `start_at`, which the server treats
  /// as an ordinary subscription.
  bool get isPaid => _paid;

  /// True while this account is Pro *right now*.
  ///
  /// This is read on every screen build, so it evaluates the stored dates
  /// itself instead of trusting the flag computed in [load]. A referral
  /// window that ends while the app is open used to keep showing Pro until
  /// the next restart.
  bool get isSubscribed => isSubscribedAt(DateTime.now());

  /// [now] is injectable so the expiry rules can be tested without waiting for
  /// a month to pass.
  bool isSubscribedAt(DateTime now) {
    if (!_subscribed) return false;
    // The admin's lifetime grant has no end date.
    if (_subscribedAt == _lifetimeDate) return true;
    if (_paid) return true;
    final until = _proUntil == null ? null : DateTime.tryParse(_proUntil!);
    if (until != null && !now.isBefore(until)) return false;
    return true;
  }

  String? get subscribedAt => _subscribedAt;

  /// ISO end date of the current Pro window (referral reward), as last
  /// reported by the server. Null for plain paid Pro (no end date).
  String? get proUntil => _proUntil;

  StreamSubscription<User?>? _authSub;

  /// True when the signed-in account carries the `admin` custom claim. The
  /// admin gets a permanent, free Pro subscription.
  ///
  /// This used to compare a locally stored email against a hardcoded constant.
  /// That put the trust in the client: the address lives in SharedPreferences,
  /// so a rooted device (or a one-line edit) granted free Pro, and the owner's
  /// personal address shipped inside the app. The privilege is now a Firebase
  /// custom claim set by the backend with the Admin SDK — the same claim
  /// `firestore.rules` checks, so the client cannot mint it.
  /// True once this process has read the claim from a FRESH token.
  ///
  /// An ID token is cached for up to an hour, and the backend mints the claim
  /// on its first request — so reading the cache meant the owner sat on the
  /// free tier until the token happened to turn over, or until they signed out
  /// and back in. One forced refresh per process is enough to pick the claim
  /// up on the next launch.
  bool _claimsRefreshed = false;

  Future<bool> isAdmin() async {
    final override = adminCheckOverride;
    if (override != null) return override();
    // No Firebase app at all (unit tests, or a build without Firebase): there
    // is no claim to read, and this is not an error worth reporting.
    if (Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final fresh = !_claimsRefreshed;
    try {
      final token = await user.getIdTokenResult(fresh);
      _claimsRefreshed = true;
      return token.claims?['admin'] == true;
    } catch (e, st) {
      // A failed refresh (offline, or the app just launched) must not cost the
      // owner their Pro: fall back to whatever the cached token says.
      if (fresh) {
        try {
          final cached = await user.getIdTokenResult(false);
          _claimsRefreshed = true;
          return cached.claims?['admin'] == true;
        } catch (e2, st2) {
          logError('SubscriptionService.isAdmin(cached)', e2, st2);
        }
      } else {
        logError('SubscriptionService.isAdmin', e, st);
      }
      return false; // fail closed: no claim, no privilege
    }
  }

  /// Whether we already know who is signed in.
  ///
  /// Firebase restores the session asynchronously, so [load] can run before
  /// `currentUser` exists. Stripping the lifetime marker at that moment would
  /// punish the admin for being first, so the strip waits for an identity.
  Future<bool> _identityKnown() async {
    try {
      if (FirebaseAuth.instance.currentUser != null) return true;
    } catch (e, st) {
      logError('SubscriptionService._identityKnown', e, st);
    }
    final p = await SharedPreferences.getInstance();
    return (p.getString('email') ?? '').isNotEmpty ||
        (p.getString('phone') ?? '').isNotEmpty;
  }

  /// Re-checks the admin claim whenever the signed-in account changes.
  ///
  /// Without this, [load] (which runs before Firebase restores the session)
  /// would never see the claim, and the admin would sit on the free tier until
  /// the next cold start. It also re-evaluates on sign-out and on a different
  /// account signing in, which is when a leaked lifetime marker must go away.
  void bindAuth() {
    if (_authSub != null) return;
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen(
        (_) {
          // A different account has its own token, so the next read is fresh
          // again — a stale cached claim from the previous user must not be
          // what decides the new one's Pro.
          _claimsRefreshed = false;
          unawaited(refreshAdminState());
        },
        onError: (Object e, StackTrace st) =>
            logError('SubscriptionService.bindAuth', e, st),
      );
    } catch (e, st) {
      // No Firebase app (tests) — nothing to bind to.
      logError('SubscriptionService.bindAuth', e, st);
    }
  }

  /// Applies the current claim: grant lifetime Pro to the admin, otherwise let
  /// [load] strip a marker that no longer belongs to this account.
  Future<void> refreshAdminState() async {
    if (await isAdmin()) {
      await _ensureAdminGrant();
    } else {
      await load();
    }
  }

  /// Idempotent: grants the lifetime marker only when it isn't already set.
  Future<void> _ensureAdminGrant() async {
    final p = await SharedPreferences.getInstance();
    if (_subscribed && p.getString(_subscribedAtKey) == _lifetimeDate) return;
    await _grantLifetimeAdmin();
  }

  /// Loads the persisted flag. Called once at app startup, but safe to call
  /// again — re-reads prefs and only notifies when the value changed.
  ///
  /// Admin override: the owner's `admin` claim always yields Pro, for free,
  /// forever. Non-admin guard: a persisted lifetime grant (the `1900` marker)
  /// must never transfer to another user who signs in on the same device, so
  /// it is cleared once we know the current user is not the admin.
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
    } else if (at == _lifetimeDate && await _identityKnown()) {
      // A non-owner signed in on a device where the owner granted lifetime
      // Pro — strip the grant so it doesn't leak to them.
      await p.remove(_subscribedAtKey);
      await p.setBool(_subscribedKey, false);
      subscribed = false;
      at = null;
    }

    // ── Free trial REMOVED ──────────────────────────
    // A stale trial marker on this device (an old install, or a previous
    // account) must never show Pro. It is dropped on the first load
    // after updating, whether or not the user is subscribed — the server
    // stopped honouring trials too, so nothing ever re-arms it.
    if (p.getString(_trialEndsAtKey) != null) {
      await p.remove(_trialEndsAtKey);
    }
    // A plain Razorpay-paid subscription never expires on its own. A
    // windowed grant (the referral reward's `pro_until`) is NOT "paid": its
    // expiry must apply, otherwise the window's end date would be dead code
    // (isSubscribedAt short-circuits on _paid before checking pro_until).
    final until = p.getString(_proUntilKey);
    final paid = subscribedNow && until == null;

    if (subscribed != _subscribed ||
        at != _subscribedAt ||
        paid != _paid ||
        until != _proUntil) {
      _subscribed = subscribed;
      _subscribedAt = at;
      _paid = paid;
      _proUntil = until;
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
    } catch (e, st) {
      logError('SubscriptionService._grantLifetimeAdmin', e, st);
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
  /// `subscribed: false` answer is authoritative and clears the saved Pro
  /// flag (trials no longer count as Pro — they are gone), so a cancelled
  /// subscription or an expired referral window stops showing the Pro look
  /// right away.
  Future<void> verifyServerSubscription() async {
    // The admin's lifetime Pro is claim-based; don't let the server override it.
    if (await isAdmin()) {
      await _ensureAdminGrant();
      return;
    }


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
          // window (a Firestore doc can be stale while the backend says
          // paid) — fall through to the backend check below to confirm.
        }
      }
    } catch (_) {
      // Firestore unavailable — fall through to the backend check.
    }

    // ── Backend fallback: /subscription/status ──────────────────────────
    // Kept for accounts whose Firestore user doc was never backfilled. The
    // server reads its own database (Firestore + Razorpay), so this is a
    // confirmation call, not a second source of truth.
    final p = await SharedPreferences.getInstance();
    final email = p.getString('email');
    final phone = p.getString('phone');
    if ((email == null || email.isEmpty) && (phone == null || phone.isEmpty)) {
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
      } else {
        // The server answered SUCCESSFULLY: this account is free and has
        // no active Pro at all (cancelled subscription, expired referral
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
    } catch (e, st) {
      logError('SubscriptionService.activate', e, st);
    }
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
    } catch (e, st) {
      logError('SubscriptionService._deactivate', e, st);
    }
  }
}
