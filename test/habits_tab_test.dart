import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/subscription_service.dart';

/// Pumps HabitsTab and waits for AnimatedEntrance+_checkSub to settle.
Future<void> pumpHabitsTab(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HabitsTab()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = HabitStore.instance;
    store.habits.clear();
  });

  // ─── WIDGET TEST: empty state (no AnimatedEntrance issues) ──
  testWidgets('renders empty state without crashing', (tester) async {
    await pumpHabitsTab(tester);

    expect(find.text('Start your rhythm'), findsOneWidget);
    expect(
      find.text('No missions scheduled for today. Tap above to create one!'),
      findsOneWidget,
    );
    expect(find.text('CREATE HABIT'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  // ─── WIDGET TEST: sections render in the correct order ──
  testWidgets(
    'sections render in correct order: Hero → Missions → Create → Water → Consistency',
    (tester) async {
      // Pre-populate with test habits so the full layout is shown
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
          name: 'Read Books',
          emoji: '📚',
          colorValue: 0xFF00FF66,
          frequency: 'Daily',
        ),
      ]);

      await pumpHabitsTab(tester);

      // 1. Hero card at the top — should be visible without scrolling
      expect(
        find.text('Make it count.'),
        findsOneWidget,
        reason: 'Hero card "Make it count." must render',
      );

      // 2. Today's Missions — also near the top
      expect(
        find.text("Today's Missions"),
        findsOneWidget,
        reason: 'Missions section header must render',
      );

      // Sections 3-5 may be below viewport fold. Scroll to each.
      // 3. CREATE HABIT button
      await tester.scrollUntilVisible(
        find.text('CREATE HABIT'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('CREATE HABIT'),
        findsOneWidget,
        reason: 'Create Habit button must render',
      );

      // 4. Water Intake
      await tester.scrollUntilVisible(
        find.text('Water Intake'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Water Intake'),
        findsOneWidget,
        reason: 'Water Intake section must render',
      );

      // 5. Consistency Map
      await tester.scrollUntilVisible(
        find.text('Consistency'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Consistency'),
        findsOneWidget,
        reason: 'Consistency Map section must render',
      );

      // Clean up
      store.habits.clear();
    },
  );

  // ─── UNIT TESTS: reorder logic ─────────────────────────────
  test('HabitStore reorder - move first habit down', () {
    final store = HabitStore.instance;
    final a = Habit(
      id: 'a',
      name: 'Alpha',
      emoji: '📚',
      colorValue: 0xFF00FF66,
    );
    final b = Habit(
      id: 'b',
      name: 'Bravo',
      emoji: '🏃',
      colorValue: 0xFFFF007F,
    );
    store.habits.addAll([a, b]);

    // Simulate onReorderItem(0, 1): take index 0, insert at adjusted index 1
    final h = store.habits[0];
    store.habits.remove(h);
    store.habits.insert(1, h); // newI is pre-adjusted

    expect(store.habits[0].name, 'Bravo');
    expect(store.habits[1].name, 'Alpha');
  });

  test('HabitStore reorder - move second habit up', () {
    final store = HabitStore.instance;
    final a = Habit(
      id: 'a',
      name: 'Alpha',
      emoji: '📚',
      colorValue: 0xFF00FF66,
    );
    final b = Habit(
      id: 'b',
      name: 'Bravo',
      emoji: '🏃',
      colorValue: 0xFFFF007F,
    );
    store.habits.addAll([a, b]);

    // Simulate onReorderItem(1, 0): newI(0) < oldI(1), no adjustment
    final h = store.habits[1];
    store.habits.remove(h);
    store.habits.insert(0, h);

    expect(store.habits[0].name, 'Bravo');
    expect(store.habits[1].name, 'Alpha');
  });

  test('HabitStore reorder - three items: move middle to end', () {
    final store = HabitStore.instance;
    final a = Habit(id: 'a', name: 'A', emoji: '📚', colorValue: 0xFF00FF66);
    final b = Habit(id: 'b', name: 'B', emoji: '🏃', colorValue: 0xFFFF007F);
    final c = Habit(id: 'c', name: 'C', emoji: '💻', colorValue: 0xFF6C3BFF);
    store.habits.addAll([a, b, c]);

    // onReorderItem(1, 2): newI(2) > oldI(1), adjustment: newI = 1
    // Wait, with pre-adjusted indices: dragging B (index 1) to position 2
    // fluter's onReorderItem adjusts newIndex. So newI should be 2 (not adjusted)
    // because we're moving DOWN and the item was removed, shifting things.
    // Actually, need to think about this...
    // If we drag B from index 1 to index 2:
    // newI is already adjusted for removal at oldI=1.
    // newI = 2 means: remove B, insert B at index 2
    // List before: [A(0), B(1), C(2)]
    // Remove B: [A(0), C(1)]
    // Insert B at 2: [A(0), C(1), B(2)]
    final h = store.habits[1];
    store.habits.remove(h);
    store.habits.insert(2, h);

    expect(store.habits[0].name, 'A');
    expect(store.habits[1].name, 'C');
    expect(store.habits[2].name, 'B');
  });

  test('HabitStore reorder - three items: move end to start', () {
    final store = HabitStore.instance;
    final a = Habit(id: 'a', name: 'A', emoji: '📚', colorValue: 0xFF00FF66);
    final b = Habit(id: 'b', name: 'B', emoji: '🏃', colorValue: 0xFFFF007F);
    final c = Habit(id: 'c', name: 'C', emoji: '💻', colorValue: 0xFF6C3BFF);
    store.habits.addAll([a, b, c]);

    // onReorderItem(2, 0): newI(0) < oldI(2), no adjustment
    // Remove C at index 2: [A(0), B(1)]
    // Insert C at index 0: [C(0), A(1), B(2)]
    final h = store.habits[2];
    store.habits.remove(h);
    store.habits.insert(0, h);

    expect(store.habits[0].name, 'C');
    expect(store.habits[1].name, 'A');
    expect(store.habits[2].name, 'B');
  });

  test('HabitStore todayHabits filters correctly', () {
    final store = HabitStore.instance;
    final daily = Habit(
      id: 'a',
      name: 'Daily',
      emoji: '📚',
      colorValue: 0xFF00FF66,
      frequency: 'Daily',
    );
    final weekly = Habit(
      id: 'b',
      name: 'Weekly',
      emoji: '🏃',
      colorValue: 0xFFFF007F,
      frequency: 'Weekly',
      weeklyDay: DateTime.now().weekday,
    );
    final paused = Habit(
      id: 'c',
      name: 'Paused',
      emoji: '💪',
      colorValue: 0xFF6C3BFF,
      frequency: 'Daily',
      paused: true,
    );
    store.habits.addAll([daily, weekly, paused]);

    final active = store.todayHabits;
    expect(active.length, 2); // daily + weekly (not paused)
    expect(active.any((h) => h.name == 'Daily'), true);
    expect(active.any((h) => h.name == 'Weekly'), true);
    expect(active.any((h) => h.name == 'Paused'), false);
  });

  test('HabitStore toggle completion updates count', () {
    final store = HabitStore.instance;
    final h = Habit(
      id: 'a',
      name: 'Test',
      emoji: '📚',
      colorValue: 0xFF00FF66,
      frequency: 'Daily',
    );
    store.habits.add(h);

    expect(store.todayCompleted, 0);

    h.toggle(DateTime.now());
    expect(store.todayCompleted, 1);

    h.toggle(DateTime.now());
    expect(store.todayCompleted, 0);
  });

  // ─── WIDGET TEST: the admin is exempt from the 3-habit free limit ─
  testWidgets(
    'admin with more than 3 habits still sees CREATE HABIT unlocked',
    (tester) async {
      // The admin is whoever carries the `admin` custom claim. The harness has
      // no Firebase app, so the claim lookup is injected.
      SubscriptionService.adminCheckOverride = () async => true;
      addTearDown(() => SubscriptionService.adminCheckOverride = null);
      SharedPreferences.setMockInitialValues({});
      final store = HabitStore.instance;
      // 4 habits — above the free limit of 3.
      for (var i = 0; i < 4; i++) {
        store.habits.add(
          Habit(
            id: 'h$i',
            name: 'Habit $i',
            emoji: '✨',
            colorValue: 0xFF00FF66,
            frequency: 'Daily',
          ),
        );
      }

      await pumpHabitsTab(tester);

      // Admin is unlimited: the button must NOT be the Pro upsell, and the
      // habit-limit card must be hidden. The create button sits below the fold
      // with 4 missions, so scroll to it (same as the sections-order test).
      await tester.scrollUntilVisible(
        find.text('CREATE HABIT'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('GO PRO FOR UNLIMITED'),
        findsNothing,
        reason: 'admin must never see the Pro upsell button',
      );
      expect(
        find.text('CREATE HABIT'),
        findsOneWidget,
        reason: 'admin with 4 habits must still be able to create more',
      );
      expect(
        find.text('Habit Limit'),
        findsNothing,
        reason: 'admin must never see the habit-limit card',
      );

      store.habits.clear();
    },
  );

  // ─── WIDGET TEST: repeated right swipes must not need repeated left swipes ─
  testWidgets('swipe right twice then left once fully un-completes', (
    tester,
  ) async {
    final store = HabitStore.instance;
    store.habits.add(
      Habit(
        id: 'v1',
        name: 'Morning Run',
        emoji: '🏃',
        colorValue: 0xFFFF007F,
        frequency: 'Daily',
      ),
    );

    await pumpHabitsTab(tester);

    final habit = store.habits.first;
    final today = dateKey(DateTime.now());

    // Completes a swipe gesture and lets the Dismissible snap-back (200ms) and
    // the deferred 350ms persist both fire. NOTE: pumpAndSettle would time out
    // here — the hero card's 🔥 StreakFlame loops forever by design.
    Future<void> doSwipe(Offset offset) async {
      await tester.drag(find.byType(Dismissible).first, offset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    // Swipe right TWICE → completes, but must NOT stack duplicate date entries
    // (an unguarded add made each right swipe create a copy of today, so undo
    // needed one left swipe per copy).
    await doSwipe(const Offset(500, 0));
    await doSwipe(const Offset(500, 0));
    expect(
      habit.completedDates.where((k) => k == today).length,
      1,
      reason: 'repeated right swipes must not stack duplicate dates',
    );

    // Swipe left ONCE → fully un-completes (removeWhere clears every copy,
    // including legacy duplicates saved by older builds).
    await doSwipe(const Offset(-500, 0));
    expect(
      habit.completedDates.where((k) => k == today),
      isEmpty,
      reason: 'one left swipe must fully undo, no matter how many right swipes',
    );

    // Let the "not completed" SnackBar auto-dismiss so no timers leak.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
