import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../services/gemini_service.dart';
import '../services/meal_store.dart';
import '../services/habit_store.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../widgets/nickname_prompt.dart';
import 'main_shell.dart';

class PhoneLoginScreen extends StatefulWidget {
  final String? returnRoute;
  const PhoneLoginScreen({super.key, this.returnRoute});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen>
    with SingleTickerProviderStateMixin {
  final _googleSignIn = GoogleSignIn(
    serverClientId:
        '562037381-u8bkrnf1mcl7k7ed6njq7ag46fefrera.apps.googleusercontent.com',
  );
  bool _loading = false;
  String _error = '';
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // Load the saved character profile
    // their own look (gender, skin tone, build).
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    await DietPlanService.instance.load();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // Clear any cached Google session first so the account chooser ALWAYS
      // appears — never silently reuse the last signed-in account.
      try {
        await _googleSignIn.signOut();
      } catch (e) { debugPrint("Error: $e"); }
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (!mounted) return;

      final googleAuth = await googleUser.authentication;
      if (!mounted) return;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user after sign in');

      final email = user.email ?? googleUser.email;
      final name = user.displayName ?? googleUser.displayName ?? 'User';
      final photoUrl = user.photoURL ?? googleUser.photoUrl;

      final prefs = await SharedPreferences.getInstance();

      // Returning user? A saved nickname marks them — they are never asked
      // again. When local prefs are empty (reinstall / new device), try to
      // restore the nickname saved on the server during a previous
      // registration so an existing user isn't re-asked on a fresh install.
      var nickname = prefs.getString('nickname');
      if (nickname == null || nickname.trim().isEmpty) {
        final restored = await NicknameStore.restoreFromServer(email);
        if (restored != null && restored.trim().isNotEmpty) {
          nickname = restored.trim();
          await prefs.setString('nickname', nickname);
        }
      }

      await prefs.setString('phone', email);
      await prefs.setString('email', email);
      // A saved nickname must NEVER be overwritten by the Google display
      // name — the greeting keeps the user's chosen nickname forever.
      await NicknameStore.persistLoginName(prefs, name);
      if (photoUrl != null) await prefs.setString('photo_url', photoUrl);

      // Brand-new users (no nickname anywhere) pick one once (limited to 15
      // characters). Skipping never blocks login — they get asked again on
      // a future login until they set one. A restored server nickname marks
      // a returning user, so isNewUser stays false for them.
      final isNewUser = NicknameStore.shouldAskNickname(prefs);
      if (NicknameStore.shouldAskNickname(prefs)) {
        final chosen = mounted ? await showNicknamePrompt(context) : null;
        if (chosen != null && chosen.trim().isNotEmpty && mounted) {
          nickname = chosen.trim();
          await prefs.setString('nickname', nickname);
          await prefs.setString('name', nickname);
        }
      }
      try {
        await http.post(
          Uri.parse('${GeminiService.serverUrl}/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': email,
            'email': email,
            'name': nickname ?? name,
          }),
        );
      } catch (e) { debugPrint("Error: $e"); }

      // Brand-new users get a one-shot Play Store rating button right after
      // their first login. Shown before navigating so the context is valid.
      if (isNewUser && mounted) {
        await RateUsService.showNewUserRatingButton(context);
      }

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context, email);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainShell()),
          );
        }
      }
      // Pull in cloud backup for the newly active account in the background
      // (non-blocking so sign-in isn't stalled by the cloud fetch).
      // Hand this account its one-time 30-day free plan — this call is
      // also what existing users get right after updating + logging in.
      unawaited(SubscriptionService.instance.verifyServerSubscription());
      unawaited(MealStore.instance.reload());
      unawaited(HabitStore.instance.reload().catchError((e) { debugPrint('HabitStore reload error: $e'); }));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Google sign in failed: ${e.toString()}';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        // Center the whole page vertically on every screen size: content
        // sits at the screen center when it fits, and scrolls instead of
        // overflowing when it doesn't (small phones / large system fonts).
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    size: 48,
                    color: MacroSnapTheme.neonGreen,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome to MacroSnap',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Snap a photo, get your macros',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 24),

                // Google Sign-In
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isDark ? MacroSnapTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.3 : 0.06,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _loading ? null : _signInWithGoogle,
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.network(
                                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                      width: 22,
                                      height: 22,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.g_mobiledata,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        'Log in with Google',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1A1A1A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Error banner
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          sin(_shakeController.value * 4 * 3.14) * 6,
                          0,
                        ),
                        child: child,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? MacroSnapTheme.neonPink.withValues(alpha: 0.15)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: isDark
                                ? MacroSnapTheme.neonPink
                                : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? MacroSnapTheme.neonPink
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Text(
                  'Your meals, habits and progress are securely backed up to your Google account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),

                const SizedBox(height: 32),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      color: MacroSnapTheme.textQuaternary(context),
                    ),
                    children: [
                      const TextSpan(text: 'By continuing, you agree to our '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: MacroSnapTheme.greenText(context),
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final uri = Uri.parse(
                              'https://raw.githubusercontent.com/prabhasaaho213-rgb/macro-snap-source-1.4.5/master/PRIVACY_POLICY.md',
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
