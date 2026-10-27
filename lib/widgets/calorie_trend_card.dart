import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/meal_store.dart';
import 'pro_badge.dart';

/// Calorie trend card for Home — a 7- or 30-day bar chart of daily calorie
/// intake with a dashed goal line, fed live from [MealStore].
///
/// This is the app's first fl_chart consumer: the package sat unused in
/// pubspec (dead APK weight) until now. All fl_chart APIs used here were
/// verified against the locked 0.70.2 version.
class CalorieTrendCard extends StatefulWidget {
  final int goalCalories;

  const CalorieTrendCard({super.key, this.goalCalories = 2000});

  @override
  State<CalorieTrendCard> createState() => _CalorieTrendCardState();
}

class _CalorieTrendCardState extends State<CalorieTrendCard> {
  /// 7 or 30 days. Seven is the default — a readable bar count on a phone.
  int _days = 7;

  /// Daily calorie sums for the last [_days] days, keyed by calendar-day
  /// midnight (oldest first — the map is built in ascending day order).
  Map<DateTime, int> _dailyTotals() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final totals = <DateTime, int>{};
    for (var i = _days - 1; i >= 0; i--) {
      totals[today.subtract(Duration(days: i))] = 0;
    }
    for (final m in MealStore.instance.allMeals) {
      final day = DateTime(m.date.year, m.date.month, m.date.day);
      if (totals.containsKey(day)) {
        totals[day] = (totals[day] ?? 0) + m.calories;
      }
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      // Rebuilds whenever a meal is logged or removed.
      child: ValueListenableBuilder<int>(
        valueListenable: MealStore.instance.changeNotifier,
        builder: (context, _, _) {
          final totals = _dailyTotals();
          final days = totals.keys.toList();
          final values = totals.values.toList();
          final maxCal = values.fold(0, (m, v) => v > m ? v : m);
          final hasData = values.any((v) => v > 0);

          return Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            decoration: MacroSnapTheme.glassDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Calorie trend',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Weekly auto-insights are sold as part of Pro, so the
                    // card says so wherever it appears.
                    const ProBadge(),
                    const Spacer(),
                    _rangeToggle(isDark),
                  ],
                ),
                const SizedBox(height: 14),
                if (!hasData)
                  SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        'Log a meal to start your trend',
                        style: TextStyle(
                          fontSize: 13,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ),
                  )
                else ...[
                  Semantics(
                    label:
                        'Bar chart of daily calories for the last '
                        '$_days days. Dashed line marks the '
                        '${widget.goalCalories} calorie goal.',
                    excludeSemantics: true,
                    child: SizedBox(
                      height: 150,
                      child: BarChart(
                        _barData(days, values, maxCal, isDark),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Mini legend: the dashed goal line.
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 2,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.textTertiary(context),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Goal ${widget.goalCalories} kcal',
                        style: TextStyle(
                          fontSize: 11,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 7D / 30D segmented control, styled with the brand accent.
  Widget _rangeToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [7, 30].map((d) {
          final selected = _days == d;
          return GestureDetector(
            onTap: () => setState(() => _days = d),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? MacroSnapTheme.neonGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${d}D',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (isDark ? Colors.black : Colors.white)
                      : MacroSnapTheme.textSecondary(context),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  BarChartData _barData(
    List<DateTime> days,
    List<int> values,
    int maxCal,
    bool isDark,
  ) {
    final goal = widget.goalCalories;
    // Nice ceiling: the bigger of today's peak and the goal, padded so bars
    // never touch the plot top and the goal line always sits inside it.
    final top = ((maxCal > goal ? maxCal : goal) * 1.15 / 100).ceil() * 100;
    final rodWidth = _days == 7 ? 18.0 : 6.0;

    return BarChartData(
      maxY: top.toDouble(),
      minY: 0,
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: rodWidth,
                borderRadius: BorderRadius.circular(4),
                gradient: MacroSnapTheme.accentGradient,
              ),
            ],
          ),
      ],
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: (top / 2).toDouble(),
        getDrawingHorizontalLine: (v) =>
            FlLine(color: MacroSnapTheme.borderSubtle(context), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: goal.toDouble(),
            color: MacroSnapTheme.textTertiary(context),
            strokeWidth: 1.5,
            dashArray: [5, 5],
          ),
        ],
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          // fl_chart 0.70.2's GetBarTooltipColor takes ONLY the group.
          getTooltipColor: (group) =>
              isDark ? MacroSnapTheme.cardDarkLight : const Color(0xFF2B2B2B),
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final day = days[group.x];
            final label = _days == 7
                ? _weekdayLetter(day)
                : '${day.day}/${day.month}';
            return BarTooltipItem(
              '$label • ${rod.toY.round()} kcal',
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= days.length) return const SizedBox.shrink();
              // 30 cramped labels would be unreadable — every 5th day + today.
              if (_days == 30 && i % 5 != 0 && i != days.length - 1) {
                return const SizedBox.shrink();
              }
              final day = days[i];
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _days == 7 ? _weekdayLetter(day) : '${day.day}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Single-letter weekday label (M T W T F S S) for compact axes.
  String _weekdayLetter(DateTime d) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
}
