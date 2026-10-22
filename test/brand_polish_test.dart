import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/widgets/streak_flame.dart';

/// Guards the two visual fixes from the 1.4.95 polish pass:
///  * headlines are upright (the dark theme used to render them in italic,
///    which read as "tilted" on the login/splash titles), and
///  * the streak flame is a bright gradient icon, not the device emoji.
void main() {
  group('headline styles', () {
    test('dark-theme display styles are upright', () {
      final text = MacroSnapTheme.dark.textTheme;
      expect(
        text.displayLarge?.fontStyle,
        isNot(FontStyle.italic),
        reason:
            '"Welcome to MacroSnap" uses displayMedium — it must not '
            'lean',
      );
      expect(text.displayMedium?.fontStyle, isNot(FontStyle.italic));
    });

    test('light-theme display styles are upright', () {
      final text = MacroSnapTheme.light.textTheme;
      expect(text.displayLarge?.fontStyle, isNot(FontStyle.italic));
      expect(text.displayMedium?.fontStyle, isNot(FontStyle.italic));
    });
  });

  group('StreakFlame', () {
    // The flicker controller repeats forever, so every test uses fixed pumps
    // instead of pumpAndSettle.
    Future<void> pumpFlame(WidgetTester tester, int streak) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MacroSnapTheme.light,
          home: Scaffold(
            body: Center(child: StreakFlame(streak: streak)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('draws a bright fire icon instead of the emoji', (
      tester,
    ) async {
      await pumpFlame(tester, 1);

      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(
        find.text('🔥'),
        findsNothing,
        reason:
            'the emoji rendered dim on Android; it is drawn as an icon '
            'now so it can carry a gradient and a glow',
      );
    });

    testWidgets('flame count follows the streak tier', (tester) async {
      await pumpFlame(tester, 2);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);

      await pumpFlame(tester, 5);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byIcon(Icons.local_fire_department_rounded),
        findsNWidgets(2),
      );

      await pumpFlame(tester, 9);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byIcon(Icons.local_fire_department_rounded),
        findsNWidgets(3),
      );
      expect(find.text('Lv 1'), findsOneWidget);
    });

    testWidgets('no flame at a zero streak', (tester) async {
      await pumpFlame(tester, 0);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    });
  });
}
