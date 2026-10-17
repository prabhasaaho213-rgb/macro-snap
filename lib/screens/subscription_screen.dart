import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/auth_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glass_card.dart';
import 'phone_login_screen.dart';
import '../services/gemini_service.dart';
import '../services/razorpay_service.dart';
import '../services/subscription_service.dart';
import 'referral_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  String? _phone;
  bool _subscribed = false;
  bool _isAdmin = false;
  bool _submitting = false;
  bool _checking = true;
  String? _subscribedDate;
  AnimationController? _animController;
  CurvedAnimation? _checkAnim;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    RazorpayService.clearCallbacks();
    _checkAnim?.dispose();
    _animController?.stop();
    _animController?.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    await SubscriptionService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone');
    final subscribed = SubscriptionService.instance.isSubscribed;
    final date = SubscriptionService.instance.subscribedAt;
    final isAdmin = await SubscriptionService.instance.isAdmin();
    if (mounted) {
      setState(() {
        _phone = phone;
        _subscribed = subscribed;
        _subscribedDate = date;
        _isAdmin = isAdmin;
      });
    }
    if (phone != null && !subscribed) await _checkPaymentStatus();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _checkPaymentStatus() async {
    try {
      // Phase 2: no identifier in the URL — the token identifies the caller,
      // so the status returned is always this user's own.
      final res = await AuthHttp.get(
        Uri.parse('${GeminiService.serverUrl}/me/payment/status'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            if (data['subscribed'] == true && !_subscribed) {
              _activateFromServer();
            }
          });
        }
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  Future<void> _activateFromServer() async {
    // Post-activation side effects (pro reminders + meal-store refresh) live
    // inside SubscriptionService.activate so they aren't duplicated here and
    // in RazorpayService.
    await SubscriptionService.instance.activate();
    final now =
        SubscriptionService.instance.subscribedAt ??
        DateTime.now().toIso8601String();
    if (mounted) {
      setState(() {
        _subscribed = true;
        _subscribedDate = now;
      });
      _showConfirmation();
    }
  }

  void _showConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _checkAnim?.dispose();
    _animController?.stop();
    _animController?.dispose();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkAnim = CurvedAnimation(
      parent: _animController!,
      curve: Curves.elasticOut,
    );
    _animController!.forward();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AnimatedBuilder(
          animation: _checkAnim!,
          builder: (_, _) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? MacroSnapTheme.cardDark
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: _checkAnim!.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
                      ),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: MacroSnapTheme.neonGreen,
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome to Pro!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your subscription is now active',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: MacroSnapTheme.neonGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Start Using MacroSnap',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: MacroSnapTheme.neonPink,
      ),
    );
  }

  Future<void> _payWithRazorpay() async {
    if (_phone == null) return;
    setState(() => _submitting = true);
    try {
      RazorpayService.setErrorCallback((msg) {
        if (mounted) _showError(msg);
      });
      RazorpayService.setSuccessCallback(() {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
          _activateFromServer();
        }
      });
      // Identity (phone/email) comes from the verified token on the server.
      await RazorpayService.startCheckout(name: 'MacroSnap User');
    } catch (e) {
      _showError('Could not start payment: $e');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startLogin() async {
    final phone = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
    );
    if (phone != null) setState(() => _phone = phone);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('MacroSnap Pro'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                // Soft tint + hairline ring instead of a heavy solid block:
                // the promo header should read as a badge, not a billboard.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MacroSnapTheme.neonOrange.withValues(alpha: 0.12),
                  border: Border.all(
                    color: MacroSnapTheme.neonOrange.withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MacroSnapTheme.neonOrange.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: MacroSnapTheme.neonOrange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _subscribed
                    ? (_isAdmin ? "You're a Lifetime Pro!" : "You're a Pro!")
                    : 'Never manually calculate macros again',
                // Center so the headline wraps cleanly on narrow screens
                // instead of hugging the left edge.
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subscribed
                    ? (_isAdmin
                          ? 'All Pro features, free forever'
                          : 'Enjoy all features. Billed ₹29 every month.')
                    : 'Snap, log, track your week automatically',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
              if (!_subscribed) ...[
                const SizedBox(height: 12),
                Text(
                  'Choose a plan below to unlock everything \u2014 cancel anytime.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.neonOrange,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              _buildFeatureRow(
                Icons.local_fire_department_rounded,
                'Streak Tracking',
                'Stay consistent with daily logging streaks',
                isDark,
              ),
              _buildFeatureRow(
                Icons.insights_rounded,
                'Weekly Auto-Insights',
                'See your protein gaps and trends without manual tracking',
                isDark,
              ),
              _buildFeatureRow(
                Icons.history_rounded,
                'Complete Meal History',
                'Review everything you ate, searchable by date',
                isDark,
              ),
              // "Cloud Backup" used to be listed here, but nothing locks it:
              // /meals/sync and /habits/sync accept any signed-in user, so it
              // is already free for everyone. A benefit that is not actually
              // gated reads as a false promise, so it has been removed and
              // replaced by the two features the server really does refuse
              // (403 pro_required).
              _buildFeatureRow(
                Icons.smart_toy_rounded,
                'Guru Assistant',
                'Ask about your own day — meals, macros, targets',
                isDark,
              ),
              _buildFeatureRow(
                Icons.restaurant_menu_rounded,
                'AI Meal Plan',
                'A full day of meals built around your goal',
                isDark,
              ),
              _buildFeatureRow(
                Icons.photo_camera_rounded,
                'Unlimited AI Scans',
                'Snap any meal for instant macros — no limits',
                isDark,
              ),
              const SizedBox(height: 32),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      // FittedBox: at large system font scales the fixed-size
                      // price glyphs would otherwise overflow the card width;
                      // scale the whole price line down as one unit instead.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\u20B9',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: MacroSnapTheme.greenText(context),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '29',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : MacroSnapTheme.cardDark,
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                '/ month',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: MacroSnapTheme.textTertiary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subscribed && _subscribedDate != null
                            ? (_isAdmin
                                  ? 'Lifetime \u2022 Free forever'
                                  : 'Auto-renews monthly')
                            : 'Auto-renews ₹29/month',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: MacroSnapTheme.greenText(
                            context,
                          ).withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_phone != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: MacroSnapTheme.successGreen,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Logged in as $_phone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: MacroSnapTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (!_subscribed && _checking)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!_subscribed && !_checking) ...[
                if (_phone == null) ...[
                  GradientButton(
                    label: 'Login to Subscribe',
                    onPressed: _startLogin,
                    height: 56,
                  ),
                ] else ...[
                  // Razorpay payment section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? MacroSnapTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: MacroSnapTheme.borderSubtle(context),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: MacroSnapTheme.neonGreen.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.credit_card_rounded,
                                color: MacroSnapTheme.neonGreen,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pay Online (Razorpay)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : MacroSnapTheme.cardDark,
                                    ),
                                  ),
                                  Text(
                                    'UPI, Card, Netbanking, Wallet',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: MacroSnapTheme.textTertiary(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        GradientButton(
                          label: 'Pay ₹29 & Subscribe',
                          icon: Icons.lock_rounded,
                          loading: _submitting,
                          onPressed: _payWithRazorpay,
                          height: 52,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Secure payment • Auto-renews ₹29/month',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: MacroSnapTheme.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (_subscribed) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      _isAdmin ? 'Lifetime Pro \u2713' : 'Subscribed \u2713',
                      style: TextStyle(
                        color: MacroSnapTheme.textSecondary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReferralScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refer a Friend',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : MacroSnapTheme.cardDark,
                              ),
                            ),
                            Text(
                              'Both get Pro free for a month',
                              style: TextStyle(
                                fontSize: 13,
                                color: MacroSnapTheme.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(
    IconData icon,
    String title,
    String subtitle,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: MacroSnapTheme.neonGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: MacroSnapTheme.neonGreen,
            size: 22,
          ),
        ],
      ),
    );
  }
}
