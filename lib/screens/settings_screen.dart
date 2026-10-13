import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../widgets/glass_card.dart';
import '../widgets/animations.dart';
import '../services/meal_store.dart';
import '../services/meal_sync_service.dart';
import '../services/habit_store.dart';
import '../services/rate_us_service.dart';
import '../services/subscription_service.dart';
import '../services/recent_food_service.dart';
import 'subscription_screen.dart';
import 'phone_login_screen.dart';
import 'updates_screen.dart';

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
  String _lastSync = '';
  bool _syncing = false;

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
    // Real installed version from the platform (zero drift with pubspec);
    // falls back to the constant when the platform channel is unavailable.
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) _packageVersion = info.version;
    } catch (e) { debugPrint("Error: $e"); }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('name') ?? 'User';
      _email = prefs.getString('email') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _subscribed = SubscriptionService.instance.isSubscribed;
      _subscribedDate = SubscriptionService.instance.subscribedAt;
      _lastSync = prefs.getString('last_sync') ?? '';
      _hasUnseenUpdate =
          (prefs.getString(UpdatesScreen.seenVersionKey) ?? '') !=
          UpdatesScreen.latestVersion;
    });
    _isAdmin = await SubscriptionService.instance.isAdmin();
    if (mounted) setState(() {});
  }

  bool get _isGuest => _phone.isEmpty || _phone.startsWith('guest_');

  /// Whether the user needs a backup reminder (no sync in 7+ days).
  bool get _needsBackupReminder {
    if (_isGuest || _lastSync.isEmpty) return false;
    try {
      // Parse the sync time (format: 'dd/MM/yyyy HH:mm')
      final parts = _lastSync.split(' ');
      if (parts.length != 2) return false;
      final dateParts = parts[0].split('/');
      if (dateParts.length != 3) return false;
      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      final timeParts = parts[1].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final lastSyncDate = DateTime(year, month, day, hour, minute);
      final daysSinceSync = DateTime.now().difference(lastSyncDate).inDays;
      return daysSinceSync >= 7;
    } catch (_) {
      return false;
    }
  }
  String _phone = '';
  String _packageVersion = '1.4.66';

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
    } catch (e) { debugPrint("Error: $e"); }
    // Also clear the GoogleSignIn session so the cached account doesn't
    // silently auto-select on the next login — the user must pick again.
    try {
      await GoogleSignIn().signOut();
    } catch (e) { debugPrint("Error: $e"); }
    final prefs = await SharedPreferences.getInstance();
    // Only clear auth/session keys — preserve subscription, habits, meals, settings
    await prefs.remove('phone');
    await prefs.remove('email');
    await prefs.remove('photo_url');
    await prefs.remove('last_sync');
    await prefs.remove('subscription_offered');
    unawaited(MealStore.instance.reload());
    unawaited(HabitStore.instance.reload());
    unawaited(DietPlanService.instance.load());
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
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
                gradient: const LinearGradient(
                  colors: [MacroSnapTheme.neonGreen, Color(0xFF00CC52)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
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
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
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
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
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
            // Backup reminder banner
            if (_needsBackupReminder) _buildBackupReminder(isDark),
            // Settings list card
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AnimatedEntrance(
                    delayMs: 50,
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
                                ? 'Subscribed since ${_subscribedDate!.substring(0, 10)}'
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
                    delayMs: 100,
                    child: _settingTile(
                      Icons.cloud_upload_rounded,
                      'Cloud Backup',
                      _syncing
                          ? 'Syncing...'
                          : (_lastSync.isNotEmpty
                                ? 'Last sync: $_lastSync'
                                : 'Never backed up'),
                      () => _showBackupDialog(isDark),
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
                    delayMs: 220,
                    child: _settingTile(
                      Icons.info_outline_rounded,
                      'App Version',
                      _packageVersion,
                      null,
                      isDark,
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
                          'https://prabhasaaho213-rgb.github.io/macro-snap-source-1.4.5/',
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
                      () async {
                        final uri = Uri.parse(
                          'https://prabhasaaho213-rgb.github.io/macro-snap-source-1.4.5/delete-account.html',
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

  Future<void> _showBackupDialog(bool isDark) async {
    final canSync = !_isGuest;

    // Fetch current counts for the status display
    final mealCount = MealStore.instance.allMeals.length;
    final habitCount = HabitStore.instance.habits.length;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [MacroSnapTheme.neonGreen, Color(0xFF00CC52)],
                ),
              ),
              child: const Icon(
                Icons.cloud_upload_rounded,
                color: Colors.black,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Cloud Backup',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),

            // Status description
            Text(
              _syncing
                  ? 'Syncing all data...'
                  : canSync
                  ? (_lastSync.isNotEmpty
                        ? 'Data backed up safely'
                        : 'Your data has never been backed up')
                  : 'Sign in to enable cloud backup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),

            if (_syncing) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MacroSnapTheme.neonGreen,
                ),
              ),
            ],

            if (!_syncing && canSync) ...[
              const SizedBox(height: 20),

              // Meals backup status
              _backupRow(
                Icons.restaurant_rounded,
                'Meals',
                '$mealCount meal${mealCount == 1 ? '' : 's'} tracked',
                isDark,
              ),
              const SizedBox(height: 10),

              // Habits backup status
              _backupRow(
                Icons.favorite_rounded,
                'Habits + Water',
                '$habitCount habit${habitCount == 1 ? '' : 's'}${HabitStore.instance.waterGoal > 0 ? ' · ${HabitStore.instance.waterGoal} glasses goal' : ''}',
                isDark,
              ),

              // Last sync time
              if (_lastSync.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Last sync: $_lastSync',
                      style: TextStyle(
                        fontSize: 12,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ],
            ],

            const SizedBox(height: 22),

            // CTA Button
            if (canSync && !_syncing)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    setState(() => _syncing = true);
                    Navigator.of(ctx).pop();
                    await _performSync();
                  },
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text(
                    'SYNC ALL DATA',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            if (!canSync)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _upgradeFromGuest();
                  },
                  // Shortened label + ellipsis safety: fits one line even on
                  // the narrowest dialog widths.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Flexible(
                        child: Text(
                          'SIGN IN FOR BACKUP',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _backupRow(IconData icon, String label, String detail, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? MacroSnapTheme.neonGreen.withValues(alpha: 0.06)
            : MacroSnapTheme.neonGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: MacroSnapTheme.neonGreen, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: MacroSnapTheme.neonGreen,
            size: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _performSync() async {
    try {
      // 1. Sync meals
      final meals = MealStore.instance.allMeals;
      await MealSyncService.syncAllMeals(meals);

      // 2. Sync habits + water
      final habitStore = HabitStore.instance;
      await MealSyncService.syncHabits(
        habitsJson: habitStore.habits.map((h) => h.toJson()).toList(),
        waterLog: Map<String, int>.from(habitStore.waterLog),
        waterGoal: habitStore.waterGoal,
      );

      // 3. Sync diet profile
      final dietProfile = DietPlanService.instance.profile;
      if (dietProfile != null) {
        await MealSyncService.syncDietProfile(dietProfile.toJson());
      }

      // 4. Sync recent foods
      final recentFoods = RecentFoodService.instance.foods;
      await MealSyncService.syncRecentFoods(
        recentFoods.map((f) => f.toJson()).toList(),
      );

      // 5. Sync user preferences (theme, name)
      final prefs = await SharedPreferences.getInstance();
      await MealSyncService.syncPreferences({
        'themeMode': prefs.getString('theme_mode') ?? 'system',
        'name': prefs.getString('name') ?? '',
      });

      // 6. Save sync timestamp
      final now = DateTime.now();
      final syncTime =
          '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      await prefs.setString('last_sync', syncTime);

      if (mounted) {
        setState(() {
          _lastSync = syncTime;
          _syncing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Backed up ${meals.length} meals + ${habitStore.habits.length} habits + ${recentFoods.length} recent foods',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: MacroSnapTheme.neonGreen,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync failed. Check your connection.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: MacroSnapTheme.neonPink,
          ),
        );
      }
    }
  }

  /// Backup reminder banner — shown when last sync was 7+ days ago.
  Widget _buildBackupReminder(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _showBackupDialog(isDark),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A1A00) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: MacroSnapTheme.neonOrange.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  color: MacroSnapTheme.neonOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup your data',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last backup was over 7 days ago. Tap to sync now.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: MacroSnapTheme.textQuaternary(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
    bool isDark,
    {bool showBadge = false}
  ) {
    return InkWell(
      onTap: onTap,
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
                        color: isDark
                            ? MacroSnapTheme.cardDark
                            : Colors.white,
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
