import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_nav.dart';
import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../widgets/notification_prompt.dart';
import '../widgets/badge_board.dart';
import 'home_screen.dart';
import 'habits_tab.dart';
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
    final prefs = await SharedPreferences.getInstance();
    final offered = prefs.getBool('subscription_offered') ?? false;
    final subscribed = SubscriptionService.instance.isSubscribed;
    final phone = prefs.getString('phone');
    if (!offered && !subscribed && phone != null && mounted) {
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_rounded, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // Short label so it fits fully on narrow screens — no
                        // wrapping or truncation of the CTA.
                        'SUBSCRIBE · ₹49/mo · 1st month free',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
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
  late final List<Widget> _tabPages = const [
    HomeScreen(),
    ScanScreen(),
    HabitsTab(),
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
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                isSelected: _currentIndex == 0,
                onTap: () => _goToTab(0),
              ),
              _NavItem(
                icon: Icons.camera_alt_rounded,
                label: 'Scan',
                isSelected: _currentIndex == 1,
                isScan: true,
                onTap: () => _goToTab(1),
              ),
              _NavItem(
                icon: Icons.favorite_rounded,
                label: 'Habits',
                isSelected: _currentIndex == 2,
                onTap: () => _goToTab(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isScan;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.isScan = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isScan) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          // 46 (was 52): the scan button still leads, but no longer dwarfs
          // the Home/Habits tabs; the halo carries the emphasis instead.
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: MacroSnapTheme.neonOrange.withValues(alpha: 0.30),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
            gradient: isSelected
                ? MacroSnapTheme.accentGradient
                : LinearGradient(
                    colors: [
                      (isDark ? Colors.white : MacroSnapTheme.neonGreen)
                          .withValues(alpha: 0.1),
                      (isDark ? Colors.white : MacroSnapTheme.neonGreen)
                          .withValues(alpha: 0.05),
                    ],
                  ),
            border: Border.all(
              color: isSelected
                  ? MacroSnapTheme.neonGreen
                  : (isDark ? Colors.white : MacroSnapTheme.neonGreen)
                        .withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: isSelected
                ? Colors.black
                : (isDark
                      ? Colors.white54
                      : MacroSnapTheme.neonGreen.withValues(alpha: 0.6)),
            size: 22,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? MacroSnapTheme.neonGreen.withValues(alpha: 0.15)
                    : MacroSnapTheme.neonGreen.withValues(alpha: 0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? MacroSnapTheme.neonGreen
                  : (MacroSnapTheme.textTertiary(context)),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.greenText(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
