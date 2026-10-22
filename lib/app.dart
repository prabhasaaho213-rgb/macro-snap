import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

/// How long the logo intro is allowed to run on the launches that show it.
///
/// The intro is a 1.6 s Lottie and startup work now finishes in a couple of
/// hundred milliseconds on a warm start, so the splash used to be torn down
/// before the animation had played — the upgrade was invisible on exactly the
/// devices it was meant for. 1.8 s lets the last frame land and the reveal
/// happen after it rather than on top of it.
///
/// Deliberately NOT every launch: a returning user on the same build opens
/// straight into the app. The floor applies only on the first launch of a
/// version — a fresh install or the first run after an update — where the
/// intro is actually new. See [_MacroSnapAppState._introFloorForLaunch].
const Duration kSplashMinimum = Duration(milliseconds: 1800);

/// Remembers which build has already shown its intro.
const String kIntroSeenVersionKey = 'intro_seen_version';

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

  /// Resolves after [kSplashMinimum] on the first launch of a version, and
  /// immediately on every other launch.
  ///
  /// The intro is new exactly once per build, so that is the only time it is
  /// worth holding the first screen back. A user who opens the app ten times a
  /// day on the same build should never wait for an animation they have already
  /// seen. If the version cannot be read, no delay is applied: an unknown
  /// build is not a reason to slow somebody down.
  Future<void> _introFloorForLaunch() async {
    String version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      return;
    }
    if (version.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(kIntroSeenVersionKey) == version) return;
      // Recorded before the wait, so an app killed mid-intro does not replay it
      // on the next launch.
      await prefs.setString(kIntroSeenVersionKey, version);
    } catch (_) {
      return;
    }
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

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
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
