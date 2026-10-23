import 'package:flutter/material.dart';
import '../core/haptics.dart';
import '../core/theme.dart';
import '../widgets/animations.dart';
import '../widgets/confetti_celebration.dart';
import '../widgets/gradient_button.dart';

/// What the user chose on a result screen. Callers use this to decide whether
/// to re-open checkout, so the screens never navigate on their own.
enum PaymentAction { done, retry }

// ─── SUCCESS ───────────────────────────────────────────────────────────────

/// Full-screen confirmation after the backend has verified the payment.
///
/// The old flow ended in an `AlertDialog` with a snapping check icon. This one
/// is the moment the user just paid for, so it gets the whole screen: a check
/// that draws itself, confetti, and the Pro badge landing with an elastic
/// pop — finished before the user has read the headline.
class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key, this.celebrate = true});

  /// Confetti is skipped in widget tests (its repeating controller would
  /// outlive the pump), and anywhere motion should stay cheap.
  final bool celebrate;

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final Animation<double> _check = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _badge = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.elasticOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Haptics.medium();
    if (widget.celebrate) {
      // After the first frame so the confetti overlay sits above the page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ConfettiCelebration.show(context, particleCount: 80);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Drawn check mark inside a soft success halo.
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MacroSnapTheme.successGreen.withValues(
                          alpha: isDark ? 0.16 : 0.12,
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _check,
                      builder: (_, _) => CustomPaint(
                        size: const Size(132, 132),
                        painter: _CheckPainter(
                          progress: _check.value,
                          color: MacroSnapTheme.successGreen,
                        ),
                      ),
                    ),
                    ScaleTransition(
                      scale: _badge,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: MacroSnapTheme.accentGradient,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "You're Pro",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹0 first month · then ₹49/month · cancel anytime',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 28),
              Column(
                children: const [
                  _SuccessRow(
                    icon: Icons.photo_camera_rounded,
                    label: 'Unlimited AI food scans',
                  ),
                  _SuccessRow(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Guru chat and AI meal plans',
                  ),
                  _SuccessRow(
                    icon: Icons.cloud_done_rounded,
                    label: 'Everything synced to your account',
                  ),
                ],
              ),
              const Spacer(flex: 3),
              GradientButton(
                label: 'Start using MacroSnap',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.of(context).pop(PaymentAction.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SuccessRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: MacroSnapTheme.successGreen.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 18, color: MacroSnapTheme.successGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF3A3A3A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the tick by revealing a stroke along its path — no asset, no icon
/// font, and it animates from zero which is what makes it read as "drawn".
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final stroke = size.width * 0.045;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.53)
      ..lineTo(size.width * 0.44, size.height * 0.71)
      ..lineTo(size.width * 0.77, size.height * 0.34);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── FAILURE ───────────────────────────────────────────────────────────────

/// Shown when the payment did not go through. The icon shakes once, so the
/// outcome registers before the text is read, and the only loud thing on the
/// screen is the retry button.
class PaymentFailureScreen extends StatefulWidget {
  const PaymentFailureScreen({
    super.key,
    required this.message,
    this.canRetry = true,
  });

  final String message;
  final bool canRetry;

  @override
  State<PaymentFailureScreen> createState() => _PaymentFailureScreenState();
}

class _PaymentFailureScreenState extends State<PaymentFailureScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              ShakeWidget(
                controller: _shake,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MacroSnapTheme.neonPink.withValues(
                      alpha: isDark ? 0.18 : 0.12,
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: MacroSnapTheme.neonPink,
                    size: 54,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Payment did not go through',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 18),
              // Set expectations instead of a vague "something went wrong":
              // a bank can confirm after the app has given up.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.7),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nothing is charged twice. If money was deducted, Pro '
                        'switches on by itself within a few minutes.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: MacroSnapTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              if (widget.canRetry)
                GradientButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: () =>
                      Navigator.of(context).pop(PaymentAction.retry),
                ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(PaymentAction.done),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── PENDING ───────────────────────────────────────────────────────────────

/// "We are waiting on the bank." Used when the payment might still land —
/// the hosted-page fallback, or a verification that has not propagated. Pro
/// activates by itself; this screen just lets the user check.
class PaymentPendingScreen extends StatefulWidget {
  const PaymentPendingScreen({
    super.key,
    required this.message,
    this.onCheckAgain,
  });

  final String message;

  /// Returns true once the backend reports Pro. When null the button just
  /// closes the screen.
  final Future<bool> Function()? onCheckAgain;

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  bool _checking = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final check = widget.onCheckAgain;
    if (check == null || _checking) return;
    setState(() => _checking = true);
    final ok = await check();
    if (!mounted) return;
    if (ok) {
      // Replace rather than stack: the wait is over.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PaymentSuccessScreen()),
      );
      return;
    }
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not confirmed yet — this can take a few minutes.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) {
                  final t = _pulse.value;
                  return Container(
                    width: 108 + 8 * t,
                    height: 108 + 8 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MacroSnapTheme.neonOrange.withValues(
                        alpha: 0.10 + 0.06 * t,
                      ),
                    ),
                    child: const Icon(
                      Icons.hourglass_bottom_rounded,
                      color: MacroSnapTheme.neonOrange,
                      size: 48,
                    ),
                  );
                },
              ),
              const SizedBox(height: 26),
              Text(
                'Confirming your payment',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
              const Spacer(flex: 3),
              GradientButton(
                label: 'Check again',
                icon: Icons.refresh_rounded,
                loading: _checking,
                onPressed: _checking ? null : _check,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(PaymentAction.done),
                child: Text(
                  "I'll check later",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
