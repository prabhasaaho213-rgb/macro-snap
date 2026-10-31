part of 'home_screen.dart';

// Split out of home_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HomeCalories on _HomeScreenState {
  // ─── HERO CALORIE CARD (Habitly Hero style) ────────────────
  Widget _buildCalorieRing(BuildContext context, bool isDark) {
    final profile = DietPlanService.instance.profile;
    final targetCal = profile?.targetCalories ?? 2000;
    final consumed = MealStore.instance.todayCalories;
    final progress = (consumed / targetCal).clamp(0.0, 1.0);

    // 🎉 Detect: calorie goal just met → confetti celebration!
    final goalMet = consumed >= targetCal;
    if (goalMet && !_previousGoalMet && targetCal > 0) {
      _previousGoalMet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ConfettiCelebration.show(context);
      });
    } else if (!goalMet) {
      _previousGoalMet = false;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: MacroSnapTheme.habitlyHeroCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : MacroSnapTheme.textTertiary(context),
                          fontSize: 12,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Calorie goal',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Progress ring (Habitly style) — animated fill: the ring
                // and the % label count up from 0 on load and glide between
                // values (adding a meal grows it smoothly, never a jump).
                //
                // The arc is the brand accent, not neonPink: the old dark
                // rose (0xFFB0281F) sat almost invisibly on the violet hero
                // gradient, and the white10 track was so faint that at 0% the
                // ring looked like an unrendered circle. white24 keeps the
                // track readable so the ring always reads as a ring.
                AnimatedProgressRing(
                  value: progress,
                  color: MacroSnapTheme.neonGreen,
                  backgroundColor: isDark
                      ? Colors.white24
                      : const Color(0xFFE8DEFF),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Animated fill — glides up as meals are logged instead of
            // snapping to the value.
            AnimatedProgressBar(
              value: progress,
              color: MacroSnapTheme.neonGreen,
              height: 10,
              backgroundColor: isDark
                  ? Colors.white10
                  : const Color(0xFFE8DEFF),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${consumed.toInt()} of ${targetCal.toInt()} kcal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? Colors.white70
                          : MacroSnapTheme.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // The flame replaces the "N left" figure: the left side
                // already states "0 of 2546 kcal", so the right side now
                // carries the same streak mark the Habits tab draws, read
                // from the same source so the two tabs can never disagree.
                StreakFlame(
                  streak: HabitStore.instance.totalStreakPower,
                  fontSize: 15,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── MACRO BARS (Habitly style) ─────────────────────────────
  Widget _buildMacroBars(BuildContext context, bool isDark) {
    final p = MealStore.instance.todayProtein;
    final c = MealStore.instance.todayCarbs;
    final f = MealStore.instance.todayFats;
    final profile = DietPlanService.instance.profile;
    final targetP = profile?.targetProtein ?? 150;
    final targetC = profile?.targetCarbs ?? 300;
    final targetF = profile?.targetFats ?? 67;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Macronutrients',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const Spacer(),
                if (p + c + f > 0)
                  Flexible(
                    child: Text(
                      '${(p / max(p + c + f, 1) * 100).round()}% P · ${(c / max(p + c + f, 1) * 100).round()}% C · ${(f / max(p + c + f, 1) * 100).round()}% F',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            MacroBar(
              'Protein',
              p,
              targetP,
              MacroSnapTheme.neonPink,
              isDark,
              'g',
            ),
            const SizedBox(height: 14),
            MacroBar(
              'Carbs',
              c,
              targetC,
              MacroSnapTheme.neonOrange,
              isDark,
              'g',
            ),
            const SizedBox(height: 14),
            MacroBar('Fats', f, targetF, MacroSnapTheme.neonCyan, isDark, 'g'),
          ],
        ),
      ),
    );
  }
}
