import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The frame the user sees while startup work finishes.
///
/// Why this exists: `runApp` used to be called only *after* Firebase,
/// notifications and every local store had finished loading. Until Flutter's
/// first frame the window keeps showing the native launch background, so a
/// slow launch (cold start, busy device, dark mode where that background is
/// near-black) read as several seconds of black before anything appeared.
///
/// Now the first frame is this screen — painted within a few milliseconds —
/// and the real UI replaces it as soon as the work is done.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key});

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Must equal android/app/src/main/res/values{,-night}/colors.xml
    // (`window_background`) so the hand-off from the native launch window is
    // invisible — same colour, no flash, and never a black frame.
    final background =
        isDark ? MacroSnapTheme.surfaceDark : MacroSnapTheme.surfaceLight;
    final wordmark = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: background,
      body: Semantics(
        label: 'MacroSnap is starting',
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: MacroSnapTheme.accentGradient,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: MacroSnapTheme.neonOrange.withValues(
                            alpha: isDark ? 0.28 : 0.22,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      size: 46,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'MacroSnap',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                      color: wordmark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Know your macros in a snap',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Thin indeterminate line — "still working" without the
                  // spinner that makes a fast launch feel slow. The splash has
                  // no work of its own, so it can animate at 60 fps while the
                  // init futures resolve behind it.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      width: 72,
                      height: 3,
                      child: LinearProgressIndicator(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.black.withValues(alpha: 0.07),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          MacroSnapTheme.neonOrange,
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
}
