import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_nav.dart';
import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/currency_service.dart';
import '../services/nav_ab_test.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../widgets/notification_prompt.dart';
import '../widgets/badge_board.dart';
import 'home_screen.dart';
import 'habits_tab.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';
import 'subscription_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Tabs that have been opened at least once. They stay mounted from then on
  /// (see [_buildTabContent]) so switching back is instant: no re-created
  /// State, no camera re-open, no entrance animations replaying from zero —
  /// all of which used to read as a second or two of black on every switch.
  final Set<int> _mountedTabs = {0};

  @override
  void initState() {
    super.initState();
    _currentIndex = shellTabIndex.value;
    _mountedTabs.add(_currentIndex);
    scanTabVisible.value = _currentIndex == 1;
    shellTabIndex.addListener(_onShellTabChanged);
    // Launch prompts, ordered so dialogs never stack: subscription upsell
    // first, then the notification-permission ask if still denied.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowLaunchPrompts(),
    );
    // Prompt for a Play Store rating after a few launches (best-effort).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RateUsService.onAppLaunch(context);
    });
  }

  /// Single entry point for tab changes (bottom-nav taps, swipes, notification
  /// taps). Tab switches are instant — no transition animation.
  void _goToTab(int index) {
    // Every tab change ticks, including a tap on the tab already showing, so
    // the bar never feels dead. Light impact (not selectionClick) — the
    // selection tick was too faint to notice on most phones.
    Haptics.light();
    // The nav A/B test counts every change, including the re-tap — which tab
    // people re-tap is part of what the two designs are measured on. Best
    // effort, never awaited.
    NavAbTest.instance.recordTabSelect(index);
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _mountedTabs.add(index);
    });
    // Lets the Scan tab pause its camera while the user is elsewhere.
    scanTabVisible.value = index == 1;
  }

  void _onShellTabChanged() {
    if (mounted) _goToTab(shellTabIndex.value);
  }

  @override
  void dispose() {
    shellTabIndex.removeListener(_onShellTabChanged);
    super.dispose();
  }

  Future<void> _maybeShowLaunchPrompts() async {
    await _maybeShowSubscription();
    // Notification permission ask — only if the user denied it.
    if (mounted) {
      await maybeShowNotificationPrompt(context);
    }
  }

  Future<void> _maybeShowSubscription() async {
    await SubscriptionService.instance.load();
    // Give Firebase a moment to restore the session before deciding: the
    // admin's lifetime grant lands via authStateChanges a beat later, and a
    // decision made before that is how the owner got asked to subscribe on
    // every fresh install.
    try {
      await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (_) {
      // No Firebase (tests, a build without it) — decide with what we have.
    }
    final prefs = await SharedPreferences.getInstance();
    final offered = prefs.getBool('subscription_offered') ?? false;
    final proOrAdmin = await SubscriptionService.instance.unlocksPro();
    final phone = prefs.getString('phone');
    if (!offered && !proOrAdmin && phone != null && mounted) {
      await prefs.setBool('subscription_offered', true);
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => _proUpsellMini(ctx),
        );
      }
    }
  }

  Widget _proUpsellMini(BuildContext dialogCtx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      // Scrollable so large system fonts can never overflow the dialog.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sparkle icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: MacroSnapTheme.accentGradient,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.black,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Unlock MacroSnap Pro',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 14),

            // Feature rows
            _proFeature(
              Icons.photo_camera_rounded,
              'Unlimited AI food scans',
              isDark,
            ),
            const SizedBox(height: 12),
            _proFeature(
              Icons.favorite_rounded,
              'Unlimited habit tracking',
              isDark,
            ),
            const SizedBox(height: 12),
            // "Cloud backup & restore" used to sit here, but it is not locked:
            // /meals/sync and /habits/sync accept any signed-in user, so every
            // account already gets it. Listing it sold something free, so it is
            // gone. The two rows below replace it — they ARE enforced by the
            // server, which refuses a free user with 403 pro_required.
            _proFeature(
              Icons.smart_toy_rounded,
              'Guru \u2014 your AI nutrition assistant',
              isDark,
            ),
            const SizedBox(height: 12),
            _proFeature(
              Icons.restaurant_menu_rounded,
              'AI meal plan built for your goals',
              isDark,
            ),
            const SizedBox(height: 12),
            _proFeature(
              Icons.insights_rounded,
              'Weekly auto-insights & trends',
              isDark,
            ),

            const SizedBox(height: 24),

            // Price & CTA
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: MacroSnapTheme.neonGreen,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_rounded, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          // Full label — FittedBox shrinks it to fit narrow
                          // screens instead of cutting it with an ellipsis.
                          // The ₹1 intro is once per account, so only promise
                          // it when this account still has it.
                          SubscriptionService.instance.introEligible
                              ? 'SUBSCRIBE · ${CurrencyService.instance.monthlyLabel}/mo · ${CurrencyService.instance.introLabel} first month'
                              : 'SUBSCRIBE · ${CurrencyService.instance.monthlyLabel}/mo',
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Dismiss
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Not now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proFeature(IconData icon, String label, bool isDark) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: MacroSnapTheme.neonGreen, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }

  /// Cached tab pages so switching tabs doesn't re-create screens.
  ///
  /// Order is the nav order: Home · Cam · Habits · Profile. Profile is a tab
  /// of its own now — it used to be the first row inside Settings, which hid
  /// the one screen that answers "what does the app know about me?" behind a
  /// settings list.
  late final List<Widget> _tabPages = const [
    HomeScreen(),
    ScanScreen(),
    HabitsTab(),
    ProfileScreen(),
  ];

  /// Keeps every visited tab mounted and paints only the selected one.
  ///
  /// `Offstage` keeps the State alive while hiding it (and `find.byType`
  /// skips it, matching the old "one page at a time" behaviour), and
  /// `TickerMode` stops hidden tabs from animating in the background.
  Widget _buildTabContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < _tabPages.length; i++)
          if (_mountedTabs.contains(i))
            Offstage(
              offstage: i != _currentIndex,
              child: TickerMode(
                enabled: i == _currentIndex,
                child: _tabPages[i],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // BadgeCelebration overlays the whole shell, so a badge earned by any
    // store (meal, weigh-in, streak) is announced without each screen caring.
    return BadgeCelebration(
      child: PopScope(
        // Back on the Scan tab returns Home (as before); on Home/Habits it
        // leaves the app. Only the visible tab may claim the back gesture.
        canPop: _currentIndex != 1,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goToTab(0);
        },
        child: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Swipe left/right anywhere on the tab body to move to the
            // adjacent tab (Home ⇄ Scan ⇄ Habits). Instant switch.
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 300) return;
              if (velocity < 0) {
                // Swipe left → next tab
                if (_currentIndex < _tabPages.length - 1) {
                  _goToTab(_currentIndex + 1);
                }
              } else {
                // Swipe right → previous tab
                if (_currentIndex > 0) _goToTab(_currentIndex - 1);
              }
            },
            child: _buildTabContent(),
          ),
          bottomNavigationBar: _buildBottomNav(context),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF17171D) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            width: 0.5,
          ),
        ),
      ),          child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // The A/B test decides which nav design this install draws:
              // pill (reference) or circle (previous). Same targets either
              // way, so the two arms differ only in the bar.
              if (NavAbTest.instance.variant == NavVariant.circle) ...[
                _NavItemCircle(
                  icon: Icons.home_rounded,
                  isSelected: _currentIndex == 0,
                  onTap: () => _goToTab(0),
                ),
                _NavItemCircle(
                  icon: Icons.photo_camera_rounded,
                  isSelected: _currentIndex == 1,
                  onTap: () => _goToTab(1),
                ),
                _NavItemCircle(
                  icon: Icons.favorite_rounded,
                  isSelected: _currentIndex == 2,
                  onTap: () => _goToTab(2),
                ),
                _NavItemCircle(
                  icon: Icons.person_rounded,
                  isSelected: _currentIndex == 3,
                  onTap: () => _goToTab(3),
                ),
              ] else ...[
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: _currentIndex == 0,
                  onTap: () => _goToTab(0),
                ),
                _NavItem(
                  icon: Icons.photo_camera_rounded,
                  label: 'Cam',
                  isSelected: _currentIndex == 1,
                  onTap: () => _goToTab(1),
                ),
                _NavItem(
                  icon: Icons.favorite_rounded,
                  label: 'Habits',
                  isSelected: _currentIndex == 2,
                  onTap: () => _goToTab(2),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _currentIndex == 3,
                  onTap: () => _goToTab(3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab button: the selected one is a filled pill carrying its label, the
/// rest are plain circles of the same height.
///
/// Every button keeps the same 46 dp height and a 46 dp minimum width, so the
/// row never shifts as selection moves — only the selected pill grows a label,
/// and the row is `spaceEvenly` so the growth is absorbed rather than pushing
/// the neighbouring circles sideways.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedIcon = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF64748B);

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 46,
          constraints: const BoxConstraints(minWidth: 46),
          padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 6),
          decoration: BoxDecoration(
            color: isSelected
                ? MacroSnapTheme.neonGreen
                : (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.06,
                  ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: isSelected ? Colors.black : unselectedIcon,
              ),
              if (isSelected) ...[
                const SizedBox(width: 7),
                // Capped width: four buttons have to fit a 320 dp phone, and
                // at 2x system text "Profile" is wider than its share of the
                // row. Ellipsising the label keeps the row inside its bounds —
                // an overflowing nav bar is a visible pink stripe on screen.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 64),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The previous nav design, preserved as the A/B control arm: every tab is a
/// plain icon-only circle of the same 46 dp height, the selected one filled
/// green. No label, no growing pill — the shape a user of 1.5.0–1.5.7 knew.
class _NavItemCircle extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItemCircle({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedIcon = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF64748B);

    return Semantics(
      button: true,
      selected: isSelected,
      label: switch (icon) {
        Icons.home_rounded => 'Home',
        Icons.photo_camera_rounded => 'Cam',
        Icons.favorite_rounded => 'Habits',
        _ => 'Profile',
      },
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? MacroSnapTheme.neonGreen
                : (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.06,
                  ),
          ),
          child: Icon(
            icon,
            size: 21,
            color: isSelected ? Colors.black : unselectedIcon,
          ),
        ),
      ),
    );
  }
}
