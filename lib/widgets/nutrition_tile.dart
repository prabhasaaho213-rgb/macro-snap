import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The small pencil that opens an editor, used on every editable value of the
/// result card (title, health score, each macro).
///
/// A full-size IconButton is 48×48 and would dominate a 2×2 grid of tiles, so
/// this is a compact tap target that still meets the 32 px minimum recommended
/// for a secondary action — and it carries a semantic label, so a screen
/// reader announces "Edit protein" instead of an unlabelled icon.
class EditPencil extends StatelessWidget {
  const EditPencil({super.key, required this.onTap, required this.semanticLabel});

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        containedInkWell: false,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.edit_outlined,
            size: 13,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
      ),
    );
  }
}

/// One cell of the 2×2 macro grid: label with a pencil, then the value, unit
/// and a tinted icon.
///
/// Sized by its parent grid rather than by its content, so the four tiles stay
/// the same height even when one value is four digits.
class NutritionTile extends StatelessWidget {
  const NutritionTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    this.onEdit,
    this.valueWidget,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  /// Null in read-only mode (a meal that is already logged).
  final VoidCallback? onEdit;

  /// Replaces the plain [value] text — used by the calories tile, which keeps
  /// the slot-machine reveal instead of printing a static number. The reveal
  /// only scales the text (it does not change the layout box), so the tile
  /// still sizes exactly like its three neighbours.
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
              if (onEdit != null)
                EditPencil(onTap: onEdit!, semanticLabel: 'Edit $label'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child:
                            valueWidget ??
                            Text(
                              value,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Health Score: 4/5" with the tick that makes it read as a verdict rather
/// than another number.
class HealthScorePill extends StatelessWidget {
  const HealthScorePill({
    super.key,
    required this.score,
    required this.max,
    required this.label,
    this.onEdit,
  });

  final int score;
  final int max;
  final String label;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    // Full marks and a poor score must not look the same at a glance: green
    // for an excellent dish, amber for the middle, orange for a heavy one.
    final color = score >= 5
        ? MacroSnapTheme.successGreen
        : score >= 4
        ? MacroSnapTheme.neonGreen
        : MacroSnapTheme.neonOrange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          'Health Score: ',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: MacroSnapTheme.textSecondary(context),
          ),
        ),
        Text(
          '$score/$max',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '· $label',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
        if (onEdit != null)
          EditPencil(onTap: onEdit!, semanticLabel: 'Edit health score'),
      ],
    );
  }
}
