import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_nav.dart';
import 'core/theme.dart';
import 'navigation/route_observer.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/phone_login_screen.dart';
import 'widgets/startup_splash.dart';

/// How long the branded splash waits for startup work before giving up and
/// showing the app anyway. Every startup step is already error-guarded, so
/// this only covers a plugin that never answers — without it a wedged
/// platform call would leave the user on the splash forever.
const Duration kStartupTimeout = Duration(seconds: 8);

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

  @override
  void initState() {
    super.initState();
    _booting = widget.startup != null;
    _loadThemeMode();
    _checkOnboardingAndLogin();
    _awaitStartup();
    themeModeNotifier.addListener(_onThemeChanged);
  }

  /// Holds the splash until the work `main()` handed over is done, so no
  /// screen is ever built against half-loaded stores.
  Future<void> _awaitStartup() async {
    final startup = widget.startup;
    if (startup == null) return;
    try {
      await startup.timeout(kStartupTimeout);
    } catch (e) {
      debugPrint('❌ startup did not finish cleanly: $e');
    }
    if (!mounted) return;
    setState(() => _booting = false);
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
      if (mounted) {
        setState(() {
          _savedPhone = phone;
          _onboardingDone = onboardingDone;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking onboarding/login: $e');
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
              ? (_savedPhone != null
                  ? const MainShell()
                  : const PhoneLoginScreen())
              : OnboardingScreen(
                  nextScreen: _savedPhone != null
                      ? const MainShell()
                      : const PhoneLoginScreen(),
                ),
    );
  }
}
