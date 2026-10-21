import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import 'gradient_button.dart';

/// Days to wait before asking again after the user dismissed the prompt.
const kNotificationPromptCooldownDays = 3;
const _keyLastPrompt = 'notif_prompt_last_shown';

/// Shows the in-app notification-permission prompt asking to be
/// allowed to remind you. No-op when notifications are already granted (or
/// the permission state can't be determined). After a "Not now" it waits
/// [kNotificationPromptCooldownDays] before asking again.
///
/// [force] skips that cooldown for an explicit request — Settings taps
/// "Notifications" to change this deliberately, so the three-day quiet
/// period (meant for unsolicited launch prompts) must not apply.
///
/// The functions are injectable so widget tests can fake the platform.
Future<void> maybeShowNotificationPrompt(
  BuildContext context, {
  Future<PermissionStatus> Function()? statusOf,
  Future<PermissionStatus> Function()? request,
  Future<void> Function()? openSettings,
  DateTime Function()? now,
  bool force = false,
}) async {
  final statusOfFn = statusOf ?? () => Permission.notification.status;
  final requestFn = request ?? () => Permission.notification.request();
  final openSettingsFn = openSettings ?? openAppSettings;
  final nowFn = now ?? DateTime.now;

  PermissionStatus status;
  try {
    status = await statusOfFn();
  } catch (_) {
    return; // Can't read the permission state — don't nag.
  }
  if (status.isGranted) return;

  final prefs = await SharedPreferences.getInstance();
  final lastShown = prefs.getString(_keyLastPrompt);
  if (!force && lastShown != null) {
    final lastDate = DateTime.tryParse(lastShown);
    if (lastDate != null &&
        nowFn().difference(lastDate).inDays < kNotificationPromptCooldownDays) {
      return;
    }
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NotificationPromptDialog(
      needsSettings: status.isPermanentlyDenied,
      request: requestFn,
      openSettings: openSettingsFn,
      onLater: () async {
        await prefs.setString(_keyLastPrompt, nowFn().toIso8601String());
      },
    ),
  );
}

class _NotificationPromptDialog extends StatefulWidget {
  final bool needsSettings;
  final Future<PermissionStatus> Function() request;
  final Future<void> Function() openSettings;
  final Future<void> Function() onLater;

  const _NotificationPromptDialog({
    required this.needsSettings,
    required this.request,
    required this.openSettings,
    required this.onLater,
  });

  @override
  State<_NotificationPromptDialog> createState() =>
      _NotificationPromptDialogState();
}

class _NotificationPromptDialogState extends State<_NotificationPromptDialog> {
  late bool _needsSettings = widget.needsSettings;

  Future<void> _handlePrimary() async {
    if (_needsSettings) {
      await widget.openSettings();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    PermissionStatus result;
    try {
      result = await widget.request();
    } catch (_) {
      setState(() => _needsSettings = true);
      return;
    }
    if (result.isGranted) {
      if (mounted) Navigator.of(context).pop();
    } else {
      // Denied again → point the user at the system settings.
      setState(() => _needsSettings = true);
    }
  }

  Future<void> _handleLater() async {
    await widget.onLater();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      // Scrollable so large system fonts can never overflow the dialog.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 72,
              color: MacroSnapTheme.neonGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'Let me remind you 💬',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _needsSettings
                  ? 'Notifications are turned off for MacroSnap. Enable them in Settings so I can remind you to log meals and keep your streaks alive.'
                  : 'I can nudge you when it\'s time to log a meal, hit your macro targets, and keep your streak alive. Will you allow notifications?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w400,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: _needsSettings ? 'Open Settings' : 'Allow notifications',
              icon: _needsSettings
                  ? Icons.settings_rounded
                  : Icons.notifications_rounded,
              height: 48,
              onPressed: _handlePrimary,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _handleLater,
              child: Text(
                'Not now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
