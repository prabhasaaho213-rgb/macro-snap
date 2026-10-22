import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/haptics.dart';
import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../widgets/glass_card.dart';
import '../widgets/animations.dart';
import '../services/badge_service.dart';
import '../services/meal_store.dart';
import '../services/meal_sync_service.dart';
import '../services/habit_store.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../services/gemini_service.dart';
import 'subscription_screen.dart';
import 'phone_login_screen.dart';
import 'profile_screen.dart';
import 'updates_screen.dart';
import '../services/crash_reporting.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _name = 'User';
  String _email = '';
  bool _subscribed = false;
  bool _isAdmin = false;
  String? _subscribedDate;
  String? _proUntil;

  /// True while the newest release has not been opened from here yet —
  /// drives the dot on the "What's New" row. (This used to live on the
  /// bottom-nav Updates tab; the tab is gone, the badge moved with it.)
  bool _hasUnseenUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only refresh if we have stale data (avoid repeated network calls).
    // The screen refreshes when the user edits name or toggles subscription.
  }

  Future<void> _load() async {
    await SubscriptionService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    // _load() does several awaits; the screen can be popped before it
    // finishes, and setState() on a disposed State throws.
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('name') ?? 'User';
      _email = prefs.getString('email') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _subscribed = SubscriptionService.instance.isSubscribed;
      _subscribedDate = SubscriptionService.instance.subscribedAt;
      _proUntil = SubscriptionService.instance.proUntil;
      _hasUnseenUpdate =
          (prefs.getString(UpdatesScreen.seenVersionKey) ?? '') !=
          UpdatesScreen.latestVersion;
    });
    _isAdmin = await SubscriptionService.instance.isAdmin();
    if (mounted) setState(() {});
  }

  bool get _isGuest => _phone.isEmpty || _phone.startsWith('guest_');

  String _phone = '';

  Future<void> _upgradeFromGuest() async {
    final phone = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
    );
    if (phone != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', phone);
      // Trigger cloud re-sync with new phone identifier
      await MealStore.instance.reload();
      await HabitStore.instance.reload();
      await BadgeService.instance.reload();
      setState(() => _phone = phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account upgraded! Your data is now linked to your Google account.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context, bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: MacroSnapTheme.neonPink,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e, st) {
      logError('SettingsScreen._logout (FirebaseAuth)', e, st);
    }
    // Also clear the GoogleSignIn session so the cached account doesn't
    // silently auto-select on the next login — the user must pick again.
    try {
      await GoogleSignIn().signOut();
    } catch (e, st) {
      logError('SettingsScreen._logout (GoogleSignIn)', e, st);
    }
    final prefs = await SharedPreferences.getInstance();
    // Only clear auth/session keys — preserve subscription, habits, meals, settings
    await prefs.remove('phone');
    await prefs.remove('email');
    await prefs.remove('photo_url');
    await prefs.remove('last_sync');
    await prefs.remove('subscription_offered');
    unawaited(MealStore.instance.reload());
    unawaited(HabitStore.instance.reload());
    unawaited(BadgeService.instance.reload());
    unawaited(DietPlanService.instance.load());
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
        (route) => false,
      );
    }
  }

  /// In-app self-service account deletion.
  ///
  /// 1. Shows a confirmation dialog explaining this is permanent.
  /// 2. Calls the backend `POST /account/delete`, which wipes all cloud data
  ///    (Firestore docs and the legacy tables) but keeps a tombstone of the identifier + its
  ///    original trial start — so re-registering can never re-claim the free
  ///    trial (no delete -> re-login trial-abuse loop).
  /// 3. Wipes this device's local data and signs out, returning to login.
  Future<void> _deleteAccount(BuildContext context, bool isDark) async {
    if (_isGuest) {
      // Guests have no server account to delete — just clear local data.
      final confirmed = await _confirmDeleteDialog(
        context,
        isDark,
        title: 'Clear All Data?',
        body:
            'This removes all meals, habits and settings stored on this device. '
            'This cannot be undone.',
      );
      if (confirmed != true || !context.mounted) return;
      await _wipeLocalAndSignOut(context);
      return;
    }

    final confirmed = await _confirmDeleteDialog(
      context,
      isDark,
      title: 'Delete Account?',
      body:
          'This permanently deletes your account and ALL associated data: '
          'meals, habits, diet plans, subscription and personal info. '
          'This cannot be undone.\n\n'
          'Note: your phone / email will be remembered so it cannot be used '
          'to claim the free trial again.',
    );
    if (confirmed != true || !context.mounted) return;

    // Show a blocking progress dialog while we delete.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    var serverOk = false;
    try {
      // The token identifies the account being deleted — nothing else is sent.
      final uri = Uri.parse('${GeminiService.serverUrl}/account/delete');
      final res = await AuthHttp.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(const <String, dynamic>{}),
      ).timeout(const Duration(seconds: 20));
      serverOk = res.statusCode == 200;
    } catch (e) {
      debugPrint('Delete account server call failed: $e');
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress dialog

    if (!serverOk) {
      // Backend unreachable — do NOT wipe locally, so the user can retry or
      // still use the app. Tell them it failed.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not reach the server to delete your account. '
              'Please check your connection and try again.',
            ),
          ),
        );
      }
      return;
    }

    await _wipeLocalAndSignOut(context);
  }

  Future<bool?> _confirmDeleteDialog(
    BuildContext context,
    bool isDark, {
    required String title,
    required String body,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: MacroSnapTheme.neonPink,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Wipes every local store + prefs for the active account, signs out of
  /// Firebase/Google, and returns to the login screen.
  Future<void> _wipeLocalAndSignOut(BuildContext context) async {
    try {
      // Firebase Auth has no instance-level deleteUser(); the correct API is
      // delete() on the currently signed-in user.
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      // delete() needs a recent login; fall back to plain signOut.
      debugPrint('Firebase delete user failed: $e');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e2) {
        debugPrint('Error: $e2');
      }
    }
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Error: $e');
    }
    // Clear ALL local preferences (this device's partition + globals).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _sendFeedback(bool isDark) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Send Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your feedback helps us improve MacroSnap!',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Tell us what you think...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final msg = ctrl.text.trim();
              if (msg.isEmpty) return;
              final uri = Uri.parse(
                'mailto:macrosnap7@gmail.com?subject=MacroSnap Feedback&body=${Uri.encodeComponent(msg)}',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Thank you for your feedback!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 15,
          decoration: const InputDecoration(
            hintText: 'Your name (max 15 chars)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != _name) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', newName);
      userNameNotifier.value = newName;
      if (!mounted) return;
      setState(() => _name = newName);
      // Auto-sync name to cloud.
      MealSyncService.syncPreferences({'name': newName});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Tap = quick toggle light/dark · Long-press = full System picker
          Tooltip(
            message: 'Tap to toggle · Long-press for more',
            child: InkWell(
              onTap: () => _toggleTheme(isDark),
              onLongPress: () => _showThemeDialog(isDark),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: MacroSnapTheme.accentGradient,
                borderRadius: BorderRadius.circular(24),
                // A soft lift so the Pro banner sits above the flat cards
                // below it instead of reading as one more flat panel.
                boxShadow: [
                  BoxShadow(
                    color: MacroSnapTheme.neonOrange.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: GestureDetector(
                          onTap: _editName,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _name.isNotEmpty ? _name : 'User',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.edit_rounded,
                                    color: Colors.black,
                                    size: 16,
                                  ),
                                ],
                              ),
                              if (_email.isNotEmpty)
                                Text(
                                  _email,
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _isAdmin
                          ? 'Lifetime Pro'
                          : (_subscribed ? 'Pro Member' : 'Free User'),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Settings list card
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AnimatedEntrance(
                    delayMs: 50,
                    child: _settingTile(
                      Icons.person_rounded,
                      'Profile',
                      _isAdmin
                          ? '${_name.isNotEmpty ? _name : 'User'} · Lifetime Pro'
                          : '${_name.isNotEmpty ? _name : 'User'} · ${_subscribed ? 'Pro Member' : 'Free User'}',
                      () async {
                        await Navigator.push(
                          context,
                          habitFlowRoute(const ProfileScreen()),
                        );
                        // The profile editor can rename the user.
                        if (mounted) await _load();
                      },
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 120,
                    child: _settingTile(
                      Icons.subscriptions_rounded,
                      _isAdmin
                          ? 'My Subscription'
                          : (_subscribed
                                ? 'Manage Subscription'
                                : 'Upgrade to Pro'),
                      _isAdmin
                          ? 'Lifetime Pro · free forever'
                          : (_subscribed && _subscribedDate != null
                                ? (_proUntil != null
                                      ? 'Pro until ${_proUntil!.substring(0, 10)}'
                                      : 'Subscribed since ${_subscribedDate!.substring(0, 10)}')
                                : 'Unlock AI meal plans & more'),
                      () {
                        Navigator.push(
                          context,
                          habitFlowRoute(const SubscriptionScreen()),
                        );
                      },
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 215,
                    child: _settingTile(
                      Icons.new_releases_rounded,
                      "What's New",
                      _hasUnseenUpdate
                          ? 'New in ${UpdatesScreen.latestVersion} — tap to see'
                          : 'Release notes and update history',
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UpdatesScreen(),
                          ),
                        );
                        // Opening the page clears the dot.
                        if (mounted) setState(() => _hasUnseenUpdate = false);
                      },
                      isDark,
                      showBadge: _hasUnseenUpdate,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 250,
                    child: _settingTile(
                      Icons.mail_outline_rounded,
                      'Contact Support',
                      'macrosnap7@gmail.com',
                      () async {
                        final uri = Uri.parse('mailto:macrosnap7@gmail.com');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 260,
                    child: _settingTile(
                      Icons.star_rounded,
                      'Rate Us',
                      'Love MacroSnap? Leave a 5-star review',
                      () => RateUsService.rateNowFromSettings(),
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  if (_isGuest)
                    AnimatedEntrance(
                      delayMs: 270,
                      child: _settingTile(
                        Icons.person_add_rounded,
                        'Save Your Account',
                        'Link Google to keep your data permanently',
                        _upgradeFromGuest,
                        isDark,
                      ),
                    ),
                  if (_isGuest) const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 280,
                    child: _settingTile(
                      Icons.privacy_tip_outlined,
                      'Privacy Policy',
                      'How we handle your data',
                      () async {
                        final uri = Uri.parse(
                          'https://prabhasaaho213-rgb.github.io/macro-snap/',
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 300,
                    child: _settingTile(
                      Icons.delete_forever_outlined,
                      'Delete Account',
                      'Permanently delete your data',
                      () => _deleteAccount(context, isDark),
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 300,
                    child: _settingTile(
                      Icons.feedback_rounded,
                      'Send Feedback',
                      'Help us improve MacroSnap',
                      () => _sendFeedback(isDark),
                      isDark,
                    ),
                  ),
                  const Divider(height: 24),
                  AnimatedEntrance(
                    delayMs: 320,
                    child: _settingTile(
                      Icons.logout_rounded,
                      'Log Out',
                      'Sign out and return to login',
                      () => _logout(context, isDark),
                      isDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Made with ❤️ in India',
              style: TextStyle(
                fontSize: 12,
                color: MacroSnapTheme.textQuaternary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Quick toggle: flips between light and dark based on the CURRENT
  /// effective brightness (so System mode resolves to whichever it's showing).
  /// Full Light/Dark/System picker lives in [_showThemeDialog] (long-press).
  Future<void> _toggleTheme(bool isDark) async {
    final current = themeModeNotifier.value;
    final effectiveDark =
        current == ThemeMode.dark || (current == ThemeMode.system && isDark);
    final next = effectiveDark ? ThemeMode.light : ThemeMode.dark;
    if (next == current) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', next.name);
    themeModeNotifier.value = next;
    HapticFeedback.selectionClick();
    // Auto-sync theme to cloud.
    MealSyncService.syncPreferences({'themeMode': next.name});
  }

  Future<void> _showThemeDialog(bool isDark) async {
    final current = themeModeNotifier.value;
    final result = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) {
        ThemeMode selected = current;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Choose Theme',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            content: RadioGroup<ThemeMode>(
              groupValue: selected,
              onChanged: (v) {
                setDialogState(() {
                  selected = v!;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(
                        _themeModeLabel(mode),
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      subtitle: Text(
                        _themeModeSubtitle(mode),
                        style: TextStyle(
                          fontSize: 12,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                      activeColor: MacroSnapTheme.neonGreen,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result != current) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', result.name);
      themeModeNotifier.value = result;
      // Auto-sync theme to cloud.
      MealSyncService.syncPreferences({'themeMode': result.name});
    }
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  String _themeModeSubtitle(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follow your device setting';
      case ThemeMode.light:
        return 'Always light background';
      case ThemeMode.dark:
        return 'Always dark background';
    }
  }

  Widget _settingTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
    bool isDark, {
    bool showBadge = false,
  }) {
    return InkWell(
      // Settings rows had no haptics at all — every row now gives a tick, and
      // a disabled row stays silent.
      onTap: onTap == null
          ? null
          : () {
              Haptics.tap();
              onTap();
            },
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: MacroSnapTheme.neonGreen, size: 20),
              ),
              if (showBadge)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.macroFiber,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
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
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: MacroSnapTheme.textQuaternary(context),
              size: 20,
            ),
        ],
      ),
    );
  }
}
