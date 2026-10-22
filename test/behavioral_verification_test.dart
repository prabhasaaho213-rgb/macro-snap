import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_store.dart';

/// ------------------------------------------------------------------
/// BEHAVIORAL VERIFICATION TESTS
///
/// These tests exercise real code paths — not just compilation checks.
/// They trace the full lifecycle of each behavioral change:
///  1. Dead-code removal  — import scanning + existence check
///  2. MealStore.remove() state transition
///  3. HabitStore CRUD behavior
/// ------------------------------------------------------------------

void main() {
  // ──────────────────────────────────────────────────────────
  // SECTION 1: Dead-code verification
  //   Confirms deleted files have zero imports and don't exist
  // ──────────────────────────────────────────────────────────
  group('Dead-code removal', () {
    test('[update_checker] is not imported anywhere', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;
      final issues = <String>[];
      for (final f
          in libDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (f.readAsStringSync().contains("update_checker")) {
          issues.add(f.path);
        }
      }
      expect(
        issues,
        isEmpty,
        reason: 'Files still importing update_checker: $issues',
      );
    });

    test('[macro_ring] is not imported anywhere', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;
      final issues = <String>[];
      for (final f
          in libDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (f.readAsStringSync().contains("macro_ring")) {
          issues.add(f.path);
        }
      }
      expect(
        issues,
        isEmpty,
        reason: 'Files still importing macro_ring: $issues',
      );
    });

    test('Deleted files no longer exist on disk', () {
      // home_screen.dart was restored from git after user reverted the DashboardScreen.
      expect(File('lib/screens/home_screen.dart').existsSync(), true);
      expect(File('lib/services/update_checker.dart').existsSync(), false);
      expect(File('lib/widgets/macro_ring.dart').existsSync(), false);
      expect(File('test_driver/app_test.dart').existsSync(), false);
      expect(File('test_driver/app.dart').existsSync(), false);
    });
  });

  // ──────────────────────────────────────────────────────────
  // SECTION 2: MealStore.remove() state transition
  //   Full lifecycle: add → verify → remove → verify gone
  // ──────────────────────────────────────────────────────────
  group('MealStore.remove() — state transition', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await MealStore.instance.reload();
    });

    test('add → appears in todayMeals', () async {
      await MealStore.instance.add(
        MealRecord(
          id: 't1',
          date: DateTime.now(),
          name: 'Test',
          category: 'x',
          calories: 350,
          protein: 12,
          carbs: 50,
          fats: 8,
          fiber: 4,
          serving: '1',
        ),
      );
      expect(MealStore.instance.todayMeals.any((m) => m.id == 't1'), true);
    });

    test('remove → disappears from todayMeals', () async {
      await MealStore.instance.add(
        MealRecord(
          id: 't2',
          date: DateTime.now(),
          name: 'Remove Me',
          category: 'x',
          calories: 500,
          protein: 20,
          carbs: 40,
          fats: 15,
          fiber: 5,
          serving: '1',
        ),
      );
      await MealStore.instance.remove('t2');
      expect(MealStore.instance.todayMeals.any((m) => m.id == 't2'), false);
    });

    test('remove one meal does not affect other meals', () async {
      await MealStore.instance.add(
        MealRecord(
          id: 'keep',
          date: DateTime.now(),
          name: 'Keep',
          category: 'x',
          calories: 300,
          protein: 10,
          carbs: 30,
          fats: 5,
          fiber: 2,
          serving: '1',
        ),
      );
      await MealStore.instance.add(
        MealRecord(
          id: 'del',
          date: DateTime.now(),
          name: 'Delete',
          category: 'x',
          calories: 400,
          protein: 15,
          carbs: 35,
          fats: 10,
          fiber: 3,
          serving: '1',
        ),
      );
      expect(MealStore.instance.todayMeals.length, 2);
      await MealStore.instance.remove('del');
      expect(MealStore.instance.todayMeals.length, 1);
      expect(MealStore.instance.todayMeals.any((m) => m.id == 'keep'), true);
      expect(MealStore.instance.todayMeals.any((m) => m.id == 'del'), false);
    });

    test('changeNotifier fires after remove (triggers UI rebuild)', () async {
      await MealStore.instance.add(
        MealRecord(
          id: 'n1',
          date: DateTime.now(),
          name: 'Notif',
          category: 'x',
          calories: 150,
          protein: 5,
          carbs: 20,
          fats: 5,
          fiber: 2,
          serving: '1',
        ),
      );
      int calls = 0;
      void listener() => calls++;
      MealStore.instance.changeNotifier.addListener(listener);
      await MealStore.instance.remove('n1');
      MealStore.instance.changeNotifier.removeListener(listener);
      expect(
        calls,
        greaterThanOrEqualTo(1),
        reason: 'changeNotifier must fire so Dashboard rebuilds',
      );
    });

    test('idempotent — removing same ID twice does not throw', () async {
      await MealStore.instance.remove('nonexistent-id');
      // Should not throw — this verifies the catch behavior is safe
    });
  });

  // ──────────────────────────────────────────────────────────
  // SECTION 2.5: Startup resilience
  //   Corrupted persisted data must reset, never crash main()
  //   (a throw in HabitStore.load() used to kill the app before
  //   runApp(), leaving it permanently unable to open)
  // ──────────────────────────────────────────────────────────
  group('Startup resilience — corrupted persisted data', () {
    test(
      'load() survives corrupted habits JSON — resets instead of throwing',
      () async {
        SharedPreferences.setMockInitialValues({'habits': '{not valid json!!'});
        await HabitStore.instance.reload();
        expect(HabitStore.instance.habits, isEmpty);
      },
    );

    test(
      'load() survives corrupted water_log JSON — resets instead of throwing',
      () async {
        SharedPreferences.setMockInitialValues({'water_log': 'oops['});
        await HabitStore.instance.reload();
        expect(HabitStore.instance.waterToday, 0);
      },
    );

    test(
      'load() survives habits stored as wrong type (Map instead of List)',
      () async {
        SharedPreferences.setMockInitialValues({'habits': '{"a":1}'});
        await HabitStore.instance.reload();
        expect(HabitStore.instance.habits, isEmpty);
      },
    );
  });

  // ──────────────────────────────────────────────────────────
  // SECTION 3: HabitStore behavioral correctness
  //   CRUD + toggle completion state transitions
  // ──────────────────────────────────────────────────────────
  group('HabitStore — CRUD & state transitions', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      HabitStore.instance.habits.clear();
    });

    test('create habit → appears in list', () async {
      await HabitStore.instance.add(
        Habit(id: 'h1', name: 'Read', emoji: '📚', colorValue: 0xFF00FF66),
      );
      expect(HabitStore.instance.habits.any((h) => h.id == 'h1'), true);
    });

    test('remove habit → disappears from list', () async {
      final h = Habit(
        id: 'h2',
        name: 'Run',
        emoji: '🏃',
        colorValue: 0xFFFF007F,
      );
      await HabitStore.instance.add(h);
      expect(HabitStore.instance.habits.length, 1);
      await HabitStore.instance.remove(h);
      expect(HabitStore.instance.habits.any((x) => x.id == 'h2'), false);
    });

    test('toggle completion two-way state transition', () {
      final h = Habit(
        id: 'h3',
        name: 'Meditate',
        emoji: '🧘',
        colorValue: 0xFF6C3BFF,
      );
      expect(h.isCompleted(DateTime.now()), false);
      h.toggle(DateTime.now());
      expect(h.isCompleted(DateTime.now()), true);
      h.toggle(DateTime.now());
      expect(h.isCompleted(DateTime.now()), false);
    });

    test('todayHabits excludes paused habits', () {
      HabitStore.instance.habits.addAll([
        Habit(
          id: 'a',
          name: 'A',
          emoji: '📚',
          colorValue: 0xFF00FF66,
          frequency: 'Daily',
        ),
        Habit(
          id: 'b',
          name: 'B',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily',
          paused: true,
        ),
      ]);
      expect(HabitStore.instance.todayHabits.length, 1);
      expect(HabitStore.instance.todayHabits.any((h) => h.id == 'a'), true);
      expect(HabitStore.instance.todayHabits.any((h) => h.id == 'b'), false);
    });

    test('todayCompleted increments correctly after toggle', () {
      HabitStore.instance.habits.add(
        Habit(
          id: 'c',
          name: 'C',
          emoji: '💻',
          colorValue: 0xFF6C3BFF,
          frequency: 'Daily',
        ),
      );
      expect(HabitStore.instance.todayCompleted, 0);
      HabitStore.instance.habits.first.toggle(DateTime.now());
      expect(HabitStore.instance.todayCompleted, 1);
      HabitStore.instance.habits.first.toggle(DateTime.now());
      expect(HabitStore.instance.todayCompleted, 0);
    });
  });
}
