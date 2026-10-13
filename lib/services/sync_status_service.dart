import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'firebase_identity.dart';
import 'gemini_service.dart';

/// Reactive tracker for backend (cloud backup) reachability.
///
/// Every [MealSyncService] sync/fetch reports success or failure here; the
/// shell shows a dismissible banner while [backendUnreachable] is true, so a
/// dead backend is never a silent failure again. A successful round-trip
/// (or a manual Retry probe) clears the banner automatically.
class SyncStatusService extends ChangeNotifier {
  SyncStatusService._();
  static final SyncStatusService instance = SyncStatusService._();

  bool _backendUnreachable = false;
  bool _dismissed = false;
  String _lastDetail = '';

  /// True when the last sync attempt failed and the banner hasn't been
  /// dismissed for that failure.
  bool get backendUnreachable => _backendUnreachable && !_dismissed;

  /// Human-readable detail of the last failure (endpoint name, HTTP code).
  String get lastDetail => _lastDetail;

  /// Called by [MealSyncService] whenever a cloud request fails.
  ///
  /// Short-circuits when the banner is already up with the same detail — a
  /// bulk sync against a dead backend (e.g. 20 meals) would otherwise fire
  /// one full shell rebuild per failed item.
  void reportFailure([String detail = '']) {
    if (_backendUnreachable && !_dismissed && _lastDetail == detail) return;
    _backendUnreachable = true;
    _dismissed = false; // a NEW failure re-shows the banner
    _lastDetail = detail;
    notifyListeners();
  }

  /// Called by [MealSyncService] whenever a cloud request succeeds.
  void reportSuccess() {
    if (!_backendUnreachable && _lastDetail.isEmpty) return;
    _backendUnreachable = false;
    _lastDetail = '';
    notifyListeners();
  }

  /// User dismissed the banner — hide it until the next failure.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  /// Re-probe the cloud (Retry button).
  ///
  /// The data plane is now Firestore, so for a signed-in user we probe it
  /// directly: reading the user's own `users/{uid}` doc verifies both
  /// connectivity and security-rule permissions (a missing doc reads fine
  /// without error). Guests have no Firestore docs, so we fall back to
  /// probing the AI/payments backend root, which still serves /analyze and
  /// Razorpay.
  Future<bool> probeBackend() async {
    // ── Firestore probe for signed-in users ───────────────────────────
    try {
      final uid = await FirebaseIdentity.currentUid();
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 8));
        reportSuccess();
        return true;
      }
    } catch (_) {
      reportFailure('Cannot reach cloud database');
      return false;
    }

    // ── Backend fallback for guests (AI + payments) ────────────────────
    try {
      final resp = await http
          .get(Uri.parse('${GeminiService.serverUrl}/'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        reportSuccess();
        return true;
      }
      reportFailure('Backend responded with HTTP ${resp.statusCode}');
      return false;
    } catch (_) {
      reportFailure('Cannot reach backup server');
      return false;
    }
  }
}
