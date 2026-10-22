import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/habit.dart' show Habit, dateKey;

/// A GitHub-style contribution heatmap showing habit completion
/// consistency as a monthly calendar.
///
/// Shows one month at a time with ◀ ▶ arrows to navigate; each day cell is
/// tinted by how many habits were completed that day (intensity scales with
/// the highest single-day count in the shown month).
class ConsistencyMap extends StatefulWidget {
  final List<Habit> habits;
  final void Function(DateTime date, int count, List<String> habitNames)?
  onCellTap;

  const ConsistencyMap({super.key, required this.habits, this.onCellTap});

  @override
  State<ConsistencyMap> createState() => _ConsistencyMapState();
}

class _ConsistencyMapState extends State<ConsistencyMap> {
  /// The month currently shown (day component is always 1).
  late DateTime _shownMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _shownMonth = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _shownMonth = DateTime(_shownMonth.year, _shownMonth.month + delta);
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _shownMonth.year == now.year && _shownMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now();
    final shownYear = _shownMonth.year;
    final shownMonth = _shownMonth.month;
    final daysInMonth = DateTime(shownYear, shownMonth + 1, 0).day;
    final firstWeekday = DateTime(shownYear, shownMonth, 1).weekday;

    // Leading empty cells so day 1 lands on the correct weekday column.
    final leading = (firstWeekday - 1) % 7;
    final trailing = (7 - ((leading + daysInMonth) % 7)) % 7;
    final totalCells = leading + daysInMonth + trailing;

    // Build a map of dateKey → completion count across all habits.
    final Map<String, int> dailyCount = {};
    int maxCount = 0;
    for (final h in widget.habits) {
      for (final key in h.completedDates) {
        dailyCount[key] = (dailyCount[key] ?? 0) + 1;
        if (dailyCount[key]! > maxCount) maxCount = dailyCount[key]!;
      }
    }
    if (maxCount < 1) maxCount = 1;

    const cellSize = 15.0;
    const cellGap = 3.0;

    Color cellColor(DateTime date) {
      final key = dateKey(date);
      final count = dailyCount[key] ?? 0;
      if (count == 0) {
        return isDark ? const Color(0xFF26262E) : const Color(0xFFEDE9FE);
      }
      final intensity = count / maxCount;
      return Color.lerp(
        MacroSnapTheme.neonGreen.withValues(alpha: 0.3),
        MacroSnapTheme.neonGreen,
        intensity,
      )!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Month header with navigation ───────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous month',
              onTap: () => _shiftMonth(-1),
            ),
            Text(
              '${_monthName(shownMonth)} $shownYear',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            _navButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next month',
              onTap: _isCurrentMonth ? null : () => _shiftMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ─── Weekday labels ──────────────────────────────────
        Row(
          children: List.generate(7, (i) {
            return SizedBox(
              width: cellSize + cellGap,
              child: Text(
                _weekdayAbbr(i),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),

        // ─── Day grid (7 columns, rows grow to fill) ────────
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(totalCells ~/ 7, (rowIndex) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: rowIndex == (totalCells ~/ 7) - 1 ? 0 : cellGap,
                ),
                child: Row(
                  children: List.generate(7, (colIndex) {
                    final cell = rowIndex * 7 + colIndex;
                    final day = cell - leading + 1;
                    final isThisMonth = day >= 1 && day <= daysInMonth;
                    final date = DateTime(shownYear, shownMonth, day);
                    final isToday =
                        isThisMonth &&
                        date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final isFuture = date.isAfter(today);

                    if (!isThisMonth) {
                      return const SizedBox(
                        width: cellSize + cellGap,
                        height: cellSize,
                      );
                    }

                    final count = dailyCount[dateKey(date)] ?? 0;
                    final names = widget.habits
                        .where((h) => h.isCompleted(date))
                        .map((h) => h.emoji + h.name)
                        .toList();

                    return Padding(
                      padding: EdgeInsets.only(
                        right: colIndex == 6 ? 0 : cellGap,
                      ),
                      child: Tooltip(
                        message:
                            '${date.day}/${date.month}/${date.year}: $count/${widget.habits.length} habits',
                        child: GestureDetector(
                          onTap: isFuture
                              ? null
                              : () =>
                                    widget.onCellTap?.call(date, count, names),
                          child: Container(
                            width: cellSize,
                            height: cellSize,
                            decoration: BoxDecoration(
                              color: cellColor(date),
                              borderRadius: BorderRadius.circular(4),
                              border: isToday
                                  ? Border.all(
                                      color: MacroSnapTheme.neonPink,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // ─── Legend ─────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Less',
              style: TextStyle(
                fontSize: 10,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
            const SizedBox(width: 6),
            ...List.generate(5, (i) {
              final intensity = (i * maxCount ~/ 4) / maxCount;
              final Color c = i == 0
                  ? (isDark ? const Color(0xFF26262E) : const Color(0xFFEDE9FE))
                  : Color.lerp(
                      MacroSnapTheme.neonGreen.withValues(alpha: 0.3),
                      MacroSnapTheme.neonGreen,
                      intensity,
                    )!;
              return Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
            const SizedBox(width: 6),
            Text(
              'More',
              style: TextStyle(
                fontSize: 10,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? MacroSnapTheme.textQuaternary(context)
              : MacroSnapTheme.neonGreen,
        ),
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _weekdayAbbr(int index) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[index.clamp(0, 6)];
  }
}
