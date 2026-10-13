import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/screens/chat_screen.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:macro_snap/services/subscription_service.dart';

/// Zone notes: MealStore.reload() awaits a platform channel, so it must run
/// in setUp (real-async zone). Inside the testWidgets FakeAsync zone a
/// fire-and-forget SubscriptionService.load() progresses via microtask
/// flushes on the pumps, while HomeScreen._loadAll() stalls on
/// path_provider — so the service is seeded directly here instead.
Future<void> pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  unawaited(SubscriptionService.instance.load());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 1300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MealStore.instance.reload();
  });

  testWidgets('trial banner shows the days left while the free plan runs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'trial_ends_at':
          DateTime.now().add(const Duration(days: 7, hours: 3)).toIso8601String(),
    });
    await pumpHome(tester);

    expect(tester.takeException(), isNull, reason: 'Home must render cleanly');
    expect(SubscriptionService.instance.trialActive, isTrue,
        reason: 'service must observe the seeded trial');
    expect(find.textContaining('Free plan'), findsOneWidget);
    expect(find.textContaining('days left'), findsOneWidget);
    expect(find.text('View plans'), findsOneWidget);
  });

  testWidgets('no banner once the free plan has expired', (tester) async {
    SharedPreferences.setMockInitialValues({
      'trial_ends_at':
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    });
    await pumpHome(tester);

    expect(find.textContaining('Free plan'), findsNothing);
    // The expired marker must be cleared so it can never resurrect.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('trial_ends_at'), isNull);
  });

  testWidgets('no banner for a regular user without a trial', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);

    expect(find.textContaining('Free plan'), findsNothing);
  });

  testWidgets('fixed chat button opens the nutrition assistant',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget, reason: 'Home hosts the fixed chat button');
    await tester.tap(fab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Nutrition Assistant'), findsOneWidget);
    expect(find.textContaining('nutrition assistant'), findsOneWidget,
        reason: 'the greeting must advertise the food/protein focus');
  });
}
