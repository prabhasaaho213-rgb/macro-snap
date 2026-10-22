import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/app_badge.dart';
import 'package:macro_snap/services/badge_service.dart';
import 'package:macro_snap/widgets/badge_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The celebration banner. Two bugs lived here: the timer outlived the widget
/// (so logging out threw while removing an overlay entry a second time), and
/// two badges earned at once showed only the last one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BadgeService.instance.resetForTest();
  });

  tearDown(() {
    BadgeService.instance.resetForTest();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BadgeCelebration(child: const Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();
  }

  testWidgets('a new badge slides in, then leaves on its own', (tester) async {
    await pumpHost(tester);

    BadgeService.instance.justEarned.value = AppBadge.firstBite;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Badge unlocked · First Bite'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Badge unlocked · First Bite'), findsNothing);
    // The notifier is cleared, so the same badge can be celebrated again.
    expect(BadgeService.instance.justEarned.value, isNull);
  });

  testWidgets('two badges in one tick are shown one after the other', (
    tester,
  ) async {
    await pumpHost(tester);

    // The tenth meal is both First Bite (new account) and Ten Plates.
    BadgeService.instance.justEarned.value = AppBadge.firstBite;
    await tester.pump();
    BadgeService.instance.justEarned.value = AppBadge.tenPlates;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Badge unlocked · First Bite'), findsOneWidget);
    expect(find.text('Badge unlocked · Ten Plates'), findsNothing);

    // After the first toast expires the second takes its place.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Badge unlocked · Ten Plates'), findsOneWidget);
    expect(find.text('Badge unlocked · First Bite'), findsNothing);
  });

  testWidgets('being torn down mid-toast does not throw', (tester) async {
    await pumpHost(tester);

    BadgeService.instance.justEarned.value = AppBadge.weekWarrior;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Badge unlocked · Week Warrior'), findsOneWidget);

    // What logout does: replace the tree while a toast is on screen.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the dismiss timer must not fire after dispose',
    );
  });
}
