import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../models/habit.dart';
import '../services/habit_store.dart';
import '../services/health_service.dart';
import '../services/meal_store.dart';
import '../services/step_counter_service.dart';
import '../services/step_goal_service.dart';
import '../services/step_limit.dart';
import '../services/weight_store.dart';

/// One card of the analysis page. The same enum is the scroll target of the
/// page and the argument the per-activity insight buttons pass in, so "open
/// the analysis of my water" and "show me everything" are the same screen.
enum AnalysisSection { nutrition, habits, water, movement, weight }

/// One place that answers "how am I doing?" across EVERY activity the app
/// tracks — food, habits, water, movement and weight — instead of making the
/// user visit five different cards to add the numbers up themselves.
///
/// Everything here is read from the stores the rest of the app already writes,
/// so the analysis can never disagree with the numbers shown elsewhere. It is
/// deliberately read-only: this is a summary, not another logging surface.
class ActivityAnalysisScreen extends StatefulWidget {
  const ActivityAnalysisScreen({super.key, this.focus});

  /// When set, the page opens scrolled to that activity's card and outlines it,
  /// so this screen serves both as the whole-day summary (Quick Actions) and as
  /// a per-activity drill-down (the insight buttons on each card).
  final AnalysisSection? focus;

  @override
  State<ActivityAnalysisScreen> createState() => _ActivityAnalysisScreenState();
}

class _ActivityAnalysisScreenState extends State<ActivityAnalysisScreen> {
  bool _loading = true;
  HealthToday? _health;

