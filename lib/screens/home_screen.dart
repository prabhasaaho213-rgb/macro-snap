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
import '../services/subscription_service.dart';
import '../models/diet_profile.dart';
import '../models/bmi.dart';
import '../services/weight_store.dart';

import '../widgets/animations.dart';
import '../widgets/bmi_gauge.dart';
import '../widgets/meal_photo.dart';
import '../widgets/pro_badge.dart';
import '../widgets/weight_trend_chart.dart';
import '../widgets/confetti_celebration.dart';
import 'diet_plan_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'subscription_screen.dart';
import 'bmi_screen.dart';
import 'barcode_scan_screen.dart';
import 'result_screen.dart';
import '../widgets/macro_bar.dart';

part 'home_screen_week.dart';
part 'home_screen_header.dart';
part 'home_screen_calories.dart';
part 'home_screen_meals.dart';

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
  int _scansLeft = 3;
  bool _previousGoalMet = false; // Track to detect transition to goal-met

  /// How many meals were logged today the last time Home painted. Used to
  /// spot the 0 → 1 transition that is a user's first log of the day.
  int _todayMealsSeen = -1;

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
    // The admin's lifetime grant often lands after the first frame (Firebase
    // restores the session asynchronously) — re-check the claim so the owner
    // gets the assistant, not the paywall, on a cold start.
    unawaited(_resolveGuruUnlock());
  }

  /// Confirms the Guru unlock against the admin claim. Cached after the first
  /// read per process; a no-op once Pro is already true.
  Future<void> _resolveGuruUnlock() async {
    if (SubscriptionService.instance.isSubscribed) return;
    final admin = await SubscriptionService.instance.isAdmin();
    if (admin && mounted && !_guruUnlocked) {
      setState(() => _guruUnlocked = true);
    }
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
      _guruUnlocked = SubscriptionService.instance.isSubscribed;
    });
    // Pro fell OFF between reads (a windowed grant expiring) while the admin
    // grant may not have been applied yet — re-check the claim so the owner
    // never sees the lock return.
    unawaited(_resolveGuruUnlock());
  }

  Future<void> _refreshName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? '';
    if (mounted && name != _name) {
      setState(() => _name = name);
    }
  }

  void _onDataChanged() {
    final count = MealStore.instance.todayMeals.length;
    final previous = _todayMealsSeen;
    _todayMealsSeen = count;
    // A log is the app's whole promise, so the first one of the day gets a
    // moment. Only the 0 → 1 transition counts: reopening Home with meals
    // already logged, or a cloud restore, must not fire it.
    if (previous == 0 && count == 1) _celebrateFirstLogOfDay();
    _loadScansOnly();
  }

  /// One small celebration per day, on the first meal logged. Confetti plus a
  /// line that names what just happened, so it reads as progress rather than
  /// a random animation.
  Future<void> _celebrateFirstLogOfDay() async {
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('first_log_celebrated_day') == day) return;
    await prefs.setString('first_log_celebrated_day', day);
    if (!mounted) return;
    ConfettiCelebration.show(context, particleCount: 45);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('First meal logged today — nice start 🔥'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    // Baseline for the "first log of the day" moment, taken as soon as meals
    // are known — not after the slower profile load below, which can take
    // seconds (or never answer) and would make the first log look like a
    // screen that was already showing one.
    _todayMealsSeen = MealStore.instance.todayMeals.length;
    await DietPlanService.instance.load();
    await SubscriptionService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? '';
    // Local estimate first (today's remainder, reset on the IST day boundary).
    final scans = await ScanGate.getScansRemaining();

    if (!mounted) return;
    setState(() {
      _name = name;
      _scansLeft = scans;
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

  /// Rebuild helper for the builders that now live in part files.
  ///
  /// `setState` is `@protected`, and an extension is not a `State` subclass,
  /// so calling it directly from a part file is rejected by the analyzer.
  /// Routing through a real member keeps the lint honest instead of silencing it.
  void _rebuild(VoidCallback fn) => setState(fn);

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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton(
              onPressed: () async {
                // Re-check the admin claim on tap: a cold-start owner who taps
                // before the lifetime grant lands still gets the assistant,
                // never the paywall. (Cached claim read — effectively free.)
                final unlocked =
                    _guruUnlocked ||
                    await SubscriptionService.instance.unlocksPro();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => unlocked
                        // Pro (paid or in the free plan): Guru answers.
                        ? const ChatScreen()
                        // Free user: the backend would refuse every turn, so
                        // open the plans instead of a chat that cannot reply.
                        : const SubscriptionScreen(),
                  ),
                );
              },
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
            // Guru is a Pro feature; the chip says so on the button itself,
            // and the locked icon inside says whether this account has it.
            const Positioned(
              top: -4,
              right: -4,
              child: ProBadge(compact: true),
            ),
          ],
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
                // The calorie ring is the first card: it is the number people
                // open the app for. The old Meal Streak card above it was
                // removed — the streak still lives in reminders and the
                // week strip, just not as a home-screen slot.
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 50,
                    child: _buildCalorieRing(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 100,
                    child: _buildMacroBars(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 150,
                    child: _buildBmiCard(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 200,
                    child: _buildQuickActions(context, isDark),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedEntrance(
                    delayMs: 250,
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
}
