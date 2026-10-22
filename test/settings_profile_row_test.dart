import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/profile_screen.dart';
import 'package:macro_snap/screens/settings_screen.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The App Version row was removed and Profile took its place at the top of
/// Settings — the first row is now "who am I", not a build number.
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

  testWidgets('Profile is the first Settings row and App Version is gone', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('App Version'), findsNothing);
    expect(find.text('Profile'), findsOneWidget);

    // First row means above every other setting, not merely present.
    final profileY = tester.getTopLeft(find.text('Profile')).dy;
    for (final other in ['Upgrade to Pro', "What's New", 'Contact Support']) {
      final finder = find.text(other);
      if (finder.evaluate().isEmpty) continue;
      expect(
        profileY,
        lessThan(tester.getTopLeft(finder).dy),
        reason: 'Profile must sit above "$other"',
      );
    }
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
