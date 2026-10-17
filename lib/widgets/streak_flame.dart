import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

/// Animated streak flames that grow with your best habit streak:
/// 🔥 1–2 days · 🔥🔥 3–6 days · 🔥🔥🔥 7+ days.
///
/// Each flame flickers on its own phase offset; the whole row pops in with
/// an overshoot spring whenever the tier changes. A glowing "Lv N" badge
/// appears and pops in every 7 days of streak (7 → Lv 1, 14 → Lv 2, …)
/// with a medium haptic on level-up.
/// A single flame drawn as a gradient-filled icon with a live glow.
///
/// This replaced the literal 🔥 emoji: the emoji renders through the device's
/// colour-emoji font, which on several Android builds is visibly dimmer and
/// flatter than the rest of the UI (and it can't take a gradient or shadow).
/// Drawing it ourselves keeps the flame hot — yellow core, orange body, pink
/// tip — with a glow that pulses with the flicker, on every device.
class _Flame extends StatelessWidget {
  const _Flame({required this.size, required this.flicker});

  final double size;
  final double flicker;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.1,
      height: size * 1.1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind the flame; pulses between 35% and 65% opacity.
          Container(
            width: size * 0.78,
            height: size * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MacroSnapTheme.neonOrange
                      .withValues(alpha: 0.35 + 0.30 * flicker),
                  blurRadius: size * 0.55,
                  spreadRadius: size * 0.10,
                ),
              ],
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFE066), // bright yellow core
                Color(0xFFFF8A3D),
                Color(0xFFFF3D6E), // hot pink tip
              ],
              stops: [0.0, 0.55, 1.0],
            ).createShader(bounds),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: size,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, required this.streak, this.fontSize = 16});

  /// Best current streak in days (e.g. HabitStore.totalStreakPower).
  final int streak;

  /// Base size of each flame in logical pixels; the drawn icon is 1.35× this
  /// so it carries the same visual weight the emoji used to.
  final double fontSize;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  /// Number of flames: 0 none, 1 for 1–2, 2 for 3–6, 3 for 7+.
  int get _flameCount => widget.streak >= 7 ? 3 : (widget.streak >= 3 ? 2 : (widget.streak >= 1 ? 1 : 0));

  /// Level badge: shown from 7 days, then +1 every full 7 days
  /// (7 → Lv 1, 14 → Lv 2, 21 → Lv 3 …). Floor so level-up lands exactly
  /// on the 7-day boundary instead of a day early.
  int get _level => widget.streak >= 7 ? (widget.streak / 7).floor() : 0;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant StreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLevel = oldWidget.streak >= 7 ? (oldWidget.streak / 7).floor() : 0;
    if (_level > oldLevel) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _flameCount;
    final level = _level;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // The AnimatedSwitcher sits OUTSIDE the per-frame flicker builder: it
        // should only rebuild/transition when the tier (count) changes. Each
        // flame below owns its own tiny AnimatedBuilder so the 900ms flicker
        // tick only rebuilds the flame's Transform.scale, not the switcher's
        // transition machinery.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Row(
            key: ValueKey<int>(count),
            mainAxisSize: MainAxisSize.min,
            children: List.generate(count, (i) {
              return AnimatedBuilder(
                animation: _flicker,
                builder: (context, _) {
                  // Phase-shifted sine so flames flicker out of sync.
                  final t = _flicker.value * 2 * math.pi;
                  final flicker = 0.5 + 0.5 * math.sin(t + i * 1.1);
                  final scale = 1 + 0.09 * flicker;
                  return Transform.scale(
                    scale: scale,
                    child: _Flame(
                      size: widget.fontSize * 1.35,
                      flicker: flicker,
                    ),
                  );
                },
              );
            }),
          ),
        ),
        if (level > 0) ...[
          const SizedBox(height: 3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Container(
              key: ValueKey<int>(level),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MacroSnapTheme.neonOrange, MacroSnapTheme.neonPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: MacroSnapTheme.neonOrange.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.military_tech_rounded,
                      color: Colors.black, size: 12),
                  const SizedBox(width: 3),
                  Text('Lv $level',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
