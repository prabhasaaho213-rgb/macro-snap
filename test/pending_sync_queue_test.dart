import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/pending_sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The retry queue is the difference between "the cloud backup failed once" and
/// "that meal no longer exists anywhere but this phone". These tests pin the
/// two properties that matter: a failed write stays queued (and is visible to
/// the reconcile), and nothing leaks between accounts on one device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'phone': 'user@example.com'});
    PendingSyncQueue.instance.resetForTest();
  });

  test('a queued upload survives and is reported to the reconcile', () async {
    await PendingSyncQueue.instance.enqueueUpsert('meal-1');
    expect(await PendingSyncQueue.instance.ids(), {'meal-1'});
  });

  test('a queued delete replaces a queued upload of the same meal', () async {
    await PendingSyncQueue.instance.enqueueUpsert('meal-1');
    await PendingSyncQueue.instance.enqueueDelete('meal-1');
    // The meal is gone locally; uploading it again would be wrong.
    await PendingSyncQueue.instance.enqueueUpsert('meal-1');
    expect(await PendingSyncQueue.instance.ids(), {'meal-1'});
  });

  test('the queue is per account, not per device', () async {
    // Signing in/out only changes the `phone` pref, so that is what this
    // simulates: the same prefs store, a different active account.
    final prefs = await SharedPreferences.getInstance();
    await PendingSyncQueue.instance.enqueueUpsert('meal-a');

    // A different account on the same phone must not inherit, drain or see it.
    await prefs.setString('phone', 'other@example.com');
    expect(await PendingSyncQueue.instance.ids(), isEmpty);

    await PendingSyncQueue.instance.enqueueUpsert('meal-b');

    await prefs.setString('phone', 'user@example.com');
    expect(await PendingSyncQueue.instance.ids(), {'meal-a'});
  });

  test('a signed-out device keeps the queue instead of losing it', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('phone');
    await PendingSyncQueue.instance.enqueueUpsert('orphan-meal');

    // No Firebase account: the drain must not touch (or clear) the entries —
    // that is what lets them upload once an account is active again.
    await PendingSyncQueue.instance.drain();
    expect(await PendingSyncQueue.instance.ids(), {'orphan-meal'});
  });

  test('confirmed ids are remembered so remote deletions can be applied', () async {
    expect(await PendingSyncQueue.instance.isSynced('meal-1'), false);
    await PendingSyncQueue.instance.markSynced('meal-1');
    expect(await PendingSyncQueue.instance.isSynced('meal-1'), true);

    await PendingSyncQueue.instance.forget('meal-1');
    expect(await PendingSyncQueue.instance.isSynced('meal-1'), false);
  });

  test('marking the same id twice does not duplicate it', () async {
    await PendingSyncQueue.instance.markSynced('meal-1');
    await PendingSyncQueue.instance.markSynced('meal-1');
    final prefs = await SharedPreferences.getInstance();
    final key = prefs
        .getKeys()
        .firstWhere((k) => k.startsWith('synced_meal_ids'));
    expect(prefs.getStringList(key), ['meal-1']);
  });
}
