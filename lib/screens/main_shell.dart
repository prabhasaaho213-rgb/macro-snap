import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_nav.dart';
import '../core/theme.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../widgets/notification_prompt.dart';
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

  @override
  void initState() {
    super.initState();
    _currentIndex = shellTabIndex.value;
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
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
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
                gradient: const LinearGradient(
                  colors: [MacroSnapTheme.neonGreen, Color(0xFF00CC52)],
                ),
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
            _proFeature(
              Icons.cloud_upload_rounded,
              'Cloud backup & restore',
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
                        'SUBSCRIBE · ₹29/mo',
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
  late final List<Widget> _tabPages = [
    const HomeScreen(),
    PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToTab(0);
      },
      child: const ScanScreen(),
    ),
    const HabitsTab(),
  ];

  /// Build the current tab content — plain instant switch, no transition.
  Widget _buildTabContent() {
    return _tabPages[_currentIndex.clamp(0, _tabPages.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isSelected
                ? const LinearGradient(
                    colors: [MacroSnapTheme.neonGreen, Color(0xFF00CC52)],
                  )
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
            size: 24,
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
