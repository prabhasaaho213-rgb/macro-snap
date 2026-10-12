import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/core/app_nav.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/screens/main_shell.dart';
import 'package:macro_snap/screens/scan_screen.dart';
import 'package:macro_snap/screens/updates_tab.dart';
import 'package:macro_snap/services/habit_store.dart';

/// Pumps MainShell and settles the initial async work (subscription check,
/// RateUs launch counter, HomeScreen _loadAll, entrance animations).
Future<void> pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: MainShell()));
  await tester.pump(); // post-frame callbacks (subscription offer check)
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Flushes AnimatedEntrance `Future.delayed` timers so a test can end without
/// "A Timer is still pending" failures. StreakFlame repeats forever, so we
/// must use fixed pumps — never pumpAndSettle once the Habits tab is mounted.
Future<void> flushEntranceTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  const cameraChannel = MethodChannel('plugins.flutter.io/camera');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HabitStore.instance.habits.clear();
    // The shell reads the shared tab index at startup — reset it so a prior
    // test that switched tabs can't leak into this one.
    shellTabIndex.value = 0;

    // ScanScreen (tab 1) requests the camera permission in initState OUTSIDE
    // its try/catch, so an unmocked channel would throw an unhandled async
    // error and fail the test. Grant the permission and return no cameras so
    // the screen lands in its safe "Camera unavailable" state.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'requestPermissions') {
        final args = (call.arguments as List).cast<int>();
        return <int, int>{for (final a in args) a: 1}; // granted
      }
      if (call.method == 'checkPermissionStatus') return 1; // granted
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
      if (call.method == 'availableCameras') return <dynamic>[];
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null);
    shellTabIndex.value = 0;
  });

  // ─── SWIPE-TO-SWITCH-TABS GESTURE ──────────────────────────
  //
  // NOTE: these tests fling at the center of MainShell. That is only safe
  // because setUp clears all habits — if habits are ever seeded here, the
  // mission cards' Dismissibles would claim the horizontal drag (completing/
  // resetting a habit instead of switching tabs). Keep habits empty in this
  // file, or fling from a fixed offset away from mission cards.

  testWidgets('swipe left moves Home → Scan → Habits', (tester) async {
    await pumpShell(tester);

    expect(find.byType(HomeScreen), findsOneWidget,
        reason: 'shell must start on the Home tab');

    // Swipe left (negative velocity) → next tab (Scan).
    await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450)); // AnimatedSwitcher 400ms
    expect(find.byType(ScanScreen), findsOneWidget,
        reason: 'swipe left on Home must open the Scan tab');
    expect(find.byType(HomeScreen), findsNothing,
        reason: 'Home must be removed after the transition completes');

    // Swipe left again → Habits.
    await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(HabitsTab), findsOneWidget,
        reason: 'swipe left on Scan must open the Habits tab');
    expect(find.byType(ScanScreen), findsNothing);

    await flushEntranceTimers(tester);
  });

  testWidgets('swipe right moves Habits → Scan → Home', (tester) async {
    await pumpShell(tester);

    // Go to the Habits tab first (two left swipes).
    await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(HabitsTab), findsOneWidget);

    // Swipe right (positive velocity) → previous tab (Scan).
    await tester.fling(find.byType(MainShell), const Offset(300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(ScanScreen), findsOneWidget,
        reason: 'swipe right on Habits must open the Scan tab');
    expect(find.byType(HabitsTab), findsNothing);

    // Swipe right again → Home.
    await tester.fling(find.byType(MainShell), const Offset(300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(HomeScreen), findsOneWidget,
        reason: 'swipe right on Scan must open the Home tab');

    await flushEntranceTimers(tester);
  });

  testWidgets('slow drag (below 300 px/s velocity) does NOT switch tabs',
      (tester) async {
    await pumpShell(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // 300px over 2s → 150 px/s < the 300 px/s threshold.
    await tester.timedDrag(
        find.byType(MainShell), const Offset(-300, 0), const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(HomeScreen), findsOneWidget,
        reason: 'a slow drag under the velocity threshold must not switch tabs');
    expect(find.byType(ScanScreen), findsNothing);

    await flushEntranceTimers(tester);
  });

  testWidgets('swipe left on the last tab (Updates) stays on Updates',
      (tester) async {
    await pumpShell(tester);

    // Three left swipes: Home → Scan → Habits → Updates.
    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
    }
    expect(find.byType(UpdatesTab), findsOneWidget);

    // Already at the last tab — swiping further left must be a no-op.
    await tester.fling(find.byType(MainShell), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(UpdatesTab), findsOneWidget,
        reason: 'swiping left past the last tab must stay on the Updates tab');

    await flushEntranceTimers(tester);
  });

  // ─── NOTIFICATION TAP → HABITS TAB (via shellTabIndex) ────

  testWidgets('openShellTab(2) switches the shell to the Habits tab',
      (tester) async {
    await pumpShell(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    // This is exactly what a plain tap on a habit reminder notification does
    // (NotificationService calls openShellTab(2)).
    openShellTab(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(shellTabIndex.value, 2,
        reason: 'openShellTab must update the shared tab index');
    expect(find.byType(HabitsTab), findsOneWidget,
        reason: 'the shell must listen to shellTabIndex and switch to Habits');

    await flushEntranceTimers(tester);
  });
}
