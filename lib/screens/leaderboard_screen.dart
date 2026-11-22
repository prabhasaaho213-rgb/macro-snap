import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/leaderboard_service.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';

/// Fitness points — what the user earned this week, where those points came
/// from, and the leaderboard scopes they will rank in.
///
/// Opened only from Home's Quick Actions: this is a "how am I doing" page, not
/// a fifth tab, and it should not compete with Home, Scan, Habits or Health.
///
/// Points are computed by [LeaderboardService] from the app's own stores, so
/// the numbers here are never a separate copy that can drift from the meal log,
/// the habits, the water log, a weigh-in or the step count.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LeaderboardService get _service => LeaderboardService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _service.load();
    // Re-reads today from the stores: opening the page after a meal logged on
    // another tab must show that meal's points, not the ones from last open.
    await _service.sync();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Leaderboard',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () {
              unawaited(Haptics.light());
              unawaited(_refresh());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: MacroSnapTheme.neonGreen,
        backgroundColor: isDark
            ? MacroSnapTheme.cardDark
            : MacroSnapTheme.surfaceLight,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            AnimatedEntrance(delayMs: 20, child: _buildHero(context, isDark)),
            const SizedBox(height: 14),
            AnimatedEntrance(delayMs: 70, child: _buildWeekStrip(context, isDark)),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 120,
              child: _buildBreakdown(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 170,
              child: _buildRankings(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(delayMs: 210, child: _buildRules(context, isDark)),
          ],
        ),
      ),
    );
  }

  /// This week's total, today's total and the active-day streak.
  Widget _buildHero(BuildContext context, bool isDark) {
    final week = _service.weekPoints;
    final today = _service.todayPoints;
    final streak = _service.activeStreak;
    final possible = LeaderboardService.dailyMax * 7;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'THIS WEEK',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (streak > 0)
                Text(
                  '$streak-day streak 🔥',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedValue(
                target: week.toDouble(),
                duration: const Duration(milliseconds: 700),
                builder: (context, v) => Text(
                  '${v.round()}',
                  style: const TextStyle(
                    fontSize: 52,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'pts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'of $possible possible this week',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: possible == 0 ? 0 : (week / possible).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.today_rounded,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                '$today points today',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Monday..Sunday strip: which days paid, and how much.
  Widget _buildWeekStrip(BuildContext context, bool isDark) {
    final week = _service.currentWeek;
    final today = DateTime.now();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (:date, :points) in week)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: points.isEmpty
                              ? MacroSnapTheme.borderSubtle(
                                  context,
                                ).withValues(alpha: 0.35)
                              : MacroSnapTheme.neonGreen.withValues(
                                  alpha: 0.16,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _sameDay(date, today)
                                ? MacroSnapTheme.neonGreen
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${points.total}',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: points.isEmpty
                                    ? MacroSnapTheme.textTertiary(context)
                                    : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'pts',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: MacroSnapTheme.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _weekdayLetter(date.weekday),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _sameDay(date, today)
                              ? MacroSnapTheme.neonGreen
                              : MacroSnapTheme.textTertiary(context),
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

  /// Where today's points came from, against each bucket's daily ceiling.
  Widget _buildBreakdown(BuildContext context, bool isDark) {
    final points = _service.dayPoints(DateTime.now());
    final rows = <({IconData icon, Color colour, String label, String hint, int value, int cap})>[
      (
        icon: Icons.directions_walk_rounded,
        colour: MacroSnapTheme.neonCyan,
        label: 'Movement',
        hint: 'Daily step goal reached',
        value: points.movement,
        cap: LeaderboardService.stepGoalDailyCap,
      ),
      (
        icon: Icons.restaurant_rounded,
        colour: MacroSnapTheme.neonPurple,
        label: 'Nutrition',
        hint: 'Meals logged + calorie goal',
        value: points.nutrition,
        cap: LeaderboardService.nutritionDailyCap,
      ),
      (
        icon: Icons.checklist_rounded,
        colour: MacroSnapTheme.neonGreen,
        label: 'Habits',
        hint: 'Completed habits',
        value: points.habits,
        cap: LeaderboardService.habitDailyCap,
      ),
      (
        icon: Icons.water_drop_rounded,
        colour: MacroSnapTheme.neonCyan,
        label: 'Hydration',
        hint: 'Water logged + daily goal',
        value: points.hydration,
        cap: LeaderboardService.hydrationDailyCap,
      ),
      (
        icon: Icons.monitor_weight_rounded,
        colour: MacroSnapTheme.neonOrange,
        label: 'Body',
        hint: 'A weigh-in',
        value: points.body,
        cap: LeaderboardService.weighInPoints,
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Today's points",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Text(
                '${points.total} / ${LeaderboardService.dailyMax}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: row.colour.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(row.icon, size: 17, color: row.colour),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              row.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                row.hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: MacroSnapTheme.textTertiary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: row.cap == 0
                                ? 0
                                : (row.value / row.cap).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: MacroSnapTheme.borderSubtle(
                              context,
                            ).withValues(alpha: 0.5),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              row.colour,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${row.value}/${row.cap}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: row.value >= row.cap
                          ? row.colour
                          : MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The ranking scopes.
  ///
  /// Deliberately honest: the shared scoreboard needs the server-side scoring
  /// endpoint (weekly totals per district / state / India), which this build
  /// does not have yet. Rather than invent a rank, the page says so — the
  /// points themselves are already being counted and kept.
  Widget _buildRankings(BuildContext context, bool isDark) {
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.public_rounded,
                size: 18,
                color: MacroSnapTheme.textTertiary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Rankings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: titleColour,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final scope in const ['District', 'State', 'India'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.borderSubtle(
                        context,
                      ).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      scope,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: MacroSnapTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rankings go live once leaderboard sync is enabled. Your points '
            'are already counted on this phone, so nothing you earn today is '
            'lost — it uploads as soon as the shared scoreboard is switched on.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// What pays, how much, and how often — the same table the scoring code uses.
  Widget _buildRules(BuildContext context, bool isDark) {
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final rules = <({String label, String points, String limit})>[
      (label: 'Reach your step goal', points: '+20', limit: 'once a day'),
      (label: 'Log a meal', points: '+10', limit: 'up to 3 meals'),
      (label: 'Meet your calorie goal', points: '+10', limit: 'once a day'),
      (label: 'Complete a habit', points: '+5', limit: 'up to 3 habits'),
      (label: 'Record a weigh-in', points: '+5', limit: 'once a day'),
      (label: 'Reach your water goal', points: '+5', limit: 'once a day'),
      (label: 'Log a glass of water', points: '+1', limit: 'up to 5'),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How points work',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: titleColour,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Points are for doing the habits, not for eating less or losing '
            'weight. Editing or deleting a logged action never pays twice.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF3A3A3A),
                      ),
                    ),
                  ),
                  Text(
                    rule.points,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(
                      rule.limit,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _weekdayLetter(int weekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
