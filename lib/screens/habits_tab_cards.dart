part of 'habits_tab.dart';

// Split out of habits_tab.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HabitsCards on _HabitsTabState {
  Widget _createButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: () => _onCreateTap(context),
        icon: Icon(
          store.habitLimitReached && !_unlimitedHabits
              ? Icons.lock_rounded
              : Icons.add_rounded,
        ),
        label: Text(
          store.habitLimitReached && !_unlimitedHabits
              ? 'GO PRO FOR UNLIMITED'
              : 'CREATE HABIT',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: store.habitLimitReached && !_unlimitedHabits
              ? MacroSnapTheme.neonPurple
              : MacroSnapTheme.neonGreen,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ─── COIN PILL ─────────────────────────────────────────────
  Widget _coinPill(bool isDark) {
    final coins = store.totalStreakPower;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF303030) : const Color(0xFFE8DEFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: MacroSnapTheme.neonPink,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '$coins',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // ─── HERO CARD ─────────────────────────────────────────────
  Widget _heroCard(double progress, int completed, int total, bool isDark) {
    return Container(
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
                      'Make it count.',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _progressRing(progress, isDark),
            ],
          ),
          const SizedBox(height: 22),
          // Animated fill — glides up as missions are completed.
          AnimatedProgressBar(
            value: progress,
            color: MacroSnapTheme.neonGreen,
            height: 10,
            backgroundColor: isDark ? Colors.white10 : const Color(0xFFE8DEFF),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'Create your first habit'
                      : '$completed of $total missions complete',
                  // Allow wrapping — single-line ellipsis hid the tail of the
                  // count on narrow screens ("4 of 4 mission…").
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
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Streak display (NOT a celebration) — grows with best streak
                    StreakFlame(streak: store.totalStreakPower, fontSize: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${store.totalStreakPower}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : MacroSnapTheme.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressRing(double progress, bool isDark) {
    // Animated fill: ring + % count up on load and glide between values.
    // Track is white24 (not white10) to match the Home calorie ring — the
    // test suite treats the two hero rings as sharing one track color, and
    // white10 left an unreadable ring at 0% progress.
    return AnimatedProgressRing(
      value: progress,
      color: MacroSnapTheme.neonPink,
      backgroundColor: isDark ? Colors.white24 : const Color(0xFFE8DEFF),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w900,
        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
        fontSize: 16,
      ),
    );
  }

  // ─── WATER TRACKER ─────────────────────────────────────────
  Widget _waterCard(double progress, bool isDark) {
    final glasses = store.waterToday;
    final goal = store.waterGoal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('💧', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(
                    'Water Intake',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              Text(
                '$glasses / $goal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.neonCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Water glass icons
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(goal, (i) {
              final filled = i < glasses;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (filled) {
                    store.removeWater();
                  } else {
                    store.addWater();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: filled
                        ? MacroSnapTheme.neonCyan.withValues(alpha: 0.2)
                        : (isDark
                              ? const Color(0xFF303030)
                              : const Color(0xFFE8DEFF)),
                    borderRadius: BorderRadius.circular(10),
                    border: filled
                        ? Border.all(
                            color: MacroSnapTheme.neonCyan.withValues(
                              alpha: 0.4,
                            ),
                          )
                        : null,
                  ),
                  child: Icon(
                    filled
                        ? Icons.water_drop_rounded
                        : Icons.water_drop_outlined,
                    color: filled
                        ? MacroSnapTheme.neonCyan
                        : (MacroSnapTheme.textQuaternary(context)),
                    size: 18,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Progress bar (animated fill)
          AnimatedProgressBar(
            value: progress,
            color: MacroSnapTheme.neonCyan,
            height: 6,
            backgroundColor: isDark
                ? const Color(0xFF303030)
                : const Color(0xFFE8DEFF),
          ),
        ],
      ),
    );
  }

  // ─── SWIPE BACKGROUND ──────────────────────────────────────

  // ─── CONSISTENCY MAP CARD ─────────────────────────────────
  Widget _consistencyMapCard(bool isDark) {
    final active = store.habits.where((h) => !h.paused).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: MacroSnapTheme.neonGreen,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Consistency',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                '${active.length} habits',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Create habits to see your consistency map',
                  style: TextStyle(
                    fontSize: 13,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            )
          else
            ConsistencyMap(
              habits: active,
              onCellTap: (date, count, names) =>
                  _showDayDetail(date, count, names),
            ),
        ],
      ),
    );
  }

  // ─── HABIT LIMIT CARD ─────────────────────────────────────
  Widget _habitLimitCard(bool isDark) {
    final used = store.habits.length;
    final limit = HabitStore.freeHabitLimit;
    final pct = (used / limit).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: used >= limit
                    ? MacroSnapTheme.neonOrange
                    : MacroSnapTheme.successGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Habit Limit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Text(
                '$used / $limit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: used >= limit
                      ? MacroSnapTheme.neonOrange
                      : MacroSnapTheme.greenText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedProgressBar(
            value: pct,
            height: 6,
            backgroundColor: isDark
                ? const Color(0xFF303030)
                : const Color(0xFFE8DEFF),
            color: used >= limit
                ? MacroSnapTheme.neonOrange
                : MacroSnapTheme.successGreen,
          ),
          const SizedBox(height: 10),
          Text(
            used >= limit
                ? 'Upgrade to Pro for unlimited habits'
                : '${limit - used} habit${limit - used == 1 ? '' : 's'} remaining on Free',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MacroSnapTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _emptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '✨',
            style: TextStyle(
              fontSize: 40,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Start your rhythm',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'No missions scheduled for today. Tap above to create one!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
