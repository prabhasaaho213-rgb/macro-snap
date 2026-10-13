import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_nav.dart';
import 'core/theme.dart';
import 'navigation/route_observer.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/phone_login_screen.dart';

class MacroSnapApp extends StatefulWidget {
  const MacroSnapApp({super.key});

  @override
  State<MacroSnapApp> createState() => _MacroSnapAppState();
}

class _MacroSnapAppState extends State<MacroSnapApp> {
  bool _loading = true;
  String? _savedPhone;
  bool _onboardingDone = false;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _checkOnboardingAndLogin();
    themeModeNotifier.addListener(_onThemeChanged);
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
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
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
