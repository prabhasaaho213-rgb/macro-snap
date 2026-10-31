import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/subscription_service.dart';
import 'package:macro_snap/widgets/pro_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The PRO chip is an upgrade prompt, so it belongs to free accounts only.
/// Every screen renders the same widget, so the rule is enforced once here
/// rather than re-tested on each of the six call sites.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionService.instance.load();
  });

  testWidgets('a free account sees the PRO mark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProBadge())),
    );
    expect(find.text('PRO'), findsOneWidget);
  });

  testWidgets('a subscribed account sees no PRO mark at all', (tester) async {
    await SubscriptionService.instance.activate();
    expect(SubscriptionService.instance.isSubscribed, isTrue);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProBadge())),
    );
    expect(find.text('PRO'), findsNothing);
    // Not merely invisible: it must take no space in the row it sits in.
    expect(tester.getSize(find.byType(ProBadge)), Size.zero);
  });
}
