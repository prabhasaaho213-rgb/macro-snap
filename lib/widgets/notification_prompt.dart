import 'package:permission_handler/permission_handler.dart';

/// Asks the PHONE for notification permission — the system Allow / Deny
/// dialog, answered with the phone's own controls.
///
/// There is deliberately no in-app pre-prompt any more. The old dialog
/// explained the reason first, which meant two dialogs for one permission, and
/// its "Not now" only postponed the real one — the OS dialog is the ask.
///
/// Returns true when notifications are allowed after the call.
///
/// [force] is for an explicit request (a settings row). When Android has
/// already stopped showing its dialog because the permission is permanently
/// denied, that is the only case that sends the user to the system screen; a
/// launch-time call never leaves the app on its own.
///
/// The functions are injectable so tests can fake the platform.
Future<bool> maybeShowNotificationPrompt({
  Future<PermissionStatus> Function()? statusOf,
  Future<PermissionStatus> Function()? request,
  Future<void> Function()? openSettings,
  bool force = false,
}) async {
  final statusOfFn = statusOf ?? () => Permission.notification.status;
  final requestFn = request ?? () => Permission.notification.request();
  final openSettingsFn = openSettings ?? openAppSettings;

  PermissionStatus status;
  try {
    status = await statusOfFn();
  } catch (_) {
    return false; // Can't read the permission state — don't ask.
  }
  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied) {
    // The OS will not show its dialog again, so asking would be a no-op. Only
    // an explicit request should take the user out to the system screen.
    if (!force) return false;
    try {
      await openSettingsFn();
    } catch (_) {
      // Nothing to recover from: the user can still open Settings by hand.
    }
    return false;
  }

  try {
    final result = await requestFn();
    return result.isGranted || result.isLimited;
  } catch (_) {
    return false;
  }
}
