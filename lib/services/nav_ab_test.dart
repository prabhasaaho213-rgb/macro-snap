import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporting.dart';

/// Which bottom-navigation design this install draws.
enum NavVariant {
  /// The 1.5.8 "reference design": the current page is a filled pill carrying
  /// its icon and label, the other three are plain circles.
  pill,

  /// The previous design: every tab is a plain circle, icon-only, the selected
  /// one tinted. Kept intact as the A/B control arm.
  circle,
}

/// The bottom-navigation A/B test.
///
/// A 1.5.8 rebuild turned the nav bar into a pill design without evidence it
/// is actually better at getting people between the four tabs. The test keeps
/// both designs and measures which one people use.
///
/// Assignment is per install: the variant is drawn once at random on first
/// launch, persisted in prefs, and never redrawn — a design that flips between
/// sessions measures nothing. Rendering reads [variant]; the shell's tab
/// handler calls [recordTabSelect], which increments per-tab counters in the
/// signed-in user's Firestore analytics doc, best effort: a guest or an
/// offline moment simply skips the write and costs nothing.
///
/// Every write lands in the current user's OWN document (`analytics/{uid}`),
/// never a shared collection, so the security rules stay owner-only and two
/// accounts on one device can never mix their counts.
class NavAbTest {
  NavAbTest._();
  static final NavAbTest instance = NavAbTest._();

  /// Prefs key holding the assigned variant. Absent = unassigned yet.
  static const String _prefsKey = 'nav_ab_variant';

  NavVariant? _variant;

  /// The assigned variant, or null before the first [load] completes. Main
  /// shell builds after bootstrap, so it is normally assigned already.
  NavVariant? get variant => _variant;

  /// Notifies listeners when the variant is assigned (or forced).
  final ValueNotifier<int> changeNotifier = ValueNotifier(0);

  /// Test seam: pin the variant instead of drawing randomly. Null restores
  /// normal behaviour.
  @visibleForTesting
  static NavVariant? forcedVariant;

  /// Loads (or draws) the persisted variant. Never throws: an unusable prefs
  /// store leaves this session on the reference design, which is what the app
  /// shipped with.
  Future<void> load() async {
    final forced = forcedVariant;
    if (forced != null) {
      _variant = forced;
      changeNotifier.value++;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored == NavVariant.pill.name) {
        _variant = NavVariant.pill;
      } else if (stored == NavVariant.circle.name) {
        _variant = NavVariant.circle;
      } else {
        // First launch of the test: draw 50/50 and freeze it.
        final drawn = Random().nextBool()
            ? NavVariant.pill
            : NavVariant.circle;
        _variant = drawn;
        await prefs.setString(_prefsKey, drawn.name);
      }
    } catch (e, st) {
      logError('NavAbTest.load', e, st);
      // Reference design is the shipped default — fall back to it.
      _variant = NavVariant.pill;
    }
    changeNotifier.value++;
  }

  /// Called by the shell on EVERY tab change (including a re-tap of the tab
  /// already showing — the strongest signal a nav is doing its job). Fire and
  /// forget; a guest, offline device or closed Firestore simply skips.
  void recordTabSelect(int index) {
    if (_variant == null) return;
    unawaitedError(_bumpSelect(index));
  }

  Future<void> _bumpSelect(int index) async {
    try {
      final uid = await _currentUid();
      if (uid == null || uid.isEmpty) return;
      final tab = switch (index) {
        0 => 'home',
        1 => 'cam',
        2 => 'habits',
        _ => 'profile',
      };
      // `selects` is a real nested map, not a dotted key: writing the string
      // 'selects.$tab' created a single field literally named "selects.home"
      // and no nested structure at all. SetOptions(merge: true) merges maps
      // recursively, so each tab's counter survives the next write.
      //
      // Documents written before this fix still carry those flat
      // `selects.home` / `selects.cam` / … fields alongside the new nested
      // map, so a report has to read BOTH shapes (old flat keys plus
      // selects.<tab>) or it will undercount the older installs.
      await FirebaseFirestore.instance
          .collection('analytics')
          .doc(uid)
          .set({
            'navAb': {
              'variant': _variant!.name,
              'selects': {tab: FieldValue.increment(1)},
            },
          }, SetOptions(merge: true));
    } catch (_) {
      // Analytics must never surface an error to the user.
    }
  }

  /// Resolves the Firebase Auth UID without importing Firebase Auth here —
  /// this mirrors the guest-skip logic [MealSyncService] uses. Null = guest.
  static Future<String?> _currentUid() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return user?.uid;
    } catch (_) {
      return null;
    }
  }
}

/// Wait for a future, swallowing cancellation — analytics writes are best
/// effort by design.
void unawaitedError(Future<void> future) {
  future.catchError((_) {
    // Ignored: analytics never surfaces an error.
  });
}
