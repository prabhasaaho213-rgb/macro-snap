import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/services/share_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The share card is captured off-screen and leaves the app, so nothing else
/// in the suite ever sees it. These tests render it at the narrowest phone
/// width and with extreme numbers, because an overflow here would ship a
/// clipped image to everybody who taps Share.
void main() {
  WeeklySummary summary({
    int daysLogged = 4,
    double avgCalories = 1840,
    int proteinHitDays = 3,
    int streakDays = 5,
  }) => WeeklySummary(
    daysLogged: daysLogged,
    avgCalories: avgCalories,
    proteinHitDays: proteinHitDays,
    streakDays: streakDays,
    proteinTarget: 150,
  );

  Widget host(Widget child, {double width = 320}) => MaterialApp(
    theme: MacroSnapTheme.light,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('renders the three stats and the day strip', (tester) async {
    await tester.pumpWidget(
      host(WeeklyShareCard(summary: summary(), isDark: false)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1840'), findsOneWidget);
    expect(find.text('3/7'), findsOneWidget);
    expect(find.text('4 of 7 days logged'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
  });

  testWidgets('does not overflow at 320 px with a three-digit streak', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WeeklyShareCard(
          summary: summary(
            daysLogged: 7,
            avgCalories: 3200,
            proteinHitDays: 7,
            streakDays: 365,
          ),
          isDark: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A RenderFlex overflow throws in tests; the card must stay inside 320 px.
    expect(tester.takeException(), isNull);
    expect(find.text('365'), findsOneWidget);
    expect(find.text('7/7'), findsOneWidget);
    final cardWidth = tester.getSize(find.byType(WeeklyShareCard)).width;
    expect(cardWidth, lessThanOrEqualTo(320));
  });

  // The card is an advert that leaves the app: without a scannable code the
  // only install path on it is text nobody can tap inside a chat thread.
  testWidgets('the card carries a scannable Play Store link', (tester) async {
    await tester.pumpWidget(
      host(WeeklyShareCard(summary: summary(), isDark: true)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, 'MacroSnap on Google Play');
    expect(kPlayStoreUrl, contains('com.macrosnap.macro_snap'));
    expect(find.text('Free on Google Play'), findsOneWidget);
    expect(find.text('Scan to install MacroSnap'), findsOneWidget);
  });

  testWidgets('a one-day streak reads "day", not "days"', (tester) async {
    await tester.pumpWidget(
      host(WeeklyShareCard(summary: summary(streakDays: 1), isDark: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('day'), findsOneWidget);
    expect(find.text('days'), findsNothing);
  });
}
