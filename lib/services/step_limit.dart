import 'package:flutter/foundation.dart';

import 'subscription_service.dart';

/// The daily step ceiling that separates the free plan from Pro.
///
/// The phone's sensor cannot be told to stop counting, so the cap is applied to
/// the NUMBER the app uses — the dashboard, the step goal and streak, and the
/// leaderboard's movement points. The sensor's raw reading is kept on the
/// device (see `StepCounterService.rawTodaySteps`), so buying Pro lifts the cap
/// and today's already-walked steps appear at once.
///
/// One place decides this so a second code path cannot quietly hand a free
/// account the whole day: [cap] is the only arithmetic the rest of the app
/// uses, and the backend applies the same 5,000 when it scores a sync.
class StepLimit {
  const StepLimit._();

  /// Steps a free account can bank in one day. Pro removes the ceiling.
  static const int freeDaily = 5000;

  /// Test seam: null reads the real subscription state.
  @visibleForTesting
  static bool? proOverride;

  /// True when the free ceiling applies to this account right now.
  static bool get isFree {
    final override = proOverride;
    if (override != null) return !override;
    // Deliberately the synchronous flag: this is read from a sensor callback on
    // every batch, and the async claim check belongs to the gates that can
    // await. The admin's lifetime grant is applied to this flag at startup.
    return !SubscriptionService.instance.isSubscribed;
  }

  /// [steps] as a free account may use them.
  static int cap(int steps) => isFree && steps > freeDaily ? freeDaily : steps;

  /// The free ceiling has been hit today (the upgrade prompt's condition).
  static bool reached(int steps) => isFree && steps >= freeDaily;

  /// The target the ring and the streak work toward.
  ///
  /// A free account's chosen goal is kept intact for the day it upgrades, but
  /// it is measured against the cap until then — a 10,000-step target that can
  /// never be reached would just read as a broken ring.
  static int goal(int configured) =>
      isFree && configured > freeDaily ? freeDaily : configured;
}
