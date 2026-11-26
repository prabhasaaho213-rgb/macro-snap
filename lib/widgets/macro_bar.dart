import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'animations.dart';

/// A single macro progress bar: dot + label on the left, `value / target`
/// on the right, animated fill underneath.
class MacroBar extends StatelessWidget {
  const MacroBar(
    this.label,
    this.value,
    this.target,
    this.color,
    this.isDark,
    this.unit, {
    super.key,
  });

  final String label;
  final double value;
  final double target;
  final Color color;
  final bool isDark;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final pct = (value / max(target, 1)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dot, label and value share ONE Row.
        //
        // The label used to sit in a nested Row with a Flexible inside it, and
        // that nested Row was a non-flex child of this one — so Flutter handed
        // it unbounded width and the Flexible asserted on every build:
        // "RenderFlex children have non-zero flex but incoming width
        // constraints are unbounded". A single Row with flexible children lays
        // out inside whatever width the card gives it.
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textSecondary(context),
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Expanded, not Flexible: both flex children split the free width
            // 50/50, and a loose Text only takes its intrinsic width — so the
            // grams value began at the card's midpoint and left a gap after
            // it, which is the "grams text aligned to the middle" report.
            // Expanded gives it the right half and textAlign.end puts the
            // number flush against the card's edge.
            Expanded(
              child: Text(
                '${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}$unit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedProgressBar(value: pct, color: color, height: 8),
      ],
    );
  }
}
