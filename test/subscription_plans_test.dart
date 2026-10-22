import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/subscription_screen.dart';
import 'package:macro_snap/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MacroSnap sells exactly two plans: Free and Pro (₹29/month). "Lifetime Pro"
/// is an admin marker, never a plan a normal user can see or pick.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPaywall(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubscriptionScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a normal user sees Free and Pro, and no Lifetime anywhere', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'phone': 'guest_test',
      'email': 'someone@example.com',
    });

    await pumpPaywall(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('CURRENT PLAN'), findsOneWidget);
    expect(
      find.text('\u20B90'),
      findsOneWidget,
      reason: 'the Free plan states its price',
    );
    expect(
      find.textContaining('Lifetime'),
      findsNothing,
      reason: 'Lifetime Pro is not a plan offered to users',
    );
  });

  testWidgets('the admin still sees their Lifetime Pro marker', (tester) async {
    // The privilege is a Firebase custom claim; the harness has no Firebase
    // app, so the claim check is injected.
    SubscriptionService.adminCheckOverride = () async => true;
    addTearDown(() => SubscriptionService.adminCheckOverride = null);
    SharedPreferences.setMockInitialValues({'phone': 'admin_test'});

    await pumpPaywall(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Lifetime'), findsWidgets);
    expect(find.text('Free'), findsOneWidget);
  });
}
