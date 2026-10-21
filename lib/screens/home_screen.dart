import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../navigation/route_observer.dart';
import '../services/meal_store.dart';
import '../models/meal_record.dart';
import '../services/scan_gate.dart';
import '../services/meal_streak_service.dart';
import '../services/subscription_service.dart';
import '../models/diet_profile.dart';
import '../models/bmi.dart';
import '../services/share_service.dart';
import '../services/weight_store.dart';

import '../widgets/animations.dart';
import '../widgets/bmi_gauge.dart';
import '../widgets/weight_trend_chart.dart';
import '../widgets/calorie_trend_card.dart';
import '../widgets/confetti_celebration.dart';
import 'diet_plan_screen.dart';
import 'scan_screen.dart';
import 'veg_plan_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'subscription_screen.dart';
import 'recipe_list_screen.dart';
import 'bmi_screen.dart';
import 'barcode_scan_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  String _name = '';
  int _streak = 0;
  int _bestStreak = 0;
  int _scansLeft = 3;
  bool _trialActive = false;
  int _trialDaysLeft = 0;
  bool _previousGoalMet = false; // Track to detect transition to goal-met

  /// Whether Guru is unlocked for this account (paid Pro, or inside the
  /// one-time free plan). The backend enforces the same rule on /chat — this
  /// only decides whether the button opens the assistant or the plans.
  bool _guruUnlocked = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    MealStore.instance.changeNotifier.addListener(_onDataChanged);
    userNameNotifier.addListener(_onNameChanged);
    SubscriptionService.instance.addListener(_onSubscriptionChanged);
    // The BMI card draws the weight history, so a weigh-in recorded anywhere
    // (the calculator, a future screen) repaints it.
    WeightStore.instance.addListener(_onWeightChanged);
    // Reflect the subscription state the app already loaded, so the button is
    // correct on the first frame; _loadAll() and the listener keep it current.
    _guruUnlocked = SubscriptionService.instance.isSubscribed;
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // A route pushed on top (Settings, etc.) was popped — re-read the name
    // so edits made there appear on Home immediately.
    _refreshName();
  }

  void _onNameChanged() {
    final newName = userNameNotifier.value;
    if (mounted && newName != _name) {
      setState(() => _name = newName);
    }
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() {
      _trialActive = SubscriptionService.instance.trialActive;
      _trialDaysLeft = SubscriptionService.instance.trialDaysLeft;
      _guruUnlocked = SubscriptionService.instance.isSubscribed;
    });
  }

  Future<void> _refreshName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? '';
    if (mounted && name != _name) {
      setState(() => _name = name);
    }
  }

  void _onDataChanged() {
    _loadScansOnly();
  }

  void _onWeightChanged() {
    if (mounted) setState(() {});
  }

  /// Paints Home from local data, then lets the server answer update the badge.
  ///
  /// This used to await [ScanGate.refreshFromServer] (an HTTP call with an
  /// 8-second timeout) *before* the first `setState` and before
  /// [_animController] started. On a slow or flaky connection that left the
  /// screen blank — no name, no streak, no scan badge, no entrance animation —
  /// for seconds, right after the launch splash had already disappeared.
  /// Everything below the store loads is a warm prefs/file read, so the real
  /// numbers are on screen immediately; the network is a follow-up.
  Future<void> _loadAll() async {
    await MealStore.instance.load();
    await DietPlanService.instance.load();
    await SubscriptionService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? '';
    final streak = await MealStreakService.getCurrent();
    final best = await MealStreakService.getBest();
    // Local estimate first (today's remainder, reset on the IST day boundary).
    final scans = await ScanGate.getScansRemaining();

    if (!mounted) return;
    setState(() {
      _name = name;
      _streak = streak;
      _bestStreak = best;
      _scansLeft = scans;
      _trialActive = SubscriptionService.instance.trialActive;
      _trialDaysLeft = SubscriptionService.instance.trialDaysLeft;
      _guruUnlocked = SubscriptionService.instance.isSubscribed;
    });
    userNameNotifier.value = name;
    _animController.forward();

    // Best-effort: the server is the authority on the free-scan allowance, so
    // reconcile the badge once the screen is already up.
    unawaited(_refreshScansFromServer());
  }

  /// Asks the backend for the authoritative scan allowance without ever
  /// gating the UI: offline, a timeout, or an old backend simply leaves the
  /// local estimate in place.
  Future<void> _refreshScansFromServer() async {
    try {
      if (!await ScanGate.refreshFromServer()) return;
      final scans = await ScanGate.getScansRemaining();
      if (mounted && scans != _scansLeft) {
        setState(() => _scansLeft = scans);
      }
    } catch (e) {
      debugPrint('Error refreshing scans: $e');
    }
  }

  Future<void> _loadScansOnly() async {
    final scans = await ScanGate.getScansRemaining();
    if (mounted) setState(() => _scansLeft = scans);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    MealStore.instance.changeNotifier.removeListener(_onDataChanged);
    userNameNotifier.removeListener(_onNameChanged);
    SubscriptionService.instance.removeListener(_onSubscriptionChanged);
    WeightStore.instance.removeListener(_onWeightChanged);
    _animController.stop();
    _animController.dispose();
    super.dispose();
  }

  void _refresh() => _loadAll();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      floatingActionButton: Padding(
        // Sits on the tab body, above the shell's bottom nav — its position
        // is fixed and it never moves with the scrolling content.
        padding: const EdgeInsets.only(bottom: 12),
        child: FloatingActionButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _guruUnlocked
                  // Pro (paid or in the free plan): Guru answers.
                  ? const ChatScreen()
                  // Free user: the backend would refuse every turn, so open the
                  // plans instead of a chat that cannot reply.
                  : const SubscriptionScreen(),
            ),
          ),
          tooltip: _guruUnlocked ? 'Ask Guru' : 'Ask Guru \u2014 Pro',
          backgroundColor: MacroSnapTheme.neonPink,
          child: Icon(
            _guruUnlocked
                ? Icons.chat_bubble_rounded
                : Icons.lock_outline_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      body: SafeArea(
        child: SlideTransition(
          position: _slideAnim,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, isDark)),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 25,
                    child: _buildTrialBanner(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 50,
                    child: _buildStreakCard(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 100,
                    child: _buildCalorieRing(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 150,
                    child: _buildMacroBars(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 165,
                    child: _buildBmiCard(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 175,
                    child: CalorieTrendCard(
                      goalCalories:
                          DietPlanService.instance.profile?.targetCalories ??
                          2000,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 200,
                    child: _buildWeekStrip(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 250,
                    child: _buildQuickActions(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 300,
                    child: _buildRecentMeals(context, isDark),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── FREE TRIAL COUNTDOWN ─────────────────────────────
  // Shown only while the one-time 30-day free plan runs. Tapping it opens
  // the plans screen; it disappears on its own at expiry.
  Widget _buildTrialBanner(BuildContext context, bool isDark) {
    if (!_trialActive) return const SizedBox.shrink();
    final days = _trialDaysLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  days == 1 ? 'Free plan \u00b7 last day!' : 'Free plan \u00b7 $days days left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Text(
                'View plans',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isDark) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good Morning'
        : now.hour < 18
        ? 'Good Afternoon'
        : 'Good Evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _name.isNotEmpty ? _name : 'MacroSnap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scans remaining badge (Habitly neon pill style)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: MacroSnapTheme.neonPill(
                  _scansLeft > 0
                      ? MacroSnapTheme.neonGreen
                      : MacroSnapTheme.neonPink,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 14,
                      color: _scansLeft > 0
                          ? MacroSnapTheme.neonGreen
                          : MacroSnapTheme.neonPink,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _scansLeft >= 99 ? 'Unlimited' : '$_scansLeft',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _scansLeft > 0
                            ? MacroSnapTheme.greenText(context)
                            : MacroSnapTheme.neonPink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ScaleOnPress(
                onTap: () => Navigator.push(
                  context,
                  habitFlowRoute(const SettingsScreen()),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? MacroSnapTheme.cardDark
                        : const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 20,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── STREAK CARD (Habitly style) ────────────────────────────
  Widget _buildStreakCard(BuildContext context, bool isDark) {
    final isBest = MealStreakService.isLongestStreak(_streak, _bestStreak);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: MacroSnapTheme.emojiContainer(
                MacroSnapTheme.neonPink,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: MacroSnapTheme.neonPink,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meal Streak',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MacroSnapTheme.textTertiary(context),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '$_streak',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isBest ? 'New personal best!' : 'All targets hit today!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isBest
                          ? MacroSnapTheme.greenText(context)
                          : MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            // Neon streak pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: MacroSnapTheme.neonPill(MacroSnapTheme.neonGreen),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 14,
                    color: MacroSnapTheme.neonGreen,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+$_streak',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: MacroSnapTheme.greenText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HERO CALORIE CARD (Habitly Hero style) ────────────────
  Widget _buildCalorieRing(BuildContext context, bool isDark) {
    final profile = DietPlanService.instance.profile;
    final targetCal = profile?.targetCalories ?? 2000;
    final consumed = MealStore.instance.todayCalories;
    final progress = (consumed / targetCal).clamp(0.0, 1.0);
    final remaining = max(targetCal - consumed, 0);

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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: MacroSnapTheme.neonGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$remaining remaining',
                      maxLines: 1,
                      style: TextStyle(
                        color: MacroSnapTheme.greenText(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
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
            _macroBar(
              'Protein',
              p,
              targetP,
              MacroSnapTheme.neonPink,
              isDark,
              'g',
            ),
            const SizedBox(height: 14),
            _macroBar(
              'Carbs',
              c,
              targetC,
              MacroSnapTheme.neonOrange,
              isDark,
              'g',
            ),
            const SizedBox(height: 14),
            _macroBar('Fats', f, targetF, MacroSnapTheme.neonCyan, isDark, 'g'),
          ],
        ),
      ),
    );
  }

  Widget _macroBar(
    String label,
    double value,
    double target,
    Color color,
    bool isDark,
    String unit,
  ) {
    final pct = (value / max(target, 1)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
            Text(
              '${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}$unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedProgressBar(value: pct, color: color, height: 8),
      ],
    );
  }

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
                    final shared = await ShareService.shareWeekSummary();
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
    final category = bmi == null ? null : BmiCalculator.categoryFor(bmi);
    final accent = category?.color ?? MacroSnapTheme.neonCyan;
    // The trend is the point of keeping a history: a single BMI number tells
    // you where you are, the line tells you which way you're going.
    final trend = WeightStore.instance.summary(days: 30);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          await Navigator.push(
            context,
            habitFlowRoute(const BmiScreen()),
          );
          // The calculator can save a new weight — repaint with it.
          if (mounted) setState(() {});
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
                    child: Icon(
                      Icons.speed_rounded,
                      size: 21,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        bmi == null ? '—' : bmi.toStringAsFixed(1),
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

  // ─── QUICK ACTIONS (Habitly style) ──────────────────────────
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: five actions must still fit a 320dp phone at 2x
            // system font without a RenderFlex overflow.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceAround,
              children: [
                _quickAction(
                  Icons.camera_alt_rounded,
                  'Snap',
                  MacroSnapTheme.neonGreen,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const ScanScreen()),
                    ).then((_) => _refresh());
                  },
                ),
                _quickAction(
                  Icons.qr_code_scanner_rounded,
                  'Barcode',
                  MacroSnapTheme.neonCyan,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const BarcodeScanScreen()),
                    );
                  },
                ),
                _quickAction(
                  Icons.auto_awesome_rounded,
                  'Diet',
                  MacroSnapTheme.neonPurple,
                  isDark,
                  () async {
                    await DietPlanService.instance.load();
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        habitFlowRoute(const DietPlanScreen()),
                      );
                    }
                  },
                ),
                _quickAction(
                  Icons.menu_book_rounded,
                  'Recipes',
                  MacroSnapTheme.neonPink,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const RecipeListScreen()),
                    );
                  },
                ),
                _quickAction(
                  Icons.grass_rounded,
                  'Veg Plan',
                  MacroSnapTheme.macroFiber,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const VegPlanScreen()),
                    ).then((_) => _refresh());
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Uniform tile width for the Quick Actions row. Narrow enough that five
  /// tiles fit a 320dp phone (the Wrap still wraps rather than overflowing if
  /// the system font is scaled up), wide enough for "Barcode" at 11sp.
  static const double _quickActionWidth = 72;

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    // Fixed width, not intrinsic: sizing the tile to its label made every
    // action a different width ("Snap" narrow, "Veg Plan" wide) with the icon
    // floating in a skinny pill and the label spilling past the tile edges —
    // which is what made the row look broken. Every tile is now identical and
    // the label ellipsises instead of overflowing.
    return ScaleOnPress(
      // Tap feedback for every quick action (Snap, Barcode, Diet, ...).
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      scaleAmount: 0.93,
      child: Container(
        width: _quickActionWidth,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TODAY'S MISSION (Meals as Habitly-style missions) ──────
  Widget _buildRecentMeals(BuildContext context, bool isDark) {
    final meals = MealStore.instance.todayMeals;
    if (meals.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Meals",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: MacroSnapTheme.neonPill(MacroSnapTheme.neonGreen),
                child: Text(
                  '${meals.fold(0, (s, m) => s + m.calories)} kcal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: MacroSnapTheme.greenText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...meals.take(5).map((m) => _buildMissionMealCard(m, isDark)),
        ],
      ),
    );
  }

  /// Habitly-style mission card with emoji + check button.
  /// Tapping the card opens the same meal-info view shown right after a scan
  /// (read-only detail of the logged nutrition); the bolt button deletes.
  Widget _buildMissionMealCard(MealRecord m, bool isDark) {
    final color = _mealIcon(m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          habitFlowRoute(ResultScreen(imagePath: '', existingMeal: m)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: MacroSnapTheme.habitlyCard(context),
          child: Row(
            children: [
              // Emoji container (Habitly mission style)
              Container(
                width: 52,
                height: 52,
                decoration: MacroSnapTheme.emojiContainer(color),
                child: Center(
                  child: Icon(_mealIconData(m), color: color, size: 25),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          color: MacroSnapTheme.neonPink,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${m.calories} kcal',
                          style: TextStyle(
                            color: MacroSnapTheme.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (m.serving.isNotEmpty)
                          Flexible(
                            child: Text(
                              ' · ${m.serving}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MacroSnapTheme.textTertiary(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Check button (Habitly style)
              GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: isDark
                          ? MacroSnapTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      title: const Text(
                        'Delete Meal',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      content: Text('Remove "${m.name}" from your log?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: MacroSnapTheme.neonPink,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    MealStore.instance.remove(m.id);
                    _refresh();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 27,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _mealIcon(MealRecord m) {
    final h = m.date.hour;
    if (h >= 5 && h < 11) return MacroSnapTheme.macroCalories;
    if (h >= 11 && h < 15) return MacroSnapTheme.neonGreen;
    if (h >= 17 && h < 22) return MacroSnapTheme.macroFats;
    return MacroSnapTheme.macroProtein;
  }

  IconData _mealIconData(MealRecord m) {
    final h = m.date.hour;
    if (h >= 5 && h < 11) return Icons.wb_sunny_rounded;
    if (h >= 11 && h < 15) return Icons.restaurant_rounded;
    if (h >= 17 && h < 22) return Icons.nights_stay_rounded;
    return Icons.cookie_rounded;
  }
}
