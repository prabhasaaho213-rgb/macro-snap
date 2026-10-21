import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/notification_prompt.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the in-app notification-permission prompt: the prompt asks to send
/// reminders when permission is denied, "Not now" sets a cooldown, and the
/// dialog escalates to Open Settings when the permission is permanently
/// denied.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget host({
    required Future<PermissionStatus> Function() statusOf,
    Future<PermissionStatus> Function()? request,
    Future<void> Function()? openSettings,
    bool force = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybeShowNotificationPrompt(
              context,
              statusOf: statusOf,
              request: request ?? () async => PermissionStatus.granted,
              openSettings: openSettings ?? () async {},
              force: force,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
  }

  testWidgets('granted permission → no prompt shown', (tester) async {
    await tester.pumpWidget(
      host(statusOf: () async => PermissionStatus.granted),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets(
    'denied → prompt shows, Not now closes and sets cooldown',
    (tester) async {
      await tester.pumpWidget(
        host(statusOf: () async => PermissionStatus.denied),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(find.text('Let me remind you 💬'), findsOneWidget);
      expect(find.text('Allow notifications'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pump(); // let the pop fire
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notif_prompt_last_shown'), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied → allowing the permission closes the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        statusOf: () async => PermissionStatus.denied,
        request: () async => PermissionStatus.granted,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Allow notifications'));
    await tester.pump(); // let the pop fire
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
  });

  testWidgets('denied twice → button flips to Open Settings and opens it', (
    tester,
  ) async {
    var settingsOpened = false;
    await tester.pumpWidget(
      host(
        statusOf: () async => PermissionStatus.denied,
        request: () async => PermissionStatus.denied,
        openSettings: () async => settingsOpened = true,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Allow notifications'));
    await tester.pump(); // let the request complete
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Open Settings'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pump(); // let the pop fire
    await tester.pump(const Duration(milliseconds: 300));
    expect(settingsOpened, isTrue);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
  });

  testWidgets('permanently denied → shows Open Settings directly', (
    tester,
  ) async {
    var settingsOpened = false;
    await tester.pumpWidget(
      host(
        statusOf: () async => PermissionStatus.permanentlyDenied,
        openSettings: () async => settingsOpened = true,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump(); // let the pop fire
    await tester.pump(const Duration(milliseconds: 300));
    expect(settingsOpened, isTrue);
  });

  testWidgets('recently dismissed → prompt is suppressed (cooldown)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'notif_prompt_last_shown': DateTime.now().toIso8601String(),
    });
    await tester.pumpWidget(
      host(statusOf: () async => PermissionStatus.denied),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
  });

  testWidgets('force ignores the cooldown (Settings asks on purpose)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'notif_prompt_last_shown': DateTime.now().toIso8601String(),
    });
    await tester.pumpWidget(
      host(statusOf: () async => PermissionStatus.denied, force: true),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The launch prompt still respects the three-day quiet period; an explicit
    // tap in Settings must always be able to reach the permission.
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(find.text('Allow notifications'), findsOneWidget);
  });
}
