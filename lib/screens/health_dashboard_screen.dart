import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_nav.dart';
import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/health_service.dart';
import '../services/leaderboard_service.dart';
import '../services/meal_store.dart';
import '../services/step_counter_service.dart';
import '../services/step_goal_service.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';

/// The Health dashboard — steps and calories burned from Health Connect,
/// shown alongside the app's food-logging flow so a user can see intake and
/// activity in one place.
///
/// The screen has three states:
///   * disconnected — Health Connect is unavailable or not authorised; a CTA
///     offers to connect
///   * connected, no data — permissions granted but nothing read yet today
///   * connected with data — today's steps and calories displayed
///
/// It polls the platform every [_pollInterval] while it is the visible tab
/// (the phone keeps counting steps whether or not the app is open) and offers
/// a manual refresh in the app bar and by pulling down.
class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen>
    with WidgetsBindingObserver {
  /// How often the steps/calories pair is re-read while the tab is visible.
  /// Five seconds is short enough that the number visibly moves while the
  /// phone is in a pocket, and far below anything that shows up in battery
  /// stats for a foreground screen.
  static const Duration _pollInterval = Duration(seconds: 5);

  /// The daily step goal the ring fills toward. Kept in [StepGoalService]
  /// (prefs-backed) so the target — and the streak that depends on it — is
  /// the same every time the tab is rebuilt.
  int get _stepGoal => StepGoalService.instance.goal;

  bool _initialized = false;
  bool _available = false;
  bool _hasReadPermission = false;
  int? _steps;
  double? _caloriesBurned;
  double? _activeCalories;
  bool _loadFailed = false;
  bool _refreshing = false;
  DateTime? _lastUpdated;

  Timer? _pollTimer;
  bool _appInForeground = true;

  /// The phone's own step counter. This is the PRIMARY source: Health Connect
  /// is optional, and a user who never connects it still gets steps, a ring and
  /// leaderboard movement points from the sensor the phone already has.
  bool _sensorActive = false;
  int? _sensorSteps;

  /// Today's steps from whichever source has the higher count. Health Connect
  /// de-duplicates a phone and a watch, so when it is connected its number can
  /// be larger; the sensor is the fallback that always exists.
  int? get _stepsNow {
    final sensor = StepCounterService.instance.todaySteps ?? _sensorSteps;
    final health = _steps;
    if (sensor == null) return health;
    if (health == null) return sensor;
    return sensor > health ? sensor : health;
  }

  bool get _connected => _sensorActive || _hasReadPermission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    healthTabVisible.addListener(_onTabVisibilityChanged);
    // The "Eaten" figure is read from the meal store, so a meal logged from
    // another tab must repaint this one.
    MealStore.instance.changeNotifier.addListener(_onMealsChanged);
    // The target and the streak are redrawn from the same store that owns
    // them, so changing the goal in the picker repaints this screen without
    // any state being copied twice.
    StepGoalService.instance.addListener(_onGoalChanged);
    StepCounterService.instance.addListener(_onSensorChanged);
    _initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    healthTabVisible.removeListener(_onTabVisibilityChanged);
    MealStore.instance.changeNotifier.removeListener(_onMealsChanged);
    StepGoalService.instance.removeListener(_onGoalChanged);
    StepCounterService.instance.removeListener(_onSensorChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onMealsChanged() {
    if (mounted) setState(() {});
  }

  void _onGoalChanged() {
    if (mounted) setState(() {});
  }

  void _onSensorChanged() {
    if (!mounted) return;
    final service = StepCounterService.instance;
    setState(() {
      _sensorActive = service.active;
      _sensorSteps = service.todaySteps;
      if (service.todaySteps != null) _lastUpdated = DateTime.now();
    });
    // Scoring is handled centrally (LeaderboardService listens to the sensor),
    // so this only repaints the number. Doing the store writes here as well
    // meant two prefs writes per sensor tick.
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _appInForeground;
    _appInForeground = state == AppLifecycleState.resumed;
    _syncPolling();
    // Coming back to the app should show current numbers immediately: the
    // phone kept counting steps while the app was in the background, and
    // waiting up to a full poll interval made the dashboard look stuck.
    if (!wasForeground && _appInForeground && _connected) {
      unawaited(_loadToday(silent: true));
    }
  }

  void _onTabVisibilityChanged() {
    _syncPolling();
    // Returning to the tab should show current numbers immediately, not the
    // ones from up to [_pollInterval] ago.
    if (healthTabVisible.value && _connected) {
      unawaited(_loadToday(silent: true));
    }
  }

  /// Runs the 5-second poll only while this tab is visible and the app is in
  /// the foreground. A timer left running behind another tab (or behind the
  /// lock screen) is pure battery cost for a number nobody can see.
  void _syncPolling() {
    final shouldPoll =
        _connected && _available && _appInForeground && healthTabVisible.value;
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      unawaited(_loadToday(silent: true));
    });
  }

  /// One-time check: is Health Connect / HealthKit available on this device,
  /// is the stored step target loaded, and do we already have read permission?
  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() => _initialized = true);

    await StepGoalService.instance.load();
    if (!mounted) return;

    // The phone's own step counter is the primary source. Its permission
    // (ACTIVITY_RECOGNITION) is asked for HERE, on the screen that shows the
    // number — never at launch — and Android remembers the grant afterwards.
    await StepCounterService.instance.start(requestPermission: true);
    if (!mounted) return;
    setState(() {
      _sensorActive = StepCounterService.instance.active;
      _sensorSteps = StepCounterService.instance.todaySteps;
    });
    _syncPolling();

    final service = HealthService.instance;
    if (!service.isPlatformSupported) {
      if (!mounted) return;
      setState(() => _available = false);
      return;
    }

    final ok = await service.isHealthAvailable;
    if (!mounted) return;
    setState(() {
      _available = ok;
    });
    if (ok) {
      await _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final service = HealthService.instance;
    final access = await service.checkAccess();
    if (!mounted) return;
    setState(() {
      _hasReadPermission = access.canReadActivity;
    });
    if (access.canReadActivity) {
      await _loadToday(silent: true);
    }
    _syncPolling();
  }

  /// Connect / authorize: ask the user for read permission to steps and
  /// calories burned. On success, load today's data immediately.
  Future<void> _connect() async {
    unawaited(Haptics.light());
    // Step counting must work with no health app at all, so the phone sensor is
    // started first and Health Connect is the optional extra.
    if (!StepCounterService.instance.active) {
      await StepCounterService.instance.start(requestPermission: true);
      if (mounted) {
        setState(() => _sensorActive = StepCounterService.instance.active);
      }
    }
    final service = HealthService.instance;
    // The request itself is only half of "connected": Health Connect can
    // accept the dialog and still hold no grant for a type this build asked
    // for wrongly. The fresh check is what the dashboard trusts.
    await service.requestReadPermissions();
    if (!mounted) return;
    final access = await service.checkAccess();
    if (!mounted) return;
    setState(() {
      _hasReadPermission = access.canReadActivity;
      _loadFailed = false;
    });
    if (access.canReadActivity) {
      await _loadToday();
    }
    _syncPolling();
  }

  /// Refresh today's steps and calories from the health platform.
  ///
  /// [silent] is the background poll: it updates the numbers without flipping
  /// the app-bar button into its spinner, and a failed silent read keeps the
  /// last good numbers on screen instead of blanking them.
  Future<void> _loadToday({bool silent = false}) async {
    if (!_connected) return;
    if (!silent && mounted) setState(() => _refreshing = true);
    try {
      final today = await HealthService.instance.fetchToday();
      if (!mounted) return;
      setState(() {
        if (today.ok) {
          _steps = today.steps ?? _steps;
          _caloriesBurned = today.caloriesBurned ?? _caloriesBurned;
          _activeCalories = today.activeCalories ?? _activeCalories;
          _lastUpdated = DateTime.now();
          _loadFailed = false;
        } else if (_hasReadPermission) {
          // Only a GRANTED Health Connect read can "fail": a phone without it
          // is not an error, because the sensor is still counting.
          _loadFailed = true;
        }
        _refreshing = false;
      });
      // The streak advances the moment the target is crossed, not at the next
      // launch — the poll runs while the tab is open, so this is the only
      // place that sees the crossing happen.
      final steps = _stepsNow;
      if (steps != null) {
        await StepGoalService.instance.recordToday(steps);
        // The leaderboard's movement points use THIS number — the one the
        // dashboard shows. It comes from the phone's sensor (or Health
        // Connect when that is higher), so it is never a figure the user typed
        // in.
        await LeaderboardService.instance.noteSteps(steps);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _refreshing = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (!_connected) {
      // No permission yet: the button still does something useful instead of
      // being a dead tap.
      await _connect();
      return;
    }
    unawaited(Haptics.light());
    await _loadToday();
  }

  /// Lets the user move the daily target in 5,000-step steps.
  Future<void> _pickGoal() async {
    unawaited(Haptics.light());
    final goal = StepGoalService.instance.goal;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? MacroSnapTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.textTertiary(ctx),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.flag_rounded,
                      color: MacroSnapTheme.neonGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Daily step target',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'The ring, the percentage and the streak all count toward '
                  'this number.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: MacroSnapTheme.textTertiary(ctx),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in StepGoalService.goalOptions)
                      ChoiceChip(
                        label: Text(
                          '${_thousands(option)} steps',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        selected: option == goal,
                        onSelected: (_) => Navigator.pop(ctx, option),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null) return;
    await StepGoalService.instance.setGoal(chosen);
    if (!mounted) return;
    // A new, smaller target may already be met by today's steps.
    final steps = _steps;
    if (steps != null) await StepGoalService.instance.recordToday(steps);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        title: const Text(
          'Health',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MacroSnapTheme.neonGreen,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 22),
              // Never disabled while the screen is up: tapping it while
              // disconnected starts the connect flow rather than doing nothing.
              onPressed: _initialized ? _refresh : null,
            ),
        ],
      ),
      body: _buildBody(context, isDark),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    // Health Connect being unavailable is NOT a dead end any more: the phone's
    // own step counter is enough, so the dashboard shows as soon as that is
    // running.
    if (!_connected) {
      return _buildConnectState(context, isDark);
    }
    return _buildDashboard(context, isDark);
  }

  /// Nothing is counting yet. The phone's own step sensor is offered first —
  /// it needs no Health Connect and no extra app — so a user who declines the
  /// health platform still gets steps, a ring and movement points.
  Widget _buildConnectState(BuildContext context, bool isDark) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            AnimatedEntrance(
              delayMs: 40,
              child: _buildIconCard(
                context,
                isDark,
                icon: Icons.directions_walk_rounded,
                iconColor: MacroSnapTheme.neonGreen,
                backgroundColor: MacroSnapTheme.neonGreen.withValues(
                  alpha: 0.12,
                ),
                title: 'Count your steps',
                body:
                    'MacroSnap counts steps with your phone\'s own sensor — no '
                    'Health Connect, no watch. Allow "Physical activity" to '
                    'start. Health Connect is optional and only adds a watch '
                    'and calories burned.',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.directions_walk_rounded, size: 20),
                label: const Text('Enable step counting'),
                style: FilledButton.styleFrom(
                  backgroundColor: MacroSnapTheme.neonGreen,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tap Enable and allow "Physical activity" (Android) or "Motion & '
              'Fitness" (iOS). Your steps appear here immediately; connect '
              'Health Connect later from the same button if you want your '
              'watch and calorie burn included.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Permissions granted: the live dashboard.
  Widget _buildDashboard(BuildContext context, bool isDark) {
    final steps = _stepsNow ?? 0;
    final cals = _caloriesBurned;
    final goal = _stepGoal;
    final progress = (steps / goal).clamp(0.0, 1.0);
    final eaten = MealStore.instance.todayCalories;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: MacroSnapTheme.neonGreen,
      backgroundColor: isDark
          ? MacroSnapTheme.cardDark
          : MacroSnapTheme.surfaceLight,
      child: SingleChildScrollView(
        // Always scrollable so pull-to-refresh works even when the content is
        // shorter than the screen — without it the gesture did nothing on tall
        // phones, which is why the manual refresh looked broken.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedEntrance(
              delayMs: 20,
              child: _buildStepsHero(
                context,
                isDark,
                steps: steps,
                progress: progress,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AnimatedEntrance(
                    delayMs: 90,
                    child: _buildMetricTile(
                      context,
                      isDark,
                      icon: Icons.local_fire_department_rounded,
                      color: MacroSnapTheme.neonOrange,
                      label: 'Burned',
                      value: cals,
                      unit: 'kcal',
                      subtitle: cals == null
                          ? 'No data yet'
                          : (_activeCalories != null &&
                                    cals > _activeCalories! + 1
                                ? 'includes resting burn'
                                : 'active energy'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedEntrance(
                    delayMs: 140,
                    child: _buildMetricTile(
                      context,
                      isDark,
                      icon: Icons.restaurant_rounded,
                      color: MacroSnapTheme.neonPurple,
                      label: 'Eaten',
                      value: eaten.toDouble(),
                      unit: 'kcal',
                      subtitle: 'from your food log',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 160,
              child: _buildStreakCard(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 190,
              child: _buildBalanceCard(context, isDark, steps, cals, eaten),
            ),
            if (_loadFailed) ...[
              const SizedBox(height: 12),
              Text(
                'Health Connect did not answer just now. Pull down (or tap '
                'refresh) to try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: MacroSnapTheme.neonPink,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              _lastUpdated == null
                  ? 'Waiting for the first reading…'
                  : _updatedLabel(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AnimatedEntrance(
                    delayMs: 240,
                    child: _buildNoteCard(
                      context,
                      isDark,
                      icon: Icons.sync_rounded,
                      iconColor: MacroSnapTheme.textTertiary(context),
                      title: 'Updates itself',
                      body:
                          'Steps refresh every 5 seconds while this tab is '
                          'open, from your phone\'s own step sensor.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedEntrance(
                    delayMs: 280,
                    child: _buildNoteCard(
                      context,
                      isDark,
                      icon: Icons.phone_android_rounded,
                      iconColor: MacroSnapTheme.textTertiary(context),
                      title: 'Source',
                      body:
                          'Steps come from your phone\'s sensor; Health '
                          'Connect adds a watch and calorie burn. MacroSnap '
                          'only reads them — it never edits them.',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  String _updatedLabel() {
    final at = _lastUpdated;
    if (at == null) return '';
    final diff = DateTime.now().difference(at).inSeconds;
    if (diff < 5) return 'Live · just updated';
    if (diff < 60) return 'Updated ${diff}s ago';
    final mins = diff ~/ 60;
    return 'Updated ${mins}m ago';
  }

  /// The hero card: today's steps in a big counting number, with a ring that
  /// fills toward the daily target and a soft pulsing glow. The target itself
  /// is editable from here — it is the number the ring is measured against, so
  /// it belongs next to the ring, not buried in Settings.
  Widget _buildStepsHero(
    BuildContext context,
    bool isDark, {
    required int steps,
    required double progress,
  }) {
    final goal = _stepGoal;
    final goalReached = steps >= goal;
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
                      Icons.directions_walk_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'STEPS TODAY',
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
              Text(
                goalReached ? 'Goal reached 🎉' : '${(progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Soft halo behind the ring so it lifts off the gradient.
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.16),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: AnimatedProgressRing(
                  value: progress,
                  size: 108,
                  strokeWidth: 9,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  labelStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedValue(
                        target: steps.toDouble(),
                        duration: const Duration(milliseconds: 700),
                        builder: (context, v) => Text(
                          _thousands(v.round()),
                          style: const TextStyle(
                            fontSize: 44,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      goalReached
                          ? 'You hit your ${_thousands(goal)} step goal'
                          : '${_thousands((goal - steps).clamp(0, goal))} steps to go',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // The target, inline and editable.
                    GestureDetector(
                      onTap: _pickGoal,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.flag_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Goal ${_thousands(goal)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit_rounded,
                              size: 12,
                              color: Colors.white70,
                            ),
                          ],
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

  /// The step streak: consecutive days the daily target was reached.
  Widget _buildStreakCard(BuildContext context, bool isDark) {
    final service = StepGoalService.instance;
    final streak = service.streak;
    final best = service.bestStreak;
    final reachedToday = service.reachedToday;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonOrange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: MacroSnapTheme.neonOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$streak',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: titleColour,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        streak == 1 ? 'day streak' : 'day streak',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: MacroSnapTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reachedToday
                      ? 'Today is counted — nice work.'
                      : 'Hit ${_thousands(_stepGoal)} steps today to '
                            '${streak == 0 ? 'start' : 'keep'} the streak.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          if (best > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MacroSnapTheme.neonOrange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Best $best',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.neonOrange,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One white-on-dark stat tile (Burned / Eaten).
  Widget _buildMetricTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color color,
    required String label,
    required double? value,
    required String unit,
    required String subtitle,
  }) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: value == null
                    ? Text(
                        '—',
                        style: TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      )
                    : AnimatedValue(
                        target: value,
                        duration: const Duration(milliseconds: 700),
                        builder: (context, v) => Text(
                          _thousands(v.round()),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 26,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Burn vs intake, the one comparison a food logger and a step counter can
  /// only make together.
  Widget _buildBalanceCard(
    BuildContext context,
    bool isDark,
    int steps,
    double? burned,
    int eaten,
  ) {
    final burn = burned ?? 0;
    final net = eaten - burn;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today at a glance',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: titleColour,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  context,
                  label: 'Eaten',
                  value: '${_thousands(eaten)} kcal',
                  colour: MacroSnapTheme.neonPurple,
                ),
              ),
              _divider(context, isDark),
              Expanded(
                child: _miniStat(
                  context,
                  label: 'Burned',
                  value: burned == null
                      ? '—'
                      : '${_thousands(burn.round())} kcal',
                  colour: MacroSnapTheme.neonOrange,
                ),
              ),
              _divider(context, isDark),
              Expanded(
                child: _miniStat(
                  context,
                  label: net >= 0 ? 'Net in' : 'Deficit',
                  value: '${_thousands(net.abs().round())} kcal',
                  colour: net >= 0
                      ? MacroSnapTheme.neonGreen
                      : MacroSnapTheme.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            burned == null
                ? 'No burn recorded yet today — your phone records this as you '
                      'move, and it appears here automatically.'
                : 'Net = what you ate minus what you burned so far today.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context, bool isDark) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: MacroSnapTheme.borderSubtle(context),
    );
  }

  Widget _miniStat(
    BuildContext context, {
    required String label,
    required String value,
    required Color colour,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: colour,
            ),
          ),
        ),
      ],
    );
  }

  /// "12,345" — step counts get long and a bare 10480 reads worse than 10,480.
  static String _thousands(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Widget _buildIconCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String body,
  }) {
    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: MacroSnapTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: MacroSnapTheme.borderSubtle(context).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            body,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}
