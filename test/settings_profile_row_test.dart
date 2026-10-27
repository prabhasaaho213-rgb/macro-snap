import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/profile_screen.dart';
import 'package:macro_snap/screens/settings_screen.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile used to be the first row of Settings. It is its own tab on the
/// bottom nav now (home · cam · habits · profile), so this file pins two
/// things: Settings no longer offers it, and the screen itself still renders
/// on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'phone': 'guest_test',
      'name': 'Ada',
      'email': 'ada@example.com',
    });
    await MealStore.instance.reload();
  });

  testWidgets('Profile is gone from Settings and App Version stays gone', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('App Version'), findsNothing);
    expect(
      find.text('Profile'),
      findsNothing,
      reason: 'Profile is a bottom-nav tab now, not a settings row',
    );
    // The subscriber row moved up to take the first slot.
    expect(find.text('Upgrade to Pro'), findsOneWidget);
  });

  testWidgets('profile screen says when there is nothing saved yet', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('No height, weight or goal saved yet'),
      findsOneWidget,
    );
    expect(find.text('Ada'), findsWidgets, reason: 'name comes from prefs');
    expect(find.text('YOUR DETAILS'), findsOneWidget);
    expect(find.text('ACHIEVEMENTS'), findsOneWidget);
    expect(find.text('Add your details'), findsOneWidget);

    // The achievements board sits between the details and the account card,
    // so ACCOUNT may start below the fold — scroll it into view before
    // asserting on it.
    await tester.scrollUntilVisible(
      find.text('ACCOUNT'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Guest (not linked)'), findsOneWidget);
  });
}
