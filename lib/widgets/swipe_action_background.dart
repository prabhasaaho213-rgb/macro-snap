import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The coloured background revealed while a habit tile is swiped:
/// green check for complete, red undo for the other direction.
class SwipeActionBackground extends StatelessWidget {
  const SwipeActionBackground({super.key, required this.rightSwipe});

  /// True for the complete gesture, false for undo.
  final bool rightSwipe;

  @override
  Widget build(BuildContext context) {
    // Distinct states: complete is green, undo is red. Both sides used to
    // resolve to the same orange (neonGreen is the brand accent), so the two
    // actions read identically.
    final color = rightSwipe
        ? MacroSnapTheme.successGreen
        : MacroSnapTheme.neonRed;
    final icon = rightSwipe ? Icons.check_circle_rounded : Icons.undo_rounded;
    final label = rightSwipe ? 'Complete' : 'Undo';
    return Container(
      decoration: BoxDecoration(
        color: color,
        // Full-bleed square: the outer ClipRRect(28) owns the tile's rounding.
        // A square reveal sits flush under the moving card's rounded corners
        // at every drag position, so the card's corner cutout always shows
        // reveal color — never a dark gap or the page background.
      ),
      alignment: rightSwipe ? Alignment.centerRight : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: rightSwipe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!rightSwipe) ...[
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ] else ...[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, color: Colors.white, size: 28),
          ],
        ],
      ),
    );
  }
}
