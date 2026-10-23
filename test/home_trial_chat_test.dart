import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/screens/chat_screen.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/screens/subscription_screen.dart';
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

  // ── Free trials are REMOVED ───────────────────────────────────────────────
  // Pro now starts with a Razorpay autopay subscription whose first month is
  // ₹1 (approve ₹49/mo at checkout, first ₹49 charge in 30 days). No countdown
  // banner exists anywhere on the home screen, and a stale marker left by an
  // old installed version must be wiped so it can never resurrect.

  testWidgets('the trial banner is gone — a stale trial marker is wiped too', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'trial_ends_at': DateTime.now()
          .add(const Duration(days: 7, hours: 3))
          .toIso8601String(),
    });
    await pumpHome(tester);

    expect(tester.takeException(), isNull, reason: 'Home must render cleanly');
    expect(find.textContaining('Free plan'), findsNothing,
        reason: 'no trial banner exists any more');
    expect(find.textContaining('days left'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('trial_ends_at'), isNull,
        reason: 'load() must clear the stale trial marker so it never resurrects');
  });

  testWidgets('a regular user without any plan marker has no banner either', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);

    expect(find.textContaining('Free plan'), findsNothing);
    expect(find.textContaining('days left'), findsNothing);
  });

  testWidgets('fixed chat button opens the nutrition assistant for Pro', (
    tester,
  ) async {
    // Guru is a Pro feature (the backend 403s a free user), so the button only
    // opens the assistant for a subscribed account. Trials no longer count:
    // the subscribed flag is exactly what Razorpay verify/webhook writes.
    SharedPreferences.setMockInitialValues({'subscribed': true});
    await pumpHome(tester);

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget, reason: 'Home hosts the fixed chat button');
    await tester.tap(fab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Guru'), findsOneWidget);
    expect(
      find.textContaining('nutrition assistant'),
      findsOneWidget,
      reason: 'the greeting must advertise the food/protein focus',
    );
  });

  testWidgets('a free user tapping the chat button is sent to the plans, not '
      'the assistant', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(ChatScreen),
      findsNothing,
      reason: 'a free user must never reach a chat the backend would refuse',
    );
    expect(
      find.byType(SubscriptionScreen),
      findsOneWidget,
      reason: 'the button must route them to the upgrade path instead',
    );
  });

  testWidgets('a stale trial marker is NOT Pro — plans screen instead of chat', (
    tester,
  ) async {
    // An old install once relied on trial_ends_at; after the removal the app
    // must treat it as a plain free user (the server's no-trial verdict is
    // authoritative, and load() clears the marker).
    SharedPreferences.setMockInitialValues({
      'trial_ends_at': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
    });
    await pumpHome(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(ChatScreen),
      findsNothing,
      reason: 'an active trial no longer counts as Pro',
    );
    expect(
      find.byType(SubscriptionScreen),
      findsOneWidget,
      reason: 'the upgrade path is the way to Guru, not an old trial marker',
    );
  });
}