  /// Scroll targets for the focused card. Every section gets one so the page
  /// can also be focused after the fact without rebuilding keys.
  final Map<AnalysisSection, GlobalKey> _keys = {
    for (final section in AnalysisSection.values) section: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Each store is loaded defensively: one unavailable source (a missing
    // profile, a health platform that is not installed) must not blank the
    // whole analysis.
    try {
      await MealStore.instance.load();
    } catch (_) {}
    try {
      await HabitStore.instance.load();
    } catch (_) {}
    try {
      await WeightStore.instance.load();
    } catch (_) {}
    try {
      await DietPlanService.instance.load();
    } catch (_) {}
    try {
      _health = await HealthService.instance.fetchToday();
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      _scrollToFocus();
    }
  }

  /// Brings the focused activity's card into view once it has been laid out.
  void _scrollToFocus() {
    final section = widget.focus;
    if (section == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[section]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  GlobalKey _keyFor(AnalysisSection section) => _keys[section]!;

  /// One distinct colour per activity.
  ///
  /// The palette names lie: `neonGreen` is the SAME value as `neonOrange`
  /// (0xFFFF6B2B, "kept name for API compat") and `neonCyan` is a lighter
  /// violet. Reading them by name painted Nutrition, Habits and Weight the
  /// same orange and Water and Movement the same violet — five sections, three
  /// colours. These are the tokens that actually differ.
  Color _sectionColor(AnalysisSection section) => switch (section) {
    AnalysisSection.nutrition => MacroSnapTheme.neonOrange,
    AnalysisSection.habits => MacroSnapTheme.successGreen,
    AnalysisSection.water => MacroSnapTheme.neonPurple,
    AnalysisSection.movement => MacroSnapTheme.activityCyan,
    AnalysisSection.weight => MacroSnapTheme.neonYellow,
  };

  // ─── Date helpers ────────────────────────────────────────────────────────

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Primary text colour. `MacroSnapTheme` exposes the muted variant only, so
  /// this mirrors the `isDark ? white : near-black` choice used on Home.
  Color _primary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF1A1A1A);

  static List<DateTime> get _weekDays {
    final today = _dayOnly(DateTime.now());
    return List<DateTime>.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );
  }

  // ─── Derived numbers ─────────────────────────────────────────────────────

  int _caloriesOn(DateTime day) => MealStore.instance.allMeals
      .where((m) => _dayOnly(m.date) == day)
      .fold(0, (sum, m) => sum + m.calories);

  /// Habit completions across all habits for one day.
  int _habitsDoneOn(DateTime day) =>
      HabitStore.instance.habits.where((h) => h.isCompleted(day)).length;

  double? get _weightDeltaKg {
    final entries = WeightStore.instance.entries;
    if (entries.length < 2) return null;
    final cutoff = _dayOnly(DateTime.now()).subtract(const Duration(days: 7));
    final recent = entries.where((e) => !e.date.isBefore(cutoff)).toList();
    if (recent.length < 2) return null;
    return recent.last.kg - recent.first.kg;
  }

  /// Today's steps from whichever source has the higher count.
  ///
  /// This page used to read Health Connect only, so a user whose steps come
  /// from the phone's own sensor — the Health tab's primary source — was told
  /// "Not connected" while thousands of steps were already counted. Both
  /// numbers are capped for a free account, so the two sources mean the same
  /// thing here and on the dashboard.
  int? get _stepsNow {
    final sensor = StepCounterService.instance.todaySteps;
    final health = _health?.steps;
    final cappedHealth = health == null ? null : StepLimit.cap(health);
    if (sensor == null) return cappedHealth;
    if (cappedHealth == null) return sensor;
    return sensor > cappedHealth ? sensor : cappedHealth;
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _summaryCard(isDark),
                  const SizedBox(height: 16),
                  _nutritionCard(isDark),
                  const SizedBox(height: 12),
                  _habitsCard(isDark),
                  const SizedBox(height: 12),
                  _waterCard(isDark),
                  const SizedBox(height: 12),
                  _movementCard(isDark),
                  const SizedBox(height: 12),
                  _weightCard(isDark),
                  const SizedBox(height: 16),
                  _weekCard(isDark),
                ],
              ),
            ),
    );
  }

  Widget _card({
    required bool isDark,
    required List<Widget> children,
    GlobalKey? key,
    AnalysisSection? section,
  }) {
    final focused = section != null && widget.focus == section;
    final decoration = MacroSnapTheme.habitlyCard(context);
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      // A focused card is outlined in its activity colour: arriving mid-list,
      // it has to be obvious which card the button was about.
      decoration: focused
          ? decoration.copyWith(
              border: Border.all(
                color: _sectionColor(section).withValues(alpha: 0.55),
                width: 1.4,
              ),
            )
          : decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: _primary(context),
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: MacroSnapTheme.textPrimaryMuted(context),
          ),
        ),
      ],
    );
  }

  Widget _bar(double progress, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress.isFinite ? progress.clamp(0.0, 1.0) : 0,
        minHeight: 6,
        backgroundColor: color.withValues(alpha: 0.12),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _summaryCard(bool isDark) {
    final habitsDone = HabitStore.instance.todayCompleted;
    final habitsTotal = HabitStore.instance.todayHabits.length;
    return _card(
      isDark: isDark,
      children: [
        Text(
          'Today at a glance',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _primary(context),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 14,
          children: [
            _stat(
              '${MealStore.instance.todayCalories} kcal',
              'eaten',
              MacroSnapTheme.neonOrange,
            ),
            _stat(
              habitsTotal == 0 ? '—' : '$habitsDone/$habitsTotal',
              'habits',
              _sectionColor(AnalysisSection.habits),
            ),
            _stat(
              '${HabitStore.instance.waterToday}/${HabitStore.instance.waterGoal}',
              'water',
              MacroSnapTheme.neonPurple,
            ),
            _stat(
              _stepsNow?.toString() ?? '—',
              'steps',
              _sectionColor(AnalysisSection.movement),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nutritionCard(bool isDark) {
    final profile = DietPlanService.instance.profile;
    final target = profile?.targetCalories;
    final eaten = MealStore.instance.todayCalories;
    final protein = MealStore.instance.todayProtein;
    final carbs = MealStore.instance.todayCarbs;
    final fats = MealStore.instance.todayFats;
    return _card(
      key: _keyFor(AnalysisSection.nutrition),
      section: AnalysisSection.nutrition,
      isDark: isDark,
      children: [
        _sectionTitle(
          'Nutrition',
          Icons.restaurant_rounded,
          _sectionColor(AnalysisSection.nutrition),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$eaten kcal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _primary(context),
              ),
            ),
            Text(
              target == null ? 'no goal set' : 'of $target kcal',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _bar(
          target == null || target <= 0 ? 0 : eaten / target,
          MacroSnapTheme.neonOrange,
        ),
        const SizedBox(height: 14),
        _macroRow(
          'Protein',
          protein,
          profile?.targetProtein,
          MacroSnapTheme.macroProtein,
        ),
        const SizedBox(height: 8),
        // `DietProfile.targetCarbs` already derives the target from whatever
        // the protein and fat targets leave (4 kcal/g); passing null here made
        // the carbs bar permanently empty and printed grams with no goal.
        _macroRow(
          'Carbs',
          carbs,
          profile?.targetCarbs,
          MacroSnapTheme.macroCarbs,
        ),
        const SizedBox(height: 8),
        _macroRow('Fat', fats, profile?.targetFats, MacroSnapTheme.macroFats),
        const SizedBox(height: 12),
        Text(
          '${MealStore.instance.todayMeals.length} meal'
          '${MealStore.instance.todayMeals.length == 1 ? '' : 's'} logged today',
          style: TextStyle(
            fontSize: 11,
            color: MacroSnapTheme.textPrimaryMuted(context),
          ),
        ),
      ],
    );
  }

  Widget _macroRow(String label, double value, double? target, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
        ),
        Expanded(
          child: _bar(
            target == null || target <= 0 ? 0 : value / target,
            color,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          target == null
              ? '${value.round()} g'
              : '${value.round()}/${target.round()} g',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _primary(context),
          ),
        ),
      ],
    );
  }

  Widget _habitsCard(bool isDark) {
    final store = HabitStore.instance;
    final total = store.todayHabits.length;
    final done = store.todayCompleted;
    final streak = store.totalStreakPower;
    return _card(
      key: _keyFor(AnalysisSection.habits),
      section: AnalysisSection.habits,
      isDark: isDark,
      children: [
        _sectionTitle(
          'Habits',
          Icons.check_circle_rounded,
          _sectionColor(AnalysisSection.habits),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              total == 0 ? 'No habits yet' : '$done of $total done',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _primary(context),
              ),
            ),
            Text(
              total == 0 ? '' : '${(done / total * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _bar(
          total == 0 ? 0 : done / total,
          _sectionColor(AnalysisSection.habits),
        ),
        if (streak > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$streak-day best streak',
            style: TextStyle(
              fontSize: 11,
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _waterCard(bool isDark) {
    final store = HabitStore.instance;
    final goal = store.waterGoal;
    final today = store.waterToday;
    return _card(
      key: _keyFor(AnalysisSection.water),
      section: AnalysisSection.water,
      isDark: isDark,
      children: [
        _sectionTitle(
          'Water',
          Icons.water_drop_rounded,
          _sectionColor(AnalysisSection.water),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$today of $goal glasses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _primary(context),
              ),
            ),
            Text(
              goal <= 0 ? '' : '${(today / goal * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _bar(
          goal <= 0 ? 0 : today / goal,
          _sectionColor(AnalysisSection.water),
        ),
      ],
    );
  }

  Widget _movementCard(bool isDark) {
    final steps = _stepsNow;
    // The target the ring and the streak work toward, not the chosen number:
    // a free account's 10,000 goal is measured against the 5,000 ceiling, so
    // this bar can actually fill.
    final goal = StepGoalService.instance.effectiveGoal;
    final burned = _health?.caloriesBurned;
    return _card(
      key: _keyFor(AnalysisSection.movement),
      section: AnalysisSection.movement,
      isDark: isDark,
      children: [
        _sectionTitle(
          'Movement',
          Icons.directions_walk_rounded,
          _sectionColor(AnalysisSection.movement),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              steps == null ? 'No steps yet' : '$steps steps',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _primary(context),
              ),
            ),
            Text(
              steps == null ? '' : 'goal $goal',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _bar(
          steps == null || goal <= 0 ? 0 : steps / goal,
          _sectionColor(AnalysisSection.movement),
        ),
        const SizedBox(height: 12),
        Text(
          steps == null
              ? 'Open the Health tab to start counting steps.'
              : burned == null
              ? 'Steps from your phone · connect Health for burn'
              : '${burned.round()} kcal burned today',
          style: TextStyle(
            fontSize: 11,
            color: MacroSnapTheme.textPrimaryMuted(context),
          ),
        ),
      ],
    );
  }

  Widget _weightCard(bool isDark) {
    final latest = WeightStore.instance.latestKg;
    final delta = _weightDeltaKg;
    return _card(
      key: _keyFor(AnalysisSection.weight),
      section: AnalysisSection.weight,
      isDark: isDark,
      children: [
        _sectionTitle(
          'Weight',
          Icons.monitor_weight_rounded,
          _sectionColor(AnalysisSection.weight),
        ),
        const SizedBox(height: 12),
        Text(
          latest == null
              ? 'No weigh-in yet'
              : '${latest.toStringAsFixed(1)} kg',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: _primary(context),
          ),
        ),
        if (delta != null) ...[
          const SizedBox(height: 6),
          Text(
            '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg in the last 7 days',
            style: TextStyle(
              fontSize: 11,
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _weekCard(bool isDark) {
    final days = _weekDays;
    // Each day is read ONCE and the weekly totals are folded from the series.
    // The summaries used to re-run `_caloriesOn`/`_habitsDoneOn` for all seven
    // days on top of the series, so a build scanned the whole meal history
    // fourteen times instead of seven.
    final calorieSeries = days.map(_caloriesOn).toList();
    final habitSeries = days.map(_habitsDoneOn).toList();
    final waterSeries = days
        .map((day) => HabitStore.instance.waterLog[dateKey(day)] ?? 0)
        .toList();
    final weekCalories = calorieSeries.fold(0, (sum, v) => sum + v);
    final weekHabitCompletions = habitSeries.fold(0, (sum, v) => sum + v);
    final weekWater = waterSeries.fold(0, (sum, v) => sum + v);
    final avgCalories = (weekCalories / 7).round();

    return _card(
      isDark: isDark,
      children: [
        Text(
          'Last 7 days',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _primary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'One bar per day, oldest on the left, today on the right.',
          style: TextStyle(
            fontSize: 11,
            color: MacroSnapTheme.textPrimaryMuted(context),
          ),
        ),
        const SizedBox(height: 16),
        _trendBlock(
          label: 'Calories',
          value: '$avgCalories kcal/day avg',
          series: calorieSeries,
          color: MacroSnapTheme.neonOrange,
        ),
        const SizedBox(height: 16),
        _trendBlock(
          label: 'Habits done',
          value: '$weekHabitCompletions this week',
          series: habitSeries,
          color: MacroSnapTheme.neonGreen,
        ),
        const SizedBox(height: 16),
        _trendBlock(
          label: 'Water',
          value: '$weekWater glasses',
          series: waterSeries,
          color: MacroSnapTheme.neonPurple,
        ),
        const SizedBox(height: 10),
        _weekdayAxis(days),
      ],
    );
  }

  /// A label, its weekly summary and the seven daily bars under it.
  Widget _trendBlock({
    required String label,
    required String value,
    required List<int> series,
    required Color color,
  }) {
    return Semantics(
      label: '$label, last seven days: ${series.join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _primary(context),
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MacroSnapTheme.textPrimaryMuted(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bars(series, color),
        ],
      ),
    );
  }

  /// Seven bars scaled to the busiest day in the window. A zero day keeps a
  /// 4px stub so "nothing logged" reads as a low bar rather than a gap, and
  /// today is drawn solid while the rest are tinted.
  Widget _bars(List<int> series, Color color) {
    final peak = series.fold<int>(0, (m, v) => v > m ? v : m);
    final scale = peak <= 0 ? 1 : peak;
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < series.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    // Explicit width: a childless Container shrink-wraps to
                    // zero and the bars would be invisible.
                    width: double.infinity,
                    height: 4 + (series[i] / scale) * 32,
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: i == series.length - 1 ? 1.0 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(4),
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

  /// One shared weekday axis, so the three charts below read as days rather
  /// than as anonymous bars.
  Widget _weekdayAxis(List<DateTime> days) {
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final muted = MacroSnapTheme.textPrimaryMuted(context);
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Text(
              initials[days[i].weekday - 1],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: i == days.length - 1
                    ? FontWeight.w900
                    : FontWeight.w600,
                color: i == days.length - 1 ? _primary(context) : muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
