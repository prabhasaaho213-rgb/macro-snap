import 'package:firebase_auth/firebase_auth.dart';

/// Shared Firebase identity helpers for the cloud layer.
///
/// Centralizes the "resolve the signed-in user's UID" pattern so the three
/// cloud services ([MealSyncService], [SubscriptionService],
/// [SyncStatusService]) can't drift on timeout/error semantics.
class FirebaseIdentity {
  FirebaseIdentity._();

  /// Resolves the current Firebase Auth UID. **Never throws.**
  ///
  /// On a cold start the session may still be restoring when `currentUser` is
  /// null, so we briefly wait for the auth-state stream. Guests (no account)
  /// resolve to null fast, because the stream emits the current (null) state
  /// immediately. In test environments without Firebase initialized, the
  /// getter throws and we fall back to null — a guest, silently.
  static Future<String?> currentUid({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      var user = FirebaseAuth.instance.currentUser;
      user ??= await FirebaseAuth.instance.authStateChanges().first.timeout(
        timeout,
      );
      return user?.uid;
    } catch (_) {
      return null;
    }
  }
}
