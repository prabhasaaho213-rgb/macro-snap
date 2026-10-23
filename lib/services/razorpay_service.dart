import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'auth_http.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gemini_service.dart';
import 'subscription_service.dart';

/// How a purchase attempt ended.
enum PaymentOutcome {
  /// The backend verified the payment and Pro is active.
  success,

  /// The user closed checkout without paying — not an error worth alarming
  /// them with.
  cancelled,

  /// The attempt did not go through.
  failed,

  /// Money may still be on its way: the hosted page was opened, or the bank /
  /// webhook has not confirmed yet. Pro switches on by itself when it does.
  pending,
}

class PaymentResult {
  final PaymentOutcome outcome;
  final String? message;

  const PaymentResult(this.outcome, [this.message]);

  const PaymentResult.success()
    : outcome = PaymentOutcome.success,
      message = null;
  const PaymentResult.cancelled()
    : outcome = PaymentOutcome.cancelled,
      message = null;
  const PaymentResult.pending([this.message])
    : outcome = PaymentOutcome.pending;
  const PaymentResult.failed(this.message) : outcome = PaymentOutcome.failed;
}

class RazorpayService {
  static final Razorpay _razorpay = Razorpay();
  static bool _initialized = false;

  /// The open checkout, if any. `null` means no purchase is in flight, so
  /// late plugin callbacks (a sheet dismissed after the screen was left) are
  /// dropped instead of reviving a stale flow.
  static Completer<PaymentResult>? _pending;

  /// The subscription currently being paid for — needed by the hosted-page
  /// fallback and by the verify call when the SDK omits the id.
  static String? _subscriptionId;

  /// True while a purchase is still being *set up* (server call + sheet open).
  /// A second tap in that window used to create a second Razorpay subscription
  /// for the same user, which is one of the ways a person can be charged twice.
  static bool _starting = false;

  /// Test seams. Both default to the real network calls; tests replace them so
  /// the no-double-charge guards can be exercised without a device or keys.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function({required String name})?
  createSubscriptionForTest;
  @visibleForTesting
  static Future<bool> Function()? refreshStatusForTest;

  /// Initialize Razorpay. Call this once in the app lifecycle.
  static void init() {
    if (_initialized) return;
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _initialized = true;
  }

  /// Clean up listeners when no longer needed.
  static void dispose() {
    if (!_initialized) return;
    _razorpay.clear();
    _initialized = false;
  }

