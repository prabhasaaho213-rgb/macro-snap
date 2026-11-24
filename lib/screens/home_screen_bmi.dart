part of 'home_screen.dart';

// Split out of home_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HomeBmi on _HomeScreenState {
  // ─── BMI CARD (Habitly style) ────────────────────────────
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
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          // BMI is a Pro feature: free users land on the paywall instead of
          // the calculator — same rule as the AI meal plan. The card still
          // shows their current number as the teaser. unlocksPro() also
          // admits the admin's lifetime grant, so the owner never sees the
          // paywall here.
          if (!await SubscriptionService.instance.unlocksPro()) {
            if (!context.mounted) return;
            await Navigator.push(
              context,
              habitFlowRoute(const SubscriptionScreen()),
            );
            return;
          }
          if (!context.mounted) return;
          await Navigator.push(context, habitFlowRoute(const BmiScreen()));
          // The calculator can save a new weight — repaint with it.
          if (mounted) _rebuild(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(20),
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
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                            if (!SubscriptionService.instance.isSubscribed)
                              // ProBadge audit: Pro marks must all be ONE shared
                              // chip, not a screen-invented orange variant.
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                child: const ProBadge(),
                              ),
                          ],
                        ),
                        Text(
                          profile == null
                              ? 'Add your height & weight'
                              : '${BmiCalculator.formatHeight(profile.heightCm)} · ${profile.weightKg.toStringAsFixed(profile.weightKg % 1 == 0 ? 0 : 1)} kg',
                          style: TextStyle(
                            fontSize: 13,
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
