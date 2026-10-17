import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One place for the app's haptic vocabulary, so feedback feels the same on
/// every screen instead of each widget picking its own strength.
///
/// | Intent | Call |
/// |---|---|
/// | tab change, chip, stepper, toggle | [tap] |
/// | card open, swipe action, send | [light] |
/// | habit complete, quantity ±, save | [medium] |
/// | destructive / irreversible | [heavy] |
///
/// Every call is best-effort: platforms and devices without a vibrator (or
/// with haptics disabled) throw [MissingPluginException] / [PlatformException],
/// and a missing buzz must never break the tap it was decorating.
class Haptics {
  const Haptics._();

  /// Selection tick — the lightest feedback. Use for state changes that
  /// aren't destructive: switching tabs, picking a chip, stepping a dial.
  static Future<void> tap() => _run(HapticFeedback.selectionClick);

  /// Confirms a successful action (card opened, message sent, swipe action).
  static Future<void> light() => _run(HapticFeedback.lightImpact);

  /// Confirms something was committed (habit completed, meal saved).
  static Future<void> medium() => _run(HapticFeedback.mediumImpact);

  /// Warns before/after something irreversible (delete, reset, undo of data).
  static Future<void> heavy() => _run(HapticFeedback.heavyImpact);

  static Future<void> _run(Future<void> Function() feedback) async {
    if (kIsWeb) return;
    try {
      await feedback();
    } catch (_) {
      // No vibrator / haptics disabled — the interaction still works.
    }
  }
}