  /// Collects the ₹49/month subscription **inside the app**.
  ///
  /// The backend creates the Razorpay subscription and hands back its id plus
  /// the public key; [Razorpay.open] then slides Razorpay's native checkout
  /// sheet over MacroSnap. The user never leaves the app, the payment happens
  /// in-place, and the result arrives here — success, cancel or failure.
  ///
  /// Previously this opened `api.razorpay.com/v1/l/subscriptions/{id}` in the
  /// system browser, which is why paying looked like being "redirected to
  /// another page": the app was backgrounded mid-purchase and the user had to
  /// find their way back.
  ///
  /// The Flutter SDK has a long-standing bug with recurring plans (error VC,
  /// "INCORRECT RECURRENCE PATTERN RULE" — razorpay/razorpay-flutter#396).
  /// If this device hits it, the flow degrades to the hosted page that is
  /// known to work rather than failing the purchase outright; either way the
  /// caller gets one [PaymentResult].
  static Future<PaymentResult> purchase({required String name}) async {
    // One purchase at a time. Retrying while a checkout is opening, or while
    // the hosted page is still being polled, must never mint a second
    // subscription — that is exactly how a "try again" tap becomes a second
    // charge for the same ₹49.
    if (_starting || _pending != null) {
      return const PaymentResult.pending(
        'A payment is already in progress. Finish it in the window that is '
        'open — Pro switches on by itself once it clears.',
      );
    }
    _starting = true;
    try {
      // Someone who already paid (e.g. a hosted-page payment that cleared
      // after we gave up polling) must not be charged again.
      if (await refreshStatus()) return const PaymentResult.success();

      final created = await _createSubscription(name: name);
      final subscriptionId = created['subscription_id'];
      if (subscriptionId is! String || subscriptionId.isEmpty) {
        return const PaymentResult.failed('Could not start the payment.');
      }
      _subscriptionId = subscriptionId;

      final key = created['razorpay_key'];
      if (key is! String || key.isEmpty) {
        // No publishable key from the server → the native sheet cannot open.
        return _openHostedPage(subscriptionId);
      }

      final pending = Completer<PaymentResult>();
      _pending = pending;
      try {
        _razorpay.open({
          'key': key,
          // Subscriptions are charged from the plan, so no amount/currency
          // here: sending them alongside subscription_id is what triggers the
          // SDK's recurrence-pattern rejection.
          'subscription_id': subscriptionId,
          'name': 'MacroSnap',
          'description': 'MacroSnap Pro · ₹1 first month, then ₹49/month',
          'theme': {'color': '#FF6B2B'},
          'send_sms_hash': true,
          'retry': {'enabled': true, 'max_count': 2},
        });
      } catch (e) {
        // Some SDK versions throw instead of reporting the recurrence bug.
        debugPrint('Razorpay checkout could not open ($e) — using hosted page');
        _pending = null;
        return _openHostedPage(subscriptionId);
      }
      // Safety valve: some SDK builds close the sheet without firing either
      // callback, which would leave the caller's button spinning forever.
      return pending.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          _pending = null;
          _subscriptionId = null;
          return const PaymentResult.pending(
            'No confirmation yet. If money was deducted, Pro switches on by '
            'itself within a few minutes.',
          );
        },
      );
    } finally {
      _starting = false;
    }
  }

  /// Re-asks the backend whether Pro is active yet. Used by the "pending"
  /// screen: a bank confirmation can land seconds after the sheet closes.
  static Future<bool> refreshStatus() async {
    final override = refreshStatusForTest;
    if (override != null) return override();
    try {
      final resp = await AuthHttp.get(
        Uri.parse('${GeminiService.serverUrl}/me/payment/status'),
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      if (data is Map && data['subscribed'] == true) {
        await SubscriptionService.instance.activate();
        return true;
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
    return false;
  }

  /// True when a checkout error is the known recurring-plan SDK bug, i.e. a
  /// reason to fall back to the hosted page instead of telling the user their
  /// payment failed. Kept public so the mapping is testable without a device.
  static bool looksLikeRecurrenceBug(String message) {
    final m = message.toLowerCase();
    return m.contains('recurrence') ||
        m.contains('recurring') ||
        m.contains('incorrect pattern');
  }

  // ─── Backend ───────────────────────────────────────────────────────────

  /// Creates the recurring subscription for the token's user. Identity
  /// (phone/email) is resolved server-side — only the display name travels.
  static Future<Map<String, dynamic>> _createSubscription({
    required String name,
  }) async {
    final override = createSubscriptionForTest;
    if (override != null) return override(name: name);
    final res = await AuthHttp.post(
      Uri.parse('${GeminiService.serverUrl}/payment/create-subscription'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode == 409) {
      // The account already has an auto-charging subscription. Razorpay will
      // happily create a second one, so the server refuses — saying "already
      // Pro" is much better than silently billing the user twice.
      throw Exception('This account already has an active Pro subscription.');
    }
    if (res.statusCode != 200) {
      throw Exception('Could not start the payment (${res.statusCode}).');
    }
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the payment server.');
    }
    return data;
  }

  /// Verifies the payment server-side, then switches Pro on.
  static Future<void> _verifyAndActivate(
    PaymentSuccessResponse response,
  ) async {
    final subscriptionId =
        (response.data?['razorpay_subscription_id'] as String?) ??
        _subscriptionId;
    bool verified = false;
    // A 202 means the payment was genuine but could not be SAVED yet, and the
    // server explains why — quoting it is far more useful than a generic
    // "could not confirm".
    String? pendingReason;
    try {
      final res = await AuthHttp.post(
        Uri.parse('${GeminiService.serverUrl}/payment/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_subscription_id': ?subscriptionId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        }),
      );
      verified = res.statusCode == 200;
      if (res.statusCode == 202) {
        final data = jsonDecode(res.body);
        if (data is Map && data['message'] is String) {
          pendingReason = data['message'] as String;
        }
      }
    } catch (e) {
      debugPrint('Payment verification error: $e');
    }

    if (verified) {
      try {
        await SubscriptionService.instance.activate();
      } catch (e) {
        debugPrint('Activation after payment failed: $e');
      }
      _finish(const PaymentResult.success());
    } else {
      // /payment/verify may be unreachable while the webhook has already
      // landed. Ask the authoritative status once before calling this
      // unconfirmed — telling a paid user "we could not confirm" is one of the
      // worst outcomes in the flow.
      if (await refreshStatus()) {
        _finish(const PaymentResult.success());
        return;
      }
      // The money may still be fine — the webhook just has not landed yet.
      _finish(
        PaymentResult.pending(
          pendingReason ??
              'We could not confirm the payment yet. If money was deducted, Pro '
                  'switches on by itself within a few minutes.',
        ),
      );
    }
  }

  /// Opens the hosted subscription page as the fallback path and waits for
  /// activation. Returns `pending` when the page was opened but nothing has
  /// been confirmed yet (the webhook still activates Pro later).
  static Future<PaymentResult> _openHostedPage(String subscriptionId) async {
    final uri = Uri.parse(
      'https://api.razorpay.com/v1/l/subscriptions/$subscriptionId',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      return const PaymentResult.failed(
        'Could not open the secure payment page. Please try again.',
      );
    }
    final activated = await _pollForActivation();
    if (activated) return const PaymentResult.success();
    return const PaymentResult.pending(
      'Finish the payment in the page we opened — Pro switches on as soon as '
      'the bank confirms.',
    );
  }

  /// Polls the backend (Firestore-backed) until the user is subscribed.
  static Future<bool> _pollForActivation({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final resp = await AuthHttp.get(
          Uri.parse('${GeminiService.serverUrl}/me/payment/status'),
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map && data['subscribed'] == true) {
            await SubscriptionService.instance.activate();
            return true;
          }
        }
      } catch (_) {
        // Network hiccup while polling — keep trying until the deadline.
      }
      await Future.delayed(const Duration(seconds: 4));
    }
    return false;
  }

  // ─── Plugin callbacks ──────────────────────────────────────────────────

  static void _handlePaymentSuccess(PaymentSuccessResponse response) {
    unawaited(_verifyAndActivate(response));
  }

  static void _handlePaymentError(PaymentFailureResponse response) {
    final message = response.message ?? '';
    final subscriptionId = _subscriptionId;

    if (looksLikeRecurrenceBug(message) && subscriptionId != null) {
      // Not the user's fault and not a failed payment — switch to the hosted
      // page in place, keeping the same completer so the caller sees one
      // continuous flow.
      debugPrint('SDK recurrence bug hit — falling back to hosted page');
      unawaited(_openHostedPage(subscriptionId).then(_finish));
      return;
    }

    if (response.code == 0) {
      _finish(const PaymentResult.cancelled());
      return;
    }
    _finish(
      PaymentResult.failed(
        message.isEmpty ? 'The payment did not go through.' : message,
      ),
    );
  }

  static void _handleExternalWallet(ExternalWalletResponse response) {
    // The sheet is still open (the user was handed off to a wallet app), so
    // there is nothing to report yet — the success/error callback follows.
    debugPrint('External wallet selected: ${response.walletName}');
  }

  /// Completes the in-flight purchase exactly once and clears the flow state.
  static void _finish(PaymentResult result) {
    final pending = _pending;
    _pending = null;
    _subscriptionId = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }
}
