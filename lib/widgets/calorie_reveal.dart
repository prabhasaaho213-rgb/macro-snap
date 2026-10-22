// lib/widgets/calorie_reveal.dart
//
// Calorie "slot machine" reveal for MacroSnap.
//
//  * The number spins up from 0 and slows down as it lands (ease-out), with a
//    light haptic tick each time it passes a step, so the ticks naturally slow
//    down like a slot machine stopping.
//  * On landing it pops (scale bounce) and gives a medium haptic.
//  * If the meal fits the user's goal, it also fires the existing
//    ConfettiCelebration. Confetti plays once per widget instance.
//  * If the calories change later (user edits the grams), the number glides to
//    the new value quietly: no ticks, no confetti.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../services/meal_store.dart';
import 'confetti_celebration.dart';

/// Decides whether a scanned meal "fits" the user's goal.
class GoalFit {
  /// Returns true (celebrate), false (no confetti) or null (no profile yet).
  ///
  /// Call this BEFORE the meal is logged: today's total must not include it.
  static bool? check({required int calories, required double protein}) {
    final p = DietPlanService.instance.profile;
    if (p == null) return null;

    final remaining = p.targetCalories - MealStore.instance.todayCalories;

    switch (p.goal) {
      case Goal.loseWeight:
      case Goal.maintain:
        // Meal fits in what is left of today's calorie budget.
        return remaining > 0 && calories <= remaining;
      case Goal.gainMuscle:
        // Meal brings a solid chunk of the daily protein target
        // (20%+) and does not blow the calorie budget.
        return protein >= p.targetProtein * 0.20 &&
            calories <= math.max(remaining, 0) + 150;
    }
  }
}

class CalorieReveal extends StatefulWidget {
  final int calories;
  final double protein;

  /// false for a saved meal viewed later: shows the number instantly.
  final bool animate;

  /// Delay before the spin starts (lets the card slide in first).
  final Duration startDelay;

  final TextStyle style;

  /// Colour the number flashes to on landing when the meal fits the goal.
  final Color? celebrateColor;

  const CalorieReveal({
    super.key,
    required this.calories,
    required this.protein,
    this.animate = true,
    this.startDelay = const Duration(milliseconds: 450),
    this.style = const TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
      height: 1,
    ),
    this.celebrateColor,
  });

  @override
  State<CalorieReveal> createState() => _CalorieRevealState();
}

class _CalorieRevealState extends State<CalorieReveal>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pop;
  late Animation<double> _spinAnim;

  double _from = 0;
  double _to = 0;
  bool _landed = false;
  bool _celebrated = false;
  int _lastTickBucket = -1;

  double get _shown => _from + _spinAnim.value * (_to - _from);

  @override
  void initState() {
    super.initState();
    _to = widget.calories.toDouble();

    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _spinAnim = CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic);
    _spin.addListener(_tick);
    _spin.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onLanded();
    });

    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    if (!widget.animate) {
      _from = _to;
      _landed = true;
      _spin.value = 1;
    } else {
      Future.delayed(widget.startDelay, () {
        if (mounted && !_landed) _spin.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CalorieReveal old) {
    super.didUpdateWidget(old);
    if (old.calories == widget.calories) return;

    // Still spinning: just aim at the new target, the spin continues.
    if (!_landed) {
      _to = widget.calories.toDouble();
      return;
    }

    // Already landed (e.g. grams edited): glide quietly, no ticks/confetti.
    _from = _shown;
    _to = widget.calories.toDouble();
    _spin.duration = const Duration(milliseconds: 500);
    _spin.forward(from: 0);
  }

  void _tick() {
    if (_landed || !widget.animate) return;
    // One tick per ~4% of the target value -> about 25 ticks that
    // spread out as the curve slows down.
    final step = math.max(1.0, _to / 25);
    final bucket = (_shown / step).floor();
    if (bucket != _lastTickBucket) {
      _lastTickBucket = bucket;
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _onLanded() async {
    if (_landed) return;
    _landed = true;
    HapticFeedback.mediumImpact();
    _pop.forward(from: 0);

    if (_celebrated) return;
    final fits = GoalFit.check(
      calories: widget.calories,
      protein: widget.protein,
    );
    if (fits == true) {
      _celebrated = true;
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) ConfettiCelebration.show(context);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flash = widget.celebrateColor ?? MacroSnapTheme.neonOrange;
    final baseStyle = widget.style.copyWith(
      // Fixed-width digits so the number does not jitter while spinning.
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _pop]),
      builder: (context, _) {
        // Scale bounce: 1 -> 1.14 -> 1
        final p = _pop.value;
        final scale = 1 + 0.14 * math.sin(p * math.pi);

        // Colour flash on landing: base -> accent -> base.
        final base =
            baseStyle.color ??
            DefaultTextStyle.of(context).style.color ??
            Colors.white;
        final color = Color.lerp(base, flash, math.sin(p * math.pi))!;

        return Transform.scale(
          scale: scale,
          child: Text(
            '${_shown.round()}',
            style: baseStyle.copyWith(color: color),
          ),
        );
      },
    );
  }
}
