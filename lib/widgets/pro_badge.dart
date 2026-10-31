import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/subscription_service.dart';

/// The little "PRO" chip that marks a Pro feature wherever it appears.
///
/// One widget for every Pro-gated entry point (Guru, the AI meal plan, the
/// weekly trend card, the scan and habit limits) so the mark reads the same
/// everywhere instead of each screen inventing its own lock glyph. The chip
/// labels a feature as Pro; whether an account can use it right now is decided
/// by [SubscriptionService], not by this widget.
///
/// The accent gradient with black text is the same treatment the primary CTA
/// uses, so a badge never competes with the button it sits next to.
class ProBadge extends StatelessWidget {
  /// Smaller padding and type, for corners and overlay positions where the
  /// chip must not push the content it marks.
  final bool compact;

  const ProBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    // The chip exists to sell the upgrade: it says "this feature is Pro".
    // For an account that already has Pro it is pure noise, and a PRO tag on
    // something you already paid for reads like a lock that should have been
    // removed. So the mark is for free accounts only — access is still decided
    // by SubscriptionService at each gate, never by this widget.
    //
    // isSubscribed covers all three ways to be Pro: a paid Razorpay plan, a
    // referral window, and the admin lifetime grant (which is stored as a
    // subscription with the 1900 marker), so the owner stops seeing chips too.
    if (SubscriptionService.instance.isSubscribed) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: 'Pro feature',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          gradient: MacroSnapTheme.accentGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          'PRO',
          style: TextStyle(
            fontSize: compact ? 8 : 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            height: 1.15,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
