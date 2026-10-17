import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_http.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gemini_service.dart';
import 'subscription_service.dart';

class RazorpayService {
  static final Razorpay _razorpay = Razorpay();
  static bool _initialized = false;
  static String? _lastSubscriptionId;

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

  /// Start the payment flow for the ₹29/month RECURRING subscription.
  ///
  /// Creates the Razorpay Subscription on the backend, then opens Razorpay's
  /// HOSTED subscription page (the /v1/l/subscriptions/{id} URL) in the
  /// system browser instead of the SDK checkout.
  ///
  /// WHY: the razorpay_flutter SDK checkout throws Razorpay error VC
  /// ("INCORRECT RECURRENCE PATTERN RULE") on this plan even though the
  /// plan/subscription are valid — the hosted page is proven to work
  /// (razorpay/razorpay-flutter#396, open since 2024). The subscription is
  /// auto-charged monthly by Razorpay either way; the backend webhook
  /// (subscription.charged) activates Pro in Firestore, which we poll for.
  static Future<void> startCheckout({
    required String name,
  }) async {
    try {
      // 1. Create recurring subscription on backend. The payer's identity
      // (phone/email) comes from the verified token there — only the display
      // name travels in the body.
      final subResponse = await AuthHttp.post(
        Uri.parse('${GeminiService.serverUrl}/payment/create-subscription'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );

      if (subResponse.statusCode != 200) {
        throw Exception('Failed to create payment subscription');
      }

      final subData = jsonDecode(subResponse.body);
      final subscriptionId = subData['subscription_id'] as String;
      _lastSubscriptionId = subscriptionId;

      // 2. Open the hosted subscription payment page in the system browser.
      final uri = Uri.parse(
        'https://api.razorpay.com/v1/l/subscriptions/$subscriptionId',
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw Exception('Could not open the payment page');
      }

      unawaited(_pollForActivation());
    } catch (e) {
      _lastSubscriptionId = null;
      rethrow;
    }
  }

  /// Polls /me/payment/status (Firestore-backed) until the user is
  /// subscribed, then triggers the success callback. Silently gives up after
  /// the timeout — the webhook still activates Pro in the background, so a
  /// slow webhook only delays the on-screen confirmation.
  static Future<void> _pollForActivation({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        // Phase 2: the caller's own status, identified by the token alone.
        final resp = await AuthHttp.get(
          Uri.parse('${GeminiService.serverUrl}/me/payment/status'),
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map && data['subscribed'] == true) {
            _lastSubscriptionId = null;
            if (_onSuccessCallback != null) _onSuccessCallback!();
            return;
          }
        }
        await Future.delayed(const Duration(seconds: 4));
      }
    } catch (_) {
      // Network hiccup while polling — the webhook still activates Pro.
    }
    _lastSubscriptionId = null;
  }

  /// Handle successful payment from Razorpay.
  static void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      // The SDK puts razorpay_subscription_id in the raw response map for
      // subscription checkouts; fall back to the id we created it with.
      final subscriptionId =
          (response.data?['razorpay_subscription_id'] as String?) ??
              _lastSubscriptionId;
      // Verify payment on backend (subscription signature is
      // HMAC(subscription_id|payment_id))
      final verifyResponse = await AuthHttp.post(
        Uri.parse('${GeminiService.serverUrl}/payment/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_subscription_id': ?subscriptionId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        }),
      );

      if (verifyResponse.statusCode == 200) {
        // Payment verified — activate subscription
        await _activateSubscription();
        // Notify the UI that payment succeeded
        if (_onSuccessCallback != null) {
          _onSuccessCallback!();
        }
      } else {
        _showError('Payment verification failed. Please contact support.');
      }
    } catch (e) {
      _showError('Verification error. Your payment may still be processed.');
    }
  }

  /// Handle payment failure.
  static void _handlePaymentError(PaymentFailureResponse response) {
    _lastSubscriptionId = null;
    String message = 'Payment cancelled';
    if (response.code != 0) {
      message = 'Payment failed: ${response.message ?? "Please try again"}';
    }
    _showError(message);
  }

  /// Handle external wallet selection.
  static void _handleExternalWallet(ExternalWalletResponse response) {
    _showError('${response.walletName} selected. Please complete the payment.');
  }

  /// Activate the subscription after successful payment verification.
  ///
  /// Post-activation side effects (pro reminders + meal-store refresh) live
  /// inside [SubscriptionService.activate] so they aren't duplicated here and
  /// in the subscription screen.
  static Future<void> _activateSubscription() async {
    await SubscriptionService.instance.activate();
    _lastSubscriptionId = null;
  }

  /// Show a snackbar error message (uses a global key approach).
  static void _showError(String message) {
    if (_onErrorCallback != null) {
      _onErrorCallback!(message);
    }
  }

  static void Function(String)? _onErrorCallback;
  static VoidCallback? _onSuccessCallback;

  /// Set a callback for showing error messages from the UI.
  static void setErrorCallback(void Function(String) callback) {
    _onErrorCallback = callback;
  }

  /// Set a callback for when payment succeeds and is verified.
  static void setSuccessCallback(VoidCallback callback) {
    _onSuccessCallback = callback;
  }

  /// Clear all callbacks.
  static void clearCallbacks() {
    _onErrorCallback = null;
    _onSuccessCallback = null;
  }
}
