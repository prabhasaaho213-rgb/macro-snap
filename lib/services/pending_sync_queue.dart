import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_partition.dart';
import 'crash_reporting.dart';
import 'firebase_identity.dart';
import 'meal_sync_service.dart';
import '../models/meal_record.dart';

/// Durable retry queue for cloud writes that failed.
///
/// The app's cloud backup used to be strictly fire-and-forget: `MealStore.add`
/// called [MealSyncService.syncMeal] without awaiting it and dropped the
/// result. A meal logged in a lift, on flaky data, or while the backend was
/// briefly down therefore lived ONLY on that phone, while the privacy policy
/// promises meals are "saved to the cloud automatically". Reinstalling then
/// lost them, with nothing on screen ever having said so.
///
/// This queue records the meal ids whose write did not land and replays them
/// later: after the next launch, whenever the app returns to the foreground,
/// and after a later write succeeds (a success is proof the network is back).
/// Entries live in prefs under the account partition, so switching accounts
/// neither drains nor mixes another account's pending work.
///
/// It also remembers which meal ids this device has successfully uploaded
/// ([isSynced]). That record is what makes remote deletions safe to apply:
/// a local meal can only be considered "deleted on another device" once we
/// know it really did reach the cloud once. Meals written before this bookkeeping
/// existed are never eligible for that prune, so an upgrade can never delete
/// anyone's history.
class PendingSyncQueue with WidgetsBindingObserver {
  PendingSyncQueue._();
  static final PendingSyncQueue instance = PendingSyncQueue._();

  /// Base prefs key for the pending map. Partitioned per account.
  static const String _pendingBase = 'pending_sync';

  /// Base prefs key for the ids this device has confirmed in the cloud.
  static const String _syncedBase = 'synced_meal_ids';

  /// How many confirmed ids are remembered. Each is a 36-char uuid, so this is
  /// roughly 18 KB of prefs — enough to cover months of logging, and bounded so
  /// the value can never grow without limit.
  static const int maxSyncedIds = 500;

  /// How long one drain may keep retrying before giving up for this attempt.
  /// A dead network fails fast; this only bounds a pathological backend.
  static const Duration drainBudget = Duration(seconds: 20);

  /// Supplies the meals of the active account. Wired once from `main()` so
  /// this service never has to import the store (and create an import cycle).
  List<MealRecord> Function()? mealSource;

  bool _draining = false;
  bool _observing = false;

