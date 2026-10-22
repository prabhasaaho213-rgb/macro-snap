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

/// How long the splash stays up when the app is really launching.
///
/// The logo intro is a 1.6 s Lottie, but startup work now finishes in a couple
/// of hundred milliseconds on a warm start — so the splash was torn down long
/// before the animation had played and the upgrade was effectively invisible
/// on exactly the devices it was meant for. The extra 200 ms lets the last
/// frame land before the first real screen replaces it.
///
/// Only applied when `main()` handed over startup work (a real launch); widget
/// tests construct `MacroSnapApp` without it and get the immediate hand-off.
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
  ThemeMode _themeMode = ThemeMode.system;

  /// Completes once the splash has been up for [kSplashMinimum].
  ///
  /// A timer started here (not a timestamp compared later) so the wait is
  /// driven by the same clock as the rest of the app — including the fake one
  /// widget tests run on — and so a slow startup simply arrives after it.
  final Completer<void> _introSettled = Completer<void>();
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    _booting = widget.startup != null;
    // No startup work means no real launch (widget tests): no minimum either.
    if (widget.startup != null) {
      _introTimer = Timer(kSplashMinimum, () {
        if (!_introSettled.isCompleted) _introSettled.complete();
      });
    }
    _loadThemeMode();
    _checkOnboardingAndLogin();
    _awaitStartup();
    themeModeNotifier.addListener(_onThemeChanged);
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

  /// Holds the splash until the logo intro has had room to play.
  ///
  /// A no-op once startup has already taken longer than [kSplashMinimum], so
  /// a slow launch is never made slower.
  Future<void> _waitForIntro() async {
    if (widget.startup == null) return;
    await _introSettled.future;
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    _introTimer?.cancel();
    _introTimer = null;
    // Release anyone still waiting rather than leaving them suspended forever.
    if (!_introSettled.isCompleted) _introSettled.complete();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _themeMode = themeModeNotifier.value;
      });
    }
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('theme_mode') ?? 'system';
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ThemeMode.system,
      );
      themeModeNotifier.value = _themeMode;
    } catch (e) {
      debugPrint('Error loading theme: $e');
      _themeMode = ThemeMode.system;
      themeModeNotifier.value = _themeMode;
    }
    if (mounted) {
      setState(() {});
    }
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
      theme: MacroSnapTheme.light,
      darkTheme: MacroSnapTheme.dark,
      themeMode: _themeMode,
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
