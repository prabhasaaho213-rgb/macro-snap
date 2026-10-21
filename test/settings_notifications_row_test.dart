import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/settings_screen.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Startup no longer throws the system permission dialog at the user before
/// the first frame, so Settings is now the guaranteed way back to it — the
/// reminder permission has to be reachable from here even after a "Not now".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'phone': 'guest_test', 'name': 'Ada'});
    // Home/Settings read the store; reload keeps it in a known state.
    await MealStore.instance.reload();
  });

  testWidgets('Settings shows a Notifications row that can be tapped',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull, reason: 'Settings must render');
    expect(find.text('Notifications'), findsOneWidget);

    // The tap must be safe even where the platform channel is unavailable
    // (tests, desktop): the prompt treats an unreadable status as "don't nag".
    await tester.tap(find.text('Notifications'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
