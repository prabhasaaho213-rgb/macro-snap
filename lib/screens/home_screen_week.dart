part of 'home_screen.dart';

// Split out of home_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HomeWeek on _HomeScreenState {
  // ─── WEEK STRIP (Habitly style) ────────────────────────────
  Widget _buildWeekStrip(BuildContext context, bool isDark) {
    final meals = MealStore.instance.allMeals;
    final now = DateTime.now();
    final dayMeals = <String, List<MealRecord>>{};
    for (final m in meals) {
      final key = '${m.date.year}-${m.date.month}-${m.date.day}';
      dayMeals.putIfAbsent(key, () => []).add(m);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'This Week',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                ScaleOnPress(
                  onTap: () async {
                    // Branded card image first; the text summary is the
                    // fallback when there is nothing to render a card from.
                    var shared = await ShareService.shareWeeklyCard(context);
                    if (!shared) shared = await ShareService.shareWeekSummary();
                    if (!shared && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'No meals logged this week yet. Log a meal to share your progress!',
                          ),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.share_rounded,
                      size: 16,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final d = DateTime(now.year, now.month, now.day - (6 - i));
                final key = '${d.year}-${d.month}-${d.day}';
                final dayList = dayMeals[key] ?? [];
                final logged = dayList.isNotEmpty;
                final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                final isToday =
                    d.day == now.day &&
                    d.month == now.month &&
                    d.year == now.year;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      days[d.weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? MacroSnapTheme.greenText(context)
                            : (MacroSnapTheme.textTertiary(context)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: logged
                            ? MacroSnapTheme.neonGreen.withValues(alpha: 0.2)
                            : (isDark
                                  ? const Color(0xFF303030)
                                  : const Color(0xFFE8DEFF)),
                        border: isToday
                            ? Border.all(
                                color: MacroSnapTheme.neonGreen,
                                width: 2,
                              )
                            : null,
                      ),
                      child: Center(
                        child: logged
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: MacroSnapTheme.neonGreen,
                              )
                            : Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: MacroSnapTheme.textQuaternary(context),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (dayList.isNotEmpty)
                      Text(
                        '${dayList.fold(0, (s, m) => s + m.calories)}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: MacroSnapTheme.greenText(
                            context,
                          ).withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ─── BMI CARD ──────────────────────────────────────────
  // A compact read of the user's own BMI (weight/height from the diet
  // profile) that opens the full calculator. Kept on Home because weight is
  // something people check far more often than they change their plan.
  Widget _buildBmiCard(BuildContext context, bool isDark) {
    final profile = DietPlanService.instance.profile;
    final bmi = profile == null
        ? null
        : BmiCalculator.value(
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
          );
    // Same rounding rule as the calculator: the band must match the digits on
    // screen, not the unrounded value behind them.
    final shownBmi = bmi == null ? null : BmiCalculator.displayValue(bmi);
    final category = shownBmi == null
        ? null
        : BmiCalculator.categoryFor(shownBmi);
    final accent = category?.color ?? MacroSnapTheme.neonCyan;
    // The trend is the point of keeping a history: a single BMI number tells
    // you where you are, the line tells you which way you're going.
    final trend = WeightStore.instance.summary(days: 30);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          // BMI is a Pro feature: free users land on the paywall instead of
          // the calculator — same rule as the AI meal plan. The card still
          // shows their current number as the teaser.
          if (!SubscriptionService.instance.isSubscribed) {
            await Navigator.push(
              context,
              habitFlowRoute(const SubscriptionScreen()),
            );
            return;
          }
          await Navigator.push(context, habitFlowRoute(const BmiScreen()));
          // The calculator can save a new weight — repaint with it.
          if (mounted) _rebuild(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: MacroSnapTheme.habitlyCard(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.speed_rounded, size: 21, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'BMI',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                            if (!SubscriptionService.instance.isSubscribed)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: MacroSnapTheme.neonOrange
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'PRO',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                    color: MacroSnapTheme.neonOrange,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          profile == null
                              ? 'Add your height & weight'
                              : '${BmiCalculator.formatHeight(profile.heightCm)} · ${profile.weightKg.toStringAsFixed(profile.weightKg % 1 == 0 ? 0 : 1)} kg',
                          style: TextStyle(
                            fontSize: 12,
                            color: MacroSnapTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        shownBmi == null ? '—' : shownBmi.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: accent,
                        ),
                      ),
                      if (category != null)
                        Text(
                          category.label.replaceAll('Underweight', 'Under'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (bmi != null) ...[
                const SizedBox(height: 14),
                BmiBandBar(bmi: bmi, height: 7),
              ],
              if (trend.points.length >= 2) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: WeightTrendChart(
                        points: trend.points,
                        height: 44,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    _trendChip(context, trend),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    bmi == null ? 'Tap to calculate' : 'Open calculator',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Direction-of-travel readout beside the sparkline: signed delta over the
  /// window, with a coloured arrow that matches what it means.
  Widget _trendChip(BuildContext context, WeightSummary trend) {
    final delta = trend.deltaKg;
    final direction = trend.direction;
    final color = switch (direction) {
      WeightTrend.losing => MacroSnapTheme.successGreen,
      WeightTrend.gaining => MacroSnapTheme.neonOrange,
      WeightTrend.holding => MacroSnapTheme.textTertiary(context),
    };
    final icon = switch (direction) {
      WeightTrend.losing => Icons.trending_down_rounded,
      WeightTrend.gaining => Icons.trending_up_rounded,
      WeightTrend.holding => Icons.trending_flat_rounded,
    };
    // Under 300 g is scale noise, so it is shown as flat rather than a fake
    // up or down — the number is still printed if it exists.
    final deltaLabel = delta == null
        ? ''
        : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg';
    final period = trend.spanDays > 0 ? '· ${trend.spanDays}d' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              deltaLabel.isEmpty ? 'No change' : deltaLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          period.isEmpty ? '30 days' : period,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
      ],
    );
  }
}
