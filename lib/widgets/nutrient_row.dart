import 'package:flutter/material.dart';
import '../core/theme.dart';

/// One nutrient line: coloured dot, label, then `value unit` right-aligned.
class NutrientRow extends StatelessWidget {
  const NutrientRow(
    this.label,
    this.value,
    this.unit,
    this.color,
    this.isDark, {
    super.key,
  });

  final String label;
  final num value;
  final String unit;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(value is int ? 0 : 1)} $unit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
