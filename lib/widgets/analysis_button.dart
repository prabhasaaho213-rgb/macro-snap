import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../screens/activity_analysis_screen.dart';
import 'animations.dart';

// Re-exported so a card only has to import this button to name a section.
export '../screens/activity_analysis_screen.dart' show AnalysisSection;

/// The little "insights" button that sits on an activity card (meals, habits,
/// water, steps, weight) and opens [ActivityAnalysisScreen] already scrolled to
/// that activity.
///
/// It is deliberately small and quiet: the card itself stays the primary tap
/// target, so this only adds a shortcut for "show me the numbers behind this".
class AnalysisButton extends StatelessWidget {
  const AnalysisButton({
    super.key,
    required this.section,
    this.onDark = false,
  });

  /// Which activity the analysis screen should focus on.
  final AnalysisSection section;

  /// Set on cards with a saturated background (the steps hero), where the
  /// tinted-on-light style would disappear.
  final bool onDark;

  Color get _color => switch (section) {
    AnalysisSection.nutrition => MacroSnapTheme.neonOrange,
    AnalysisSection.habits => MacroSnapTheme.neonGreen,
    AnalysisSection.water => MacroSnapTheme.neonPurple,
    AnalysisSection.movement => MacroSnapTheme.neonCyan,
    AnalysisSection.weight => MacroSnapTheme.neonOrange,
  };

  String get _label => switch (section) {
    AnalysisSection.nutrition => 'Nutrition analysis',
    AnalysisSection.habits => 'Habits analysis',
    AnalysisSection.water => 'Water analysis',
    AnalysisSection.movement => 'Steps analysis',
    AnalysisSection.weight => 'Weight analysis',
  };

  @override
  Widget build(BuildContext context) {
    final tint = onDark ? Colors.white : _color;
    return Semantics(
      button: true,
      label: _label,
      child: Tooltip(
        message: _label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.light();
            Navigator.push(
              context,
              habitFlowRoute(ActivityAnalysisScreen(focus: section)),
            );
          },
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: onDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.insights_rounded,
              size: 16,
              color: onDark ? Colors.white : tint,
            ),
          ),
        ),
      ),
    );
  }
}
