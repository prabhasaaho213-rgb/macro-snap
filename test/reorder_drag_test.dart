import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_store.dart';

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

  List<Habit> threeHabits() => [
    Habit(
      id: 'v1',
      name: 'Alpha',
      emoji: '🏃',
      colorValue: 0xFFFF007F,
      frequency: 'Daily',
    ),
    Habit(
      id: 'v2',
      name: 'Bravo',
      emoji: '🏋️',
      colorValue: 0xFF00FF66,
      frequency: 'Daily',
    ),
    Habit(
      id: 'v3',
      name: 'Charlie',
      emoji: '📚',
      colorValue: 0xFF007FFF,
      frequency: 'Daily',
    ),
  ];

  testWidgets('grip drag reorders the visible list in order', (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll(threeHabits());
    await pumpHabitsTab(tester);

    expect(store.habits.map((h) => h.id).toList(), ['v1', 'v2', 'v3']);

    // Grab the FIRST card's grip and drag it down past the last card.
    final grips = find.byIcon(Icons.drag_handle_rounded);
    expect(grips, findsNWidgets(3));

    await tester.drag(grips.first, const Offset(0, 200), warnIfMissed: false);
    // Drop animation, then the 350ms deferred persist.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    // The reorder must persist into store.habits.
    final order = store.habits.map((h) => h.name).toList();
    expect(
      order.first,
      isNot('Alpha'),
      reason:
          'dragging Alpha down should move it below Bravo at least. '
          'Actual order: $order',
    );
  });

  testWidgets('reorder drag does not throw and cards keep unique keys', (
    tester,
  ) async {
    final store = HabitStore.instance;
    store.habits.addAll(threeHabits());
    await pumpHabitsTab(tester);

    final grips = find.byIcon(Icons.drag_handle_rounded);
    await tester.drag(grips.at(2), const Offset(0, -200), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(Dismissible), findsNWidgets(3));
  });
}
