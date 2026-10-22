import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/diet_profile.dart';

void main() {
  test('falls back to safe defaults for invalid persisted enum values', () {
    final profile = DietProfile.fromJson({
      'weightKg': 70,
      'heightCm': 175,
      'age': 28,
      'gender': 'unknown',
      'goal': 'unknown',
      'activity': 'unknown',
      'avatar': '😎',
    });

    expect(profile.gender, Gender.male);
    // Neutral default: a missing goal must never silently become a deficit.
    expect(profile.goal, Goal.maintain);
    expect(profile.activity, ActivityLevel.sedentary);
    // A profile saved before the food preference existed is vegetarian - the
    // plan those users were already being shown.
    expect(profile.diet, DietPreference.vegetarian);
  });

  test('an unknown food preference falls back to vegetarian', () {
    final profile = DietProfile.fromJson({'diet': 'pescatarian'});
    expect(profile.diet, DietPreference.vegetarian);
  });

  test('the food preference survives a save/load round trip', () {
    final original = DietProfile(
      weightKg: 80,
      heightCm: 180,
      age: 30,
      gender: Gender.male,
      goal: Goal.gainMuscle,
      activity: ActivityLevel.active,
      diet: DietPreference.nonVegetarian,
    );

    final restored = DietProfile.fromJson(original.toJson());

    expect(restored.diet, DietPreference.nonVegetarian);
    expect(original.toJson()['diet'], 'nonVegetarian');
  });
}
