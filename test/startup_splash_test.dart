import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/app.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/widgets/startup_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The launch used to look dead for seconds: `runApp` was only called after
/// Firebase, the notification plugin and every local store had loaded, so the
/// window showed the native launch background (black in dark mode) until all
/// of it finished. These tests pin the fix: the splash is the FIRST frame and
/// it only gives way once startup work is done.
void main() {
  setUp(() {
    // A fresh install, so the screen below the splash is the onboarding flow —
    // the same thing `widget_test.dart` already renders without any plugin
    // fakes. (Signed-in builds MainShell, which opens the camera.)
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: brightness == Brightness.light
          ? MacroSnapTheme.light
          : MacroSnapTheme.dark,
      home: child,
    );
  }

  testWidgets('splash is shown while startup is still running', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(MacroSnapApp(startup: gate.future));
    // One frame in, and the app is already drawing — not a blank window.
    expect(find.byType(StartupSplash), findsOneWidget);
    expect(find.text('MacroSnap'), findsOneWidget);

    // Still pending after the prefs read resolves: the splash holds.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(StartupSplash), findsOneWidget);

    // Startup finished → the real UI takes over on the next frame.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StartupSplash), findsNothing);
  });

  testWidgets('no startup future means no splash to wait for', (tester) async {
    await tester.pumpWidget(const MacroSnapApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StartupSplash), findsNothing);
  });

  testWidgets('a startup step that never returns cannot wedge the app', (
    tester,
  ) async {
    final never = Completer<void>(); // deliberately never completed
    await tester.pumpWidget(MacroSnapApp(startup: never.future));
    expect(find.byType(StartupSplash), findsOneWidget);

    // The safety valve fires and the app becomes usable instead of hanging on
    // the splash forever.
    await tester.pump(kStartupTimeout + const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StartupSplash), findsNothing);
  });

  testWidgets('splash background matches the native launch window', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const StartupSplash()));
    await tester.pump(const Duration(milliseconds: 500));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // Same value as res/values/colors.xml → window_background.
    expect(scaffold.backgroundColor, MacroSnapTheme.surfaceLight);
  });

  testWidgets('splash background follows dark mode without a black frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const StartupSplash(), brightness: Brightness.dark),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // res/values-night/colors.xml → window_background (#0A0A0A), which is
    // exactly what the app's dark surface is, so there is no flash.
    expect(scaffold.backgroundColor, MacroSnapTheme.surfaceDark);
  });
}
