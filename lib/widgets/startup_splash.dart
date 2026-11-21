import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
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

  /// True once the intro animation has finished (or failed to load).
  ///
  /// The Lottie plays exactly once — 96 frames at 60 fps, 1.6 s — so a splash
  /// that outlives a slow startup shows the settled logo, not a looped
  /// animation that makes the wait feel longer than it is.
  bool _introDone = false;

  /// The static flame logo shown behind the Lottie and as the Lottie's
  /// first-frame placeholder. Showing it (instead of an empty [SizedBox])
  /// during the brief `loaded == null` window means the logo area is never
  /// momentarily transparent over the dark splash.
  static Widget get _logoMarker {
    return Container(
      width: 88,
      height: 88,
      decoration: const BoxDecoration(
        gradient: MacroSnapTheme.accentGradient,
        borderRadius: BorderRadius.all(Radius.circular(26)),
      ),
      child: const Icon(
        Icons.local_fire_department_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  /// The delayed detach fired when the composition ends. Held so [dispose]
  /// can cancel it — a timer outliving the widget leaks (and fails tests).
  Timer? _introEnd;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _introEnd?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Must equal android/app/src/main/res/values{,-night}/colors.xml
    // (`window_background`) so the hand-off from the native launch window is
    // invisible — same colour, no flash, and never a black frame.
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;
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
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Logo intro: rings + sparks around the mark, plays
                        // once while startup keeps running behind the splash.
                        // errorBuilder: a corrupt asset degrades to the plain
                        // logo instead of a broken screen on launch.
                        if (!_introDone)
                          Lottie.asset(
                            'assets/animations/logo_intro.json',
                            repeat: false,
                            frameBuilder: (context, child, loaded) {
                              // Never paint an empty (transparent) slot over the dark
                              // splash: while the composition is still being resolved show
                              // the static flame logo instead, so the logo area is never
                              // momentarily blank at the very first frame.
                              if (loaded == null) {
                                return _logoMarker;
                              }
                              return child;
                            },
                            errorBuilder: (context, error, stack) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && !_introDone) {
                                  setState(() => _introDone = true);
                                }
                              });
                              // A corrupt Lottie asset degrades to the static logo
                              // rather than an empty screen on launch.
                              return _logoMarker;
                            },
                            onLoaded: (composition) {
                              // Detach after the composition ends so the last
                              // frame does not linger under the logo.
                              _introEnd?.cancel();
                              _introEnd = Timer(composition.duration, () {
                                if (mounted && !_introDone) {
                                  setState(() => _introDone = true);
                                }
                              });
                            },
                          ),
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
                      ],
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
