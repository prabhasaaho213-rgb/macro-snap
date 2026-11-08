import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Habit _habit(String id, String name) => Habit(
  id: id,
  name: name,
  emoji: '💧',
  colorValue: 0xFF00FF00,
  frequency: 'Daily',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HabitStore.instance.reload();
  });

  test('an edited copy is persisted in its original position', () async {
    final store = HabitStore.instance;
    store.habits
      ..clear()
      ..addAll([
        _habit('1', 'Water'),
        _habit('2', 'Walk'),
        _habit('3', 'Sleep'),
      ]);

    await store.update(_habit('2', 'Walk 10k'));

    expect(store.habits.map((h) => h.name).toList(), [
      'Water',
      'Walk 10k',
      'Sleep',
    ]);
  });

  test('mutating the stored instance still saves', () async {
    final store = HabitStore.instance;
    store.habits
      ..clear()
      ..add(_habit('1', 'Water'));
    store.habits.first.name = 'Water 3L';

    await store.update(store.habits.first);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('habits'), contains('Water 3L'));
  });
}
