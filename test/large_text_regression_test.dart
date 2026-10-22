import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/screens/diet_plan_screen.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/screens/onboarding_screen.dart';
import 'package:macro_snap/screens/phone_login_screen.dart';
import 'package:macro_snap/screens/referral_screen.dart';
import 'package:macro_snap/screens/settings_screen.dart';
import 'package:macro_snap/screens/subscription_screen.dart';
import 'package:macro_snap/widgets/notification_prompt.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression sweep: every screen must render at the largest system font
/// scale (2x), on a narrow (320dp) and a large (430dp) phone, in BOTH light
/// and dark mode, without a single overflow exception (RenderFlex / text
/// overflow). Uses fixed pumps — screens contain infinitely repeating
/// animations (streak flame), so pumpAndSettle would hang.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final themes = <String, ThemeData>{
    'light': MacroSnapTheme.light,
    'dark': MacroSnapTheme.dark,
  };

  final sizes = <String, Size>{
    '320dp': const Size(320, 568), // small phone
    '430dp': const Size(430, 932), // large phone
  };

  Future<void> expectNoOverflowAtLargeText(
    WidgetTester tester,
    String name,
    Widget screen, {
    required ThemeData theme,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: screen,
      ),
    );
    // Let async loads complete and animations advance (fixed pumps only).
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    final exception = tester.takeException();
    if (exception != null &&
        exception.toString().toLowerCase().contains('overflow')) {
      fail('$name overflowed at 2x font scale: $exception');
    }
    // Other exceptions (plugin/network noise in the test environment) are
    // intentionally ignored — this sweep only guards against overflow.
    // Unmount so repeating controllers are disposed cleanly.
    await tester.pumpWidget(const SizedBox());
  }

  final screens = <String, Widget Function()>{
    'Onboarding': () =>
        const OnboardingScreen(nextScreen: Scaffold(body: SizedBox())),
    'PhoneLogin': () => const PhoneLoginScreen(),
    'Habits': () => const HabitsTab(),
    'DietPlan': () => const DietPlanScreen(),
    'Settings': () => const SettingsScreen(),
    'Referral': () => const ReferralScreen(),
    'Home': () => const HomeScreen(),
    'Subscription': () => const SubscriptionScreen(),
  };

  for (final sizeEntry in sizes.entries) {
    for (final mode in themes.entries) {
      screens.forEach((name, builder) {
        testWidgets(
          '$name (${mode.key}, ${sizeEntry.key}) renders at 2x without '
          'overflow',
          (tester) async {
            await expectNoOverflowAtLargeText(
              tester,
              '$name (${mode.key}, ${sizeEntry.key})',
              builder(),
              theme: mode.value,
              size: sizeEntry.value,
            );
          },
        );
      });
    }
  }

  for (final sizeEntry in sizes.entries) {
    for (final mode in themes.entries) {
      testWidgets(
        'Notification prompt dialog (${mode.key}, ${sizeEntry.key}) renders '
        'at 2x without overflow',
        (tester) async {
          tester.view.physicalSize = sizeEntry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: mode.value,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => maybeShowNotificationPrompt(
                      context,
                      statusOf: () async => PermissionStatus.denied,
                      request: () async => PermissionStatus.denied,
                      openSettings: () async {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          final exception = tester.takeException();
          if (exception != null &&
              exception.toString().toLowerCase().contains('overflow')) {
            fail(
              'NotificationPrompt dialog (${mode.key}, ${sizeEntry.key}) '
              'overflowed at 2x font scale: $exception',
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
