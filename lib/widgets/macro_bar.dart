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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
            Text(
              '${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}$unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textTertiary(context),
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
