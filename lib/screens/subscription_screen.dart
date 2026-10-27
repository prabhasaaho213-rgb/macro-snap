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
import '../services/currency_service.dart';
import '../services/scan_gate.dart';
import '../services/subscription_service.dart';
import 'referral_screen.dart';
import 'payment_result_screen.dart';
import '../services/crash_reporting.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String? _phone;
  bool _subscribed = false;
  bool _isAdmin = false;
  bool _submitting = false;
  bool _checking = true;
  String? _subscribedDate;

  /// Whether this account still has the ₹1 intro month on offer. Set from
  /// the server (`intro_eligible`) — the paywall never promises ₹1 to an
  /// account whose checkout would charge ₹49 from day one.
  bool _introEligible = true;

  /// Prices on this screen are re-labelled in the buyer's own currency (see
  /// [CurrencyService]); what Razorpay actually charges stays ₹49 INR.
  final CurrencyService _money = CurrencyService.instance;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
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
        if (data is Map) {
          final eligible = data['intro_eligible'] != false;
          if (eligible != _introEligible && mounted) {
            setState(() => _introEligible = eligible);
          }
          if (data['subscribed'] == true && !_subscribed) {
            // A restore, not a purchase: no celebration.
            await _activateFromServer(announce: false);
          }
        }
      }
    } catch (e, st) {
      logError('SubscriptionScreen._checkPaymentStatus', e, st);
    }
  }

  /// Switches the screen to Pro and (unless [announce] is false) plays the
  /// full-screen celebration. [announce] is false when Pro was simply restored
  /// on opening the screen — that is not a purchase the user just made.
  Future<void> _activateFromServer({bool announce = true}) async {
    // Post-activation side effects (pro reminders + meal-store refresh) live
    // inside SubscriptionService.activate so they aren't duplicated here and
    // in RazorpayService.
    await SubscriptionService.instance.activate();
    final now =
        SubscriptionService.instance.subscribedAt ??
        DateTime.now().toIso8601String();
    if (!mounted) return;
    setState(() {
      _subscribed = true;
      _subscribedDate = now;
    });
    if (announce) await _showSuccess();
  }

  /// Full-screen celebration after a verified purchase. Awaited so the screen
  /// can refresh its Pro state once the user dismisses it.
  Future<void> _showSuccess() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        // The server's verdict from this screen's own status check: the
        // confirmation quotes the price the checkout actually charged.
        builder: (_) => PaymentSuccessScreen(introOffer: _introEligible),
      ),
    );
    if (mounted) {
      await SubscriptionService.instance.load();
      setState(() {
        _subscribed = SubscriptionService.instance.isSubscribed;
        _subscribedDate = SubscriptionService.instance.subscribedAt;
      });
    }
  }

  /// Returns [PaymentAction.retry] when the user wants another attempt.
  Future<PaymentAction?> _showFailure(String message) {
    return Navigator.of(context).push<PaymentAction>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaymentFailureScreen(message: message),
      ),
    );
  }

  Future<void> _showPending(String message) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaymentPendingScreen(
          message: message,
          onCheckAgain: RazorpayService.refreshStatus,
        ),
      ),
    );
    if (mounted) {
      await SubscriptionService.instance.load();
      setState(() {
        _subscribed = SubscriptionService.instance.isSubscribed;
        _subscribedDate = SubscriptionService.instance.subscribedAt;
      });
    }
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

  /// Paying happens inside the app: Razorpay's native sheet opens over this
  /// screen and the outcome comes back as one [PaymentResult], so the user is
  /// never bounced into a browser mid-purchase.
  Future<void> _payWithRazorpay() async {
    if (_phone == null) return;
    setState(() => _submitting = true);
    PaymentResult result;
    try {
      // Identity (phone/email) comes from the verified token on the server.
      result = await RazorpayService.purchase(name: 'MacroSnap User');
    } catch (e) {
      result = PaymentResult.failed('Could not start the payment: $e');
    }
    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result.outcome) {
      case PaymentOutcome.success:
        await _activateFromServer();
        break;
      case PaymentOutcome.cancelled:
        _showError('Payment cancelled');
        break;
      case PaymentOutcome.pending:
        await _showPending(
          result.message ?? 'Confirming your payment with the bank.',
        );
        break;
      case PaymentOutcome.failed:
        final action = await _showFailure(
          result.message ?? 'The payment did not go through.',
        );
        if (action == PaymentAction.retry && mounted) await _payWithRazorpay();
        break;
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
                          : 'Enjoy all features. The ${_money.monthlyLabel} autopay runs from month 2.')
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
                  _introEligible
                      ? 'Pro costs ${_money.introLabel} for the first month — '
                            'you approve the ${_money.monthlyLabel}/month autopay '
                            'at checkout, and the first '
                            '${_money.monthlyLabel} charge happens 30 days in. '
                            'Cancel anytime.'
                      : 'Pro is ${_money.monthlyLabel}/month — cancel anytime. '
                            'Your ${_money.introLabel} first month was already '
                            'used on this account, so billing starts today.',
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
              // The whole app has exactly two plans. Free is listed first so the
              // price card below reads as "the other plan", not the only plan.
              _buildFreePlanCard(context, isDark),
              const SizedBox(height: 14),
              _buildProPlanHeader(context, isDark),
              const SizedBox(height: 10),
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
                              _money.currency.symbol,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: MacroSnapTheme.greenText(context),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _money.amount(CurrencyService.proMonthlyInr),
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
                            : (_introEligible
                                  ? 'First month ${_money.introLabel}, then ${_money.monthlyLabel}/month'
                                  : '${_money.monthlyLabel}/month \u2022 renews automatically'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: MacroSnapTheme.greenText(
                            context,
                          ).withValues(alpha: 0.8),
                        ),
                      ),
                      // Only shown when the price had to be converted: the
                      // buyer is told which currency their bank settles in, so
                      // the label and the statement never surprise each other.
                      if (_money.chargeNote != null) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _money.chargeNote!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: MacroSnapTheme.textTertiary(context),
                            ),
                          ),
                        ),
                      ],
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
                          label: _introEligible
                              ? 'Approve & Start — ${_money.introLabel} Today'
                              : 'Start Pro — ${_money.monthlyLabel} Today',
                          icon: Icons.lock_rounded,
                          loading: _submitting,
                          onPressed: _payWithRazorpay,
                          height: 52,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _introEligible
                              ? '${_money.introLabel} today • approves ${_money.monthlyLabel}/month autopay • ${_money.monthlyLabel} from day 31'
                              : '${_money.monthlyLabel} today • renews monthly • cancel anytime',
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

  /// A small rounded label, e.g. "CURRENT PLAN" or "₹49 / MONTH".
  Widget _planChip(String text, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: colour,
        ),
      ),
    );
  }

  Widget _planPoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_rounded,
            size: 15,
            color: MacroSnapTheme.successGreen,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Plan 1 of 2: what every account has without paying.
  Widget _buildFreePlanCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at 2x system text these labels are wide enough to
          // run off a 430dp card, and a plan name is not worth an overflow.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Free',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              _planChip(
                '${_money.currency.symbol}0',
                MacroSnapTheme.textSecondary(context),
              ),
              if (!_subscribed)
                _planChip('CURRENT PLAN', MacroSnapTheme.neonCyan),
            ],
          ),
          _planPoint(context, 'Manual meal logging and macros'),
          _planPoint(context, 'Streaks, meal history and charts'),
          _planPoint(context, '${ScanGate.freeLimitPerDay} AI scans a day'),
        ],
      ),
    );
  }

  /// Plan 2 of 2: the one you can buy. The price card right below carries the
  /// actual amount and the pay button.
  Widget _buildProPlanHeader(BuildContext context, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Pro',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
        _planChip(
          _introEligible
              ? '${_money.monthlyLabel} / MONTH · ${_money.introLabel} FIRST MONTH'
              : '${_money.monthlyLabel} / MONTH',
          MacroSnapTheme.neonOrange,
        ),
        if (_subscribed)
          _planChip(
            _isAdmin ? 'ADMIN \u2014 LIFETIME' : 'ACTIVE',
            MacroSnapTheme.successGreen,
          ),
      ],
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
