import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/notification_prompt.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pins the notification ask: the phone's own Allow / Deny dialog is the only
/// prompt. There is no in-app dialog, "Not now" or cooldown any more.
void main() {
  test('granted → the phone is not asked again', () async {
    var requests = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => PermissionStatus.granted,
      request: () async {
        requests++;
        return PermissionStatus.granted;
      },
    );

    expect(granted, isTrue);
    expect(requests, 0);
  });

  test('denied → the system dialog is requested directly', () async {
    var requests = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => PermissionStatus.denied,
      request: () async {
        requests++;
        return PermissionStatus.granted;
      },
    );

    expect(requests, 1, reason: 'The OS dialog is the ask — no in-app step');
    expect(granted, isTrue);
  });

  test('answered Deny → reports not granted', () async {
    var requests = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => PermissionStatus.denied,
      request: () async {
        requests++;
        return PermissionStatus.denied;
      },
    );

    expect(requests, 1);
    expect(granted, isFalse);
  });

  test('permanently denied at launch → no request, no settings jump', () async {
    var requests = 0;
    var openedSettings = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => PermissionStatus.permanentlyDenied,
      request: () async {
        requests++;
        return PermissionStatus.denied;
      },
      openSettings: () async => openedSettings++,
    );

    expect(requests, 0, reason: 'Android would not show a dialog anyway');
    expect(openedSettings, 0, reason: 'A launch must not leave the app');
    expect(granted, isFalse);
  });

  test('permanently denied + force → opens the system settings', () async {
    var openedSettings = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => PermissionStatus.permanentlyDenied,
      openSettings: () async => openedSettings++,
      force: true,
    );

    expect(openedSettings, 1);
    expect(granted, isFalse);
  });

  test('unreadable status → asks nothing', () async {
    var requests = 0;
    final granted = await maybeShowNotificationPrompt(
      statusOf: () async => throw Exception('no platform'),
      request: () async {
        requests++;
        return PermissionStatus.granted;
      },
    );

    expect(requests, 0);
    expect(granted, isFalse);
  });
}