  /// Starts replaying pending writes when the app returns to the foreground.
  /// Called once at startup; safe to call again.
  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(drain());
  }

  static Future<(SharedPreferences, String)> _partition() async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs));
    return (prefs, suffix);
  }

  Future<Map<String, String>> _readPending() async {
    try {
      final (prefs, suffix) = await _partition();
      final raw = prefs.getString(AccountPartition.key(_pendingBase, suffix));
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String && e.key is String)
            e.key as String: e.value as String,
      };
    } catch (e, st) {
      logError('PendingSyncQueue._readPending', e, st);
      return {};
    }
  }

  Future<void> _writePending(Map<String, String> pending) async {
    try {
      final (prefs, suffix) = await _partition();
      final key = AccountPartition.key(_pendingBase, suffix);
      if (pending.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(pending));
      }
    } catch (e, st) {
      logError('PendingSyncQueue._writePending', e, st);
    }
  }

  /// Marks [mealId] as needing an upload (create or update).
  Future<void> enqueueUpsert(String mealId) => _put(mealId, 'set');

  /// Marks [mealId] as needing a cloud delete.
  Future<void> enqueueDelete(String mealId) => _put(mealId, 'del');

  Future<void> _put(String mealId, String op) async {
    if (mealId.isEmpty) return;
    final pending = await _readPending();
    // A delete always wins over a queued upload of the same id.
    if (pending[mealId] == 'del' && op == 'set') return;
    pending[mealId] = op;
    await _writePending(pending);
  }

  /// The ids currently waiting to be replayed.
  Future<Set<String>> ids() async => (await _readPending()).keys.toSet();

  /// Whether anything is waiting right now (used by tests and the reconcile).
  Future<bool> get isEmpty async => (await _readPending()).isEmpty;

  /// Records that [mealId] is in the cloud. Called after a successful upload.
  Future<void> markSynced(String mealId) async {
    if (mealId.isEmpty) return;
    try {
      final (prefs, suffix) = await _partition();
      final key = AccountPartition.key(_syncedBase, suffix);
      final list = prefs.getStringList(key) ?? <String>[];
      if (list.contains(mealId)) return;
      list.add(mealId);
      // Keep the newest [maxSyncedIds]: the oldest confirmations stop mattering
      // long before they fall off the end of this window.
      final trimmed = list.length > maxSyncedIds
          ? list.sublist(list.length - maxSyncedIds)
          : list;
      await prefs.setStringList(key, trimmed);
    } catch (e, st) {
      logError('PendingSyncQueue.markSynced', e, st);
    }
  }

  /// Whether this device has ever confirmed [mealId] in the cloud.
  Future<bool> isSynced(String mealId) async {
    try {
      final (prefs, suffix) = await _partition();
      final list =
          prefs.getStringList(AccountPartition.key(_syncedBase, suffix)) ??
          const <String>[];
      return list.contains(mealId);
    } catch (_) {
      return false;
    }
  }

  /// Forgets [mealId]'s confirmation — used once a meal is gone, so the list
  /// does not accumulate ids of meals that no longer exist anywhere.
  Future<void> forget(String mealId) async {
    try {
      final (prefs, suffix) = await _partition();
      final key = AccountPartition.key(_syncedBase, suffix);
      final list = prefs.getStringList(key);
      if (list == null || !list.contains(mealId)) return;
      list.remove(mealId);
      await prefs.setStringList(key, list);
    } catch (e, st) {
      logError('PendingSyncQueue.forget', e, st);
    }
  }

  /// Replays every queued write. Safe to call repeatedly and concurrently: a
  /// second call while a drain is running is a no-op.
  ///
  /// Stops at the first failed write — that is the offline case, and hammering
  /// the remaining entries would only repeat the same failure. Everything left
  /// stays queued for the next launch or resume.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // No signed-in account: leaving the queue untouched is correct, and it
      // is what lets those writes upload once an account is active again.
      final uid = await FirebaseIdentity.currentUid();
      if (uid == null || uid.isEmpty) return;
      final pending = await _readPending();
      if (pending.isEmpty) return;

      final meals = mealSource?.call() ?? const <MealRecord>[];
      final byId = {for (final m in meals) m.id: m};
      final started = DateTime.now();
      final done = <String>[];

      for (final entry in pending.entries.toList()) {
        if (DateTime.now().difference(started) > drainBudget) break;
        final id = entry.key;
        if (entry.value == 'del') {
          final ok = await MealSyncService.removeMeal(id);
          if (!ok) break;
          await forget(id);
          done.add(id);
        } else {
          final meal = byId[id];
          if (meal == null) {
            // The meal is gone locally (deleted, or the account was wiped), so
            // there is nothing to upload and the entry must not linger.
            done.add(id);
            continue;
          }
          final ok = await MealSyncService.syncMeal(meal);
          if (!ok) break;
          await markSynced(id);
          done.add(id);
        }
      }

      if (done.isEmpty) return;
      final remaining = Map<String, String>.from(pending);
      for (final id in done) {
        remaining.remove(id);
      }
      await _writePending(remaining);
    } catch (e, st) {
      logError('PendingSyncQueue.drain', e, st);
    } finally {
      _draining = false;
    }
  }

  /// Test seam: drops the in-memory guard so a test can run a second drain.
  @visibleForTesting
  void resetForTest() => _draining = false;
}
