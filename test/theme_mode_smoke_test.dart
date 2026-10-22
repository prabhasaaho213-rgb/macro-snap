import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/screens/result_screen.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:macro_snap/widgets/animations.dart';

/// Pumps [child] under a light or dark MaterialApp and advances the one-shot
/// entrance + progress animations. Never pumpAndSettle: StreakFlame's
/// flicker controller repeats forever and would time it out.
Future<void> pumpInMode(
  WidgetTester tester,
  Widget child, {
  required bool dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: child,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 1300));
}

/// Asserts the current pump left no layout overflow / build exceptions.
void expectNoRenderErrors(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: '$where must render cleanly');
}

/// Colors shared by both progress rings (Home calorie ring + Habits hero ring).
///
/// Both dark tracks are white24, not white10: at white10 a ring at 0% progress
/// had nothing to show and read as an unrendered circle — the "calorie ring
/// glitch". Light track is unchanged.
Color ringLabelColor(bool dark) =>
    dark ? Colors.white : const Color(0xFF1A1A1A);
Color ringTrackColor(bool dark) =>
    dark ? Colors.white24 : const Color(0xFFE8DEFF);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = HabitStore.instance;
    store.habits.clear();
    // MealStore caches a file-backed load; reset it so the empty-prefs state
    // applies (path_provider is unavailable in tests — load() swallows it).
    await MealStore.instance.reload();
  });

  // ─── HOME — smooth progress ring/bar ───────────────────────
  for (final dark in [false, true]) {
    testWidgets(
      'Home renders the calorie ring/bar in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await pumpInMode(tester, const HomeScreen(), dark: dark);

        expectNoRenderErrors(tester, 'Home (${dark ? 'dark' : 'light'})');
        expect(find.byType(AnimatedProgressRing), findsOneWidget);
        expect(find.byType(AnimatedProgressBar), findsWidgets);

        // Ring track + % label must use the mode-appropriate colors.
        final ring = tester.widget<AnimatedProgressRing>(
          find.byType(AnimatedProgressRing),
        );
        expect(ring.backgroundColor, ringTrackColor(dark));
        expect(ring.labelStyle?.color, ringLabelColor(dark));

        final cpi = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator).first,
        );
        expect(cpi.backgroundColor, ringTrackColor(dark));
      },
    );
  }

  // ─── HABITS — hero ring/bar + reorder list ─────────────────
  for (final dark in [false, true]) {
    testWidgets(
      'Habits renders missions + progress in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final store = HabitStore.instance;
        store.habits.addAll([
          Habit(
            id: 'v1',
            name: 'Morning Run',
            emoji: '🏃',
            colorValue: 0xFFFF007F,
            frequency: 'Daily',
          ),
          Habit(
            id: 'v2',
            name: 'Read 10 pages',
            emoji: '📚',
            colorValue: 0xFF00FF66,
            frequency: 'Daily',
          ),
        ]);
        await pumpInMode(tester, const HabitsTab(), dark: dark);

        expectNoRenderErrors(tester, 'Habits (${dark ? 'dark' : 'light'})');
        expect(find.byType(Dismissible), findsNWidgets(2));
        expect(find.byType(AnimatedProgressRing), findsOneWidget);
        expect(find.byType(AnimatedProgressBar), findsWidgets);
        expect(find.text('0%'), findsOneWidget);

        final ring = tester.widget<AnimatedProgressRing>(
          find.byType(AnimatedProgressRing),
        );
        expect(ring.backgroundColor, ringTrackColor(dark));
        expect(ring.labelStyle?.color, ringLabelColor(dark));

        // Reorder list still present with the drag-proxy fix intact.
        final reorder = tester.widget<ReorderableListView>(
          find.byType(ReorderableListView),
        );
        expect(
          reorder.proxyDecorator,
          isNotNull,
          reason: 'custom drag proxy must survive in both modes',
        );
      },
    );
  }

  // NOTE: DietPlanScreen is intentionally not smoke-tested here — its
  // profile load awaits path_provider's getApplicationDocumentsDirectory,
  // which never completes under flutter_test, and its AnimatedProgressBar is
  // the same widget already verified in both modes above (Home + Habits).

  // ─── RESULT VIEW — tap-to-view logged meal ─────────────────
  for (final dark in [false, true]) {
    testWidgets('Meal detail view renders in ${dark ? 'dark' : 'light'} mode', (
      tester,
    ) async {
      final meal = MealRecord(
        id: 'm1',
        date: DateTime.now(),
        name: 'Chocolate Cake',
        category: '',
        calories: 371,
        protein: 5.2,
        carbs: 48.0,
        fats: 18.5,
        fiber: 2.1,
        serving: 'A whole chocolate cake topped with slices',
      );
      await pumpInMode(
        tester,
        ResultScreen(imagePath: '', existingMeal: meal),
        dark: dark,
      );

      expectNoRenderErrors(tester, 'Result view (${dark ? 'dark' : 'light'})');
      expect(find.text('Nutrition Details'), findsOneWidget);
      expect(find.text('371'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Log This Meal'), findsNothing);

      // Big calorie number uses the mode-appropriate text color.
      final cal = tester.widget<Text>(find.text('371'));
      expect(cal.style?.color, dark ? Colors.white : const Color(0xFF1A1A1A));
    });
  }
}
