import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store that finishes loading *after* the app is already on screen must
/// announce that, or the late data never reaches the UI.
///
/// This is not hypothetical: the launch splash has a safety timeout, so on a
/// slow device Home can be built while these loads are still running. Before
/// these bumps, `load()` set `_loaded = true` silently and Home kept showing
/// zeros for the rest of the session.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MealStore.load notifies listeners when it completes', () async {
    final store = MealStore.instance;
    var bumps = 0;
    void listener() => bumps++;
    store.changeNotifier.addListener(listener);
    addTearDown(() => store.changeNotifier.removeListener(listener));

    await store.load();

    expect(bumps, 1);
  });

  test('HabitStore.load notifies the UI and the reminder plan', () async {
    final store = HabitStore.instance;
    var ui = 0;
    var reminders = 0;
    void uiListener() => ui++;
    void reminderListener() => reminders++;
    store.addListener(uiListener);
    store.remindersChangedNotifier.addListener(reminderListener);
    addTearDown(() {
      store.removeListener(uiListener);
      store.remindersChangedNotifier.removeListener(reminderListener);
    });

    await store.load();

    expect(ui, 1, reason: 'the habits screen must repaint with late data');
    expect(
      reminders,
      1,
      reason: 'a late habit set must still reach the reminder registry',
    );
  });
}
