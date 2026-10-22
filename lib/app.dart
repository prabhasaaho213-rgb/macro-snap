import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_nav.dart';
import 'core/theme.dart';
import 'navigation/route_observer.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/phone_login_screen.dart';
import 'widgets/startup_splash.dart';

/// Last-resort cap on the whole splash.
///
/// Each startup step now has its own bound (`_guardStartup` in `main.dart`),
/// so reaching this means something ignored its own timeout. When that
/// happens the app opens with whatever did load rather than never opening —
/// that is a deliberate trade: a missing list is recoverable, a permanent
/// splash is not.
const Duration kStartupTimeout = Duration(seconds: 12);

/// How long the logo intro is allowed to run on every launch.
///
/// The intro is a 1.6 s Lottie and startup work now finishes in a couple of
/// hundred milliseconds on a warm start, so reducing the intro to the first
/// launch of a version made every other open skip the animation entirely —
/// the user saw the splash blink and disappear. The floor applies on every
/// launch now: startup may finish in 200 ms, but the splash holds until the
/// 1.6 s Lottie has finished playing, then the screen swaps.
const Duration kSplashMinimum = Duration(milliseconds: 1800);

class MacroSnapApp extends StatefulWidget {
  /// Startup work that must finish before the first real screen is built
  /// (Firebase, plugins, local stores). Passed in by `main()` so the first
  /// frame can paint immediately; `null` — as in widget tests — means there
  /// is nothing to wait for.
  final Future<void>? startup;

  const MacroSnapApp({super.key, this.startup});

  @override
  State<MacroSnapApp> createState() => _MacroSnapAppState();
}

class _MacroSnapAppState extends State<MacroSnapApp> {
  bool _loading = true;
  bool _booting = true;
  String? _savedPhone;
  bool _onboardingDone = false;

  /// Completes once the intro has had its time (or immediately, on a launch
  /// that does not show it). Started here so the wait is measured from the
  /// first frame — including on the fake clock widget tests run on — and so a
  /// slow startup simply arrives after it.
  Future<void> _introFloor = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _booting = widget.startup != null;
    // No startup work means no real launch (widget tests): no floor either.
    if (widget.startup != null) _introFloor = _introFloorForLaunch();
    _checkOnboardingAndLogin();
    _awaitStartup();
  }

  /// Holds the splash until the work `main()` handed over is done.
  ///
  /// Each step is bounded in `main.dart`, so this normally completes once the
  /// stores are loaded. [kStartupTimeout] is the fallback for a step that
  /// ignored its own limit; in that case the app opens anyway, with a log
  /// line rather than a stuck splash.
  Future<void> _awaitStartup() async {
    final startup = widget.startup;
    if (startup == null) return;
    try {
      await startup.timeout(kStartupTimeout);
    } on TimeoutException {
      debugPrint(
        '❌ startup exceeded ${kStartupTimeout.inSeconds}s — opening with the '
        'data that did load',
      );
    } catch (e) {
      debugPrint('❌ startup did not finish cleanly: $e');
    }
    await _waitForIntro();
    if (!mounted) return;
    setState(() => _booting = false);
  }

  /// Resolves after [kSplashMinimum] on every launch.
  ///
  /// This used to apply only on the first launch of a version, so the
  /// animation the user already saw was cut short on every later open — the
  /// splash was torn down the moment startup resolved. Holding for the intro
  /// on every launch is what the user actually wants to see; startup work
  /// keeps running behind the splash the whole time, so the only cost is the
  /// wait itself.
  Future<void> _introFloorForLaunch() async {
    await Future<void>.delayed(kSplashMinimum);
  }

  /// Holds the splash until the logo intro has had room to play.
  ///
  /// A no-op once startup has already taken longer than [kSplashMinimum], so
  /// a slow launch is never made slower.
  Future<void> _waitForIntro() async {
    if (widget.startup == null) return;
    await _introFloor;
  }

  Future<void> _checkOnboardingAndLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone');
      // Use v2 key so existing users (who completed old feature tour)
      // see the new Cal AI-style onboarding once.
      final onboardingDone = prefs.getBool('onboarding_v2_done') ?? false;
      await _waitForIntro();
      if (mounted) {
        setState(() {
          _savedPhone = phone;
          _onboardingDone = onboardingDone;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking onboarding/login: $e');
      await _waitForIntro();
      if (mounted) {
        setState(() {
          _savedPhone = null;
          _onboardingDone = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MacroSnap',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      navigatorObservers: [routeObserver],
      // MacroSnap is dark-only: the user picks nothing, nothing is persisted,
      // and both MaterialApp bots point at the dark theme so no requested
      // brightness (or a stale 'theme_mode' pref left on devices) can ever
      // produce a light screen.
      theme: MacroSnapTheme.dark,
      darkTheme: MacroSnapTheme.dark,
      themeMode: ThemeMode.dark,
      // The splash is painted on the very first frame; the home below is
      // chosen only once prefs are read and startup work has finished.
      home: _loading || _booting
          ? const StartupSplash()
          : _onboardingDone
          ? (_savedPhone != null ? const MainShell() : const PhoneLoginScreen())
          : OnboardingScreen(
              nextScreen: _savedPhone != null
                  ? const MainShell()
                  : const PhoneLoginScreen(),
            ),
    );
  }
}
